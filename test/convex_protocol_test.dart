import 'dart:async';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:convex_flutter/src/impl/auth_refresh.dart';
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

  group('auth refresh delay', () {
    final now = DateTime.utc(2026);

    test('uses a fraction of a short-lived token lifetime', () {
      expect(
        authRefreshDelay(
          expiry: now.add(const Duration(seconds: 60)),
          now: now,
        ),
        const Duration(seconds: 45),
      );
    });

    test('refreshes a five-minute token one minute before expiry', () {
      expect(
        authRefreshDelay(expiry: now.add(const Duration(minutes: 5)), now: now),
        const Duration(minutes: 4),
      );
    });

    test('refreshes a one-hour token one minute before expiry', () {
      expect(
        authRefreshDelay(expiry: now.add(const Duration(hours: 1)), now: now),
        const Duration(minutes: 59),
      );
    });

    test('waits before refreshing an already-expired token', () {
      expect(
        authRefreshDelay(
          expiry: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        const Duration(seconds: 30),
      );
    });
  });

  group('reconnect delay', () {
    test('grows with increasing attempt number', () {
      final first = reconnectDelay(0);
      final second = reconnectDelay(1);
      final third = reconnectDelay(2);

      expect(first, lessThan(second));
      expect(second, lessThan(third));
    });

    test('caps the base before applying jitter', () {
      expect(reconnectDelay(10), const Duration(seconds: 30));
      expect(reconnectDelay(20), const Duration(seconds: 30));
      expect(
        reconnectDelay(20, jitterFactor: 1.2),
        const Duration(seconds: 36),
      );
    });

    test('keeps jitter within twenty percent of the base delay', () {
      expect(
        reconnectDelay(3, jitterFactor: 0.8),
        const Duration(milliseconds: 6400),
      );
      expect(
        reconnectDelay(3, jitterFactor: 1.2),
        const Duration(milliseconds: 9600),
      );
    });
  });
}
