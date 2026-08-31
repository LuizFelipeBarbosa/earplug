import 'package:earplug/widgets/video_player_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video sizing constrains landscape, square, and portrait media', () {
    const available = Size(400, 500);
    for (final ratio in [16 / 9, 1.0, 9 / 16]) {
      final size = constrainedVideoSize(
        available: available,
        aspectRatio: ratio,
      );
      expect(size.width, lessThanOrEqualTo(available.width));
      expect(size.height, lessThanOrEqualTo(available.height - 150));
      expect(size.width / size.height, closeTo(ratio, 0.001));
    }
  });

  test('short layouts reserve a scrollable minimum video region', () {
    final size = constrainedVideoSize(
      available: const Size(400, 220),
      aspectRatio: 16 / 9,
    );
    expect(size.height, 120);
    expect(size.width, closeTo(120 * 16 / 9, 0.001));
  });
}
