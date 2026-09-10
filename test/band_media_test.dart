import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_media.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';
import 'support/ui_test_helpers.dart';

void main() {
  testWidgets('focuses on videos and gallery photos with no artwork controls', (
    tester,
  ) async {
    await _pumpBandMedia(tester);
    tester.view.physicalSize = const Size(402, 3600);
    await tester.pumpAndSettle();

    expect(findUiText('UPLOAD VIDEO'), findsOne);
    expect(findUiText('UPLOAD PHOTOS'), findsOne);
    expect(findUiText('THIS IS WHAT WE SOUND LIKE · 5'), findsOne);
    expect(findUiText('GALLERY PHOTOS · 2'), findsOne);
    expect(findUiText('PROFILE BANNER'), findsNothing);
    expect(find.textContaining('PROFILE IMAGE'), findsNothing);
    expect(find.byKey(const ValueKey('profile-banner-picker')), findsNothing);

    for (final video in DemoData.b1Media.where((item) => item.isVideo)) {
      expect(find.byKey(ValueKey('video-media-${video.id}')), findsOne);
      expect(find.text(video.title), findsOne);
    }
    for (final photo in DemoData.b1Media.where((item) => !item.isVideo)) {
      expect(find.byKey(ValueKey('photo-media-${photo.id}')), findsOne);
    }
    expect(find.byType(BandVideoThumbnail), findsNWidgets(5));
    expect(findUiText('FEATURED FIRST'), findsOne);
    expect(findUiText('PROCESSING'), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'header and upload actions remain usable at increased text scale',
    (tester) async {
      await pumpApp(
        tester,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(402, 900),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(body: BandMediaScreen(bandId: 'b1')),
        ),
      );

      expect(findUiText('BAND MEDIA'), findsOne);
      expect(find.textContaining('ITEMS'), findsOne);
      expect(findUiText('UPLOAD VIDEO'), findsOne);
      expect(findUiText('UPLOAD PHOTOS'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty video and photo sections each explain their next step', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await _pumpBandMedia(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns('mediaFor', const <BandMedia>[]),
    );
    tester.view.physicalSize = const Size(402, 1800);
    await tester.pumpAndSettle();

    expect(findUiText('NO VIDEOS YET'), findsOne);
    expect(findUiText('NO GALLERY PHOTOS YET'), findsOne);
    expect(findUiText('UPLOAD A MUSIC CLIP'), findsOne);
    expect(findUiText('UPLOAD PHOTOS'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an in-flight upload and then its new video card', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth);
    final saveGate = repository.gate('addBandMedia');
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: repository,
    );
    harness.picker.nextVideo = videoFixture();

    await tester.tap(findUiText('UPLOAD VIDEO'));
    await tester.pump();

    expect(findUiText('UPLOADS · 1'), findsOne);
    expect(find.text('riptide_live.mp4'), findsOne);
    expect(findUiText('SAVING'), findsOne);

    saveGate.complete();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      findUiText('RIPTIDE LIVE'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(findUiText('RIPTIDE LIVE'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed uploads keep retry and discard recovery together', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = HttpUploadDemoRepository(auth: auth);
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: repository,
      uploader: MediaUploadService(
        repository: repository,
        thumbnailGenerator: FakeVideoThumbnailGenerator(),
        post: (url, bytes, contentType) async {
          throw Exception('simulated upload failure');
        },
      ),
    );
    harness.picker.nextVideo = videoFixture();

    await tester.tap(findUiText('UPLOAD VIDEO'));
    await tester.pumpAndSettle();

    expect(findUiText('UPLOAD FAILED'), findsOne);
    expect(findUiText('RETRY'), findsOne);
    expect(findUiText('DISCARD'), findsOne);
    expect(find.textContaining('simulated upload failure'), findsOne);

    await tester.tap(findUiText('DISCARD'));
    await tester.pump();

    expect(find.text('riptide_live.mp4'), findsNothing);
    expect(findUiText('RETRY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('members can browse media without management actions', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream<List<BandMembership>>(
          'myBands',
          () => Stream.value([
            BandMembership(band: DemoData.bands['b1']!, role: 'member'),
          ]),
        ),
    );
    tester.view.physicalSize = const Size(402, 3600);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('media-actions-bm1')), findsNothing);
    expect(find.byKey(const ValueKey('media-actions-bm6')), findsNothing);

    final videoUploadCard = tester.widget<EpCard>(
      find.ancestor(
        of: findUiText('UPLOAD VIDEO'),
        matching: find.byType(EpCard),
      ),
    );
    expect(videoUploadCard.variant, EpCardVariant.disabled);
    expect(harness.app.toast, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clip menu makes feature and ordering actions explicit', (
    tester,
  ) async {
    final harness = await _pumpBandMedia(tester);
    tester.view.physicalSize = const Size(402, 2600);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('media-actions-bm2')));
    await tester.pumpAndSettle();

    expect(find.text('Feature first'), findsOne);
    expect(find.text('Move earlier'), findsOne);
    expect(find.text('Move later'), findsOne);
    expect(find.text('Remove video…'), findsOne);

    await tester.tap(find.text('Feature first'));
    await tester.pumpAndSettle();
    expect(harness.media.pinnedVideoFor('b1')?.id, 'bm2');

    await tester.tap(find.byKey(const ValueKey('media-actions-bm2')));
    await tester.pumpAndSettle();
    expect(find.text('Feature first'), findsNothing);
    await tester.tap(find.text('Move later'));
    await tester.pumpAndSettle();
    expect(harness.media.videosFor('b1').map((item) => item.id), [
      'bm1',
      'bm3',
      'bm2',
      'bm4',
      'bm5',
    ]);
  });

  testWidgets('featured clip stays featured until another clip replaces it', (
    tester,
  ) async {
    await _pumpBandMedia(tester);
    tester.view.physicalSize = const Size(402, 2200);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('media-actions-bm1')));
    await tester.pumpAndSettle();

    expect(find.text('Feature first'), findsNothing);
    expect(find.text('Move later'), findsOne);
    expect(find.text('Remove video…'), findsOne);
  });

  testWidgets('photo menu offers ordering without identity-artwork actions', (
    tester,
  ) async {
    await _pumpBandMedia(tester);
    tester.view.physicalSize = const Size(402, 3600);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('media-actions-bm7')));
    await tester.pumpAndSettle();

    expect(find.text('Move earlier'), findsOne);
    expect(find.text('Remove photo…'), findsOne);
    expect(find.text('Use as profile image'), findsNothing);
    expect(find.text('Use as header image'), findsNothing);
    expect(find.byKey(const ValueKey('profile-banner-picker')), findsNothing);
  });

  testWidgets('removal still requires confirmation and removes one item', (
    tester,
  ) async {
    await _pumpBandMedia(tester);
    tester.view.physicalSize = const Size(402, 2200);
    await tester.pumpAndSettle();
    const title = 'This is what we sound like — live at Foghorn Club';

    await tester.tap(find.byKey(const ValueKey('media-actions-bm1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove video…'));
    await tester.pumpAndSettle();

    expect(findUiText('REMOVE VIDEO?'), findsOne);
    expect(findUiText('DELETE'), findsOne);
    expect(findUiText('KEEP'), findsOne);
    expect(find.text(title), findsWidgets);

    await tester.tap(findUiText('DELETE'));
    await tester.pumpAndSettle();

    expect(find.text(title), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<AppHarness> _pumpBandMedia(
  WidgetTester tester, {
  FakeAuthService? auth,
  EarplugRepository? repository,
  MediaUploadService? uploader,
}) => pumpApp(
  tester,
  auth: auth,
  repository: repository,
  uploader: uploader,
  home: const BandMediaScreen(bandId: 'b1'),
);
