import 'package:flutter/foundation.dart';

@immutable
class ConvexDebugStats {
  const ConvexDebugStats({
    required this.activeSubscriptions,
    required this.transitionsReceived,
    required this.bytesReceived,
    required this.duplicatePayloadsSkipped,
    required this.lastTransitionBytes,
    this.lastTransitionAt,
  });

  final int activeSubscriptions;
  final int transitionsReceived;
  final int bytesReceived;
  final int duplicatePayloadsSkipped;
  final int lastTransitionBytes;
  final DateTime? lastTransitionAt;

  ConvexDebugStats copyWith({
    int? activeSubscriptions,
    int? transitionsReceived,
    int? bytesReceived,
    int? duplicatePayloadsSkipped,
    int? lastTransitionBytes,
    DateTime? lastTransitionAt,
  }) {
    return ConvexDebugStats(
      activeSubscriptions: activeSubscriptions ?? this.activeSubscriptions,
      transitionsReceived: transitionsReceived ?? this.transitionsReceived,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      duplicatePayloadsSkipped:
          duplicatePayloadsSkipped ?? this.duplicatePayloadsSkipped,
      lastTransitionBytes: lastTransitionBytes ?? this.lastTransitionBytes,
      lastTransitionAt: lastTransitionAt ?? this.lastTransitionAt,
    );
  }

  @override
  String toString() {
    final receivedKilobytes = (bytesReceived / 1024).round();
    final lastKilobytes = (lastTransitionBytes / 1024).round();
    return 'subs $activeSubscriptions · tx $transitionsReceived · '
        '$receivedKilobytes KB · dup $duplicatePayloadsSkipped · '
        'last $lastKilobytes KB';
  }
}
