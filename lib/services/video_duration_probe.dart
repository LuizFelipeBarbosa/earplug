import 'media_picker.dart';
import 'video_duration_probe_stub.dart'
    if (dart.library.io) 'video_duration_probe_native.dart'
    if (dart.library.js_interop) 'video_duration_probe_web.dart';

/// Best-effort video duration in whole seconds. Returns null if the current
/// platform can't determine it or on failure; null means unknown.
Future<int?> probeVideoDurationSec(PickedMedia video) =>
    probePlatformVideoDurationSec(video);
