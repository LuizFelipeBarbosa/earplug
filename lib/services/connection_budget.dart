import 'package:convex_flutter/convex_flutter.dart';

Future<T> runWithConnectionBudget<T>({
  required bool connected,
  required Stream<WebSocketConnectionState> connectionStates,
  required Duration timeout,
  required Future<T> Function() operation,
}) {
  return (() async {
    if (!connected) {
      await connectionStates.firstWhere(
        (state) => state == WebSocketConnectionState.connected,
      );
    }
    return operation();
  })().timeout(timeout);
}
