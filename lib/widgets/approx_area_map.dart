import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'ep_map.dart';

/// Builds the area ring shared by approximate venue maps.
Widget approxAreaRingLayer(LatLng centroid, double radiusMeters) {
  return CircleLayer(
    circles: [
      CircleMarker(
        point: centroid,
        radius: radiusMeters,
        useRadiusInMeter: true,
        color: Ep.brand.withValues(alpha: .18),
        borderStrokeWidth: 1.5,
        borderColor: Ep.brand,
      ),
    ],
  );
}

class ApproxAreaMap extends StatelessWidget {
  const ApproxAreaMap({
    super.key,
    required this.centroid,
    this.radiusMeters = 600,
    this.label,
    this.height = 160,
  });

  final LatLng centroid;
  final double radiusMeters;
  final String? label;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: EpMap(
              options: MapOptions(
                initialCenter: centroid,
                initialZoom: 13,
                backgroundColor: context.epColors.background,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              layers: [approxAreaRingLayer(centroid, radiusMeters)],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label ?? 'Approximate area',
          style: epText(size: 11, color: context.epColors.contentDisabled),
        ),
      ],
    );
  }
}
