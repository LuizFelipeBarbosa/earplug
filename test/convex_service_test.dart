import 'dart:async';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:earplug/services/convex_service.dart';
import 'package:earplug/services/convex_transport.dart';
// fake_async is already resolved transitively for deterministic timer tests.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _pastGracePeriod = Duration(milliseconds: 251);

void main() {
  group('ConvexService shared subscriptions', () {
    test('shares equal canonical args and replays the current value', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final firstValues = <int>[];
        final secondValues = <String>[];
        final first = service
            .subscribe<int>('messages:list', <String, dynamic>{
              'page': 1,
              'filter': <String, dynamic>{'b': 2, 'a': 1},
            }, _parseValue)
            .listen(firstValues.add);
        addTearDown(first.cancel);
        async.flushMicrotasks();

        expect(transport.subscribeCalls, 1);
        transport.sendUpdate(0, '{"value":7}');
        async.flushMicrotasks();
        expect(firstValues, <int>[7]);

        final second = service
            .subscribe<String>('messages:list', <String, dynamic>{
              'filter': <String, dynamic>{'a': 1, 'b': 2},
              'page': 1,
            }, (decoded) => 'value:${_parseValue(decoded)}')
            .listen(secondValues.add);
        addTearDown(second.cancel);
        async.flushMicrotasks();

        expect(transport.subscribeCalls, 1);
        expect(secondValues, <String>['value:7']);
        _cancelAndExpire(async, <StreamSubscription<Object?>>[first, second]);
      });
    });

    test('creates independent subscriptions for different args', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final first = service
            .subscribe<int>('messages:list', <String, dynamic>{
              'page': 1,
            }, (decoded) => decoded as int)
            .listen((_) {});
        final second = service
            .subscribe<int>('messages:list', <String, dynamic>{
              'page': 2,
            }, (decoded) => decoded as int)
            .listen((_) {});
        addTearDown(first.cancel);
        addTearDown(second.cancel);
        async.flushMicrotasks();

        expect(transport.subscribeCalls, 2);
        _cancelAndExpire(async, <StreamSubscription<Object?>>[first, second]);
      });
    });

    test('reuses an upstream subscription during the cancellation grace', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final first = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              (decoded) => decoded as int,
            )
            .listen((_) {});
        addTearDown(first.cancel);
        async.flushMicrotasks();
        expect(transport.subscribeCalls, 1);

        unawaited(first.cancel());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));

        final second = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              (decoded) => decoded as int,
            )
            .listen((_) {});
        addTearDown(second.cancel);
        async.flushMicrotasks();

        expect(transport.subscribeCalls, 1);
        expect(transport.cancelCalls, 0);
        _cancelAndExpire(async, <StreamSubscription<Object?>>[second]);
        expect(transport.cancelCalls, 1);
      });
    });

    test('cancels after grace and starts fresh on a later listen', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final first = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              (decoded) => decoded as int,
            )
            .listen((_) {});
        addTearDown(first.cancel);
        async.flushMicrotasks();

        unawaited(first.cancel());
        async.flushMicrotasks();
        async.elapse(_pastGracePeriod);
        async.flushMicrotasks();
        expect(transport.cancelCalls, 1);

        final second = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              (decoded) => decoded as int,
            )
            .listen((_) {});
        addTearDown(second.cancel);
        async.flushMicrotasks();

        expect(transport.subscribeCalls, 2);
        _cancelAndExpire(async, <StreamSubscription<Object?>>[second]);
        expect(transport.cancelCalls, 2);
      });
    });

    test('skips byte-identical payloads and updates debug deltas', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final beforeSubscribe = ConvexService.debugStats.value;
        var parseCalls = 0;
        final values = <int>[];
        final subscription = service
            .subscribe<int>('messages:list', const <String, dynamic>{}, (
              decoded,
            ) {
              parseCalls++;
              return _parseValue(decoded);
            })
            .listen(values.add);
        addTearDown(subscription.cancel);
        async.flushMicrotasks();

        final afterSubscribe = ConvexService.debugStats.value;
        expect(
          afterSubscribe.activeSubscriptions -
              beforeSubscribe.activeSubscriptions,
          1,
        );

        const raw = '{"value":1}';
        final beforeUpdates = ConvexService.debugStats.value;
        transport
          ..sendUpdate(0, raw)
          ..sendUpdate(0, raw);
        async.flushMicrotasks();

        final afterUpdates = ConvexService.debugStats.value;
        expect(values, <int>[1]);
        expect(parseCalls, 1);
        expect(
          afterUpdates.duplicatePayloadsSkipped -
              beforeUpdates.duplicatePayloadsSkipped,
          1,
        );
        expect(
          afterUpdates.transitionsReceived - beforeUpdates.transitionsReceived,
          2,
        );
        expect(
          afterUpdates.bytesReceived - beforeUpdates.bytesReceived,
          raw.length * 2,
        );
        expect(afterUpdates.lastTransitionBytes, raw.length);
        expect(afterUpdates.lastTransitionAt, isNotNull);

        _cancelAndExpire(async, <StreamSubscription<Object?>>[subscription]);
        final afterCancel = ConvexService.debugStats.value;
        expect(
          afterCancel.activeSubscriptions - afterSubscribe.activeSubscriptions,
          -1,
        );
      });
    });

    test('delivers each changed payload to every attached parser', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        var firstParseCalls = 0;
        var secondParseCalls = 0;
        final firstValues = <int>[];
        final secondValues = <String>[];
        final first = service
            .subscribe<int>('messages:list', const <String, dynamic>{}, (
              decoded,
            ) {
              firstParseCalls++;
              return _parseValue(decoded);
            })
            .listen(firstValues.add);
        final second = service
            .subscribe<String>('messages:list', const <String, dynamic>{}, (
              decoded,
            ) {
              secondParseCalls++;
              return 'value:${_parseValue(decoded)}';
            })
            .listen(secondValues.add);
        addTearDown(first.cancel);
        addTearDown(second.cancel);
        async.flushMicrotasks();

        transport
          ..sendUpdate(0, '{"value":1}')
          ..sendUpdate(0, '{"value":2}');
        async.flushMicrotasks();

        expect(transport.subscribeCalls, 1);
        expect(firstValues, <int>[1, 2]);
        expect(secondValues, <String>['value:1', 'value:2']);
        expect(firstParseCalls, 2);
        expect(secondParseCalls, 2);
        _cancelAndExpire(async, <StreamSubscription<Object?>>[first, second]);
      });
    });

    test('forwards upstream errors to every attached listener', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final firstErrors = <Object>[];
        final secondErrors = <Object>[];
        final first = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              (decoded) => decoded as int,
            )
            .listen((_) {}, onError: firstErrors.add);
        final second = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              (decoded) => decoded as int,
            )
            .listen((_) {}, onError: secondErrors.add);
        addTearDown(first.cancel);
        addTearDown(second.cancel);
        async.flushMicrotasks();

        transport.sendError(0, 'subscription failed', 'details');
        async.flushMicrotasks();

        expect(
          firstErrors.single.toString(),
          'Exception: subscription failed: details',
        );
        expect(
          secondErrors.single.toString(),
          'Exception: subscription failed: details',
        );
        _cancelAndExpire(async, <StreamSubscription<Object?>>[first, second]);
      });
    });

    test('replays a decoded JSON null value', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final firstValues = <String>[];
        final secondValues = <String>[];
        String parseNull(dynamic decoded) => decoded == null ? 'null' : 'value';
        final first = service
            .subscribe<String>(
              'nullable:get',
              const <String, dynamic>{},
              parseNull,
            )
            .listen(firstValues.add);
        addTearDown(first.cancel);
        async.flushMicrotasks();
        transport.sendUpdate(0, 'null');
        async.flushMicrotasks();

        final second = service
            .subscribe<String>(
              'nullable:get',
              const <String, dynamic>{},
              parseNull,
            )
            .listen(secondValues.add);
        addTearDown(second.cancel);
        async.flushMicrotasks();

        expect(firstValues, <String>['null']);
        expect(secondValues, <String>['null']);
        _cancelAndExpire(async, <StreamSubscription<Object?>>[first, second]);
      });
    });
  });
}

ConvexService _initializedService(
  _FakeConvexTransport transport,
  FakeAsync async,
) {
  final service = ConvexService(transport: transport);
  unawaited(service.init('https://fake.convex.cloud'));
  async.flushMicrotasks();
  expect(transport.initializeCalls, 1);
  return service;
}

int _parseValue(dynamic decoded) {
  final value = decoded as Map<String, dynamic>;
  return value['value'] as int;
}

void _cancelAndExpire(
  FakeAsync async,
  List<StreamSubscription<Object?>> subscriptions,
) {
  for (final subscription in subscriptions) {
    unawaited(subscription.cancel());
  }
  async.flushMicrotasks();
  async.elapse(_pastGracePeriod);
  async.flushMicrotasks();
}

class _FakeConvexTransport implements ConvexTransport {
  final List<_FakeSubscriptionCall> subscriptions = [];
  int initializeCalls = 0;
  int subscribeCalls = 0;
  int cancelCalls = 0;

  @override
  bool get isConnected => true;

  @override
  Stream<WebSocketConnectionState> get connectionState => const Stream.empty();

  @override
  Duration get operationTimeout => const Duration(seconds: 1);

  @override
  Future<void> initialize(String url) {
    initializeCalls++;
    return Future<void>.value();
  }

  @override
  Future<String> query(String name, Map<String, dynamic> args) {
    return Future<String>.value('null');
  }

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) {
    return Future<String>.value('null');
  }

  @override
  Future<ConvexTransportSubscription> subscribe({
    required String name,
    required Map<String, dynamic> args,
    required void Function(String) onUpdate,
    required void Function(String, String?) onError,
  }) {
    subscribeCalls++;
    final call = _FakeSubscriptionCall(
      name: name,
      args: args,
      onUpdate: onUpdate,
      onError: onError,
    );
    subscriptions.add(call);
    return Future<ConvexTransportSubscription>.value(
      _FakeSubscriptionHandle(() {
        if (call.cancelled) return;
        call.cancelled = true;
        cancelCalls++;
      }),
    );
  }

  @override
  Future<void> setAuthWithRefresh({
    required Future<String?> Function() fetchToken,
  }) {
    return Future<void>.value();
  }

  @override
  Future<void> clearAuth() => Future<void>.value();

  void sendUpdate(int index, String raw) {
    subscriptions[index].onUpdate(raw);
  }

  void sendError(int index, String message, String? value) {
    subscriptions[index].onError(message, value);
  }
}

class _FakeSubscriptionCall {
  _FakeSubscriptionCall({
    required this.name,
    required this.args,
    required this.onUpdate,
    required this.onError,
  });

  final String name;
  final Map<String, dynamic> args;
  final void Function(String) onUpdate;
  final void Function(String, String?) onError;
  bool cancelled = false;
}

class _FakeSubscriptionHandle implements ConvexTransportSubscription {
  _FakeSubscriptionHandle(this._onCancel);

  final void Function() _onCancel;

  @override
  void cancel() => _onCancel();
}
