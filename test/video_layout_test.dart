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

  test('progress fraction is bounded to the video duration', () {
    expect(
      videoProgressFraction(
        position: const Duration(seconds: 15),
        duration: const Duration(seconds: 30),
      ),
      .5,
    );
    expect(
      videoProgressFraction(
        position: const Duration(seconds: 40),
        duration: const Duration(seconds: 30),
      ),
      1,
    );
    expect(
      videoProgressFraction(
        position: const Duration(seconds: -5),
        duration: const Duration(seconds: 30),
      ),
      0,
    );
    expect(
      videoProgressFraction(position: Duration.zero, duration: Duration.zero),
      0,
    );
  });
}
