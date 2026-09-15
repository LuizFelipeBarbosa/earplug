import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../theme.dart';
import 'ep_map.dart';

class VenueMapPreview extends StatelessWidget {
  const VenueMapPreview({
    super.key,
    required this.venue,
    this.height,
    this.overlayLabel,
  });

  final Venue venue;
  final double? height;
  final String? overlayLabel;

  @override
  Widget build(BuildContext context) {
    final LatLng point = venue.point;

    return ClipRect(
      child: SizedBox(
        height: height ?? 160,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Let the venue card handle taps instead of the map's recognizer.
            AbsorbPointer(
              child: EpMap(
                tiles: EpMapTiles.raster,
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 15,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                  backgroundColor: context.epColors.background,
                ),
                layers: [
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: const Center(child: _VenueDot()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (overlayLabel != null && overlayLabel!.isNotEmpty)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  key: const Key('venue-map-overlay'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: context.epColors.background,
                  child: Text(
                    overlayLabel!,
                    style: Theme.of(context).textTheme.epLabel.copyWith(
                      fontSize: 11,
                      color: context.epColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VenueDot extends StatelessWidget {
  const _VenueDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 16,
      child: Container(
        decoration: BoxDecoration(
          color: context.epColors.accent,
          shape: BoxShape.circle,
          border: Border.all(color: context.epColors.panel, width: 2),
        ),
      ),
    );
  }
}
