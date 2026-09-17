import 'package:earplug/services/readiness_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'support/fakes.dart';

final _seenAt = DateTime.utc(2026, 9, 15, 12);
final _regressedAt = DateTime.utc(2026, 9, 16, 8, 30);

ReadinessMemory _regressed() => ReadinessMemory(
  doneIds: {'band-discovery-profile', 'band-setup-social'},
  seenAt: _seenAt,
  regressedAt: _regressedAt,
  regressedIds: {'band-discovery-image'},
  regressionAcknowledged: true,
);

void main() {
  group('ReadinessMemory', () {
    test('round trips through JSON', () {
      final memory = _regressed();
      final decoded = ReadinessMemory.fromJson(memory.toJson());

      expect(decoded.doneIds, memory.doneIds);
      expect(decoded.seenAt, memory.seenAt);
      expect(decoded.regressedAt, memory.regressedAt);
      expect(decoded.regressedIds, memory.regressedIds);
      expect(decoded.regressionAcknowledged, isTrue);
      expect(decoded.hasRegression, isTrue);
      expect(decoded.hasSameStateAs(memory), isTrue);
    });

    test('round trips through its string form without a regression', () {
      final memory = ReadinessMemory(
        doneIds: {'band-discovery-clip'},
        seenAt: _seenAt,
      );
      final decoded = ReadinessMemory.decode(memory.encode())!;

      expect(decoded.doneIds, {'band-discovery-clip'});
      expect(decoded.seenAt, _seenAt);
      expect(decoded.regressedAt, isNull);
      expect(decoded.regressedIds, isEmpty);
      expect(decoded.regressionAcknowledged, isFalse);
      expect(decoded.hasRegression, isFalse);
    });

    test('decode rejects corrupt or non-object records', () {
      expect(ReadinessMemory.decode('not json'), isNull);
      expect(ReadinessMemory.decode('[1, 2]'), isNull);
      expect(ReadinessMemory.decode('"text"'), isNull);
    });

    test('decode tolerates missing or mistyped fields', () {
      final decoded = ReadinessMemory.decode(
        '{"doneIds": ["a", 3, null], "seenAt": 12, "regressedIds": "x"}',
      )!;
      expect(decoded.doneIds, {'a'});
      expect(decoded.regressedIds, isEmpty);
      expect(decoded.regressedAt, isNull);
      expect(decoded.hasRegression, isFalse);
    });

    test('sameness ignores seenAt but not the regression fields', () {
      final memory = _regressed();
      expect(
        memory.hasSameStateAs(memory.copyWith(seenAt: DateTime.utc(2030))),
        isTrue,
      );
      expect(
        memory.hasSameStateAs(memory.copyWith(regressionAcknowledged: false)),
        isFalse,
      );
      expect(
        memory.hasSameStateAs(memory.copyWith(doneIds: {'band-setup-social'})),
        isFalse,
      );
      expect(
        memory.hasSameStateAs(memory.copyWith(clearRegression: true)),
        isFalse,
      );
    });

    test('clearRegression drops every regression field', () {
      final cleared = _regressed().copyWith(clearRegression: true);
      expect(cleared.regressedAt, isNull);
      expect(cleared.regressedIds, isEmpty);
      expect(cleared.regressionAcknowledged, isFalse);
      expect(cleared.doneIds, _regressed().doneIds);
    });
  });

  group('MemoryReadinessMemoryStore', () {
    test('starts empty and keeps one record per scope', () async {
      final store = MemoryReadinessMemoryStore();
      expect(await store.read('band:b1'), isNull);

      await store.write('band:b1', _regressed());
      expect((await store.read('band:b1'))!.regressedIds, {
        'band-discovery-image',
      });
      expect(await store.read('band:b2'), isNull);
      expect(await store.read('org:b1'), isNull);
    });
  });

  group('PrefsReadinessMemoryStore', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });
    tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

    test('reads missing bands as null and persists a band scope under the '
        'legacy per-band key', () async {
      final preferences = SharedPreferencesAsync();
      final store = PrefsReadinessMemoryStore(preferences: preferences);
      expect(await store.read('band:b1'), isNull);

      await store.write('band:b1', _regressed());

      final stored = await preferences.getString('readiness-memory-b1');
      expect(stored, isNotNull);
      expect(
        ReadinessMemory.decode(stored!)!.hasSameStateAs(_regressed()),
        isTrue,
      );
      expect(await preferences.getString('readiness-memory-band:b1'), isNull);
      expect(await preferences.getString('readiness-memory-b2'), isNull);

      final reread = (await PrefsReadinessMemoryStore().read('band:b1'))!;
      expect(reread.hasSameStateAs(_regressed()), isTrue);
      expect(reread.seenAt, _seenAt);
      expect(await PrefsReadinessMemoryStore().read('band:b2'), isNull);
    });

    test('a band scope reads a record written before scope keys', () async {
      final preferences = SharedPreferencesAsync();
      await preferences.setString('readiness-memory-b1', _regressed().encode());

      final store = PrefsReadinessMemoryStore(preferences: preferences);
      expect(
        (await store.read('band:b1'))!.hasSameStateAs(_regressed()),
        isTrue,
      );
      expect(await store.read('org:b1'), isNull);
    });

    test('an org scope persists under its own scoped key', () async {
      final preferences = SharedPreferencesAsync();
      final store = PrefsReadinessMemoryStore(preferences: preferences);

      await store.write('org:o1', _regressed());

      final stored = await preferences.getString('readiness-memory-org:o1');
      expect(stored, isNotNull);
      expect(
        ReadinessMemory.decode(stored!)!.hasSameStateAs(_regressed()),
        isTrue,
      );
      expect(await preferences.getString('readiness-memory-o1'), isNull);
      expect(
        (await store.read('org:o1'))!.hasSameStateAs(_regressed()),
        isTrue,
      );
      expect(await store.read('band:o1'), isNull);
    });

    test('a corrupt record reads as null', () async {
      final preferences = SharedPreferencesAsync();
      await preferences.setString('readiness-memory-b1', '{broken');
      expect(
        await PrefsReadinessMemoryStore(
          preferences: preferences,
        ).read('band:b1'),
        isNull,
      );
    });

    test('storage is lazy and unavailable platforms do not throw', () async {
      SharedPreferencesAsyncPlatform.instance = null;
      final store = PrefsReadinessMemoryStore();
      expect(await store.read('band:b1'), isNull);
      await expectLater(store.write('band:b1', _regressed()), completes);
    });
  });
}
