import 'dart:convert';

import 'key_value_store.dart';
import '../models/server_entry.dart';
import '../models/server_profile.dart';

/// Persists a configured server profile (contract §10.1).
///
/// Server-scoped (S20): [defaultServerId] keeps the original key; other ids get
/// a suffixed key in the same backend.
class ProfileStore {
  ProfileStore(this._store, {this.serverId = defaultServerId});

  static const String key = 'mp.profile.v1';
  static const int schemaVersion = 1;

  final KeyValueStore _store;
  final String serverId;

  /// Effective storage key for [serverId].
  String get scopedKey => serverId == defaultServerId ? key : '$key.$serverId';

  Future<ServerProfile?> read() async {
    final raw = await _store.read(scopedKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['schemaVersion'] != schemaVersion) return null;
      final profile = map['profile'];
      if (profile is! Map) return null;
      final parsed = ServerProfile.fromJson(Map<String, dynamic>.from(profile));
      return parsed.hasAnyAddress ? parsed : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(ServerProfile profile) {
    return _store.write(
      scopedKey,
      jsonEncode(<String, dynamic>{
        'schemaVersion': schemaVersion,
        'profile': profile.toJson(),
      }),
    );
  }

  Future<void> delete() => _store.delete(scopedKey);
}
