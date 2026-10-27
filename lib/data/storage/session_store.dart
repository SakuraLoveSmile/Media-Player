import 'dart:convert';

import 'key_value_store.dart';
import '../models/auth_session.dart';

/// Session metadata without the token (contract §10.1).
class SessionStore {
  SessionStore(this._store);

  static const String key = 'mp.session.v1';

  final KeyValueStore _store;

  /// Returns metadata with an empty [AuthSession.accessToken]; the caller
  /// combines it with `TokenStore`.
  Future<AuthSession?> read() async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final session = AuthSession.fromMetaJson(
        Map<String, dynamic>.from(decoded),
        accessToken: '',
      );
      if (session.userId.isEmpty) return null;
      return session;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(AuthSession session) =>
      _store.write(key, jsonEncode(session.toMetaJson()));

  Future<void> delete() => _store.delete(key);
}
