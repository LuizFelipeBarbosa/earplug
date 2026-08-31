import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

@visibleForTesting
Size constrainedVideoSize({
  required Size available,
  required double aspectRatio,
}) {
  final safeAspectRatio = aspectRatio > 0 ? aspectRatio : 16 / 9;
  final maxVideoHeight = math.max(120.0, available.height - 150);
  final width = math.min(available.width, maxVideoHeight * safeAspectRatio);
  return Size(width, width / safeAspectRatio);
}

Future<void> showBandVideo(
  BuildContext context, {
  required BandMedia media,
  required String bandName,
}) async {
  if (media.url == null || media.url!.isEmpty) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _VideoPlayerModal(media: media, bandName: bandName),
    ),
  );
}

class _VideoPlayerModal extends StatefulWidget {
  final BandMedia media;
  final String bandName;

  const _VideoPlayerModal({required this.media, required this.bandName});

  @override
  State<_VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<_VideoPlayerModal> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.media.url!),
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() => _error = "Couldn't play this clip. Try again on Wi-Fi.");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller!;
    final value = controller.value;
    if (value.isPlaying) {
      await controller.pause();
      return;
    }
    if (value.duration.inMilliseconds != 0 &&
        value.position >= value.duration) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ep.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.close,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.bandName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: epText(
                        size: 11,
                        weight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Ep.contentSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: Center(child: _content(context))),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_error case final error?) {
      return SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              textAlign: TextAlign.center,
              style: epText(size: 13, color: Ep.contentSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            EpButton('CLOSE', onTap: () => Navigator.of(context).pop()),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return Text(
        'LOADING…',
        style: epText(size: 11, color: Ep.contentSecondary, letterSpacing: 1.4),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final videoSize = constrainedVideoSize(
          available: Size(constraints.maxWidth, constraints.maxHeight),
          aspectRatio: controller.value.aspectRatio,
        );
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SizedBox(
                  width: videoSize.width,
                  height: videoSize.height,
                  child: VideoPlayer(controller),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final duration = value.duration.inMilliseconds;
                    final progress = duration == 0
                        ? 0.0
                        : (value.position.inMilliseconds / duration).clamp(
                            0.0,
                            1.0,
                          );
                    return Row(
                      children: [
                        IconButton(
                          onPressed: _togglePlayback,
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          icon: value.isPlaying
                              ? const Icon(Icons.pause)
                              : const Icon(Icons.play_arrow),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 3,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ColoredBox(
                                        color: Ep.surfaceDisabled,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        width: constraints.maxWidth * progress,
                                        height: 3,
                                        color: Ep.brand,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  widget.media.title,
                  style: epText(size: 13, weight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 16),
                child: Text(
                  '${widget.media.viewsLabel} · ${widget.media.lenLabel}',
                  style: epText(size: 11, color: Ep.contentSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
