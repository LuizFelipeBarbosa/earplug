import 'dart:convert';
import 'dart:typed_data';

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/services/video_thumbnail_generator_contract.dart';

/// Hands back whatever the test staged instead of opening a real picker, and
/// counts what was asked for.
class FakeMediaPicker implements MediaPicker {
  PickedMedia? nextPhoto;
  List<PickedMedia> nextPhotos = [];
  List<String> nextOversized = [];
  PickedMedia? nextVideo;
  MediaPickException? nextException;

  int photoCalls = 0;
  int photoListCalls = 0;
  int videoCalls = 0;

  @override
  Future<PickedMedia?> pickPhoto() async {
    photoCalls++;
    _throwIfNeeded();
    return nextPhoto;
  }

  @override
  Future<({List<PickedMedia> photos, List<String> oversized})> pickPhotos({
    int limit = 10,
  }) async {
    photoListCalls++;
    _throwIfNeeded();
    return (photos: nextPhotos, oversized: nextOversized);
  }

  @override
  Future<PickedMedia?> pickVideo() async {
    videoCalls++;
    _throwIfNeeded();
    return nextVideo;
  }

  void _throwIfNeeded() {
    final error = nextException;
    if (error != null) throw error;
  }
}

class FakeVideoThumbnailGenerator implements VideoThumbnailGenerator {
  FakeVideoThumbnailGenerator({Uint8List? bytes, this.error})
    : bytes =
          bytes ??
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
            '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          );

  final Uint8List bytes;
  final Object? error;
  int calls = 0;

  @override
  Future<Uint8List> generate(PickedMedia video) async {
    calls++;
    if (error case final error?) throw error;
    return bytes;
  }
}

/// Hands out an upload URL that resolves to nothing, so the upload service
/// takes its real HTTP path and the test's `post` decides how it ends.
class HttpUploadDemoRepository extends DemoRepository {
  HttpUploadDemoRepository({AuthService? auth})
    : super(auth: auth ?? FakeAuthService());

  @override
  Future<String> generateMediaUploadUrl(String bandId) async =>
      'https://fake.upload/x';

  @override
  Future<String> generateAvatarUploadUrl() async =>
      'https://fake.upload/avatar';
}
