import 'dart:typed_data';

import 'media_picker.dart';

class VideoThumbnailGenerationException implements Exception {
  const VideoThumbnailGenerationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract class VideoThumbnailGenerator {
  Future<Uint8List> generate(PickedMedia video);
}
