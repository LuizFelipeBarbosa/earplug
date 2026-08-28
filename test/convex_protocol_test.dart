import 'dart:async';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:convex_flutter/src/impl/protocol_value.dart';
import 'package:earplug/services/connection_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protocol values preserve an explicit JSON null result', () {
    expect(encodeProtocolValue({'value': null}, 'value'), 'null');
    expect(
      encodeProtocolValue({
        'value': {'ok': true},
      }, 'value'),
      '{"ok":true}',
    );
    expect(encodeProtocolValue(const {}, 'value'), isNull);
  });

  test('connection wait and operation share one bounded timeout', () async {
    final states = StreamController<WebSocketConnectionState>();
    var operationCalled = false;
    addTearDown(states.close);

    await expectLater(
      runWithConnectionBudget<void>(
        connected: false,
        connectionStates: states.stream,
        timeout: const Duration(milliseconds: 20),
        operation: () async => operationCalled = true,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(operationCalled, isFalse);
  });

  test('connected operations run without waiting for another state event', () {
    expect(
      runWithConnectionBudget(
        connected: true,
        connectionStates: const Stream.empty(),
        timeout: const Duration(seconds: 1),
        operation: () async => 'done',
      ),
      completion('done'),
    );
  });
}
