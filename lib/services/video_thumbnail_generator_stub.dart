import 'video_thumbnail_generator_contract.dart';

VideoThumbnailGenerator createPlatformVideoThumbnailGenerator() =>
    _UnsupportedVideoThumbnailGenerator();

class _UnsupportedVideoThumbnailGenerator implements VideoThumbnailGenerator {
  @override
  Future<Never> generate(_) {
    throw const VideoThumbnailGenerationException(
      'Video thumbnails are not supported on this device.',
    );
  }
}
