import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_map.dart';

class _Pin extends StatelessWidget {
  final int count;
  final bool emphasized;
  final bool selected;

  const _Pin({this.count = 1, this.emphasized = false, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final grouped = count > 1;
    return Container(
      decoration: BoxDecoration(
        color: context.epColors.brand,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected || emphasized
              ? context.epColors.contentPrimary
              : context.epColors.surface,
          width: selected ? 3 : 2,
        ),
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

class _MapPinButton extends StatefulWidget {
  const _MapPinButton({
    super.key,
    required this.alignment,
    required this.dimension,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final Alignment alignment;
  final double dimension;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_MapPinButton> createState() => _MapPinButtonState();
}

class _MapPinButtonState extends State<_MapPinButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final emphasized = _hovered || _focused || _pressed;
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: widget.onTap,
        onHover: _setHovered,
        onFocusChange: _setFocused,
        onHighlightChanged: _setPressed,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Align(
          alignment: widget.alignment,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: widget.dimension,
            height: widget.dimension,
            child: _Pin(
              count: widget.count,
              emphasized: emphasized,
              selected: widget.selected,
            ),
          ),
        ),
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
        color: context.epColors.brand,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Center(
        child: SizedBox.square(
          dimension: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.epColors.contentPrimary,
              shape: BoxShape.circle,
            ),
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

class _VenueMarkerLayer extends StatelessWidget {
  const _VenueMarkerLayer({
    required this.groups,
    required this.selectedGig,
    required this.onSelect,
  });

  final List<_VenueGigGroup> groups;
  final Gig? selectedGig;
  final ValueChanged<Gig> onSelect;

  @override
  Widget build(BuildContext context) {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        markers: [for (final group in groups) _venueMarker(group)],
        maxClusterRadius: 44,
        size: const Size.square(48),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(50),
        disableClusteringAtZoom: 15,
        maxZoom: 18,
        zoomToBoundsOnClick: true,
        spiderfyCluster: true,
        showPolygon: false,
        centerMarkerOnClick: false,
        markerChildBehavior: true,
        builder: (context, markers) {
          final memberKeys =
              markers
                  .map((marker) => (marker.child.key as ValueKey<String>).value)
                  .toList()
                ..sort();
          return Semantics(
            key: ValueKey('venue-cluster-${memberKeys.join('-')}'),
            button: true,
            label: '${markers.length} venues',
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.epColors.brand,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.epColors.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${markers.length}',
                  style: Theme.of(context).textTheme.epLabel.copyWith(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Marker _venueMarker(_VenueGigGroup group) {
    final selected = group.gigs.any((gig) => gig.id == selectedGig?.id);
    return Marker(
      point: group.venue.point,
      width: 48,
      height: 48,
      alignment: Alignment.center,
      child: Semantics(
        key: Key(
          group.gigs.length == 1
              ? 'gig-marker-${group.gigs.single.id}'
              : 'venue-marker-${group.venue.id}',
        ),
        button: true,
        selected: selected,
        label: group.gigs.length == 1
            ? '${group.venue.name}, 1 gig'
            : '${group.venue.name}, ${group.gigs.length} gigs',
        child: _MapPinButton(
          key: ValueKey('map-marker-button-${group.venue.id}'),
          alignment: Alignment.center,
          dimension: selected ? 24 : (group.gigs.length == 1 ? 16 : 26),
          count: group.gigs.length,
          selected: selected,
          onTap: () => onSelect(group.gigs.first),
        ),
      ),
    );
  }
}

/// What the map renders off [AppState]; the pins and camera follow [feed] and
/// [center], the user marker follows [position] and [location].
typedef _MapInputs = ({
  List<Gig> feed,
  LatLng center,
  LatLng? position,
  DiscoveryLocation location,
});

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
  List<Object>? _cameraSignature;
  List<Gig>? _lastFeed;
  LatLng? _lastCenter;
  List<_VenueGigGroup>? _lastGroups;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_VenueGigGroup> _mapGroups(AppState app, List<Gig> gigs) {
    final center = app.discoveryCenter;
    if (identical(gigs, _lastFeed) && center == _lastCenter) {
      return _lastGroups!;
    }

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
    groups.sort((a, b) => a.gigs.length.compareTo(b.gigs.length));
    _lastFeed = gigs;
    _lastCenter = center;
    _lastGroups = groups;
    return groups;
  }

  void _updateCamera(AppState app, List<_VenueGigGroup> groups) {
    final center = app.discoveryCenter;
    final cameraSignature = <Object>[
      (center.latitude * 100000).round(),
      (center.longitude * 100000).round(),
      for (final group in groups) ...[
        group.venue.id,
        (group.venue.point.latitude * 100000).round(),
        (group.venue.point.longitude * 100000).round(),
        for (final gig in group.gigs) gig.id,
      ],
    ];
    if (!_mapReady || listEquals(cameraSignature, _cameraSignature)) return;
    _cameraSignature = cameraSignature;

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
    final app = context.read<AppState>();
    final view = context.select<AppState, _MapInputs>(
      (app) => (
        feed: app.feed,
        center: app.discoveryCenter,
        position: app.currentPosition,
        location: app.discoveryLocation,
      ),
    );
    final gigs = view.feed;
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
    _updateCamera(app, groups);

    return Stack(
      children: [
        EpMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: view.center,
            initialZoom: 13,
            backgroundColor: context.epColors.background,
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
          layers: [
            MarkerLayer(
              markers: [
                if (view.position case final position?)
                  if (view.location == DiscoveryLocation.current)
                    Marker(
                      key: const Key('current-location-marker'),
                      point: position,
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: const Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: _UserPin(),
                        ),
                      ),
                    ),
              ],
            ),
            _VenueMarkerLayer(
              groups: groups,
              selectedGig: selected,
              onSelect: (gig) => setState(() => selected = gig),
            ),
          ],
        ),
        if (gigs.isEmpty && widget.emptyState != null)
          Positioned(left: 18, right: 18, top: 34, child: widget.emptyState!),
        if (selected case final Gig g when selectedGroup != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: tabBarClearance + 10,
            child: TapRegion(
              onTapOutside: (_) => setState(() => selected = null),
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
      key: ValueKey('map-gig-card-${gig.id}'),
      variant: EpCardVariant.raised,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      radius: 14,
      onTap: onOpen,
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
              FilledButton(onPressed: onOpen, child: Text('OPEN GIG →')),
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
    final button = IconButton(
      onPressed: onTap,
      style: const ButtonStyle(
        fixedSize: WidgetStatePropertyAll(Size.square(48)),
      ),
      icon: Icon(icon, size: 20),
    );
    if (onTap != null) return button;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: button,
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
      child: EpMap(
        options: MapOptions(
          initialCenter: venue.point,
          initialZoom: 15,
          backgroundColor: context.epColors.background,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        layers: [
          MarkerLayer(
            markers: [
              Marker(
                point: venue.point,
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: const Center(
                  child: SizedBox.square(dimension: 16, child: _Pin()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
