import 'dart:convert';

import '../moviepilot/models/media_request.dart';
import '../moviepilot/progress/poll_snapshot.dart';
import 'key_value_store.dart';

/// Persists the user's 求片 list plus the last poll snapshot (plan S5).
///
/// One key holds both so a restored page can paint the last known progress
/// before the first poll answers. Nothing here is a credential; the API token
/// lives in [MoviePilotConfigStore].
class RequestStore {
  RequestStore(this._store);

  static const String key = 'mp.requests.v1';
  static const int schemaVersion = 1;

  final KeyValueStore _store;

  /// Reads the records in creation order. A corrupt payload yields an empty
  /// list instead of throwing: losing the list is recoverable, a crash on the
  /// 求片 page is not.
  Future<List<MediaRequest>> read() async {
    final raw = await _store.read(key);
    final decoded = _decode(raw);
    if (decoded == null) return const <MediaRequest>[];
    return <MediaRequest>[
      for (final map in _maps(decoded['requests']))
        ?MediaRequest.fromJson(map),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// The snapshot from the last completed round, or null when there is none.
  Future<PollSnapshot?> readSnapshot() async {
    final raw = await _store.read(key);
    final decoded = _decode(raw);
    if (decoded == null) return null;
    final snapshot = decoded['snapshot'];
    if (snapshot is! Map) return null;
    try {
      return PollSnapshot.fromJson(Map<String, dynamic>.from(snapshot));
    } on FormatException {
      return null;
    }
  }

  Future<void> write(
    List<MediaRequest> requests, {
    PollSnapshot? snapshot,
  }) {
    return _store.write(
      key,
      jsonEncode(<String, dynamic>{
        'schemaVersion': schemaVersion,
        'requests': <Map<String, dynamic>>[
          for (final request in requests) request.toJson(),
        ],
        if (snapshot != null) 'snapshot': snapshot.toJson(),
      }),
    );
  }

  /// Replaces the request list and keeps the stored snapshot.
  Future<void> writeRequests(List<MediaRequest> requests) async {
    final snapshot = await readSnapshot();
    await write(requests, snapshot: snapshot);
  }

  Future<void> delete() => _store.delete(key);

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['schemaVersion'] != schemaVersion) return null;
      return map;
    } on FormatException {
      return null;
    }
  }

  static List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}
