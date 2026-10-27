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
  final secure = SecureKeyValueStore(_buildSecureStorage());

  try {
    await secure.write(probeKey, 'ok');
    final value = await secure.read(probeKey);
    await secure.delete(probeKey);
    if (value == 'ok') return secure;
  } catch (error) {
    // Only the exception type is logged; values never reach the log.
    log?.call(
      'secure storage unavailable (${error.runtimeType}); '
      'using 0600 file fallback',
    );
  }

  final directory = fallbackDirectory ?? await getApplicationSupportDirectory();
  return FileKeyValueStore(File('${directory.path}/mp_storage_v1.json'));
}

FlutterSecureStorage _buildSecureStorage() {
  if (Platform.isMacOS) {
    // The data-protection keychain requires a team identifier, which ad-hoc
    // builds do not have (errSecMissingEntitlement). The login keychain works
    // without one, so try it first and keep the file fallback for the rest.
    return const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    );
  }
  return const FlutterSecureStorage();
}
