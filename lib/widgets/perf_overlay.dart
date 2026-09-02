import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

typedef _FrameSample = ({int buildMicros, int rasterMicros, int totalMicros});

/// A compact performance readout that must be placed directly inside a [Stack].
///
/// This widget builds a top-left [Positioned] child. Mount it only when
/// [PerfOverlay.enabled] is true.
class PerfOverlay extends StatefulWidget {
  const PerfOverlay({super.key, this.marks, this.extraStats});

  final List<({String name, double ms})> Function()? marks;
  final ValueListenable<Object?>? extraStats;

  static bool get enabled => Uri.base.queryParameters['perf'] == '1';

  static final ValueNotifier<String> summary = ValueNotifier<String>('');

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  static const _maxFrames = 180;
  static const _jankThresholdMicros = 16700;
  static const _slowFrameThresholdMicros = 33000;

  final List<_FrameSample> _frames = <_FrameSample>[];
  late final Timer _refreshTimer;
  late String _displayedSummary;
  bool _refreshRequested = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    widget.extraStats?.addListener(_onExtraStatsChanged);

    _displayedSummary = _formatSummary();
    PerfOverlay.summary.value = _displayedSummary;
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), _onRefreshTimer);
  }

  @override
  void didUpdateWidget(PerfOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extraStats == widget.extraStats) {
      return;
    }

    oldWidget.extraStats?.removeListener(_onExtraStatsChanged);
    widget.extraStats?.addListener(_onExtraStatsChanged);
    _refreshRequested = true;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildMicros = timing.buildDuration.inMicroseconds;
      final rasterMicros = timing.rasterDuration.inMicroseconds;
      _frames.add((
        buildMicros: buildMicros,
        rasterMicros: rasterMicros,
        totalMicros: buildMicros + rasterMicros,
      ));
    }

    if (_frames.length > _maxFrames) {
      _frames.removeRange(0, _frames.length - _maxFrames);
    }
    _refreshRequested = true;
  }

  void _onExtraStatsChanged() {
    _refreshRequested = true;
  }

  void _onRefreshTimer(Timer _) {
    if (!_refreshRequested) {
      return;
    }

    _refreshRequested = false;
    _refreshSummary();
  }

  void _refreshSummary() {
    final nextSummary = _formatSummary();
    PerfOverlay.summary.value = nextSummary;
    if (nextSummary == _displayedSummary || !mounted) {
      return;
    }

    setState(() {
      _displayedSummary = nextSummary;
    });
  }

  void _reset() {
    _frames.clear();
    _refreshRequested = false;
    _refreshSummary();
  }

  String _formatSummary() {
    final buildTimes = _frames
        .map((frame) => frame.buildMicros)
        .toList(growable: false);
    final rasterTimes = _frames
        .map((frame) => frame.rasterMicros)
        .toList(growable: false);
    final totalTimes = _frames
        .map((frame) => frame.totalMicros)
        .toList(growable: false);

    final jankCount = totalTimes
        .where((duration) => duration > _jankThresholdMicros)
        .length;
    final over33Count = totalTimes
        .where((duration) => duration > _slowFrameThresholdMicros)
        .length;
    final jankPercent = totalTimes.isEmpty
        ? 0.0
        : (jankCount / totalTimes.length) * 100;
    final worstMicros = totalTimes.fold<int>(
      0,
      (worst, duration) => duration > worst ? duration : worst,
    );

    final lines = <String>[
      'frames: ${_frames.length}',
      'build p50/p95: ${_milliseconds(_percentile(buildTimes, 0.50))} / '
          '${_milliseconds(_percentile(buildTimes, 0.95))} ms',
      'raster p95: ${_milliseconds(_percentile(rasterTimes, 0.95))} ms',
      'jank >16.7 ms: ${jankPercent.toStringAsFixed(1)}%',
      'frames >33 ms: $over33Count',
      'worst: ${_milliseconds(worstMicros)} ms',
    ];

    final marks = widget.marks?.call() ?? const [];
    for (final mark in marks) {
      lines.add('${mark.name}: ${mark.ms.toStringAsFixed(1)} ms');
    }

    final extraStats = widget.extraStats?.value;
    if (extraStats != null) {
      lines.add(extraStats.toString());
    }

    return lines.join('\n');
  }

  int _percentile(List<int> values, double percentile) {
    if (values.isEmpty) {
      return 0;
    }

    final sortedValues = List<int>.of(values)..sort();
    final index = (sortedValues.length * percentile).ceil() - 1;
    final safeIndex = index.clamp(0, sortedValues.length - 1).toInt();
    return sortedValues[safeIndex];
  }

  String _milliseconds(int microseconds) {
    return (microseconds / Duration.microsecondsPerMillisecond).toStringAsFixed(
      1,
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _refreshTimer.cancel();
    widget.extraStats?.removeListener(_onExtraStatsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      child: RepaintBoundary(
        child: Stack(
          children: [
            IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 30),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _displayedSummary,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 5,
              bottom: 4,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _reset,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: Text(
                    'RESET',
                    style: TextStyle(
                      color: Colors.amber,
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
