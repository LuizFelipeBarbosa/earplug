import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'ep_map.dart';
import 'ep_text.dart';

/// Builds the area ring shared by approximate venue maps: an accent fill at
/// 18% behind a 1.5px accent ring.
Widget approxAreaRingLayer(
  LatLng centroid,
  double radiusMeters, {
  Color accent = Ep.accent,
}) {
  return CircleLayer(
    circles: [
      CircleMarker(
        point: centroid,
        radius: radiusMeters,
        useRadiusInMeter: true,
        color: accent.withValues(alpha: .18),
        borderStrokeWidth: 1.5,
        borderColor: accent,
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
        EpPanel(
          height: height,
          child: EpMap(
            options: MapOptions(
              initialCenter: centroid,
              initialZoom: 13,
              backgroundColor: context.epColors.background,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            layers: [
              approxAreaRingLayer(
                centroid,
                radiusMeters,
                accent: context.epColors.accent,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        EpEyebrow(label ?? 'Approximate area'),
      ],
    );
  }
}
