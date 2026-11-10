import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Storage key for the 求片 notification preference.
const String requestNotificationStorageKey = 'request.notifications.v1';

/// Raised when the preference cannot be persisted.
class RequestNotificationSettingsException implements Exception {
  const RequestNotificationSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Key/value store backing the preference.
///
/// Reads the store created once by [bootstrapProvider] so the app never opens a
/// second backend. Tests override it with an in-memory store.
final FutureProvider<KeyValueStore?> requestNotificationStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Which channels announce a finished 求片.
///
/// Both default to on: a request that finished while the user was elsewhere is
/// exactly the thing they asked to be told about, and the settings toggle is
/// there to turn it off.
class RequestNotificationSettings {
  const RequestNotificationSettings({
    this.inApp = true,
    this.system = true,
  });

  static const RequestNotificationSettings defaults =
      RequestNotificationSettings();

  /// Show the in-app glass banner.
  final bool inApp;

  /// Show an OS notification (Android / macOS / Windows).
  final bool system;

  RequestNotificationSettings copyWith({bool? inApp, bool? system}) {
    return RequestNotificationSettings(
      inApp: inApp ?? this.inApp,
      system: system ?? this.system,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RequestNotificationSettings &&
      other.inApp == inApp &&
      other.system == system;

  @override
  int get hashCode => Object.hash(inApp, system);
}

/// Loads and persists the notification preference.
///
/// Unreadable values fall back to [RequestNotificationSettings.defaults] so a
/// corrupt write never silences a user for good; write errors surface as
/// [RequestNotificationSettingsException] and keep the previous selection.
class RequestNotificationSettingsController
    extends AsyncNotifier<RequestNotificationSettings> {
  @override
  Future<RequestNotificationSettings> build() async {
    final KeyValueStore? store =
        await ref.watch(requestNotificationStoreProvider.future);
    if (store == null) return RequestNotificationSettings.defaults;
    try {
      return _decode(await store.read(requestNotificationStorageKey));
    } catch (_) {
      return RequestNotificationSettings.defaults;
    }
  }

  Future<void> set({bool? inApp, bool? system}) async {
    final next = (state.value ?? RequestNotificationSettings.defaults)
        .copyWith(inApp: inApp, system: system);
    if (next == state.value) return;
    final KeyValueStore? store =
        await ref.read(requestNotificationStoreProvider.future);
    if (store != null) {
      try {
        await store.write(requestNotificationStorageKey, _encode(next));
      } catch (error) {
        throw RequestNotificationSettingsException('通知设置保存失败：$error');
      }
    }
    state = AsyncData(next);
  }

  /// `1|0` — short, versioned by the key, and tolerant of anything else.
  static String _encode(RequestNotificationSettings settings) =>
      '${settings.inApp ? 1 : 0}|${settings.system ? 1 : 0}';

  static RequestNotificationSettings _decode(String? raw) {
    if (raw == null) return RequestNotificationSettings.defaults;
    final parts = raw.split('|');
    if (parts.length != 2) return RequestNotificationSettings.defaults;
    return RequestNotificationSettings(
      inApp: parts[0] == '1',
      system: parts[1] == '1',
    );
  }
}

final AsyncNotifierProvider<
  RequestNotificationSettingsController,
  RequestNotificationSettings
>
requestNotificationSettingsProvider =
    AsyncNotifierProvider<
      RequestNotificationSettingsController,
      RequestNotificationSettings
    >(RequestNotificationSettingsController.new);
