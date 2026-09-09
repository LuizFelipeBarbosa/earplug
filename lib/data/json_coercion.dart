// Shared JSON-coercion helpers used when parsing Convex query/mutation
// results into typed models. Several variants exist because call sites
// historically tolerated different malformed-input shapes; keep the
// distinctions below rather than merging them, or you will change parsing
// behavior for real payloads.

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is! List<Object?>) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in value)
      if (item is Map<String, dynamic>) item,
  ];
}

String asString(Object? value) => value is String ? value : '';

String? asOptionalString(Object? value) => value is String ? value : null;

int asInt(Object? value) => value is num ? value.toInt() : 0;

int? asOptionalInt(Object? value) => value is num ? value.toInt() : null;

num asNum(Object? value) => value is num ? value : 0;

num? asOptionalNum(Object? value) => value is num ? value : null;

bool asBool(Object? value) => value is bool ? value : false;

List<String> asStringList(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is String) item,
];

// Finite-number-aware int coercion. Differs from asInt/asOptionalInt: NaN
// and +/-Infinity are treated as absent rather than converted with toInt().
int asFiniteInt(Object? value) => asOptionalFiniteInt(value) ?? 0;

int? asOptionalFiniteInt(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

DateTime asDate(Object? value) =>
    asOptionalDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

DateTime? asOptionalDate(Object? value) {
  final milliseconds = asOptionalFiniteInt(value);
  if (milliseconds == null ||
      milliseconds < -8640000000000000 ||
      milliseconds > 8640000000000000) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

// Lenient map coercion: accepts any Map (not just Map<String, dynamic>) and
// keeps only entries whose key is a String, instead of rejecting the whole
// value like asMap does.
Map<String, dynamic> asFilteredMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

List<Map<String, dynamic>> asFilteredMapList(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map) asFilteredMap(item),
];

// Cast-based map coercion: treats null as {} but otherwise force-casts,
// throwing if [value] is not a Map or has non-castable entries. Differs
// from asMap and asFilteredMap, which never throw.
Map<String, dynamic> asCastMap(dynamic value) {
  if (value == null) return const {};
  return Map<String, dynamic>.from(value as Map);
}

List<Map<String, dynamic>> asCastMapList(dynamic value) {
  if (value == null) return const [];
  return [
    for (final item in value as List) Map<String, dynamic>.from(item as Map),
  ];
}
