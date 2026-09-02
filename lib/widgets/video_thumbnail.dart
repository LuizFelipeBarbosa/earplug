import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import 'common.dart';

/// A real poster for a band clip. New clips use their stored JPEG thumbnail;
/// legacy clips briefly initialize the video and hold a muted frame instead.
class BandVideoThumbnail extends StatefulWidget {
  const BandVideoThumbnail({
    super.key,
    required this.media,
    required this.fallback,
    this.legacyFrameEnabled = !kIsWeb,
  });

  final BandMedia media;
  final Widget fallback;
  final bool legacyFrameEnabled;

  @override
  State<BandVideoThumbnail> createState() => _BandVideoThumbnailState();
}

class _BandVideoThumbnailState extends State<BandVideoThumbnail> {
  VideoPlayerController? _legacyController;
  bool _legacyReady = false;

  bool get _needsLegacyFrame =>
      widget.legacyFrameEnabled &&
      (widget.media.thumbnailUrl == null ||
          widget.media.thumbnailUrl!.isEmpty) &&
      widget.media.url != null &&
      widget.media.url!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadLegacyFrameIfNeeded();
  }

  @override
  void didUpdateWidget(covariant BandVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.legacyFrameEnabled != widget.legacyFrameEnabled ||
        oldWidget.media.url != widget.media.url ||
        oldWidget.media.thumbnailUrl != widget.media.thumbnailUrl) {
      _disposeLegacyController();
      _loadLegacyFrameIfNeeded();
    }
  }

  Future<void> _loadLegacyFrameIfNeeded() async {
    if (!_needsLegacyFrame) return;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.media.url!),
    );
    _legacyController = controller;
    try {
      await controller.setVolume(0);
      await controller.initialize();
      final duration = controller.value.duration;
      if (duration > Duration.zero) {
        final targetMs = math.min(1000, duration.inMilliseconds ~/ 2);
        await controller.seekTo(Duration(milliseconds: targetMs));
      }
      await controller.pause();
      if (mounted && identical(_legacyController, controller)) {
        setState(() => _legacyReady = true);
      }
    } catch (_) {
      if (identical(_legacyController, controller)) {
        await _disposeLegacyController();
      }
    }
  }

  Future<void> _disposeLegacyController() async {
    final controller = _legacyController;
    _legacyController = null;
    _legacyReady = false;
    await controller?.dispose();
  }

  @override
  void dispose() {
    _disposeLegacyController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = widget.media.thumbnailUrl;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      return EpNetworkImage(
        key: ValueKey('stored-thumbnail-${widget.media.id}'),
        url: thumbnailUrl,
        fit: BoxFit.cover,
        fallback: widget.fallback,
      );
    }

    final controller = _legacyController;
    if (!_legacyReady || controller == null) return widget.fallback;
    return ClipRect(
      key: ValueKey('legacy-thumbnail-${widget.media.id}'),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox.fromSize(
          size: controller.value.size,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
