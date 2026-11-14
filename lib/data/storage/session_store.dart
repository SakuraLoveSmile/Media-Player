import 'dart:convert';

import 'key_value_store.dart';
import '../models/auth_session.dart';
import '../models/server_entry.dart';

/// Session metadata without the token (contract §10.1).
///
/// Server-scoped (S20): [defaultServerId] keeps the original key; other ids get
/// a suffixed key in the same secure backend.
class SessionStore {
  SessionStore(this._store, {this.serverId = defaultServerId});

  static const String key = 'mp.session.v1';

  final KeyValueStore _store;
  final String serverId;

  /// Effective storage key for [serverId].
  String get scopedKey => serverId == defaultServerId ? key : '$key.$serverId';

  /// Returns metadata with an empty [AuthSession.accessToken]; the caller
  /// combines it with `TokenStore`.
  Future<AuthSession?> read() async {
    final raw = await _store.read(scopedKey);
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
      _store.write(scopedKey, jsonEncode(session.toMetaJson()));

  Future<void> delete() => _store.delete(scopedKey);
}
