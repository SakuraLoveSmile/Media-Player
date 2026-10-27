import 'key_value_store.dart';

/// Access token persistence (contract §7).
class TokenStore {
  TokenStore(this._store);

  static const String key = 'mp.token.v1';

  final KeyValueStore _store;

  Future<String?> read() => _store.read(key);

  Future<void> write(String token) => _store.write(key, token);

  Future<void> delete() => _store.delete(key);
}
