import 'package:earplug/models.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:earplug/services/video_thumbnail_generator_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

void main() {
  test('video poster is generated before either blob is uploaded', () async {
    final repository = _RecordingMediaRepository();
    final generator = FakeVideoThumbnailGenerator();
    final events = <String>[];
    var uploadCount = 0;
    final service = MediaUploadService(
      repository: repository,
      thumbnailGenerator: generator,
      post: (url, bytes, contentType) async {
        events.add('upload:$contentType');
        uploadCount++;
        return uploadCount == 1 ? 'video-storage' : 'thumbnail-storage';
      },
    );

    final result = await service.upload(
      bandId: 'b1',
      kind: MediaKind.video,
      media: videoFixture(),
      onThumbnailReady: (_) => events.add('poster-ready'),
    );

    expect(result, 'saved-media');
    expect(generator.calls, 1);
    expect(events, ['poster-ready', 'upload:video/mp4', 'upload:image/jpeg']);
    expect(repository.savedStorageId, 'video-storage');
    expect(repository.savedThumbnailStorageId, 'thumbnail-storage');
  });

  test('thumbnail failure uploads nothing and creates no media row', () async {
    final repository = _RecordingMediaRepository();
    var uploadCalls = 0;
    final service = MediaUploadService(
      repository: repository,
      thumbnailGenerator: FakeVideoThumbnailGenerator(
        error: const VideoThumbnailGenerationException(
          'No usable frame was found.',
        ),
      ),
      post: (url, bytes, contentType) async {
        uploadCalls++;
        return 'unexpected';
      },
    );

    await expectLater(
      service.upload(
        bandId: 'b1',
        kind: MediaKind.video,
        media: videoFixture(),
      ),
      throwsA(
        isA<MediaUploadException>().having(
          (error) => error.message,
          'message',
          'No usable frame was found.',
        ),
      ),
    );
    expect(uploadCalls, 0);
    expect(repository.addCalls, 0);
  });
}

class _RecordingMediaRepository extends HttpUploadDemoRepository {
  int addCalls = 0;
  String? savedStorageId;
  String? savedThumbnailStorageId;

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
    addCalls++;
    savedStorageId = storageId;
    savedThumbnailStorageId = thumbnailStorageId;
    return 'saved-media';
  }
}
