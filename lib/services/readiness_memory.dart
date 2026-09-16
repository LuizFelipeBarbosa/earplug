import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What a band's readiness checklist looked like the last time it was seen,
/// plus any regression noticed since: steps that were done and later failed.
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
  /// the band's memory over rather than failing the read.
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
  Future<ReadinessMemory?> read(String bandId);
  Future<void> write(String bandId, ReadinessMemory memory);
}

class MemoryReadinessMemoryStore implements ReadinessMemoryStore {
  MemoryReadinessMemoryStore([Map<String, ReadinessMemory> initial = const {}])
    : _memories = Map.of(initial);

  final Map<String, ReadinessMemory> _memories;

  @override
  Future<ReadinessMemory?> read(String bandId) async => _memories[bandId];

  @override
  Future<void> write(String bandId, ReadinessMemory memory) async {
    _memories[bandId] = memory;
  }
}

class PrefsReadinessMemoryStore implements ReadinessMemoryStore {
  PrefsReadinessMemoryStore({this._preferences});

  SharedPreferencesAsync? _preferences;

  static String _key(String bandId) => 'readiness-memory-$bandId';

  @override
  Future<ReadinessMemory?> read(String bandId) async {
    try {
      final preferences = _preferences ??= SharedPreferencesAsync();
      final stored = await preferences.getString(_key(bandId));
      return stored == null ? null : ReadinessMemory.decode(stored);
    } on Object {
      // Readiness memory is optional; unavailable storage starts fresh.
      return null;
    }
  }

  @override
  Future<void> write(String bandId, ReadinessMemory memory) async {
    try {
      final preferences = _preferences ??= SharedPreferencesAsync();
      await preferences.setString(_key(bandId), memory.encode());
    } on Object {
      // Storage failure must not interrupt the dashboard.
    }
  }
}
