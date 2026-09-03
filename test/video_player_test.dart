import 'package:earplug/widgets/video_player_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_video_player_platform.dart';
import 'support/fixtures.dart';

void main() {
  late VideoPlayerPlatform originalPlatform;
  late FakeVideoPlayerPlatform fakePlatform;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
    fakePlatform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
  });

  testWidgets('video tap toggles playback without a visible play button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBandVideo(
              context,
              media: videoMediaFixture(title: 'Clip title', views: 1200),
              bandName: 'Test Band',
            ),
            child: const Text('OPEN'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('full-screen-cover-video')), findsOneWidget);
    expect(find.byKey(const Key('center-play-pause')), findsNothing);
    expect(find.byTooltip('Play'), findsNothing);
    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.byKey(const Key('video-progress-slider')), findsOneWidget);
    expect(find.text('TEST BAND'), findsOneWidget);
    expect(find.text('Clip title'), findsOneWidget);
    expect(fakePlatform.calls, contains('setVolume:1.0'));
    expect(fakePlatform.calls, contains('play'));

    final progressTarget = tester.getSize(
      find.byKey(const Key('video-progress-touch-target')),
    );
    expect(progressTarget, const Size(400, 44));
    final progressLine = tester.getRect(
      find.byKey(const Key('video-progress-line')),
    );
    expect(progressLine.height, 2);
    expect(progressLine.bottom, 700);

    await tester.pump(const Duration(seconds: 2));
    final hidden = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('video-controls-overlay')),
    );
    expect(hidden.opacity, 0);
    expect(find.byKey(const Key('video-progress-slider')), findsOneWidget);

    await tester.tapAt(const Offset(30, 350));
    await tester.pump();
    expect(fakePlatform.calls.last, 'pause');
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('video-controls-overlay')),
          )
          .opacity,
      1,
    );

    await tester.tapAt(const Offset(30, 350));
    await tester.pump();
    expect(fakePlatform.calls.last, 'play');

    await tester.pump(const Duration(seconds: 2));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('video-controls-overlay')),
          )
          .opacity,
      0,
    );

    final seekCount = fakePlatform.seekTargets.length;
    await tester.tapAt(const Offset(300, 699));
    await tester.pump();
    expect(fakePlatform.seekTargets.length, greaterThan(seekCount));
    expect(
      fakePlatform.seekTargets.last,
      greaterThan(const Duration(seconds: 15)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(fakePlatform.calls.last, 'pause');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      fakePlatform.seekTargets.last,
      greaterThan(const Duration(seconds: 20)),
    );

    fakePlatform.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Replay'), findsNothing);
    await tester.tapAt(const Offset(30, 350));
    await tester.pump();
    expect(fakePlatform.seekTargets, contains(Duration.zero));
    expect(fakePlatform.calls.last, 'play');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('OPEN'), findsOneWidget);
  });

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
