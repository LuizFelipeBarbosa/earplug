import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../env.dart';
import '../services/stadia_map_style_repository.dart';
import '../theme.dart';

enum EpMapTiles { vector, raster }

typedef _AttributionEntry = ({String text, String? url});

class EpMap extends StatefulWidget {
  const EpMap({
    super.key,
    required this.options,
    this.mapController,
    this.layers = const [],
    this.tiles = kIsWeb ? EpMapTiles.raster : EpMapTiles.vector,
  });

  final MapOptions options;
  final MapController? mapController;
  final List<Widget> layers;
  final EpMapTiles tiles;

  @override
  State<EpMap> createState() => _EpMapState();
}

class _EpMapState extends State<EpMap> {
  StadiaMapStyleRepository? _repository;
  vt.Style? _style;
  Brightness? _styleBrightness;
  Brightness? _requestedBrightness;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.tiles == EpMapTiles.raster) return;

    final repository = context.read<StadiaMapStyleRepository>();
    final brightness = Theme.of(context).brightness;
    if (_repository == repository && _requestedBrightness == brightness) return;
    _repository = repository;
    _load(brightness);
  }

  void _load(Brightness brightness) {
    _requestedBrightness = brightness;
    _error = null;
    _repository!
        .load(brightness)
        .then(
          (style) {
            if (!mounted || _requestedBrightness != brightness) return;
            setState(() {
              _style = style;
              _styleBrightness = brightness;
              _error = null;
            });
          },
          onError: (Object error) {
            if (!mounted || _requestedBrightness != brightness) return;
            setState(() => _error = error);
          },
        );
  }

  void _retry() {
    final brightness = Theme.of(context).brightness;
    _repository!.retry(brightness);
    setState(() {
      _style = null;
      _styleBrightness = null;
      _error = null;
    });
    _load(brightness);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final style = _style;
    final colors = context.epColors;
    final raster = widget.tiles == EpMapTiles.raster;
    final ready = raster || (style != null && _error == null);

    late final Widget tiles;
    late final List<_AttributionEntry> attributions;
    if (raster) {
      final styleName = brightness == Brightness.dark
          ? 'alidade_smooth_dark'
          : 'alidade_smooth';
      final apiKeyQuery = Env.stadiaMapsApiKey.isEmpty
          ? ''
          : '?api_key=${Env.stadiaMapsApiKey}';
      tiles = TileLayer(
        key: ValueKey(brightness),
        urlTemplate:
            'https://tiles.stadiamaps.com/tiles/$styleName/{z}/{x}/{y}{r}.png$apiKeyQuery',
        retinaMode: RetinaMode.isHighDensity(context),
        userAgentPackageName: 'dev.earplug',
        maxNativeZoom: 20,
      );
      attributions = const [
        (text: '© Stadia Maps', url: 'https://stadiamaps.com/'),
        (text: '© OpenMapTiles', url: 'https://openmaptiles.org/'),
        (
          text: '© OpenStreetMap',
          url: 'https://www.openstreetmap.org/copyright',
        ),
      ];
    } else {
      tiles = style == null
          ? ColoredBox(
              key: const ValueKey('map-background'),
              color: colors.background,
            )
          : vt.VectorTileLayer(
              key: ValueKey(_styleBrightness),
              theme: style.theme,
              tileProviders: style.providers,
              rasterSources: style.rasterSources,
              sprites: style.sprites,
              diskCacheMaximumSizeInBytes: 50 * 1024 * 1024,
              diskCacheTtl: const Duration(days: 7),
              logger: const vt.Logger.noop(),
            );
      attributions = style == null
          ? const []
          : [
              for (final attribution in style.attributions)
                for (final span in attribution.spans)
                  (text: span.text, url: span.url),
            ];
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          key: const Key('map-input-blocker'),
          absorbing: !ready,
          child: RepaintBoundary(
            child: FlutterMap(
              mapController: widget.mapController,
              options: widget.options,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: tiles,
                ),
                if (ready) ...widget.layers,
              ],
            ),
          ),
        ),
        if (!raster && !ready && _error == null) const _MapLoading(),
        if (!raster && !ready && _error != null) _MapError(onRetry: _retry),
        if (raster || style != null) _MapAttribution(entries: attributions),
      ],
    );
  }
}

class _MapLoading extends StatelessWidget {
  const _MapLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading map',
      liveRegion: true,
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.epColors.accent,
          ),
        ),
      ),
    );
  }
}

class _MapError extends StatelessWidget {
  const _MapError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: context.epColors.surface,
            border: Border.all(color: context.epColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MAP UNAVAILABLE',
                style: Theme.of(context).textTheme.epLabel,
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onRetry, child: Text('RETRY')),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapAttribution extends StatelessWidget {
  const _MapAttribution({required this.entries});

  final List<_AttributionEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: context.epColors.surface.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 1,
          alignment: WrapAlignment.end,
          children: [
            for (final entry in entries)
              Semantics(
                link: entry.url != null,
                label: entry.text,
                child: InkWell(
                  onTap: entry.url == null
                      ? null
                      : () => launchUrl(
                          Uri.parse(entry.url!),
                          mode: LaunchMode.externalApplication,
                        ),
                  child: Text(
                    entry.text,
                    style: Theme.of(context).textTheme.epCaption.copyWith(
                      fontSize: 9,
                      color: context.epColors.contentSecondary,
                      decoration: entry.url == null
                          ? TextDecoration.none
                          : TextDecoration.underline,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
