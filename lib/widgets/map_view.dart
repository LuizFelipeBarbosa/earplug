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

Widget _attribution(BuildContext context) {
  return Positioned(
    right: 4,
    bottom: 2,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: Colors.black.withValues(alpha: .7),
      child: Text(
        '© OpenStreetMap contributors',
        style: Theme.of(
          context,
        ).textTheme.epCaption.copyWith(fontSize: 9, color: Colors.white),
      ),
    ),
  );
}

class _Pin extends StatelessWidget {
  final bool free;
  final int count;

  const _Pin({required this.free, this.count = 1});

  @override
  Widget build(BuildContext context) {
    final grouped = count > 1;
    return Container(
      decoration: BoxDecoration(
        color: grouped ? Colors.black : (free ? Ep.brand : Colors.black),
        shape: BoxShape.circle,
        border: Border.all(
          color: grouped || !free ? Ep.brand : Colors.white,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: grouped
          ? Center(
              child: Text(
                '$count',
                style: Theme.of(
                  context,
                ).textTheme.epLabel.copyWith(fontSize: 10, color: Colors.white),
              ),
            )
          : null,
    );
  }
}

class _UserPin extends StatelessWidget {
  const _UserPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Ep.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Ep.brand.withValues(alpha: .45),
            blurRadius: 12,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Center(
        child: SizedBox.square(
          dimension: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Ep.brand, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _VenueGigGroup {
  const _VenueGigGroup({required this.venue, required this.gigs});

  final Venue venue;
  final List<Gig> gigs;
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

  List<_VenueGigGroup> _mapGroups(AppState app, List<Gig> gigs) {
    final gigsByVenue = <String, List<Gig>>{};
    for (final gig in gigs) {
      if (app.knownVenue(gig.venueId) == null) continue;
      gigsByVenue.putIfAbsent(gig.venueId, () => []).add(gig);
    }

    final groups = [
      for (final entry in gigsByVenue.entries)
        _VenueGigGroup(
          venue: app.knownVenue(entry.key)!,
          gigs: entry.value..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
        ),
    ];
    // Paint denser venue groups last so their larger count marker remains
    // usable when nearby 48px touch targets overlap at a wide map zoom.
    groups.sort((a, b) => a.gigs.length.compareTo(b.gigs.length));
    return groups;
  }

  void _updateCamera(AppState app, List<_VenueGigGroup> groups) {
    final center = app.discoveryCenter;
    final signature = <String>[
      center.latitude.toStringAsFixed(5),
      center.longitude.toStringAsFixed(5),
      for (final group in groups) ...[
        group.venue.id,
        group.venue.point.latitude.toStringAsFixed(5),
        group.venue.point.longitude.toStringAsFixed(5),
        for (final gig in group.gigs) gig.id,
      ],
    ].join('|');
    if (!_mapReady || signature == _cameraSignature) return;
    _cameraSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      if (groups.isEmpty) {
        _controller.move(center, 13);
        return;
      }

      final points = [
        app.discoveryCenter,
        for (final group in groups) group.venue.point,
      ];
      _controller.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(46, 46, 46, 240),
          maxZoom: 14,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final gigs = app.feed;
    final groups = _mapGroups(app, gigs);
    _VenueGigGroup? selectedGroup;
    var selectedIndex = -1;
    if (selected != null) {
      for (final group in groups) {
        final index = group.gigs.indexWhere((gig) => gig.id == selected!.id);
        if (index == -1) continue;
        selectedGroup = group;
        selectedIndex = index;
        break;
      }
    }
    if (selected != null && selectedGroup == null) {
      selected = null;
    }
    final groupsByLatitude = [
      ...groups,
    ]..sort((a, b) => b.venue.point.latitude.compareTo(a.venue.point.latitude));
    final markersAbovePoint = <String>{
      for (var index = 0; index < groupsByLatitude.length; index += 2)
        groupsByLatitude[index].venue.id,
    };
    _updateCamera(app, groups);

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: app.discoveryCenter,
            initialZoom: 13,
            backgroundColor: Ep.background,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: (_, _) => setState(() => selected = null),
            onMapReady: () {
              _mapReady = true;
              _cameraSignature = null;
              _updateCamera(app, groups);
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
                for (final group in groups)
                  Marker(
                    key: Key(
                      group.gigs.length == 1
                          ? 'gig-marker-${group.gigs.single.id}'
                          : 'venue-marker-${group.venue.id}',
                    ),
                    point: group.venue.point,
                    width: 48,
                    height: 48,
                    alignment: markersAbovePoint.contains(group.venue.id)
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    child: Material(
                      color: Colors.transparent,
                      child: InkResponse(
                        onTap: () =>
                            setState(() => selected = group.gigs.first),
                        radius: 24,
                        child: Align(
                          alignment: markersAbovePoint.contains(group.venue.id)
                              ? Alignment.bottomCenter
                              : Alignment.topCenter,
                          child: SizedBox.square(
                            dimension: group.gigs.length == 1 ? 18 : 26,
                            child: _Pin(
                              free: group.gigs.length == 1
                                  ? group.gigs.single.free
                                  : false,
                              count: group.gigs.length,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        _attribution(context),
        if (gigs.isEmpty && widget.emptyState != null)
          Positioned(left: 18, right: 18, top: 18, child: widget.emptyState!),
        if (selected case final Gig g when selectedGroup != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: tabBarClearance + 10,
            child: _MapGigCard(
              gig: g,
              venue: selectedGroup.venue,
              position: selectedIndex,
              total: selectedGroup.gigs.length,
              onPrevious: selectedIndex > 0
                  ? () => setState(
                      () => selected = selectedGroup!.gigs[selectedIndex - 1],
                    )
                  : null,
              onNext: selectedIndex < selectedGroup.gigs.length - 1
                  ? () => setState(
                      () => selected = selectedGroup!.gigs[selectedIndex + 1],
                    )
                  : null,
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
  final int position;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onOpen;

  const _MapGigCard({
    required this.gig,
    required this.venue,
    required this.position,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return EpCard(
      variant: EpCardVariant.raised,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total > 1) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${position + 1} OF $total GIGS AT THIS VENUE',
                    key: const Key('map-gig-position'),
                    style: Theme.of(context).textTheme.epCaption.copyWith(
                      fontSize: 10,
                      letterSpacing: .7,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _CarouselButton(
                  key: const Key('previous-map-gig'),
                  icon: Icons.chevron_left,
                  onTap: onPrevious,
                ),
                const SizedBox(width: 6),
                _CarouselButton(
                  key: const Key('next-map-gig'),
                  icon: Icons.chevron_right,
                  onTap: onNext,
                ),
              ],
            ),
            const SizedBox(height: 7),
          ],
          Text(
            gig.title.toUpperCase(),
            style: Theme.of(context).textTheme.epSectionHeading.copyWith(
              fontSize: 15,
              letterSpacing: .2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${venue.name} · ${venue.area} · ${gig.dateLine}',
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PriceBadge(gig),
              FilledButton(onPressed: onOpen, child: const Text('OPEN GIG →')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarouselButton extends StatelessWidget {
  const _CarouselButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      style: const ButtonStyle(
        fixedSize: WidgetStatePropertyAll(Size.square(48)),
      ),
      icon: Icon(icon, size: 20),
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
              backgroundColor: Ep.background,
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
          _attribution(context),
        ],
      ),
    );
  }
}
