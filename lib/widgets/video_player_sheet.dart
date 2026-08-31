import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../theme.dart';

const _controlsHideDelay = Duration(seconds: 2);

@visibleForTesting
Size coverVideoSize({required Size viewport, required Size video}) {
  if (viewport.isEmpty || video.isEmpty) return viewport;
  final scale = math.max(
    viewport.width / video.width,
    viewport.height / video.height,
  );
  return Size(video.width * scale, video.height * scale);
}

@visibleForTesting
double playerProgressWidth(double viewportWidth) => math.min(
  math.max(0, viewportWidth - 32),
  math.min(220, math.max(120, viewportWidth * .4)),
);

Future<void> showBandVideo(
  BuildContext context, {
  required BandMedia media,
  required String bandName,
}) async {
  if (media.url == null || media.url!.isEmpty) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _VideoPlayerModal(media: media, bandName: bandName),
    ),
  );
}

class _VideoPlayerModal extends StatefulWidget {
  const _VideoPlayerModal({required this.media, required this.bandName});

  final BandMedia media;
  final String bandName;

  @override
  State<_VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<_VideoPlayerModal> {
  VideoPlayerController? _controller;
  Timer? _hideTimer;
  String? _error;
  bool _controlsVisible = true;
  bool _wasPlayingBeforeSeek = false;
  bool _lastPlaying = false;
  bool _lastEnded = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
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
      controller.addListener(_handlePlaybackState);
      setState(() => _controller = controller);
      await controller.setVolume(1);
      try {
        await controller.play();
        _scheduleControlsHide();
      } catch (_) {
        // Some browsers still reject audible autoplay after a navigation. The
        // visible Play control is the recovery path, so the clip remains usable.
      }
    } catch (_) {
      controller?.removeListener(_handlePlaybackState);
      await controller?.dispose();
      if (!mounted) return;
      setState(() => _error = "Couldn't play this clip. Try again on Wi-Fi.");
    }
  }

  void _handlePlaybackState() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    final ended = _hasEnded(value);
    if (value.isPlaying == _lastPlaying && ended == _lastEnded) return;
    _lastPlaying = value.isPlaying;
    _lastEnded = ended;
    if (!value.isPlaying || ended) {
      _hideTimer?.cancel();
      if (!_controlsVisible) setState(() => _controlsVisible = true);
    }
  }

  bool _hasEnded(VideoPlayerValue value) =>
      value.isCompleted ||
      (value.duration > Duration.zero &&
          !value.isPlaying &&
          value.position >= value.duration);

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_handlePlaybackState);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    _showControls();
    if (value.isPlaying) {
      await controller.pause();
      return;
    }
    if (_hasEnded(value)) await controller.seekTo(Duration.zero);
    await controller.play();
    _scheduleControlsHide();
  }

  Future<void> _seekBy(Duration offset) async {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    final targetMs = (value.position + offset).inMilliseconds.clamp(
      0,
      value.duration.inMilliseconds,
    );
    await controller.seekTo(Duration(milliseconds: targetMs));
    _showControls();
  }

  void _toggleControls() {
    final controller = _controller;
    if (controller == null) return;
    if (_controlsVisible && controller.value.isPlaying) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _showControls() {
    _hideTimer?.cancel();
    if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
    if (_controller?.value.isPlaying ?? false) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsHideDelay, () {
      if (!mounted || !(_controller?.value.isPlaying ?? false)) return;
      setState(() => _controlsVisible = false);
    });
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      _togglePlayback();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _seekBy(const Duration(seconds: -5));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _seekBy(const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _videoSurface(),
                if (_controller != null) _playerOverlays(),
                if (_controller == null) _nonPlayingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoSurface() {
    final controller = _controller;
    if (controller == null) return const ColoredBox(color: Colors.black);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final videoSize = coverVideoSize(
          viewport: viewport,
          video: controller.value.size,
        );
        return ClipRect(
          key: const Key('full-screen-cover-video'),
          child: Center(
            child: SizedBox.fromSize(
              size: videoSize,
              child: VideoPlayer(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _playerOverlays() {
    final controller = _controller!;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final ended = _hasEnded(value);
        return AnimatedOpacity(
          key: const Key('video-controls-overlay'),
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _topOverlay(),
                _centerControls(value, ended),
                _bottomMetadata(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topOverlay() {
    return Align(
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xB8000000), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 36),
            child: Row(
              children: [
                IconButton(
                  key: const Key('close-video-player'),
                  tooltip: 'Close video',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.bandName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: epText(
                      size: 11,
                      weight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerControls(VideoPlayerValue value, bool ended) {
    final controller = _controller!;
    final durationMs = value.duration.inMilliseconds;
    final position = durationMs == 0
        ? 0.0
        : value.position.inMilliseconds.clamp(0, durationMs).toDouble();
    final label = ended
        ? 'Replay'
        : value.isPlaying
        ? 'Pause'
        : 'Play';
    final icon = ended
        ? Icons.replay
        : value.isPlaying
        ? Icons.pause
        : Icons.play_arrow;

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxProgress = math.max(1.0, durationMs.toDouble());
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: label,
                child: IconButton.filled(
                  key: const Key('center-play-pause'),
                  tooltip: label,
                  onPressed: _togglePlayback,
                  iconSize: 34,
                  padding: const EdgeInsets.all(15),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(64),
                    backgroundColor: Colors.black.withValues(alpha: .62),
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(icon),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                key: const Key('video-progress-touch-target'),
                width: playerProgressWidth(constraints.maxWidth),
                height: 44,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    activeTrackColor: Ep.brand,
                    inactiveTrackColor: Colors.white38,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Semantics(
                    label: 'Video progress',
                    value: '${value.position.inSeconds} seconds',
                    child: Slider(
                      key: const Key('video-progress-slider'),
                      min: 0,
                      max: maxProgress,
                      value: position.clamp(0.0, maxProgress),
                      onChangeStart: (_) {
                        _hideTimer?.cancel();
                        _wasPlayingBeforeSeek = value.isPlaying;
                        if (_wasPlayingBeforeSeek) controller.pause();
                      },
                      onChanged: (milliseconds) {
                        controller.seekTo(
                          Duration(milliseconds: milliseconds.round()),
                        );
                      },
                      onChangeEnd: (milliseconds) async {
                        await controller.seekTo(
                          Duration(milliseconds: milliseconds.round()),
                        );
                        if (_wasPlayingBeforeSeek) {
                          await controller.play();
                          _scheduleControlsHide();
                        } else {
                          _showControls();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bottomMetadata() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Color(0xD9000000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 54, 18, 18),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: epText(
                      size: 14,
                      weight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${widget.media.viewsLabel} · ${widget.media.lenLabel}',
                    style: epText(size: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nonPlayingOverlay() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: _error == null
              ? const CircularProgressIndicator(color: Ep.brand)
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: epText(size: 13, color: Colors.white70, height: 1.4),
                  ),
                ),
        ),
        Align(
          alignment: Alignment.topLeft,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: IconButton(
                tooltip: 'Close video',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
