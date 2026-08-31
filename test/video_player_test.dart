import 'package:earplug/models.dart';
import 'package:earplug/widgets/video_player_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_video_player_platform.dart';

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

  testWidgets('player autoplays edge-to-edge with centered overlay controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showBandVideo(context, media: _media(), bandName: 'Test Band'),
            child: const Text('OPEN'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('full-screen-cover-video')), findsOneWidget);
    expect(find.byKey(const Key('center-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('video-progress-slider')), findsOneWidget);
    expect(find.text('TEST BAND'), findsOneWidget);
    expect(find.text('Clip title'), findsOneWidget);
    expect(fakePlatform.calls, contains('setVolume:1.0'));
    expect(fakePlatform.calls, contains('play'));

    final progressTarget = tester.getSize(
      find.byKey(const Key('video-progress-touch-target')),
    );
    expect(progressTarget, const Size(160, 44));

    await tester.pump(const Duration(seconds: 2));
    final hidden = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('video-controls-overlay')),
    );
    expect(hidden.opacity, 0);

    await tester.tapAt(const Offset(30, 350));
    await tester.pump();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('video-controls-overlay')),
          )
          .opacity,
      1,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(fakePlatform.calls.last, 'pause');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(fakePlatform.seekTargets, contains(const Duration(seconds: 5)));

    fakePlatform.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Replay'), findsOneWidget);
    await tester.tap(find.byTooltip('Replay'));
    await tester.pump();
    expect(fakePlatform.seekTargets, contains(Duration.zero));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('OPEN'), findsOneWidget);
  });
}

BandMedia _media() => const BandMedia(
  id: 'm1',
  bandId: 'b1',
  kind: MediaKind.video,
  url: 'https://example.com/video.mp4',
  title: 'Clip title',
  caption: null,
  sizeBytes: 10,
  views: 1200,
  lengthSec: 30,
  pinned: true,
  order: 0,
  isHero: false,
);
