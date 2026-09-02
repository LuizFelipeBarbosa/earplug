import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/stadia_map_style_repository.dart';
import '../theme.dart';

class EpMap extends StatefulWidget {
  const EpMap({
    super.key,
    required this.options,
    this.mapController,
    this.layers = const [],
  });

  final MapOptions options;
  final MapController? mapController;
  final List<Widget> layers;

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
    final style = _style;
    final ready = style != null && _error == null;
    final colors = context.epColors;

    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          key: const Key('map-input-blocker'),
          absorbing: !ready,
          child: FlutterMap(
            mapController: widget.mapController,
            options: widget.options,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: style == null
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
                      ),
              ),
              if (ready) ...widget.layers,
            ],
          ),
        ),
        if (!ready && _error == null) const _MapLoading(),
        if (!ready && _error != null) _MapError(onRetry: _retry),
        if (style != null) _MapAttribution(style: style),
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
  const _MapAttribution({required this.style});

  final vt.Style style;

  @override
  Widget build(BuildContext context) {
    final spans = [
      for (final attribution in style.attributions) ...attribution.spans,
    ];
    if (spans.isEmpty) return const SizedBox.shrink();

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
            for (final span in spans)
              Semantics(
                link: span.url != null,
                label: span.text,
                child: InkWell(
                  onTap: span.url == null
                      ? null
                      : () => launchUrl(
                          Uri.parse(span.url!),
                          mode: LaunchMode.externalApplication,
                        ),
                  child: Text(
                    span.text,
                    style: Theme.of(context).textTheme.epCaption.copyWith(
                      fontSize: 9,
                      color: context.epColors.contentSecondary,
                      decoration: span.url == null
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
