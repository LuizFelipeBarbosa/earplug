import 'dart:typed_data';

import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

void main() {
  group('BandMediaController', () {
    test('mediaFor starts empty and populates after its lazy load', () async {
      final harness = _makeController();
      const bandId = 'b1';

      expect(harness.controller.mediaFor(bandId), isEmpty);
      expect(harness.controller.isLoading(bandId), isTrue);

      await _waitForLoad(harness.controller, bandId);

      expect(harness.controller.mediaFor(bandId), isNotEmpty);
      expect(harness.controller.isLoading(bandId), isFalse);
      expect(harness.controller.loadErrorFor(bandId), isNull);
    });

    test('video upload advances phases, lands, and auto-pins', () async {
      final harness = _makeController();
      const bandId = 'fresh-band';
      harness.picker.nextVideo = videoFixture();
      final phases = <MediaUploadPhase>[];
      harness.controller.addListener(() {
        final uploads = harness.controller.uploadsFor(bandId);
        if (uploads.isNotEmpty) phases.add(uploads.single.phase);
      });

      await harness.controller.pickAndUploadVideo(bandId);

      expect(
        phases,
        containsAllInOrder([
          MediaUploadPhase.preparing,
          MediaUploadPhase.saving,
          MediaUploadPhase.done,
        ]),
      );
      expect(harness.controller.uploadsFor(bandId), isEmpty);
      final video = harness.controller.videosFor(bandId).single;
      expect(video.title, 'RIPTIDE LIVE');
      expect(video.pinned, isTrue);
      expect(harness.controller.pinnedVideoFor(bandId)?.id, video.id);
      expect(harness.said, isEmpty);
    });

    test('failed upload retains its payload and can be retried', () async {
      final repository = HttpUploadDemoRepository();
      var shouldFail = true;
      var postCalls = 0;
      Future<String> poster(
        Uri url,
        Uint8List bytes,
        String contentType,
      ) async {
        postCalls++;
        if (shouldFail) throw Exception('simulated upload failure');
        return 'st_fake';
      }

      final harness = _makeController(
        repository: repository,
        uploader: MediaUploadService(repository: repository, post: poster),
      );
      const bandId = 'retry-band';
      final fixture = videoFixture();
      harness.picker.nextVideo = fixture;

      await harness.controller.pickAndUploadVideo(bandId);

      final failed = harness.controller.uploadsFor(bandId).single;
      expect(failed.phase, MediaUploadPhase.failed);
      expect(failed.error, contains('simulated upload failure'));
      expect(identical(failed.payload, fixture), isTrue);
      expect(postCalls, 1);

      shouldFail = false;
      await harness.controller.retryUpload(failed.id);

      expect(postCalls, 2);
      expect(harness.controller.uploadsFor(bandId), isEmpty);
      expect(harness.controller.videosFor(bandId).map((media) => media.title), [
        'RIPTIDE LIVE',
      ]);
    });

    test('cancelled video and photo pickers stay silent', () async {
      final harness = _makeController();
      const bandId = 'cancel-band';

      await harness.controller.pickAndUploadVideo(bandId);
      await harness.controller.pickAndUploadPhotos(bandId);

      expect(harness.picker.videoCalls, 1);
      expect(harness.picker.photoListCalls, 1);
      expect(harness.controller.uploadsFor(bandId), isEmpty);
      expect(harness.said, isEmpty);
    });

    test(
      'oversized photos are skipped without losing accepted photos',
      () async {
        final harness = _makeController();
        const bandId = 'photo-batch-band';
        harness.picker.nextPhotos = [stubPhotoFixture()];
        harness.picker.nextOversized = ['too-large.jpg', 'also-too-large.png'];

        await harness.controller.pickAndUploadPhotos(bandId);

        expect(harness.said, [
          '2 photos were over 8 MB — export smaller and retry.',
        ]);
        expect(harness.controller.photosFor(bandId), hasLength(1));
      },
    );

    test(
      'picker validation errors are said without creating an upload',
      () async {
        final harness = _makeController();
        const bandId = 'invalid-band';
        harness.picker.nextException = const MediaPickException(
          "That file type won't play everywhere — export as MP4.",
        );

        await harness.controller.pickAndUploadVideo(bandId);

        expect(harness.picker.videoCalls, 1);
        expect(harness.controller.uploadsFor(bandId), isEmpty);
        expect(harness.said, [
          "That file type won't play everywhere — export as MP4.",
        ]);
      },
    );

    test('pin, move, remove, and hero changes refresh the cache', () async {
      final harness = _makeController();
      const bandId = 'b1';
      await harness.controller.refresh(bandId);

      await harness.controller.pin(bandId, 'bm2');
      expect(harness.controller.pinnedVideoFor(bandId)?.id, 'bm2');
      expect(
        harness.controller.videosFor(bandId).where((media) => media.pinned),
        hasLength(1),
      );

      await harness.controller.move(bandId, 'bm2', 'down');
      expect(harness.controller.videosFor(bandId).map((media) => media.id), [
        'bm1',
        'bm3',
        'bm2',
        'bm4',
        'bm5',
      ]);

      await harness.controller.remove(bandId, 'bm3');
      expect(harness.controller.videosFor(bandId).map((media) => media.id), [
        'bm1',
        'bm2',
        'bm4',
        'bm5',
      ]);

      await harness.controller.setHero(bandId, 'bm7');
      expect(
        harness.controller
            .photosFor(bandId)
            .singleWhere((media) => media.isHero)
            .id,
        'bm7',
      );
      await harness.controller.clearHero(bandId);
      expect(
        harness.controller.photosFor(bandId).any((media) => media.isHero),
        isFalse,
      );
      expect(harness.said, isEmpty);
    });

    test('clearForSignOut clears caches and uploads and notifies', () async {
      final repository = HttpUploadDemoRepository();
      final harness = _makeController(
        repository: repository,
        uploader: MediaUploadService(
          repository: repository,
          post: (url, bytes, contentType) async {
            throw Exception('leave this upload failed');
          },
        ),
      );
      const bandId = 'b1';
      await harness.controller.refresh(bandId);
      expect(harness.controller.mediaFor(bandId), isNotEmpty);

      harness.picker.nextVideo = videoFixture();
      await harness.controller.pickAndUploadVideo(bandId);
      expect(harness.controller.uploadsFor(bandId), hasLength(1));

      var notifications = 0;
      harness.controller.addListener(() => notifications++);
      harness.controller.clearForSignOut();

      expect(notifications, 1);
      expect(harness.controller.uploadsFor(bandId), isEmpty);
      expect(harness.controller.loadErrorFor(bandId), isNull);
      expect(harness.controller.mediaFor(bandId), isEmpty);
      expect(harness.controller.isLoading(bandId), isTrue);

      await _waitForLoad(harness.controller, bandId);
      expect(harness.controller.mediaFor(bandId), isNotEmpty);
    });
  });
}

Future<void> _waitForLoad(BandMediaController controller, String bandId) async {
  for (
    var attempt = 0;
    attempt < 10 && controller.isLoading(bandId);
    attempt++
  ) {
    await Future<void>.delayed(Duration.zero);
  }
}

({BandMediaController controller, FakeMediaPicker picker, List<String> said})
_makeController({EarplugRepository? repository, MediaUploadService? uploader}) {
  final resolvedRepository =
      repository ?? DemoRepository(auth: FakeAuthService());
  final picker = FakeMediaPicker();
  final said = <String>[];
  final controller = BandMediaController(
    repository: resolvedRepository,
    picker: picker,
    uploader: uploader,
    say: said.add,
  );
  addTearDown(controller.dispose);
  return (controller: controller, picker: picker, said: said);
}
