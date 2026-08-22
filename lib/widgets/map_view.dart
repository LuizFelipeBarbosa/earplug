import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// invert(1) hue-rotate(200deg) saturate(.35) brightness(.85) contrast(1.05)
/// — the design's CSS tile filter, composed into one color matrix.
const _darkTileMatrix = <double>[
  0.0182, -0.9245, 0.0139, 0, 221.2125, //
  -0.2373, -0.5397, -0.1155, 0, 221.2125, //
  -0.3367, -0.7718, 0.2159, 0, 221.2125, //
  0, 0, 0, 1, 0,
];

Widget _darkTiles() {
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix(_darkTileMatrix),
    child: TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'app.earplug.earplug',
    ),
  );
}

Widget _attribution() {
  return Positioned(
    right: 4,
    bottom: 2,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: Colors.black.withValues(alpha: .7),
      child: Text(
        '© OpenStreetMap contributors',
        style: epText(size: 9, color: Ep.whiteA(.5)),
      ),
    ),
  );
}

class _Pin extends StatelessWidget {
  final bool free;

  const _Pin({required this.free});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: free ? Ep.blue : Colors.black,
        shape: BoxShape.circle,
        border: Border.all(color: free ? Colors.white : Ep.blue, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _UserPin extends StatelessWidget {
  const _UserPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Ep.linkSoft,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Ep.blue.withValues(alpha: .45),
            blurRadius: 12,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Center(
        child: SizedBox.square(
          dimension: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Ep.blue, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// Full-screen gig map with tappable pins and a bottom gig card.
class GigMapView extends StatefulWidget {
  const GigMapView({super.key, this.emptyState});

  final Widget? emptyState;

  @override
  State<GigMapView> createState() => _GigMapViewState();
}

class _GigMapViewState extends State<GigMapView> {
  final MapController _controller = MapController();
  Gig? selected;
  bool _mapReady = false;
  String? _cameraSignature;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateCamera(AppState app, List<Gig> gigs) {
    final center = app.discoveryCenter;
    final signature = <String>[
      center.latitude.toStringAsFixed(5),
      center.longitude.toStringAsFixed(5),
      for (final gig in gigs) gig.id,
    ].join('|');
    if (!_mapReady || signature == _cameraSignature) return;
    _cameraSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      if (gigs.isEmpty) {
        _controller.move(center, 13);
        return;
      }

      final points = [
        app.discoveryCenter,
        for (final gig in gigs) app.venue(gig.venueId).point,
      ];
      _controller.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(46, 46, 46, 180),
          maxZoom: 14,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final gigs = app.feed;
    if (selected != null && !gigs.any((gig) => gig.id == selected!.id)) {
      selected = null;
    }
    _updateCamera(app, gigs);

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: app.discoveryCenter,
            initialZoom: 13,
            backgroundColor: Ep.bg,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: (_, _) => setState(() => selected = null),
            onMapReady: () {
              _mapReady = true;
              _cameraSignature = null;
              _updateCamera(app, gigs);
            },
          ),
          children: [
            _darkTiles(),
            MarkerLayer(
              markers: [
                if (app.currentPosition case final position?)
                  if (app.discoveryLocation == DiscoveryLocation.current)
                    Marker(
                      key: const Key('current-location-marker'),
                      point: position,
                      width: 24,
                      height: 24,
                      child: const _UserPin(),
                    ),
                for (final g in gigs)
                  Marker(
                    key: Key('gig-marker-${g.id}'),
                    point: app.venue(g.venueId).point,
                    width: 18,
                    height: 18,
                    child: GestureDetector(
                      onTap: () => setState(() => selected = g),
                      child: _Pin(free: g.free),
                    ),
                  ),
              ],
            ),
          ],
        ),
        _attribution(),
        if (gigs.isEmpty && widget.emptyState != null)
          Positioned(left: 18, right: 18, top: 18, child: widget.emptyState!),
        if (selected case final Gig g)
          Positioned(
            left: 12,
            right: 12,
            bottom: tabBarClearance + 10,
            child: _MapGigCard(
              gig: g,
              venue: app.venue(g.venueId),
              onOpen: () {
                setState(() => selected = null);
                app.openGig(g.id);
              },
            ),
          ),
      ],
    );
  }
}

class _MapGigCard extends StatelessWidget {
  final Gig gig;
  final Venue venue;
  final VoidCallback onOpen;

  const _MapGigCard({
    required this.gig,
    required this.venue,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF101014),
        border: Border.all(color: Ep.whiteA(.14)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .6),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            gig.title.toUpperCase(),
            style: epText(size: 15, weight: FontWeight.w800, letterSpacing: .2),
          ),
          const SizedBox(height: 3),
          Text(
            '${venue.name} · ${venue.area} · ${gig.dateLine}',
            style: epText(size: 12, color: Ep.inkA(.6)),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PriceBadge(gig),
              GestureDetector(
                onTap: onOpen,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Ep.blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'OPEN GIG →',
                    style: epText(
                      size: 12,
                      weight: FontWeight.w800,
                      letterSpacing: .8,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Static venue mini-map for the gig page.
class VenueMiniMap extends StatelessWidget {
  final Venue venue;

  const VenueMiniMap({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: venue.point,
              initialZoom: 15,
              backgroundColor: Ep.bg,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              _darkTiles(),
              MarkerLayer(
                markers: [
                  Marker(
                    point: venue.point,
                    width: 18,
                    height: 18,
                    child: const _Pin(free: true),
                  ),
                ],
              ),
            ],
          ),
          _attribution(),
        ],
      ),
    );
  }
}
