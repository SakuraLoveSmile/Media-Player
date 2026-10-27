/// Tolerant JSON readers.
///
/// Emby mixes numbers, numeric strings and nulls across versions (for example
/// `RunTimeTicks`), and a single unexpected type must never crash a page.
library;

int asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? asString(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  return null;
}

String asStringOr(Object? value, String fallback) => asString(value) ?? fallback;

bool asBool(Object? value, {bool fallback = false}) =>
    value is bool ? value : fallback;

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
