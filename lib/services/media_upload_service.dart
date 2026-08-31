import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/repository.dart';
import '../models.dart';
import 'media_picker.dart';
import 'video_thumbnail_generator.dart';

enum MediaUploadPhase { preparing, uploading, saving, done, failed }

typedef HttpPoster =
    Future<String> Function(Uri url, Uint8List bytes, String contentType);

class MediaUploadException implements Exception {
  const MediaUploadException({
    required this.message,
    required this.phase,
    this.cause,
  });

  final String message;
  final MediaUploadPhase phase;
  final Object? cause;

  @override
  String toString() => message;
}

class MediaUploadService {
  MediaUploadService({
    required this.repository,
    HttpPoster? post,
    VideoThumbnailGenerator? thumbnailGenerator,
  }) : _post = post ?? _postWithHttp,
       _thumbnailGenerator =
           thumbnailGenerator ?? createVideoThumbnailGenerator();

  final EarplugRepository repository;
  final HttpPoster _post;
  final VideoThumbnailGenerator _thumbnailGenerator;
  int _demoStorageCounter = 0;

  Future<String> upload({
    required String bandId,
    required MediaKind kind,
    required PickedMedia media,
    void Function(MediaUploadPhase)? onPhase,
    void Function(Uint8List bytes)? onThumbnailReady,
  }) async {
    var phase = MediaUploadPhase.preparing;
    try {
      onPhase?.call(phase);
      PickedMedia? thumbnail;
      if (kind == MediaKind.video) {
        final bytes = await _thumbnailGenerator.generate(media);
        thumbnail = PickedMedia(
          bytes: bytes,
          filename: '${media.titleFromFilename.toLowerCase()}.thumbnail.jpg',
          contentType: 'image/jpeg',
          sizeBytes: bytes.lengthInBytes,
        );
        onThumbnailReady?.call(bytes);
      }
      final storageId = await _uploadToStorage(
        generateUploadUrl: () => repository.generateMediaUploadUrl(bandId),
        media: media,
        onUploading: () {
          phase = MediaUploadPhase.uploading;
          onPhase?.call(phase);
        },
      );
      final thumbnailStorageId = thumbnail == null
          ? null
          : await _uploadToStorage(
              generateUploadUrl: () =>
                  repository.generateMediaUploadUrl(bandId),
              media: thumbnail,
              onUploading: () {
                phase = MediaUploadPhase.uploading;
                onPhase?.call(phase);
              },
            );

      phase = MediaUploadPhase.saving;
      onPhase?.call(phase);
      final mediaId = await repository.addBandMedia(
        bandId: bandId,
        kind: kind,
        storageId: storageId,
        thumbnailStorageId: thumbnailStorageId,
        title: media.titleFromFilename,
        lengthSec: null,
      );

      phase = MediaUploadPhase.done;
      onPhase?.call(phase);
      return mediaId;
    } catch (error) {
      throw _asUploadException(error, phase);
    }
  }

  Future<String> uploadRaw({
    required String bandId,
    required PickedMedia media,
    void Function(MediaUploadPhase)? onPhase,
  }) async {
    var phase = MediaUploadPhase.preparing;
    try {
      onPhase?.call(phase);
      final storageId = await _uploadToStorage(
        generateUploadUrl: () => repository.generateMediaUploadUrl(bandId),
        media: media,
        onUploading: () {
          phase = MediaUploadPhase.uploading;
          onPhase?.call(phase);
        },
      );

      phase = MediaUploadPhase.done;
      onPhase?.call(phase);
      return storageId;
    } catch (error) {
      throw _asUploadException(error, phase);
    }
  }

  Future<String> uploadAvatarRaw({
    required PickedMedia media,
    void Function(MediaUploadPhase)? onPhase,
  }) async {
    var phase = MediaUploadPhase.preparing;
    try {
      onPhase?.call(phase);
      final storageId = await _uploadToStorage(
        generateUploadUrl: repository.generateAvatarUploadUrl,
        media: media,
        onUploading: () {
          phase = MediaUploadPhase.uploading;
          onPhase?.call(phase);
        },
      );

      phase = MediaUploadPhase.done;
      onPhase?.call(phase);
      return storageId;
    } catch (error) {
      throw _asUploadException(error, phase);
    }
  }

  Future<String> _uploadToStorage({
    required Future<String> Function() generateUploadUrl,
    required PickedMedia media,
    required void Function() onUploading,
  }) async {
    final uploadUri = Uri.parse(await generateUploadUrl());
    if (uploadUri.scheme == 'demo') {
      return 'demo-storage-${++_demoStorageCounter}';
    }

    onUploading();
    return _post(uploadUri, media.bytes, media.contentType);
  }

  MediaUploadException _asUploadException(
    Object error,
    MediaUploadPhase phase,
  ) {
    if (error is MediaUploadException && error.phase == phase) return error;

    final message = error is VideoThumbnailGenerationException
        ? error.message
        : error is MediaUploadException
        ? error.message
        : switch (phase) {
            MediaUploadPhase.preparing =>
              'Could not prepare the upload: $error',
            MediaUploadPhase.uploading => 'Could not upload the file: $error',
            MediaUploadPhase.saving => 'Could not save the upload: $error',
            MediaUploadPhase.done => 'Could not finish the upload: $error',
            MediaUploadPhase.failed => 'The upload failed: $error',
          };
    return MediaUploadException(
      message: message,
      phase: phase,
      cause: error is MediaUploadException ? error.cause ?? error : error,
    );
  }

  static Future<String> _postWithHttp(
    Uri url,
    Uint8List bytes,
    String contentType,
  ) async {
    final response = await http.post(
      url,
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      final detail = body.isEmpty ? '' : ': $body';
      throw MediaUploadException(
        message: 'Upload failed with status ${response.statusCode}$detail',
        phase: MediaUploadPhase.uploading,
      );
    }

    return (jsonDecode(response.body) as Map)['storageId'] as String;
  }
}
