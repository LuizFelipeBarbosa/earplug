import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

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
  bool _playing = false;

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
      setState(() => _error = "Couldn't play this clip — try again on wifi.");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller!;
    if (_playing) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() => _playing = !_playing);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ep.bg,
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
                        color: Ep.inkA(.55),
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
              style: epText(size: 13, color: Ep.inkA(.7), height: 1.4),
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
        style: epText(size: 11, color: Ep.inkA(.5), letterSpacing: 1.4),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: _togglePlayback,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: _playing
                        ? const Icon(Icons.pause, size: 20, color: Colors.white)
                        : const Padding(
                            padding: EdgeInsets.only(left: 2),
                            child: PlayTriangle(size: 13),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
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
                    return SizedBox(
                      height: 3,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: ColoredBox(color: Ep.whiteA(.12)),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: constraints.maxWidth * progress,
                                  height: 3,
                                  color: Ep.blue,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
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
            style: epText(size: 11, color: Ep.inkA(.55)),
          ),
        ),
      ],
    );
  }
}
