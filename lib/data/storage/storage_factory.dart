import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'file_key_value_store.dart';
import 'key_value_store.dart';
import 'secure_key_value_store.dart';

typedef StorageLogger = void Function(String message);

/// Chooses the credential backend once per process (contract §7, §10.1).
///
/// Prefers the platform keystore; if a write/read/delete round-trip fails —
/// which happens on macOS builds signed ad-hoc without a Developer ID — it
/// falls back to a `0600` JSON file in Application Support.
Future<KeyValueStore> createKeyValueStore({
  Directory? fallbackDirectory,
  StorageLogger? log,
}) async {
  const probeKey = '__mp_storage_probe__';
  final secure = SecureKeyValueStore(const FlutterSecureStorage());

  try {
    await secure.write(probeKey, 'ok');
    final value = await secure.read(probeKey);
    await secure.delete(probeKey);
    if (value == 'ok') return secure;
  } catch (_) {
    // Fall through to the file backend.
  }

  log?.call('secure storage unavailable; using 0600 file fallback');
  final directory = fallbackDirectory ?? await getApplicationSupportDirectory();
  return FileKeyValueStore(File('${directory.path}/mp_storage_v1.json'));
}
