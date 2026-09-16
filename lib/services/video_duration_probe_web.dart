import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'media_picker.dart';

Future<int?> probePlatformVideoDurationSec(PickedMedia source) async {
  try {
    final video = web.HTMLVideoElement()
      ..muted = true
      ..preload = 'metadata';
    final blob = web.Blob(
      <JSAny>[source.bytes.toJS].toJS,
      web.BlobPropertyBag(type: source.contentType),
    );
    final objectUrl = web.URL.createObjectURL(blob);
    try {
      final ready = Completer<int?>();
      final onDuration = ((web.Event _) {
        final duration = video.duration;
        if (!ready.isCompleted && duration.isFinite && duration >= 0) {
          ready.complete(duration.round());
        }
      }).toJS;
      video.onloadedmetadata = onDuration;
      video.ondurationchange = onDuration;
      video.onerror = ((JSAny? _, JSAny? _, JSAny? _, JSAny? _, JSAny? _) {
        if (!ready.isCompleted) ready.complete(null);
        return true.toJS;
      }).toJS;
      video.src = objectUrl;
      video.load();
      return await ready.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } finally {
      // Revoke first so a failure during element cleanup cannot leak the URL.
      web.URL.revokeObjectURL(objectUrl);
      video
        ..onloadedmetadata = null
        ..ondurationchange = null
        ..onerror = null
        ..pause()
        ..removeAttribute('src')
        ..load();
    }
  } catch (_) {
    return null;
  }
}
