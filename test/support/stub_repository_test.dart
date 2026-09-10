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
