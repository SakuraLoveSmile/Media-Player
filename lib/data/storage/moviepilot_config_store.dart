import 'dart:convert';

import '../moviepilot/models/moviepilot_config.dart';
import 'key_value_store.dart';

/// Persists the single MoviePilot connection (plan S1).
///
/// The API token is an administrator key, so it lives in the same key/value
/// backend as the Emby token (keystore on Android/Windows, `0600` file on
/// ad-hoc macOS builds) and never in plain preferences.
class MoviePilotConfigStore {
  MoviePilotConfigStore(this._store);

  static const String key = 'mp.moviepilot.v1';
  static const int schemaVersion = 1;

  final KeyValueStore _store;

  Future<MoviePilotConfig?> read() async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['schemaVersion'] != schemaVersion) return null;
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
