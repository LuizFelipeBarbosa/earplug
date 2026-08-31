import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final calls = <String>[];
  final seekTargets = <Duration>[];
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  var _nextPlayerId = 0;

  void complete([int playerId = 0]) {
    _positions[playerId] = const Duration(seconds: 30);
    _events[playerId]?.add(VideoEvent(eventType: VideoEventType.completed));
  }

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    calls.add('create');
    final id = _nextPlayerId++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(1920, 1080),
        duration: const Duration(seconds: 30),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seekTo');
    seekTargets.add(position);
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    calls.add('setLooping');
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('setVolume:$volume');
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Color(0xff333333));
}
