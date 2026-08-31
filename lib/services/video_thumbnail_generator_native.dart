import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

import 'media_picker.dart';
import 'video_thumbnail_generator_contract.dart';

VideoThumbnailGenerator createPlatformVideoThumbnailGenerator() =>
    _NativeVideoThumbnailGenerator();

class _NativeVideoThumbnailGenerator implements VideoThumbnailGenerator {
  @override
  Future<Uint8List> generate(PickedMedia video) async {
    final path = video.sourcePath;
    if (path == null || path.isEmpty) {
      throw const VideoThumbnailGenerationException(
        'Could not read the selected video.',
      );
    }
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        timeMs: 1000,
        quality: 78,
      );
      if (bytes == null || bytes.isEmpty) {
        throw const VideoThumbnailGenerationException(
          'Could not find a preview frame in that video.',
        );
      }
      return bytes;
    } on VideoThumbnailGenerationException {
      rethrow;
    } catch (error) {
      throw VideoThumbnailGenerationException(
        'Could not create a preview frame. Export the clip as MP4 and retry.',
        error,
      );
    }
  }
}
