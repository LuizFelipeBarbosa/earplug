import 'dart:io';

import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart' show FakeAuthService;
import 'package:flutter_test/flutter_test.dart';

import 'stub_repository.dart';

Matcher _argumentError(String method, String message) => throwsA(
  isA<ArgumentError>()
      .having((error) => error.invalidValue, 'invalidValue', method)
      .having((error) => error.name, 'name', 'method')
      .having((error) => error.message, 'message', message),
);

void main() {
  test('method sets exactly match the intercepted source methods', () {
    const path = 'test/support/stub_repository.dart';
    var sourceFile = File(path);
    if (!sourceFile.existsSync()) {
      sourceFile = File.fromUri(Directory.current.uri.resolve(path));
    }
    final source = sourceFile.readAsStringSync();

    for (final (interceptor, methods) in [
      ('intercept', StubRepository.futureMethods),
      ('_interceptStream', StubRepository.streamMethods),
    ]) {
      final names = RegExp(
        "\\b$interceptor\\(\\s*'([^']+)'",
      ).allMatches(source).map((match) => match.group(1)!).toSet();
      expect(names, isNotEmpty, reason: 'No $interceptor calls found');
      expect(
        methods,
        unorderedEquals(names),
        reason: '$interceptor keys drifted',
      );
    }
    expect(
      StubRepository.futureMethods.intersection(StubRepository.streamMethods),
      isEmpty,
    );
  });

  test('configuration rejects unknown method names', () {
    final stub = StubRepository(auth: FakeAuthService());
    final matcher = _argumentError(
      'nope',
      'StubRepository does not intercept this method',
    );

    expect(() => stub.fail('nope'), matcher);
    expect(() => stub.failOnce('nope'), matcher);
    expect(() => stub.returns('nope', null), matcher);
    expect(() => stub.wraps<Object?>('nope', (real) => real), matcher);
    expect(() => stub.gate('nope'), matcher);
    expect(
      () => stub.returnsStream<Object?>('nope', () => const Stream.empty()),
      matcher,
    );
  });

  test('configuration rejects recognized methods of the wrong kind', () {
    final stub = StubRepository(auth: FakeAuthService());
    final streamError = _argumentError(
      'myBands',
      'StubRepository does not intercept this method',
    );

    expect(() => stub.wraps<Object?>('myBands', (real) => real), streamError);
    expect(() => stub.gate('myBands'), streamError);
    expect(
      () => stub.returnsStream<Object?>('venues', () => const Stream.empty()),
      _argumentError('venues', 'StubRepository does not intercept this method'),
    );
  });

  test(
    'stream returns require a factory and allow repeated subscriptions',
    () async {
      final stub = StubRepository(auth: FakeAuthService());
      expect(
        () =>
            stub.returns('myBands', const Stream<List<BandMembership>>.empty()),
        _argumentError(
          'myBands',
          'Stream methods use returnsStream, not returns',
        ),
      );

      var builds = 0;
      stub.returnsStream<List<BandMembership>>('myBands', () {
        builds++;
        return Stream.value(<BandMembership>[]);
      });

      expect(await stub.myBands().toList(), [<BandMembership>[]]);
      expect(await stub.myBands().toList(), [<BandMembership>[]]);
      expect(builds, 2);
      expect(stub.callsTo('myBands'), 2);
    },
  );

  test(
    'failOnce throws once before returning a configured Future value',
    () async {
      final error = StateError('try again');
      final stub = StubRepository(auth: FakeAuthService())
        ..returns('venues', Future.value(<Venue>[]))
        ..failOnce('venues', error);

      await expectLater(stub.venues(), throwsA(same(error)));
      expect(await stub.venues(), isEmpty);
      expect(stub.callsTo('venues'), 2);
    },
  );

  test('stream failOnce emits an error before using the factory', () async {
    final error = StateError('try again');
    var builds = 0;
    final stub = StubRepository(auth: FakeAuthService())
      ..returnsStream<List<BandMembership>>('myBands', () {
        builds++;
        return Stream.value(<BandMembership>[]);
      })
      ..failOnce('myBands', error);

    await expectLater(stub.myBands(), emitsError(same(error)));
    expect(builds, 0);
    expect(await stub.myBands().first, isEmpty);
    expect(builds, 1);
    expect(stub.callsTo('myBands'), 2);
  });

  test('gate holds a call while counting it immediately', () async {
    final stub = StubRepository(auth: FakeAuthService())
      ..returns('venues', <Venue>[]);
    final gate = stub.gate('venues');
    var resolved = false;
    final pending = stub.venues().then((venues) {
      resolved = true;
      return venues;
    });

    expect(stub.callsTo('venues'), 1);
    await Future<void>.delayed(Duration.zero);
    expect(resolved, isFalse);

    gate.complete();
    expect(await pending, isEmpty);
    expect(resolved, isTrue);
    expect(stub.callsTo('venues'), 1);
  });

  test('wraps transforms the real result', () async {
    final stub = StubRepository(auth: FakeAuthService());
    final original = await stub.venues();
    expect(original, isNotEmpty);

    stub.wraps<List<Venue>>('venues', (real) {
      expect(real, orderedEquals(original));
      return real.skip(1).toList();
    });

    expect(await stub.venues(), orderedEquals(original.skip(1)));
    expect(stub.callsTo('venues'), 2);
  });
}
