import 'package:earplug/services/recent_searches.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('recent search list helpers', () {
    test('push trims, deduplicates ignoring case, and moves to front', () {
      final current = ['Oakland', 'Punk', 'Free tonight'];
      final updated = pushRecentSearch(current, '  pUNK  ');

      expect(updated, ['pUNK', 'Oakland', 'Free tonight']);
      expect(current, ['Oakland', 'Punk', 'Free tonight']);
      expect(identical(updated, current), isFalse);
      expect(pushRecentSearch(['Punk', 'punk', 'Oakland'], 'PUNK'), [
        'PUNK',
        'Oakland',
      ]);
    });

    test('push ignores empty or whitespace-only input', () {
      final current = ['Oakland'];
      for (final query in ['', ' \t\n ']) {
        expect(identical(pushRecentSearch(current, query), current), isTrue);
      }
    });

    test('a fourth distinct query drops the oldest', () {
      var queries = <String>[];
      for (final query in ['first', 'second', 'third', 'fourth']) {
        queries = pushRecentSearch(queries, query);
      }
      expect(kRecentSearchLimit, 3);
      expect(queries, hasLength(kRecentSearchLimit));
      expect(queries, ['fourth', 'third', 'second']);
    });

    test('remove trims and ignores case without changing other entries', () {
      final current = ['Oakland', 'Punk', 'punk', 'Free tonight'];
      final updated = removeRecentSearch(current, '  PUNK  ');

      expect(updated, ['Oakland', 'Free tonight']);
      expect(current, ['Oakland', 'Punk', 'punk', 'Free tonight']);
      expect(removeRecentSearch(current, 'missing'), current);
    });
  });

  group('MemoryRecentSearchesStore', () {
    test('starts empty and round trips saved queries', () async {
      final store = MemoryRecentSearchesStore();
      expect(await store.load(), isEmpty);
      await store.save(['Punk', 'Free tonight', 'Oakland']);
      expect(await store.load(), ['Punk', 'Free tonight', 'Oakland']);
    });

    test('copies initial, saved, and loaded lists', () async {
      final initial = ['Oakland'];
      final store = MemoryRecentSearchesStore(initial);
      initial.clear();
      expect(await store.load(), ['Oakland']);

      final queries = ['Punk'];
      await store.save(queries);
      queries.clear();
      final loaded = await store.load();
      loaded.clear();
      expect(await store.load(), ['Punk']);
    });
  });

  group('PrefsRecentSearchesStore', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });
    tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

    test(
      'loads missing preferences as empty and persists the expected key',
      () async {
        final preferences = SharedPreferencesAsync();
        final store = PrefsRecentSearchesStore(preferences: preferences);
        expect(await store.load(), isEmpty);

        await store.save(['Punk', 'Oakland']);

        expect(await preferences.getStringList('recent_searches'), [
          'Punk',
          'Oakland',
        ]);
        expect(await PrefsRecentSearchesStore().load(), ['Punk', 'Oakland']);
      },
    );

    test('read errors return empty history', () async {
      SharedPreferencesAsyncPlatform.instance = _ReadFailingStore();
      expect(await PrefsRecentSearchesStore().load(), isEmpty);
    });

    test('write errors are swallowed', () async {
      SharedPreferencesAsyncPlatform.instance = _WriteFailingStore();
      await expectLater(PrefsRecentSearchesStore().save(['Punk']), completes);
    });

    test('storage is lazy and unavailable platforms do not throw', () async {
      SharedPreferencesAsyncPlatform.instance = null;
      final store = PrefsRecentSearchesStore();
      expect(await store.load(), isEmpty);
      await expectLater(store.save(['Punk']), completes);
    });
  });
}

base class _ReadFailingStore extends InMemorySharedPreferencesAsync {
  _ReadFailingStore() : super.empty();

  @override
  Future<List<String>?> getStringList(
    String key,
    SharedPreferencesOptions options,
  ) => Future.error(StateError('read failed'));
}

base class _WriteFailingStore extends InMemorySharedPreferencesAsync {
  _WriteFailingStore() : super.empty();

  @override
  Future<bool> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) => Future.error(StateError('write failed'));
}
