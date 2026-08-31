import 'package:earplug/models.dart';
import 'package:earplug/widgets/video_thumbnail.dart';
import 'package:flutter/material.dart';
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

  test('thumbnailUrl is parsed from the repository payload', () {
    final media = BandMedia.fromJson({
      '_id': 'm1',
      'bandId': 'b1',
      'kind': 'video',
      'url': 'https://example.com/video.mp4',
      'thumbnailUrl': 'https://example.com/poster.jpg',
      'title': 'Clip',
      'caption': null,
      'sizeBytes': 10,
      'views': 2,
      'lengthSec': 30,
      'pinned': true,
      'order': 0,
      'isHero': false,
    });

    expect(media.thumbnailUrl, 'https://example.com/poster.jpg');
  });

  testWidgets('stored poster is preferred without creating a video player', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 100,
          child: BandVideoThumbnail(
            media: _media(thumbnailUrl: 'https://example.com/poster.jpg'),
            fallback: const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('stored-thumbnail-m1')), findsOneWidget);
    expect(fakePlatform.calls, isNot(contains('create')));
  });

  testWidgets('legacy clip holds a first frame and disposes its controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 100,
          child: BandVideoThumbnail(
            media: _media(),
            fallback: const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('legacy-thumbnail-m1')), findsOneWidget);
    expect(fakePlatform.calls, contains('seekTo'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(fakePlatform.calls, contains('dispose'));
  });
}

BandMedia _media({String? thumbnailUrl}) => BandMedia(
  id: 'm1',
  bandId: 'b1',
  kind: MediaKind.video,
  url: 'https://example.com/video.mp4',
  thumbnailUrl: thumbnailUrl,
  title: 'Clip',
  caption: null,
  sizeBytes: 10,
  views: 2,
  lengthSec: 30,
  pinned: true,
  order: 0,
  isHero: false,
);
