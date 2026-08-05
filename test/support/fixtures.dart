import 'dart:convert';
import 'dart:typed_data';

import 'package:earplug/services/media_picker.dart';

/// A decodable 1x1 PNG — for tests that put the picked photo on screen.
PickedMedia photoFixture({String filename = 'band_photo.png'}) {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  return PickedMedia(
    bytes: bytes,
    filename: filename,
    contentType: 'image/png',
    sizeBytes: bytes.lengthInBytes,
  );
}

/// Three opaque bytes — for tests that only carry the photo around, never
/// decode it.
PickedMedia stubPhotoFixture({String filename = 'backstage.jpg'}) =>
    PickedMedia(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: filename,
      contentType: 'image/jpeg',
      sizeBytes: 3,
    );

/// Three opaque bytes standing in for a clip.
PickedMedia videoFixture({String filename = 'riptide_live.mp4'}) => PickedMedia(
  bytes: Uint8List.fromList([1, 2, 3]),
  filename: filename,
  contentType: 'video/mp4',
  sizeBytes: 3,
);
