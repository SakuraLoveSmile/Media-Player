import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'file_key_value_store.dart';
import 'key_value_store.dart';
import 'secure_key_value_store.dart';

typedef StorageLogger = void Function(String message);

/// Chooses the credential backend once per process (contract §7, §10.1).
///
/// Android/Windows use the platform keystore after a write/read/delete probe.
/// macOS ad-hoc builds go straight to a `0600` JSON file in Application
/// Support, because re-signing on every build makes the keychain prompt for
/// access to items created by the previous build.
Future<KeyValueStore> createKeyValueStore({
  Directory? fallbackDirectory,
  StorageLogger? log,
}) async {
  // Ad-hoc signed macOS builds get a new code signature on every rebuild. The
  // login keychain then prompts "Media Player wants to use ... in your
  // keychain" for items created by the previous build — and the prompt blocks
  // the probe. Contract §7 allows the 0600 file fallback in exactly this case.
  // Switch to the keychain explicitly once a Developer ID exists:
  //   flutter build macos --dart-define=USE_KEYCHAIN_MACOS=true
  if (Platform.isMacOS && !_useKeychainOnMacOS) {
    log?.call(
      'macOS ad-hoc build: using 0600 file store; pass '
      '--dart-define=USE_KEYCHAIN_MACOS=true to use the keychain',
    );
    return _fileStore(fallbackDirectory);
  }

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

  return _fileStore(fallbackDirectory);
}

Future<FileKeyValueStore> _fileStore(Directory? fallbackDirectory) async {
  final directory = fallbackDirectory ?? await getApplicationSupportDirectory();
  return FileKeyValueStore(File('${directory.path}/mp_storage_v1.json'));
}

const bool _useKeychainOnMacOS = bool.fromEnvironment('USE_KEYCHAIN_MACOS');

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
