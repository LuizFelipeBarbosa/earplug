import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class PickedMedia {
  const PickedMedia({
    required this.bytes,
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
  final int sizeBytes;

  String get titleFromFilename {
    final extension = filename.lastIndexOf('.');
    final basename = extension > 0
        ? filename.substring(0, extension)
        : filename;
    return basename
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }
}

class MediaPickException implements Exception {
  const MediaPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MediaPicker {
  MediaPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  static const int maxPhotoBytes = 8 * 1024 * 1024;
  static const int maxVideoBytes = 25 * 1024 * 1024;
  static const Set<String> videoTypes = {'video/mp4', 'video/quicktime'};

  final ImagePicker _picker;

  Future<PickedMedia?> pickPhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 88,
    );
    if (file == null) return null;
    return _readPhoto(file);
  }

  Future<List<PickedMedia>> pickPhotos({int limit = 10}) async {
    final files = await _picker.pickMultiImage(
      limit: limit,
      maxWidth: 2048,
      imageQuality: 88,
    );
    return [for (final file in files) await _readPhoto(file)];
  }

  Future<PickedMedia?> pickVideo() async {
    final file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    if (file == null) return null;

    final media = await _read(file);
    if (media.sizeBytes > maxVideoBytes) {
      throw const MediaPickException(
        'That video is over 25 MB — trim it or export smaller.',
      );
    }
    if (!videoTypes.contains(media.contentType)) {
      throw const MediaPickException(
        "That file type won't play everywhere — export as MP4.",
      );
    }
    return media;
  }

  Future<PickedMedia> _readPhoto(XFile file) async {
    final media = await _read(file);
    if (media.sizeBytes > maxPhotoBytes) {
      throw const MediaPickException(
        'That photo is over 8 MB — resize it or export smaller.',
      );
    }
    return media;
  }

  Future<PickedMedia> _read(XFile file) async {
    final bytes = await file.readAsBytes();
    return PickedMedia(
      bytes: bytes,
      filename: file.name,
      contentType: file.mimeType ?? _contentTypeFromFilename(file.name),
      sizeBytes: bytes.lengthInBytes,
    );
  }

  String _contentTypeFromFilename(String filename) {
    final extension = filename.toLowerCase().split('.').last;
    return switch (extension) {
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }
}
