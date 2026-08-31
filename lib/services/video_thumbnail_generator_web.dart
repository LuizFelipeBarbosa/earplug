import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'media_picker.dart';
import 'video_thumbnail_generator_contract.dart';

VideoThumbnailGenerator createPlatformVideoThumbnailGenerator() =>
    _WebVideoThumbnailGenerator();

class _WebVideoThumbnailGenerator implements VideoThumbnailGenerator {
  static const _timeout = Duration(seconds: 12);

  @override
  Future<Uint8List> generate(PickedMedia source) async {
    final blob = web.Blob(
      <JSAny>[source.bytes.toJS].toJS,
      web.BlobPropertyBag(type: source.contentType),
    );
    final objectUrl = web.URL.createObjectURL(blob);
    final video = web.HTMLVideoElement()
      ..muted = true
      ..preload = 'auto';
    try {
      final ready = Completer<void>();
      video.onloadeddata = ((web.Event _) {
        if (!ready.isCompleted) ready.complete();
      }).toJS;
      video.onerror = ((JSAny? _, JSAny? _, JSAny? _, JSAny? _, JSAny? _) {
        if (!ready.isCompleted) {
          ready.completeError(
            const VideoThumbnailGenerationException(
              'The browser could not decode that video.',
            ),
          );
        }
        return true.toJS;
      }).toJS;
      video.src = objectUrl;
      video.load();
      await ready.future.timeout(_timeout);

      final duration = video.duration.isFinite ? video.duration : 0.0;
      final target = duration <= 0 ? 0.0 : math.min(1.0, duration / 2);
      if (target > 0.05) {
        final seeked = Completer<void>();
        video.onseeked = ((web.Event _) {
          if (!seeked.isCompleted) seeked.complete();
        }).toJS;
        video.currentTime = target;
        await seeked.future.timeout(_timeout);
      }

      final sourceWidth = video.videoWidth;
      final sourceHeight = video.videoHeight;
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw const VideoThumbnailGenerationException(
          'The selected video has no visible frames.',
        );
      }
      final scale = math.min(1.0, 720 / sourceWidth);
      final width = math.max(1, (sourceWidth * scale).round());
      final height = math.max(1, (sourceHeight * scale).round());
      final canvas = web.HTMLCanvasElement()
        ..width = width
        ..height = height;
      final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context == null) {
        throw const VideoThumbnailGenerationException(
          'The browser could not prepare a preview image.',
        );
      }
      context.drawImage(video, 0, 0, width, height);

      final encoded = Completer<web.Blob>();
      canvas.toBlob(
        ((web.Blob? result) {
          if (result == null) {
            encoded.completeError(
              const VideoThumbnailGenerationException(
                'The browser could not encode the preview image.',
              ),
            );
          } else {
            encoded.complete(result);
          }
        }).toJS,
        'image/jpeg',
        .78.toJS,
      );
      final jpeg = await encoded.future.timeout(_timeout);
      final buffer = await jpeg.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    } on VideoThumbnailGenerationException {
      rethrow;
    } catch (error) {
      throw VideoThumbnailGenerationException(
        'Could not create a preview frame. Export the clip as MP4 and retry.',
        error,
      );
    } finally {
      video
        ..pause()
        ..removeAttribute('src')
        ..load();
      web.URL.revokeObjectURL(objectUrl);
    }
  }
}
