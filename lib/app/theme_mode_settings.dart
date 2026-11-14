import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Storage key for the user-selected appearance mode.
const String themeModeStorageKey = 'app.themeMode.v1';

/// Raised when the appearance preference cannot be persisted.
class ThemeModeSettingsException implements Exception {
  const ThemeModeSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Key/value store backing the appearance preference.
///
/// Reads the store created once by [bootstrapProvider] so the app never opens a
/// second backend. Tests override it with an in-memory store.
final FutureProvider<KeyValueStore?> themeModeStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Loads and persists the app-wide theme mode (system / light / dark).
///
/// The root `MaterialApp` watches this, so a change repaints every page with the
/// matching Material palette. Unreadable or unknown values fall back to
/// [ThemeMode.system] — a corrupt write must never leave the app stuck in a
/// palette the user did not pick; write errors surface as
/// [ThemeModeSettingsException] and keep the previous selection.
///
/// The player page keeps forcing its own dark Material theme for overlays, so this
/// preference only governs the rest of the app.
class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final KeyValueStore? store = await ref.watch(themeModeStoreProvider.future);
    if (store == null) return ThemeMode.system;
    try {
      return decodeThemeMode(await store.read(themeModeStorageKey));
    } catch (_) {
      return ThemeMode.system;
    }
  }

  /// Persists [mode] and applies it immediately.
  ///
  /// A harness without storage still switches the live palette; only the
  /// restart-survival part is lost.
  Future<void> setMode(ThemeMode mode) async {
    final ThemeMode current = state.value ?? ThemeMode.system;
    if (current == mode) return;
    final KeyValueStore? store = await ref.read(themeModeStoreProvider.future);
    if (store != null) {
      try {
        await store.write(themeModeStorageKey, mode.name);
      } catch (error) {
        throw ThemeModeSettingsException('主题模式保存失败：$error');
      }
    }
    if (!ref.mounted) return;
    state = AsyncData<ThemeMode>(mode);
  }
}

/// Tolerant decode of the stored value: `system` / `light` / `dark`, anything
/// else (null, empty, a legacy or hand-edited string) means follow the system.
ThemeMode decodeThemeMode(String? raw) {
  final String? name = raw?.trim();
  for (final ThemeMode mode in ThemeMode.values) {
    if (mode.name == name) return mode;
  }
  return ThemeMode.system;
}

/// Selected appearance mode; defaults to following the system.
final AsyncNotifierProvider<ThemeModeController, ThemeMode>
themeModeControllerProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(
      ThemeModeController.new,
    );
