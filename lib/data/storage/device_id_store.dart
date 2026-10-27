import 'package:uuid/uuid.dart';

import 'key_value_store.dart';

/// Stable device id for `X-Emby-Device-Id` (contract §1.4, §10.7).
class DeviceIdStore {
  DeviceIdStore(this._store, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const String key = 'mp.deviceId.v1';

  final KeyValueStore _store;
  final Uuid _uuid;

  Future<String> getOrCreate() async {
    final existing = await _store.read(key);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _uuid.v4();
    await _store.write(key, generated);
    return generated;
  }
}
