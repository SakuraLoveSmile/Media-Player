import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/danmaku/danmaku_settings.dart';
import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Key/value store backing the danmaku defaults (S36).
final FutureProvider<KeyValueStore?> danmakuSettingsStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Loads and persists the app-wide danmaku defaults. The player controller
/// reads the same [DanmakuSettings.storageKey] at open, so changes apply to
/// the next playback; the in-player sheet keeps editing the same blob for
/// session-level tweaks.
class DanmakuSettingsController extends AsyncNotifier<DanmakuSettings> {
  @override
  Future<DanmakuSettings> build() async {
    final KeyValueStore? store = await ref.watch(
      danmakuSettingsStoreProvider.future,
    );
    if (store == null) return const DanmakuSettings();
    try {
      final String? raw = await store.read(DanmakuSettings.storageKey);
      if (raw == null || raw.isEmpty) return const DanmakuSettings();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const DanmakuSettings();
      return DanmakuSettings.fromJson(decoded);
    } catch (_) {
      return const DanmakuSettings();
    }
  }

  Future<void> _persist(DanmakuSettings next) async {
    final KeyValueStore? store = await ref.read(
      danmakuSettingsStoreProvider.future,
    );
    if (store != null) {
      await store.write(DanmakuSettings.storageKey, jsonEncode(next.toJson()));
    }
    if (!ref.mounted) return;
    state = AsyncData<DanmakuSettings>(next);
  }

  DanmakuSettings get _current => state.value ?? const DanmakuSettings();

  Future<void> setEnabled(bool enabled) =>
      _persist(_current.copyWith(enabled: enabled));

  Future<void> setDensity(double value) =>
      _persist(_current.copyWith(density: value.clamp(0.1, 1.0)));

  Future<void> setOpacity(double value) =>
      _persist(_current.copyWith(opacity: value.clamp(0.1, 1.0)));

  Future<void> setSpeed(double value) =>
      _persist(_current.copyWith(speed: value.clamp(0.5, 2.0)));

  Future<void> setFullArea(bool fullArea) =>
      _persist(_current.copyWith(fullArea: fullArea));
}

final AsyncNotifierProvider<DanmakuSettingsController, DanmakuSettings>
danmakuSettingsControllerProvider =
    AsyncNotifierProvider<DanmakuSettingsController, DanmakuSettings>(
      DanmakuSettingsController.new,
    );
