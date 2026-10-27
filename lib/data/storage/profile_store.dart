import 'dart:convert';

import 'key_value_store.dart';
import '../models/server_profile.dart';

/// Persists the single configured server profile (contract §10.1).
class ProfileStore {
  ProfileStore(this._store);

  static const String key = 'mp.profile.v1';
  static const int schemaVersion = 1;

  final KeyValueStore _store;

  Future<ServerProfile?> read() async {
    final raw = await _store.read(key);
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
      key,
      jsonEncode(<String, dynamic>{
        'schemaVersion': schemaVersion,
        'profile': profile.toJson(),
      }),
    );
  }

  Future<void> delete() => _store.delete(key);
}
