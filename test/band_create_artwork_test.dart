import 'package:earplug/app_state.dart';
import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

void main() {
  test(
    'concurrent avatar and banner uploads stay distinct and complete',
    () async {
      final harness = await _makeArtworkHarness();
      final observedUploadIds = <String>{};
      var maxConcurrentUploads = 0;
      harness.media.addListener(() {
        final uploads = harness.media.uploadsFor(harness.app.bandId);
        observedUploadIds.addAll(uploads.map((upload) => upload.id));
        if (uploads.length > maxConcurrentUploads) {
          maxConcurrentUploads = uploads.length;
        }
      });
      _prepareBand(
        harness.app,
        photo: stubPhotoFixture(filename: 'avatar.jpg'),
        banner: stubPhotoFixture(filename: 'banner.jpg'),
      );

      await harness.app.createBand();
      final createdBandId = harness.app.bandId;
      await _waitUntil(
        () =>
            harness.repository.addBandMediaCalls == 2 &&
            !harness.app.nbPhotoUploading &&
            !harness.app.nbBannerUploading,
      );

      expect(harness.app.nbPhotoError, isNull);
      expect(harness.app.nbBannerError, isNull);
      expect(maxConcurrentUploads, 2);
      expect(observedUploadIds, hasLength(2));
      expect(harness.repository.addedMediaIds, hasLength(2));
      expect(harness.repository.addedMediaIds.toSet(), hasLength(2));
      expect(
        harness.repository.assignedAvatarMediaId,
        isNot(harness.repository.assignedBannerMediaId),
      );

      final media = await harness.repository.mediaFor(createdBandId);
      expect(media.where((item) => item.isAvatar), hasLength(1));
      expect(media.where((item) => item.isBanner), hasLength(1));
    },
  );

  test('assignment retry reuses the uploaded avatar media row', () async {
    final harness = await _makeArtworkHarness(failFirstAvatarAssignment: true);
    _prepareBand(harness.app, photo: stubPhotoFixture(filename: 'avatar.jpg'));

    await harness.app.createBand();
    final createdBandId = harness.app.bandId;
    await _waitUntil(
      () =>
          harness.repository.avatarAttempts.isNotEmpty &&
          !harness.app.nbPhotoUploading &&
          harness.app.nbPhotoError != null,
    );

    expect(harness.app.nbPhotoError, 'assignment failed');
    expect(harness.repository.addBandMediaCalls, 1);
    final uploadedMediaId = harness.repository.addedMediaIds.single;

    await harness.app.retryNbPhoto();

    expect(harness.app.nbPhotoUploading, isFalse);
    expect(harness.app.nbPhotoError, isNull);
    expect(harness.repository.addBandMediaCalls, 1);
    expect(harness.repository.avatarAttempts, hasLength(2));
    expect(
      harness.repository.avatarAttempts.map((attempt) => attempt.mediaId),
      everyElement(uploadedMediaId),
    );
    expect(harness.repository.assignedAvatarMediaId, uploadedMediaId);

    final media = await harness.repository.mediaFor(createdBandId);
    expect(
      media.singleWhere((item) => item.id == uploadedMediaId).isAvatar,
      isTrue,
    );
  });

  test('assignment retry remains anchored to the wizard band', () async {
    final harness = await _makeArtworkHarness(failFirstAvatarAssignment: true);
    _prepareBand(harness.app, photo: stubPhotoFixture(filename: 'avatar.jpg'));

    await harness.app.createBand();
    final wizardBandId = harness.app.bandId;
    await _waitUntil(
      () =>
          harness.repository.avatarAttempts.isNotEmpty &&
          harness.app.nbPhotoError != null,
    );
    expect(wizardBandId, isNot('b1'));

    harness.app.bandId = 'b1';
    await harness.app.retryNbPhoto();

    expect(harness.app.bandId, 'b1');
    expect(harness.app.nbPhotoError, isNull);
    expect(harness.repository.addBandMediaCalls, 1);
    expect(harness.repository.avatarAttempts, hasLength(2));
    expect(
      harness.repository.avatarAttempts.map((attempt) => attempt.bandId),
      everyElement(wizardBandId),
    );
    expect(harness.repository.assignedAvatarBandId, wizardBandId);
  });
}

Future<_ArtworkHarness> _makeArtworkHarness({
  bool failFirstAvatarAssignment = false,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final repository = _ArtworkRepository(
    auth: auth,
    failFirstAvatarAssignment: failFirstAvatarAssignment,
  );
  final uploader = MediaUploadService(
    repository: repository,
    thumbnailGenerator: FakeVideoThumbnailGenerator(),
  );
  final app = AppState(
    repository: repository,
    auth: auth,
    mediaUploadService: uploader,
  );
  final media = BandMediaController(
    repository: repository,
    picker: FakeMediaPicker(),
    uploader: uploader,
    say: app.say,
  );
  app.attachMediaController(media);
  addTearDown(() {
    app.dispose();
    media.dispose();
  });
  await pumpEventQueue();
  return _ArtworkHarness(app: app, media: media, repository: repository);
}

void _prepareBand(
  AppState app, {
  required PickedMedia photo,
  PickedMedia? banner,
}) {
  app.startBandCreate();
  app.setNbName('Artwork Test Band');
  app.toggleNbGenre('punk');
  app.setNbArea('Berkeley');
  app.setNbPhoto(photo);
  app.setNbBanner(banner);
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for band artwork work to settle.');
}

class _ArtworkHarness {
  const _ArtworkHarness({
    required this.app,
    required this.media,
    required this.repository,
  });

  final AppState app;
  final BandMediaController media;
  final _ArtworkRepository repository;
}

class _ArtworkRepository extends DemoRepository {
  _ArtworkRepository({
    required super.auth,
    required this.failFirstAvatarAssignment,
  });

  final bool failFirstAvatarAssignment;
  final Set<String> _failedAvatarBandIds = {};
  int addBandMediaCalls = 0;
  final List<String> addedMediaIds = [];
  final List<({String bandId, String mediaId})> avatarAttempts = [];
  String? assignedAvatarBandId;
  String? assignedAvatarMediaId;
  String? assignedBannerMediaId;

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
    addBandMediaCalls++;
    final mediaId = await super.addBandMedia(
      bandId: bandId,
      kind: kind,
      storageId: storageId,
      thumbnailStorageId: thumbnailStorageId,
      title: title,
      caption: caption,
      lengthSec: lengthSec,
    );
    addedMediaIds.add(mediaId);
    return mediaId;
  }

  @override
  Future<void> setBandAvatar({
    required String bandId,
    required String mediaId,
  }) async {
    avatarAttempts.add((bandId: bandId, mediaId: mediaId));
    if (failFirstAvatarAssignment && _failedAvatarBandIds.add(bandId)) {
      throw Exception('assignment failed');
    }
    await super.setBandAvatar(bandId: bandId, mediaId: mediaId);
    assignedAvatarBandId = bandId;
    assignedAvatarMediaId = mediaId;
  }

  @override
  Future<void> setBandBanner({
    required String bandId,
    required String mediaId,
  }) async {
    await super.setBandBanner(bandId: bandId, mediaId: mediaId);
    assignedBannerMediaId = mediaId;
  }
}
