import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/repository.dart';
import 'errors.dart';
import 'models.dart';
import 'services/media_picker.dart';
import 'services/media_upload_service.dart';

class MediaUpload {
  const MediaUpload({
    required this.id,
    required this.bandId,
    required this.kind,
    required this.filename,
    required this.sizeBytes,
    required this.phase,
    required this.error,
    required this.payload,
    required this.preview,
  });

  final String id;
  final String bandId;
  final MediaKind kind;
  final String filename;
  final int sizeBytes;
  final MediaUploadPhase phase;
  final String? error;

  // Bytes stay alive only for retry. Done and dismissed uploads must release
  // them or every completed video could retain another 25 MB.
  final PickedMedia? payload;
  final Uint8List? preview;
}

class BandMediaController extends ChangeNotifier {
  BandMediaController({
    required this.repository,
    required this.say,
    MediaPicker? picker,
    MediaUploadService? uploader,
  }) : _picker = picker ?? MediaPicker(),
       _uploader = uploader ?? MediaUploadService(repository: repository);

  final EarplugRepository repository;
  final void Function(String) say;
  final MediaPicker _picker;
  final MediaUploadService _uploader;

  final Map<String, List<BandMedia>> _mediaCache = {};
  final Set<String> _mediaLoads = {};
  final Map<String, Object> _loadTokens = {};
  final Map<String, String> _loadErrors = {};
  final Map<String, List<MediaUpload>> _uploads = {};

  List<BandMedia> mediaFor(String bandId) {
    final cached = _mediaCache[bandId];
    if (cached != null) return cached;

    if (_mediaLoads.add(bandId)) {
      unawaited(_loadMedia(bandId));
    }
    return const <BandMedia>[];
  }

  List<BandMedia> videosFor(String bandId) {
    final videos = mediaFor(
      bandId,
    ).where((media) => media.kind == MediaKind.video).toList();
    videos.sort((a, b) => a.order.compareTo(b.order));
    return videos;
  }

  List<BandMedia> photosFor(String bandId) {
    final photos = mediaFor(
      bandId,
    ).where((media) => media.kind == MediaKind.photo).toList();
    photos.sort((a, b) => a.order.compareTo(b.order));
    return photos;
  }

  BandMedia? pinnedVideoFor(String bandId) {
    final videos = videosFor(bandId);
    for (final video in videos) {
      if (video.pinned) return video;
    }
    return videos.isEmpty ? null : videos.first;
  }

  bool isLoading(String bandId) => _mediaLoads.contains(bandId);

  String? loadErrorFor(String bandId) => _loadErrors[bandId];

  Future<void> refresh(String bandId) async {
    _mediaLoads.add(bandId);
    await _loadMedia(bandId);
  }

  Future<void> _loadMedia(String bandId) async {
    final token = Object();
    _loadTokens[bandId] = token;
    try {
      final loaded = await repository.mediaFor(bandId);
      if (!identical(_loadTokens[bandId], token)) return;
      _mediaCache[bandId] = List<BandMedia>.unmodifiable(loaded);
      _loadErrors.remove(bandId);
    } catch (error) {
      if (!identical(_loadTokens[bandId], token)) return;
      _loadErrors[bandId] = '$error';
    } finally {
      if (identical(_loadTokens[bandId], token)) {
        _loadTokens.remove(bandId);
        _mediaLoads.remove(bandId);
        notifyListeners();
      }
    }
  }

  List<MediaUpload> uploadsFor(String bandId) =>
      List<MediaUpload>.unmodifiable(_uploads[bandId] ?? const []);

  bool isUploading(String bandId) => uploadsFor(bandId).any(
    (upload) =>
        upload.phase != MediaUploadPhase.failed &&
        upload.phase != MediaUploadPhase.done,
  );

  Future<void> pickAndUploadVideo(String bandId) async {
    final PickedMedia? media;
    try {
      media = await _picker.pickVideo();
    } on MediaPickException catch (error) {
      say(error.message);
      return;
    }
    if (media == null) return;

    await _beginUpload(bandId, MediaKind.video, media);
  }

  Future<void> pickAndUploadPhotos(String bandId) async {
    final List<PickedMedia> photos;
    final List<String> oversized;
    try {
      final (photos: pickedPhotos, oversized: skippedPhotos) = await _picker
          .pickPhotos();
      photos = pickedPhotos;
      oversized = skippedPhotos;
    } on MediaPickException catch (error) {
      say(error.message);
      return;
    }
    if (oversized.isNotEmpty) {
      final count = oversized.length;
      final subject = count == 1 ? 'photo was' : 'photos were';
      say('$count $subject over 8 MB. Export smaller files and retry.');
    }
    for (final photo in photos) {
      await _beginUpload(bandId, MediaKind.photo, photo);
    }
  }

  Future<PickedMedia?> pickFlyerArt() => _picker.pickPhoto();

  Future<String?> uploadFlyerArt(String bandId, PickedMedia media) async {
    try {
      return await _uploader.uploadRaw(bandId: bandId, media: media);
    } on MediaUploadException catch (error) {
      say(error.message);
      return null;
    }
  }

  /// Uploads already-picked bytes as a photo row; returns the mediaId or null
  /// on failure. The normal upload tile lifecycle remains visible throughout.
  Future<String?> uploadHeldPhoto(String bandId, PickedMedia media) {
    return _beginUpload(bandId, MediaKind.photo, media);
  }

  Future<void> retryUpload(String uploadId) async {
    final found = _findUpload(uploadId);
    if (found == null ||
        found.upload.phase != MediaUploadPhase.failed ||
        found.upload.payload == null) {
      return;
    }
    await _runUpload(found.upload);
  }

  void dismissUpload(String uploadId) {
    final found = _findUpload(uploadId);
    if (found == null) return;
    _removeUpload(found.upload.bandId, uploadId);
    notifyListeners();
  }

  Future<String?> _beginUpload(
    String bandId,
    MediaKind kind,
    PickedMedia media,
  ) async {
    final upload = MediaUpload(
      id: '$bandId-${DateTime.now().microsecondsSinceEpoch}',
      bandId: bandId,
      kind: kind,
      filename: media.filename,
      sizeBytes: media.sizeBytes,
      phase: MediaUploadPhase.preparing,
      error: null,
      payload: media,
      preview: kind == MediaKind.photo ? media.bytes : null,
    );
    _uploads.putIfAbsent(bandId, () => []).add(upload);
    notifyListeners();
    return _runUpload(upload);
  }

  Future<String?> _runUpload(MediaUpload upload) async {
    final payload = upload.payload;
    if (payload == null) return null;

    try {
      final mediaId = await _uploader.upload(
        bandId: upload.bandId,
        kind: upload.kind,
        media: payload,
        onPhase: (phase) => _setUploadPhase(upload.bandId, upload.id, phase),
        onThumbnailReady: (bytes) =>
            _setUploadPreview(upload.bandId, upload.id, bytes),
      );
      if (!_removeUpload(upload.bandId, upload.id)) return null;
      notifyListeners();
      await refresh(upload.bandId);
      return mediaId;
    } on MediaUploadException catch (error) {
      _setUploadPhase(
        upload.bandId,
        upload.id,
        MediaUploadPhase.failed,
        error: error.message,
      );
      return null;
    }
  }

  void _setUploadPhase(
    String bandId,
    String uploadId,
    MediaUploadPhase phase, {
    String? error,
  }) {
    final uploads = _uploads[bandId];
    final index = uploads?.indexWhere((upload) => upload.id == uploadId) ?? -1;
    if (uploads == null || index == -1) return;

    final current = uploads[index];
    uploads[index] = MediaUpload(
      id: current.id,
      bandId: current.bandId,
      kind: current.kind,
      filename: current.filename,
      sizeBytes: current.sizeBytes,
      phase: phase,
      error: error,
      payload: phase == MediaUploadPhase.done ? null : current.payload,
      preview: current.preview,
    );
    notifyListeners();
  }

  void _setUploadPreview(String bandId, String uploadId, Uint8List preview) {
    final uploads = _uploads[bandId];
    final index = uploads?.indexWhere((upload) => upload.id == uploadId) ?? -1;
    if (uploads == null || index == -1) return;
    final current = uploads[index];
    uploads[index] = MediaUpload(
      id: current.id,
      bandId: current.bandId,
      kind: current.kind,
      filename: current.filename,
      sizeBytes: current.sizeBytes,
      phase: current.phase,
      error: current.error,
      payload: current.payload,
      preview: preview,
    );
    notifyListeners();
  }

  ({String bandId, MediaUpload upload})? _findUpload(String uploadId) {
    for (final entry in _uploads.entries) {
      for (final upload in entry.value) {
        if (upload.id == uploadId) {
          return (bandId: entry.key, upload: upload);
        }
      }
    }
    return null;
  }

  bool _removeUpload(String bandId, String uploadId) {
    final uploads = _uploads[bandId];
    if (uploads == null) return false;

    final before = uploads.length;
    uploads.removeWhere((upload) => upload.id == uploadId);
    if (uploads.isEmpty) _uploads.remove(bandId);
    return uploads.length != before;
  }

  Future<void> pin(String bandId, String mediaId) async {
    await _mutate(bandId, () => repository.pinBandMedia(mediaId));
  }

  Future<void> move(String bandId, String mediaId, String direction) async {
    await _mutate(bandId, () => repository.moveBandMedia(mediaId, direction));
  }

  /// Moves an item to the adjacent position fans can actually see within its
  /// video or photo section. Older/demo repositories already move by kind;
  /// production ordering may include the other kind between two visible
  /// neighbors, so cross those hidden positions in one user action.
  Future<void> moveWithinKind(
    String bandId,
    String mediaId,
    String direction,
  ) async {
    final globallyOrdered = List<BandMedia>.of(mediaFor(bandId))
      ..sort((a, b) => a.order.compareTo(b.order));
    final itemIndex = globallyOrdered.indexWhere((item) => item.id == mediaId);
    if (itemIndex == -1) return;

    final item = globallyOrdered[itemIndex];
    final visiblePeers = globallyOrdered
        .where((candidate) => candidate.kind == item.kind)
        .toList();
    final peerIndex = visiblePeers.indexWhere((peer) => peer.id == mediaId);
    final neighborIndex = direction == 'up' ? peerIndex - 1 : peerIndex + 1;
    if (peerIndex == -1 ||
        neighborIndex < 0 ||
        neighborIndex >= visiblePeers.length) {
      return;
    }

    final neighborId = visiblePeers[neighborIndex].id;
    final neighborGlobalIndex = globallyOrdered.indexWhere(
      (candidate) => candidate.id == neighborId,
    );
    final ordersAreUnique =
        globallyOrdered.map((item) => item.order).toSet().length ==
        globallyOrdered.length;
    final steps = ordersAreUnique ? (itemIndex - neighborGlobalIndex).abs() : 1;
    await _mutate(bandId, () async {
      for (var step = 0; step < steps; step++) {
        await repository.moveBandMedia(mediaId, direction);
      }
    });
  }

  Future<void> remove(String bandId, String mediaId) async {
    await _mutate(bandId, () => repository.deleteBandMedia(mediaId));
  }

  Future<void> setHero(String bandId, String mediaId) async {
    await _mutate(
      bandId,
      () => repository.setBandBanner(bandId: bandId, mediaId: mediaId),
    );
  }

  Future<void> clearHero(String bandId) async {
    await _mutate(bandId, () => repository.clearBandBanner(bandId));
  }

  Future<bool> setAvatar(String bandId, String mediaId) => _mutateResult(
    bandId,
    () => repository.setBandAvatar(bandId: bandId, mediaId: mediaId),
  );

  Future<bool> setBanner(String bandId, String mediaId) => _mutateResult(
    bandId,
    () => repository.setBandBanner(bandId: bandId, mediaId: mediaId),
  );

  Future<bool> clearAvatar(String bandId) =>
      _mutateResult(bandId, () => repository.clearBandAvatar(bandId));

  Future<bool> clearBanner(String bandId) =>
      _mutateResult(bandId, () => repository.clearBandBanner(bandId));

  Future<bool> _mutateResult(
    String bandId,
    Future<void> Function() mutation,
  ) async {
    try {
      await mutation();
      await refresh(bandId);
      return true;
    } catch (error) {
      logError('band media mutation', error);
      say(genericErrorMessage);
      return false;
    }
  }

  Future<void> _mutate(String bandId, Future<void> Function() mutation) async {
    try {
      await mutation();
      await refresh(bandId);
    } catch (error) {
      logError('band media mutation', error);
      say(genericErrorMessage);
    }
  }

  void clearForSignOut() {
    _mediaCache.clear();
    _mediaLoads.clear();
    _loadTokens.clear();
    _loadErrors.clear();
    _uploads.clear();
    notifyListeners();
  }
}
