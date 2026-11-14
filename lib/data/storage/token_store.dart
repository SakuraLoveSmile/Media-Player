import '../models/server_entry.dart';
import 'key_value_store.dart';

/// Access token persistence (contract §7).
///
/// Server-scoped (S20): the [defaultServerId] keeps the original key so an
/// existing install's token is reused untouched; any other id gets a suffixed
/// key in the same secure backend. The token is never logged.
class TokenStore {
  TokenStore(this._store, {this.serverId = defaultServerId});

  static const String key = 'mp.token.v1';

  final KeyValueStore _store;
  final String serverId;

  /// Effective storage key for [serverId].
  String get scopedKey => serverId == defaultServerId ? key : '$key.$serverId';

  Future<String?> read() => _store.read(scopedKey);

  Future<void> write(String token) => _store.write(scopedKey, token);

  Future<void> delete() => _store.delete(scopedKey);
}
