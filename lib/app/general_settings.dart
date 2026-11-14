import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import 'preference_keys.dart';
import 'providers.dart';

/// Storage key for the 忽略 SSL 证书错误 preference (S32).
const String ignoreSslStorageKey = AppPreferenceKeys.ignoreSsl;

/// Raised when the SSL preference cannot be persisted.
class GeneralSettingsException implements Exception {
  const GeneralSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Key/value store backing the general preferences.
final FutureProvider<KeyValueStore?> generalSettingsStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Whether HTTPS requests accept self-signed certificates.
///
/// The HTTP client is built once at bootstrap, so this preference applies to
/// the next app launch; the settings row says so. Off by default: certificate
/// errors stay visible unless the user opts in for a self-signed server.
class IgnoreSslController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final KeyValueStore? store = await ref.watch(
      generalSettingsStoreProvider.future,
    );
    if (store == null) return false;
    try {
      return await store.read(ignoreSslStorageKey) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final bool current = state.value ?? false;
    if (current == enabled) return;
    final KeyValueStore? store = await ref.read(
      generalSettingsStoreProvider.future,
    );
    if (store != null) {
      try {
        await store.write(ignoreSslStorageKey, enabled ? 'true' : 'false');
      } catch (error) {
        throw GeneralSettingsException('SSL 偏好保存失败：$error');
      }
    }
    if (!ref.mounted) return;
    state = AsyncData<bool>(enabled);
  }
}

final AsyncNotifierProvider<IgnoreSslController, bool>
ignoreSslControllerProvider = AsyncNotifierProvider<IgnoreSslController, bool>(
  IgnoreSslController.new,
);
