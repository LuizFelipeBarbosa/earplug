import 'dart:async';

import 'package:earplug/data/demo_repository.dart';
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

void main() {
  testWidgets('focuses on videos and gallery photos with no artwork controls', (
    tester,
  ) async {
    await _pumpBandMedia(tester);
    tester.view.physicalSize = const Size(402, 3600);
    await tester.pumpAndSettle();

    expect(find.text('UPLOAD VIDEO'), findsOne);
    expect(find.text('UPLOAD PHOTOS'), findsOne);
    expect(find.text('THIS IS WHAT WE SOUND LIKE · 5'), findsOne);
    expect(find.text('GALLERY PHOTOS · 2'), findsOne);
    expect(find.text('PROFILE BANNER'), findsNothing);
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
    expect(find.text('FEATURED FIRST'), findsOne);
    expect(find.text('PROCESSING'), findsNWidgets(7));
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

      expect(find.text('BAND MEDIA'), findsOne);
      expect(find.textContaining('ITEMS'), findsOne);
      expect(find.text('UPLOAD VIDEO'), findsOne);
      expect(find.text('UPLOAD PHOTOS'), findsOne);
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
      repository: _EmptyMediaDemoRepository(auth: auth),
    );
    tester.view.physicalSize = const Size(402, 1800);
    await tester.pumpAndSettle();

    expect(find.text('NO VIDEOS YET'), findsOne);
    expect(find.text('NO GALLERY PHOTOS YET'), findsOne);
    expect(find.text('UPLOAD A MUSIC CLIP'), findsOne);
    expect(find.text('UPLOAD PHOTOS'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an in-flight upload and then its new video card', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _GatedSaveDemoRepository(auth: auth);
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: repository,
    );
    harness.picker.nextVideo = videoFixture();

    await tester.tap(find.text('UPLOAD VIDEO'));
    await tester.pump();

    expect(find.text('UPLOADS · 1'), findsOne);
    expect(find.text('riptide_live.mp4'), findsOne);
    expect(find.text('SAVING'), findsOne);

    repository.saveGate.complete();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('RIPTIDE LIVE'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('RIPTIDE LIVE'), findsOne);
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

    await tester.tap(find.text('UPLOAD VIDEO'));
    await tester.pumpAndSettle();

    expect(find.text('UPLOAD FAILED'), findsOne);
    expect(find.text('RETRY'), findsOne);
    expect(find.text('DISCARD'), findsOne);
    expect(find.textContaining('simulated upload failure'), findsOne);

    await tester.tap(find.text('DISCARD'));
    await tester.pump();

    expect(find.text('riptide_live.mp4'), findsNothing);
    expect(find.text('RETRY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('members can browse media without management actions', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: _MemberDemoRepository(auth: auth),
    );
    tester.view.physicalSize = const Size(402, 3600);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('media-actions-bm1')), findsNothing);
    expect(find.byKey(const ValueKey('media-actions-bm6')), findsNothing);

    final videoUploadCard = tester.widget<EpCard>(
      find.ancestor(
        of: find.text('UPLOAD VIDEO'),
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

    expect(find.text('REMOVE VIDEO?'), findsOne);
    expect(find.text('DELETE'), findsOne);
    expect(find.text('KEEP'), findsOne);
    expect(find.text(title), findsWidgets);

    await tester.tap(find.text('DELETE'));
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

class _EmptyMediaDemoRepository extends DemoRepository {
  _EmptyMediaDemoRepository({required super.auth});

  @override
  Future<List<BandMedia>> mediaFor(String bandId) async => const [];
}

class _MemberDemoRepository extends DemoRepository {
  _MemberDemoRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() async* {
    yield [BandMembership(band: DemoData.bands['b1']!, role: 'member')];
  }
}

class _GatedSaveDemoRepository extends DemoRepository {
  _GatedSaveDemoRepository({required super.auth});

  final saveGate = Completer<void>();

  @override
  Future<String> addBandMedia({
    required String bandId,
    required MediaKind kind,
    required String storageId,
    String? thumbnailStorageId,
    required String title,
    String? caption,
    int? lengthSec,
  }) async {
    await saveGate.future;
    return super.addBandMedia(
      bandId: bandId,
      kind: kind,
      storageId: storageId,
      thumbnailStorageId: thumbnailStorageId,
      title: title,
      caption: caption,
      lengthSec: lengthSec,
    );
  }
}
