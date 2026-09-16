import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What a readiness checklist looked like the last time it was seen, plus
/// any regression noticed since: steps that were done and later failed. One
/// record per scope key (`band:<bandId>`, `org:<orgId>`).
class ReadinessMemory {
  final Set<String> doneIds;
  final DateTime seenAt;
  final DateTime? regressedAt;
  final Set<String> regressedIds;
  final bool regressionAcknowledged;

  const ReadinessMemory({
    required this.doneIds,
    required this.seenAt,
    this.regressedAt,
    this.regressedIds = const {},
    this.regressionAcknowledged = false,
  });

  bool get hasRegression => regressedAt != null && regressedIds.isNotEmpty;

  ReadinessMemory copyWith({
    Set<String>? doneIds,
    DateTime? seenAt,
    DateTime? regressedAt,
    Set<String>? regressedIds,
    bool? regressionAcknowledged,
    bool clearRegression = false,
  }) => ReadinessMemory(
    doneIds: doneIds ?? this.doneIds,
    seenAt: seenAt ?? this.seenAt,
    regressedAt: clearRegression ? null : regressedAt ?? this.regressedAt,
    regressedIds: clearRegression
        ? const {}
        : regressedIds ?? this.regressedIds,
    regressionAcknowledged: clearRegression
        ? false
        : regressionAcknowledged ?? this.regressionAcknowledged,
  );

  /// Equal in everything a reader can act on; [seenAt] moves on every look.
  bool hasSameStateAs(ReadinessMemory other) =>
      _sameIds(doneIds, other.doneIds) &&
      regressedAt == other.regressedAt &&
      _sameIds(regressedIds, other.regressedIds) &&
      regressionAcknowledged == other.regressionAcknowledged;

  static bool _sameIds(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Map<String, Object?> toJson() => {
    'doneIds': doneIds.toList(),
    'seenAt': seenAt.toUtc().toIso8601String(),
    'regressedAt': regressedAt?.toUtc().toIso8601String(),
    'regressedIds': regressedIds.toList(),
    'regressionAcknowledged': regressionAcknowledged,
  };

  factory ReadinessMemory.fromJson(Map<String, dynamic> json) =>
      ReadinessMemory(
        doneIds: _ids(json['doneIds']),
        seenAt: _date(json['seenAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        regressedAt: _date(json['regressedAt']),
        regressedIds: _ids(json['regressedIds']),
        regressionAcknowledged: json['regressionAcknowledged'] == true,
      );

  String encode() => jsonEncode(toJson());

  /// Null for anything that is not a JSON object; a corrupt record starts
  /// the scope's memory over rather than failing the read.
  static ReadinessMemory? decode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return ReadinessMemory.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  static Set<String> _ids(Object? value) => {
    if (value is List)
      for (final id in value)
        if (id is String) id,
  };

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

abstract class ReadinessMemoryStore {
  Future<ReadinessMemory?> read(String scopeKey);
  Future<void> write(String scopeKey, ReadinessMemory memory);
}

class MemoryReadinessMemoryStore implements ReadinessMemoryStore {
  MemoryReadinessMemoryStore([Map<String, ReadinessMemory> initial = const {}])
    : _memories = Map.of(initial);

  final Map<String, ReadinessMemory> _memories;

  @override
  Future<ReadinessMemory?> read(String scopeKey) async => _memories[scopeKey];

  @override
  Future<void> write(String scopeKey, ReadinessMemory memory) async {
    _memories[scopeKey] = memory;
  }
}

class PrefsReadinessMemoryStore implements ReadinessMemoryStore {
  PrefsReadinessMemoryStore({this._preferences});

  SharedPreferencesAsync? _preferences;

  static const _bandScopePrefix = 'band:';

  /// Band memories predate scope keys and were stored under the bare band id;
  /// keeping that key means nothing is forgotten on upgrade.
  static String _key(String scopeKey) {
    final legacyBandId = scopeKey.startsWith(_bandScopePrefix)
        ? scopeKey.substring(_bandScopePrefix.length)
        : null;
    return 'readiness-memory-${legacyBandId ?? scopeKey}';
  }

  @override
  Future<ReadinessMemory?> read(String scopeKey) async {
    try {
      final preferences = _preferences ??= SharedPreferencesAsync();
      final stored = await preferences.getString(_key(scopeKey));
      return stored == null ? null : ReadinessMemory.decode(stored);
    } on Object {
      // Readiness memory is optional; unavailable storage starts fresh.
      return null;
    }
  }

  @override
  Future<void> write(String scopeKey, ReadinessMemory memory) async {
    try {
      final preferences = _preferences ??= SharedPreferencesAsync();
      await preferences.setString(_key(scopeKey), memory.encode());
    } on Object {
      // Storage failure must not interrupt the dashboard.
    }
  }
}
