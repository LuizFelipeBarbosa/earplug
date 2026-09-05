import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:earplug/services/convex_service.dart';
import 'package:earplug/services/convex_transport.dart';
import 'package:earplug/widgets/form_bits.dart';
// fake_async is already resolved transitively for deterministic timer tests.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _pastGracePeriod = Duration(milliseconds: 251);

void main() {
  group('ConvexService query/mutation error handling', () {
    const message = 'Paid offers open once payments are enabled';
    const rawError =
        '[Request ID: abc] Server Error\n'
        'Uncaught Error: $message\n'
        '    at handler (...)\n';
    late _FakeConvexTransport transport;
    late ConvexService service;

    setUp(() async {
      transport = _FakeConvexTransport();
      service = ConvexService(transport: transport);
      await service.init('https://fake.convex.cloud');
    });

    test(
      'mutation and action throw a typed error and preserve the form message',
      () async {
        transport
          ..mutationResult = jsonEncode(rawError)
          ..actionResult = jsonEncode(rawError);
        final errorMatcher = throwsA(
          isA<ConvexFunctionException>()
              .having((error) => error.message, 'message', rawError)
              .having((error) => error.requestId, 'requestId', 'abc')
              .having((error) => error.toString(), 'toString()', rawError)
              .having(serverErrorMessage, 'serverErrorMessage()', message),
        );

        await expectLater(service.mutation('bookings:sendOffer'), errorMatcher);
        await expectLater(service.action('bookings:someAction'), errorMatcher);
      },
    );

    test(
      'query throws a typed error with the raw text and request ID',
      () async {
        transport.queryResult = jsonEncode(rawError);

        await expectLater(
          service.query('bookings:get'),
          throwsA(
            isA<ConvexFunctionException>()
                .having((error) => error.message, 'message', rawError)
                .having((error) => error.requestId, 'requestId', 'abc'),
          ),
        );
      },
    );

    test(
      'returns ordinary strings and other decoded JSON values as-is',
      () async {
        for (final value in <Object?>[
          'the-foghorn-club',
          '',
          'Uncaught Error: ordinary text without a server error marker',
          'Text mentioning [Request ID: abc] away from the start',
          'server error',
          <String, Object?>{'message': rawError},
          <Object?>[rawError],
          42,
          1.5,
          true,
          false,
          null,
        ]) {
          transport
            ..queryResult = jsonEncode(value)
            ..mutationResult = jsonEncode(value)
            ..actionResult = jsonEncode(value);

          expect(await service.query('values:get'), value);
          expect(await service.mutation('values:set'), value);
          expect(await service.action('values:doThing'), value);
        }
      },
    );

    test(
      'recognizes either error marker and parses only a leading ID',
      () async {
        for (final entry in <String, String?>{
          '[Request ID:   abc   ] Uncaught Error: $message': 'abc',
          'Unexpected Server Error\nUncaught Error: $message': null,
          'Server Error [Request ID: abc]\nUncaught Error: $message': null,
        }.entries) {
          transport
            ..queryResult = jsonEncode(entry.key)
            ..mutationResult = jsonEncode(entry.key)
            ..actionResult = jsonEncode(entry.key);
          final errorMatcher = throwsA(
            isA<ConvexFunctionException>()
                .having((error) => error.message, 'message', entry.key)
                .having((error) => error.requestId, 'requestId', entry.value),
          );

          await expectLater(service.query('values:get'), errorMatcher);
          await expectLater(service.mutation('values:set'), errorMatcher);
          await expectLater(service.action('values:doThing'), errorMatcher);
        }
      },
    );

    test('propagates transport rejections unchanged', () async {
      for (final error in <Object>[
        Exception(rawError),
        rawError,
        const ConvexFunctionException(rawError, requestId: 'abc'),
        StateError('connection failed'),
      ]) {
        transport
          ..queryError = error
          ..mutationError = error
          ..actionError = error;

        await expectLater(service.query('values:get'), throwsA(same(error)));
        await expectLater(service.mutation('values:set'), throwsA(same(error)));
        await expectLater(
          service.action('values:doThing'),
          throwsA(same(error)),
        );
      }
    });
  });

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

    test(
      'keeps the upstream registered after an error so a later update reaches '
      'long-lived listeners',
      () {
        fakeAsync((async) {
          final transport = _FakeConvexTransport();
          final service = _initializedService(transport, async);
          final values = <int>[];
          final errors = <Object>[];
          final subscription = service
              .subscribe<int>(
                'messages:list',
                const <String, dynamic>{},
                _parseValue,
              )
              .listen(values.add, onError: errors.add);
          addTearDown(subscription.cancel);
          async.flushMicrotasks();

          transport.sendError(0, 'subscription failed', null);
          async.flushMicrotasks();

          expect(errors.single.toString(), 'Exception: subscription failed');

          transport.sendUpdate(0, '{"value":5}');
          async.flushMicrotasks();

          expect(values, <int>[5]);
          expect(transport.subscribeCalls, 1);
          expect(transport.cancelCalls, 0);

          transport.sendUpdate(0, '{"value":5}');
          async.flushMicrotasks();

          expect(values, <int>[5]);
          _cancelAndExpire(async, <StreamSubscription<Object?>>[subscription]);
        });
      },
    );

    test(
      'a payload identical to the pre-error value is delivered after the error',
      () {
        fakeAsync((async) {
          final transport = _FakeConvexTransport();
          final service = _initializedService(transport, async);
          final values = <int>[];
          final subscription = service
              .subscribe<int>(
                'messages:list',
                const <String, dynamic>{},
                _parseValue,
              )
              .listen(values.add, onError: (_) {});
          addTearDown(subscription.cancel);
          async.flushMicrotasks();

          transport
            ..sendUpdate(0, '{"value":1}')
            ..sendError(0, 'subscription failed', null)
            ..sendUpdate(0, '{"value":1}');
          async.flushMicrotasks();

          expect(values, <int>[1, 1]);
          _cancelAndExpire(async, <StreamSubscription<Object?>>[subscription]);
        });
      },
    );

    test('restarts after an error when a listener quickly re-subscribes', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final firstErrors = <Object>[];
        final first = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              _parseValue,
            )
            .listen((_) {}, onError: firstErrors.add);
        addTearDown(first.cancel);
        async.flushMicrotasks();

        transport
          ..sendUpdate(0, '{"value":1}')
          ..sendError(0, 'subscription failed', 'details');
        async.flushMicrotasks();

        expect(
          firstErrors.single.toString(),
          'Exception: subscription failed: details',
        );
        expect(transport.cancelCalls, 0);
        unawaited(first.cancel());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));

        final values = <int>[];
        final second = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              _parseValue,
            )
            .listen(values.add);
        addTearDown(second.cancel);
        async.flushMicrotasks();

        expect(transport.cancelCalls, 1);
        expect(transport.subscribeCalls, 2);
        expect(values, isEmpty);
        transport.sendUpdate(1, '{"value":2}');
        async.flushMicrotasks();
        expect(values, <int>[2]);

        _cancelAndExpire(async, <StreamSubscription<Object?>>[second]);
      });
    });

    test('restarts once while another listener remains attached', () {
      fakeAsync((async) {
        final transport = _FakeConvexTransport();
        final service = _initializedService(transport, async);
        final firstErrors = <Object>[];
        final secondErrors = <Object>[];
        final secondValues = <int>[];
        final first = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              _parseValue,
            )
            .listen((_) {}, onError: firstErrors.add);
        final second = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              _parseValue,
            )
            .listen(secondValues.add, onError: secondErrors.add);
        addTearDown(first.cancel);
        addTearDown(second.cancel);
        async.flushMicrotasks();

        transport.sendError(0, 'subscription failed', null);
        async.flushMicrotasks();

        expect(firstErrors.single.toString(), 'Exception: subscription failed');
        expect(
          secondErrors.single.toString(),
          'Exception: subscription failed',
        );
        expect(transport.cancelCalls, 0);
        unawaited(first.cancel());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));

        final thirdValues = <int>[];
        final third = service
            .subscribe<int>(
              'messages:list',
              const <String, dynamic>{},
              _parseValue,
            )
            .listen(thirdValues.add);
        addTearDown(third.cancel);
        async.flushMicrotasks();

        expect(transport.cancelCalls, 1);
        expect(transport.subscribeCalls, 2);
        transport.sendUpdate(1, '{"value":3}');
        async.flushMicrotasks();
        expect(secondValues, <int>[3]);
        expect(thirdValues, <int>[3]);

        _cancelAndExpire(async, <StreamSubscription<Object?>>[second, third]);
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
  String queryResult = 'null';
  String mutationResult = 'null';
  String actionResult = 'null';
  Object? queryError;
  Object? mutationError;
  Object? actionError;

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
    final error = queryError;
    if (error != null) return Future<String>.error(error);
    return Future<String>.value(queryResult);
  }

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) {
    final error = mutationError;
    if (error != null) return Future<String>.error(error);
    return Future<String>.value(mutationResult);
  }

  @override
  Future<String> action({
    required String name,
    required Map<String, dynamic> args,
  }) {
    final error = actionError;
    if (error != null) return Future<String>.error(error);
    return Future<String>.value(actionResult);
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
