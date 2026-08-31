import 'video_thumbnail_generator_contract.dart';
import 'video_thumbnail_generator_stub.dart'
    if (dart.library.io) 'video_thumbnail_generator_native.dart'
    if (dart.library.js_interop) 'video_thumbnail_generator_web.dart';

export 'video_thumbnail_generator_contract.dart';

VideoThumbnailGenerator createVideoThumbnailGenerator() =>
    createPlatformVideoThumbnailGenerator();
