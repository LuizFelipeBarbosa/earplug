import 'package:shared_preferences/shared_preferences.dart';

abstract class RecentSearchesStore {
  Future<List<String>> load();
  Future<void> save(List<String> queries);
}

class PrefsRecentSearchesStore implements RecentSearchesStore {
  PrefsRecentSearchesStore({this._preferences});

  SharedPreferencesAsync? _preferences;
  static const _key = 'recent_searches';

  @override
  Future<List<String>> load() async {
    try {
      final preferences = _preferences ??= SharedPreferencesAsync();
      return await preferences.getStringList(_key) ?? [];
    } on Object {
      // Search history is optional; unavailable storage starts empty.
      return [];
    }
  }

  @override
  Future<void> save(List<String> queries) async {
    try {
      final preferences = _preferences ??= SharedPreferencesAsync();
      await preferences.setStringList(_key, queries);
    } on Object {
      // Storage failure must not interrupt searching.
    }
  }
}

const kRecentSearchLimit = 3;

List<String> pushRecentSearch(List<String> current, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return current;

  final normalized = trimmed.toLowerCase();
  return [
    trimmed,
    for (final entry in current)
      if (entry.trim().toLowerCase() != normalized) entry,
  ].take(kRecentSearchLimit).toList();
}

List<String> removeRecentSearch(List<String> current, String query) {
  final normalized = query.trim().toLowerCase();
  return [
    for (final entry in current)
      if (entry.trim().toLowerCase() != normalized) entry,
  ];
}
