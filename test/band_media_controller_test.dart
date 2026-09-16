import 'dart:typed_data';

import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/errors.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';
import 'support/stub_repository.dart';

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
        uploader: MediaUploadService(
          repository: repository,
          post: poster,
          thumbnailGenerator: FakeVideoThumbnailGenerator(),
        ),
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

      expect(postCalls, 3);
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
          '2 photos were over 8 MB. Export smaller files and retry.',
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
          "That file type won't play everywhere. Export it as MP4.",
        );

        await harness.controller.pickAndUploadVideo(bandId);

        expect(harness.picker.videoCalls, 1);
        expect(harness.controller.uploadsFor(bandId), isEmpty);
        expect(harness.said, [
          "That file type won't play everywhere. Export it as MP4.",
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

      expect(await harness.controller.setAvatar(bandId, 'bm6'), isTrue);
      expect(await harness.controller.setBanner(bandId, 'bm7'), isTrue);
      expect(
        harness.controller
            .photosFor(bandId)
            .singleWhere((media) => media.isHero)
            .id,
        'bm7',
      );
      expect(
        harness.controller
            .photosFor(bandId)
            .singleWhere((media) => media.isAvatar)
            .id,
        'bm6',
      );
      expect(await harness.controller.clearBanner(bandId), isTrue);
      expect(
        harness.controller.photosFor(bandId).any((media) => media.isHero),
        isFalse,
      );
      expect(
        harness.controller.photosFor(bandId).any((media) => media.isAvatar),
        isTrue,
      );
      expect(await harness.controller.clearAvatar(bandId), isTrue);
      expect(harness.said, isEmpty);
    });

    test('section ordering crosses globally interposed media', () async {
      final repository = _GlobalOrderDemoRepository(auth: FakeAuthService());
      final harness = _makeController(repository: repository);
      const bandId = 'b1';
      await harness.controller.refresh(bandId);

      await harness.controller.moveWithinKind(bandId, 'video-1', 'down');

      expect(repository.moveCalls, 1);
      expect(harness.controller.videosFor(bandId).map((item) => item.id), [
        'video-2',
        'video-1',
      ]);
      expect(harness.controller.photosFor(bandId).single.id, 'photo-1');
    });

    test(
      'reorder updates the global cache before the mutation completes',
      () async {
        final repository = StubRepository(auth: FakeAuthService());
        final harness = _makeController(repository: repository);
        const bandId = 'b1';
        await harness.controller.refresh(bandId);
        final previous = harness.controller.mediaFor(bandId);
        final expected = previous.map((item) => item.id).toList();
        final movedId = expected.removeLast();
        expected.insert(1, movedId);
        // Populate both derived caches before changing the global order.
        harness.controller.videosFor(bandId);
        harness.controller.photosFor(bandId);
        final gate = repository.gate('reorderMedia');

        final pending = harness.controller.reorder(bandId, movedId, 1);

        expect(repository.callsTo('reorderMedia'), 1);
        expect(repository.callsTo('mediaFor'), 1);
        expect(
          harness.controller.mediaFor(bandId).map((item) => item.id),
          expected,
        );
        expect(
          (await repository.mediaFor(bandId)).map((item) => item.id),
          previous.map((item) => item.id),
        );

        gate.complete();
        await pending;

        final actual = harness.controller.mediaFor(bandId);
        expect(actual.map((item) => item.id), expected);
        expect(
          harness.controller.videosFor(bandId).map((item) => item.id),
          actual.where((item) => item.isVideo).map((item) => item.id),
        );
        expect(
          harness.controller.photosFor(bandId).map((item) => item.id),
          actual.where((item) => !item.isVideo).map((item) => item.id),
        );
        expect(harness.said, isEmpty);
      },
    );

    test('reorder rolls back on failure before refreshing the cache', () async {
      final repository = StubRepository(auth: FakeAuthService());
      final harness = _makeController(repository: repository);
      const bandId = 'b1';
      await harness.controller.refresh(bandId);
      final previous = harness.controller.mediaFor(bandId);
      final reorderGate = repository.gate('reorderMedia');
      final refreshGate = repository.gate('mediaFor');
      repository.fail('reorderMedia');

      final pending = harness.controller.reorder(bandId, previous.last.id, 0);
      expect(harness.controller.mediaFor(bandId).first.id, previous.last.id);
      reorderGate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(harness.controller.mediaFor(bandId), same(previous));
      expect(harness.said, [genericErrorMessage]);
      expect(repository.callsTo('mediaFor'), 2);
      refreshGate.complete();
      await pending;

      expect(
        harness.controller.mediaFor(bandId).map((item) => item.id),
        previous.map((item) => item.id),
      );
      expect(harness.said, [genericErrorMessage]);
    });

    test('reorder ignores an unloaded band or an unknown media id', () async {
      final repository = StubRepository(auth: FakeAuthService());
      final harness = _makeController(repository: repository);
      const bandId = 'b1';

      await harness.controller.reorder(bandId, 'bm1', 1);
      expect(repository.callsTo('mediaFor'), 0);
      await harness.controller.refresh(bandId);
      final previous = harness.controller.mediaFor(bandId);
      await harness.controller.reorder(bandId, 'missing', 1);

      expect(repository.callsTo('reorderMedia'), 0);
      expect(repository.callsTo('mediaFor'), 1);
      expect(harness.controller.mediaFor(bandId), same(previous));
      expect(harness.said, isEmpty);
    });

    for (final toIndex in [-100, 100]) {
      test(
        'reorder clamps destination $toIndex optimistically and finally',
        () async {
          final repository = StubRepository(auth: FakeAuthService());
          final harness = _makeController(repository: repository);
          const bandId = 'b1';
          await harness.controller.refresh(bandId);
          final previous = harness.controller.mediaFor(bandId);
          final moved = previous[previous.length ~/ 2];
          final destination = toIndex < 0 ? 0 : previous.length - 1;
          final gate = repository.gate('reorderMedia');

          final pending = harness.controller.reorder(bandId, moved.id, toIndex);
          expect(harness.controller.mediaFor(bandId)[destination].id, moved.id);
          gate.complete();
          await pending;

          expect(harness.controller.mediaFor(bandId)[destination].id, moved.id);
          expect(harness.said, isEmpty);
        },
      );
    }

    test('moveToFront moves an item to the front of the global list', () async {
      final harness = _makeController();
      const bandId = 'b1';
      await harness.controller.refresh(bandId);
      final moved = harness.controller.mediaFor(bandId).last;

      await harness.controller.moveToFront(bandId, moved.id);

      expect(harness.controller.mediaFor(bandId).first.id, moved.id);
      expect(harness.said, isEmpty);
    });

    test('replace keeps the global position and pin of a video', () async {
      final repository = StubRepository(auth: FakeAuthService());
      final harness = _makeController(repository: repository);
      const bandId = 'b1';
      await repository.pinBandMedia('bm2');
      await harness.controller.refresh(bandId);
      final previous = harness.controller.mediaFor(bandId);
      final old = harness.controller.pinnedVideoFor(bandId)!;
      final index = previous.indexWhere((item) => item.id == old.id);
      expect(index, greaterThan(0));
      expect(previous.take(index).any((item) => !item.isVideo), isTrue);
      harness.picker.nextVideo = videoFixture(filename: 'replacement.mp4');
      final phases = <MediaUploadPhase>[];
      harness.controller.addListener(() {
        final uploads = harness.controller.uploadsFor(bandId);
        if (uploads.isNotEmpty) phases.add(uploads.single.phase);
      });

      await harness.controller.replace(bandId, old.id);

      final current = harness.controller.mediaFor(bandId);
      final replacement = current[index];
      expect(current, hasLength(previous.length));
      expect(current.any((item) => item.id == old.id), isFalse);
      expect(previous.any((item) => item.id == replacement.id), isFalse);
      expect(replacement.title, 'REPLACEMENT');
      expect(replacement.kind, MediaKind.video);
      expect(replacement.pinned, isTrue);
      expect(current.where((item) => item.pinned), hasLength(1));
      expect(harness.controller.pinnedVideoFor(bandId)?.id, replacement.id);
      expect(
        phases,
        containsAllInOrder([
          MediaUploadPhase.preparing,
          MediaUploadPhase.saving,
          MediaUploadPhase.done,
        ]),
      );
      expect(harness.controller.uploadsFor(bandId), isEmpty);
      expect(repository.callsTo('addBandMedia'), 1);
      expect(repository.callsTo('reorderMedia'), 1);
      expect(repository.callsTo('mediaFor'), 3);
      expect(harness.picker.videoCalls, 1);
      expect(harness.picker.photoCalls, 0);
      expect(harness.said, isEmpty);
    });

    test(
      'replace uses the single-photo picker and keeps its global position',
      () async {
        final harness = _makeController();
        const bandId = 'b1';
        await harness.controller.refresh(bandId);
        final previous = harness.controller.mediaFor(bandId);
        final old = harness.controller.photosFor(bandId).first;
        final index = previous.indexWhere((item) => item.id == old.id);
        harness.picker.nextPhoto = stubPhotoFixture(
          filename: 'replacement.jpg',
        );

        await harness.controller.replace(bandId, old.id);

        final current = harness.controller.mediaFor(bandId);
        expect(current, hasLength(previous.length));
        expect(current.any((item) => item.id == old.id), isFalse);
        expect(current[index].title, 'REPLACEMENT');
        expect(current[index].kind, MediaKind.photo);
        expect(harness.picker.photoCalls, 1);
        expect(harness.picker.photoListCalls, 0);
        expect(harness.picker.videoCalls, 0);
        expect(harness.said, isEmpty);
      },
    );

    for (final kind in MediaKind.values) {
      test(
        'cancelled ${kind.name} replacement leaves media and uploads unchanged',
        () async {
          final repository = StubRepository(auth: FakeAuthService());
          final harness = _makeController(repository: repository);
          const bandId = 'b1';
          await harness.controller.refresh(bandId);
          final previous = harness.controller.mediaFor(bandId);
          final old = previous.firstWhere((item) => item.kind == kind);
          var notifications = 0;
          harness.controller.addListener(() => notifications++);

          await harness.controller.replace(bandId, old.id);

          expect(harness.controller.mediaFor(bandId), same(previous));
          expect(harness.controller.uploadsFor(bandId), isEmpty);
          expect(repository.callsTo('addBandMedia'), 0);
          expect(repository.callsTo('reorderMedia'), 0);
          expect(repository.callsTo('mediaFor'), 1);
          expect(harness.picker.videoCalls, kind == MediaKind.video ? 1 : 0);
          expect(harness.picker.photoCalls, kind == MediaKind.photo ? 1 : 0);
          expect(notifications, 0);
          expect(harness.said, isEmpty);
        },
      );
    }

    test(
      'replacement upload failure retains the original media and pin',
      () async {
        final repository = StubRepository(auth: FakeAuthService())
          ..fail('addBandMedia');
        final harness = _makeController(repository: repository);
        const bandId = 'b1';
        await harness.controller.refresh(bandId);
        final previous = harness.controller.mediaFor(bandId);
        final old = harness.controller.pinnedVideoFor(bandId)!;
        harness.picker.nextVideo = videoFixture();

        await harness.controller.replace(bandId, old.id);

        expect(harness.controller.mediaFor(bandId), same(previous));
        expect(harness.controller.pinnedVideoFor(bandId)?.id, old.id);
        expect(
          harness.controller.uploadsFor(bandId).single.phase,
          MediaUploadPhase.failed,
        );
        expect(
          harness.controller.uploadsFor(bandId).single.error,
          contains('addBandMedia failed'),
        );
        expect(repository.callsTo('reorderMedia'), 0);
        expect(harness.said, isEmpty);
      },
    );

    test(
      'replacement reorder failure retains the original and reports the error',
      () async {
        final repository = StubRepository(auth: FakeAuthService())
          ..fail('reorderMedia');
        final harness = _makeController(repository: repository);
        const bandId = 'b1';
        await harness.controller.refresh(bandId);
        final old = harness.controller.pinnedVideoFor(bandId)!;
        harness.picker.nextVideo = videoFixture();

        await harness.controller.replace(bandId, old.id);

        expect(
          harness.controller.mediaFor(bandId).any((item) => item.id == old.id),
          isTrue,
        );
        expect(harness.controller.pinnedVideoFor(bandId)?.id, old.id);
        expect(repository.callsTo('mediaFor'), 3);
        expect(harness.said, [genericErrorMessage]);
      },
    );

    test('clearForSignOut clears caches and uploads and notifies', () async {
      final repository = HttpUploadDemoRepository();
      final harness = _makeController(
        repository: repository,
        uploader: MediaUploadService(
          repository: repository,
          thumbnailGenerator: FakeVideoThumbnailGenerator(),
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

  test(
    'DemoRepository reorder densely ranks both kinds in one global order',
    () async {
      final repository = DemoRepository(auth: FakeAuthService());
      const bandId = 'b1';
      await repository.setBandAvatar(bandId: bandId, mediaId: 'bm6');
      await repository.setBandBanner(bandId: bandId, mediaId: 'bm7');
      final previous = await repository.mediaFor(bandId);
      final expected = previous.map((item) => item.id).toList();
      final movedId = expected.removeLast();
      expected.insert(2, movedId);

      await repository.reorderMedia(
        bandId: bandId,
        mediaId: movedId,
        toIndex: 2,
      );

      final current = await repository.mediaFor(bandId);
      expect(
        current.map((item) => item.kind).toSet(),
        MediaKind.values.toSet(),
      );
      expect(current.map((item) => item.id), expected);
      expect(
        current.map((item) => item.order),
        List<int>.generate(current.length, (index) => index),
      );
      for (final item in current) {
        final old = previous.singleWhere(
          (candidate) => candidate.id == item.id,
        );
        expect(
          (item.pinned, item.isHero, item.isAvatar, item.isBanner),
          (old.pinned, old.isHero, old.isAvatar, old.isBanner),
        );
      }
    },
  );
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
  final resolvedUploader =
      uploader ??
      MediaUploadService(
        repository: resolvedRepository,
        thumbnailGenerator: FakeVideoThumbnailGenerator(),
      );
  final controller = BandMediaController(
    repository: resolvedRepository,
    picker: picker,
    uploader: resolvedUploader,
    say: said.add,
  );
  addTearDown(controller.dispose);
  return (controller: controller, picker: picker, said: said);
}

class _GlobalOrderDemoRepository extends DemoRepository {
  _GlobalOrderDemoRepository({required super.auth});

  var moveCalls = 0;
  final _items = <BandMedia>[
    _media('video-1', MediaKind.video, 0),
    _media('photo-1', MediaKind.photo, 1),
    _media('video-2', MediaKind.video, 2),
  ];

  @override
  Future<List<BandMedia>> mediaFor(String bandId) async {
    return List<BandMedia>.of(_items)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Future<void> moveMediaWithinKind(String mediaId, String direction) async {
    moveCalls++;
    _items.sort((a, b) => a.order.compareTo(b.order));
    final target = _items.firstWhere((item) => item.id == mediaId);
    final sameKind = _items.where((item) => item.kind == target.kind).toList();
    final index = sameKind.indexWhere((item) => item.id == mediaId);
    final neighborIndex = direction == 'earlier' ? index - 1 : index + 1;
    if (neighborIndex < 0 || neighborIndex >= sameKind.length) return;
    final neighbor = sameKind[neighborIndex];
    final targetOrder = target.order;
    final neighborOrder = neighbor.order;
    _items[_items.indexWhere((item) => item.id == target.id)] = target.copyWith(
      order: neighborOrder,
    );
    _items[_items.indexWhere((item) => item.id == neighbor.id)] = neighbor
        .copyWith(order: targetOrder);
  }
}

BandMedia _media(String id, MediaKind kind, int order) => BandMedia(
  id: id,
  bandId: 'b1',
  kind: kind,
  url: null,
  title: id,
  caption: null,
  sizeBytes: null,
  views: null,
  lengthSec: null,
  pinned: id == 'video-1',
  order: order,
  isHero: false,
);
