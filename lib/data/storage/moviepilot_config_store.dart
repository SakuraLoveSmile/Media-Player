import 'dart:convert';

import '../moviepilot/models/moviepilot_config.dart';
import 'key_value_store.dart';

/// Persists the single MoviePilot connection (plan S1).
///
/// Holds the bearer token plus the account name, in the same key/value backend
/// as the Emby token (keystore on Android/Windows, `0600` file on ad-hoc macOS
/// builds) and never in plain preferences. The password is never written here.
class MoviePilotConfigStore {
  MoviePilotConfigStore(this._store);

  static const String key = 'mp.moviepilot.v1';

  /// v2 replaced the instance API key with a per-user bearer token (求片 S16).
  /// Records of any other version are dropped on read instead of being kept
  /// around: a stale administrator key must not survive the upgrade.
  static const int schemaVersion = 2;

  final KeyValueStore _store;

  Future<MoviePilotConfig?> read() async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['schemaVersion'] != schemaVersion) {
        await _store.delete(key);
        return null;
      }
      final config = map['config'];
      if (config is! Map) return null;
      return MoviePilotConfig.fromJson(Map<String, dynamic>.from(config));
    } on FormatException {
      return null;
    }
  }

  Future<void> write(MoviePilotConfig config) {
    return _store.write(
      key,
      jsonEncode(<String, dynamic>{
        'schemaVersion': schemaVersion,
        'config': config.toJson(),
      }),
    );
  }

  Future<void> delete() => _store.delete(key);
}
