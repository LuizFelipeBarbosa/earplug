import 'package:earplug/widgets/video_player_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video sizing covers landscape, square, and portrait viewports', () {
    const available = Size(400, 500);
    for (final ratio in [16 / 9, 1.0, 9 / 16]) {
      final size = coverVideoSize(
        viewport: available,
        video: Size(100 * ratio, 100),
      );
      expect(size.width, greaterThanOrEqualTo(available.width));
      expect(size.height, greaterThanOrEqualTo(available.height));
      expect(size.width / size.height, closeTo(ratio, 0.001));
    }
  });

  test('progress control is 40 percent with 120 to 220 pixel bounds', () {
    expect(playerProgressWidth(200), 120);
    expect(playerProgressWidth(400), 160);
    expect(playerProgressWidth(800), 220);
  });
}
