import 'dart:convert';

import 'package:flutter/material.dart' show Color, ColorScheme;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import '../ui/theme/app_accent.dart';
import 'providers.dart';

/// Storage key for the user-selected accent preference (S14).
const String accentStorageKey = 'app.accent.v1';

/// How the app-wide accent colour is chosen.
enum AccentMode {
  /// The original brand seed (默认).
  defaultMode('default'),

  /// One of the fixed preset hues (蓝/绿/紫/粉/橙).
  preset('preset'),

  /// The Android 12+ system (Monet) colour, with [AccentPreference.preset] as
  /// the fallback when the platform cannot provide one.
  monet('monet');

  const AccentMode(this.wireName);

  /// Stable id used in the persisted JSON.
  final String wireName;
}

/// The persisted appearance accent choice: `{mode, preset?}`.
///
/// [preset] is the selected preset id; in [AccentMode.monet] it doubles as the
/// fallback for platforms without dynamic colour. Null means the brand default.
class AccentPreference {
  const AccentPreference({this.mode = AccentMode.defaultMode, this.preset});

  /// Off by default: the brand palette, no Monet.
  static const AccentPreference defaults = AccentPreference();

  final AccentMode mode;
  final String? preset;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.wireName,
    if (preset != null) 'preset': preset,
  };

  /// Tolerant parse of the stored map. Unknown modes or preset ids fall back
  /// to the defaults — a corrupt write must never pick a colour the user did
  /// not choose.
  static AccentPreference fromJson(Map<String, Object?> json) {
    AccentMode? mode;
    for (final AccentMode value in AccentMode.values) {
      if (value.wireName == json['mode']) mode = value;
    }
    if (mode == null) return defaults;
    final Object? rawPreset = json['preset'];
    final AppAccentPreset? preset = AppAccentPresets.byName(
      rawPreset is String ? rawPreset.trim() : null,
    );
    // 'default' is not a fallback hue; it means "no preset".
    final String? name = preset == null || preset.name == 'default'
        ? null
        : preset.name;
    return switch (mode) {
      AccentMode.defaultMode => defaults,
      AccentMode.preset =>
        name == null
            ? defaults
            : AccentPreference(mode: AccentMode.preset, preset: name),
      AccentMode.monet => AccentPreference(
        mode: AccentMode.monet,
        preset: name,
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AccentPreference && other.mode == mode && other.preset == preset;

  @override
  int get hashCode => Object.hash(mode, preset);
}

/// Raised when the accent preference cannot be persisted.
class AccentSettingsException implements Exception {
  const AccentSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Key/value store backing the accent preference.
///
/// Reads the store created once by [bootstrapProvider] so the app never opens a
/// second backend. Tests override it with an in-memory store.
final FutureProvider<KeyValueStore?> accentStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Loads and persists the app-wide accent choice (default / preset / Monet).
///
/// The root `MaterialApp` watches this, so a change repaints every page with the
/// matching seed colour. Unreadable or unknown values fall back to
/// [AccentPreference.defaults]; write errors surface as
/// [AccentSettingsException] and keep the previous selection.
///
/// The player page keeps forcing its own dark brand theme for overlays, so this
/// preference only governs the rest of the app.
class AccentController extends AsyncNotifier<AccentPreference> {
  @override
  Future<AccentPreference> build() async {
    final KeyValueStore? store = await ref.watch(accentStoreProvider.future);
    if (store == null) return AccentPreference.defaults;
    try {
      return decodeAccentPreference(await store.read(accentStorageKey));
    } catch (_) {
      return AccentPreference.defaults;
    }
  }

  /// Selects a preset by its stable id; `default` restores the brand seed.
  /// Unknown ids are ignored. Picking a preset also leaves Monet mode.
  Future<void> selectPreset(String name) async {
    final AppAccentPreset? preset = AppAccentPresets.byName(name);
    if (preset == null) return;
    await _save(
      preset.name == 'default'
          ? AccentPreference.defaults
          : AccentPreference(mode: AccentMode.preset, preset: preset.name),
    );
  }

  /// Turns the Monet (跟随系统) option on/off. Turning it off returns to the
  /// preset kept as the fallback, or to the brand default.
  Future<void> setMonet(bool enabled) async {
    final AccentPreference current = state.value ?? AccentPreference.defaults;
    final AccentPreference next = enabled
        ? AccentPreference(mode: AccentMode.monet, preset: current.preset)
        : (current.preset == null
              ? AccentPreference.defaults
              : AccentPreference(
                  mode: AccentMode.preset,
                  preset: current.preset,
                ));
    await _save(next);
  }

  /// Persists [next] and applies it immediately. A harness without storage
  /// still switches the live accent; only restart-survival is lost.
  Future<void> _save(AccentPreference next) async {
    final AccentPreference current = state.value ?? AccentPreference.defaults;
    if (current == next) return;
    final KeyValueStore? store = await ref.read(accentStoreProvider.future);
    if (store != null) {
      try {
        await store.write(accentStorageKey, jsonEncode(next.toJson()));
      } catch (error) {
        throw AccentSettingsException('主题色保存失败：$error');
      }
    }
    if (!ref.mounted) return;
    state = AsyncData<AccentPreference>(next);
  }
}

/// Tolerant decode of the stored value: the `{mode, preset?}` JSON map, a
/// legacy bare preset name (`green` / `"green"`), anything else (null, empty,
/// corrupt JSON, unknown ids) means the brand default.
AccentPreference decodeAccentPreference(String? raw) {
  final String? text = raw?.trim();
  if (text == null || text.isEmpty) return AccentPreference.defaults;
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    // Pre-JSON legacy writes stored the bare preset name.
    decoded = text;
  }
  if (decoded is Map<String, dynamic>) {
    return AccentPreference.fromJson(decoded);
  }
  if (decoded is String) {
    final AppAccentPreset? preset = AppAccentPresets.byName(decoded.trim());
    if (preset == null || preset.name == 'default') {
      return AccentPreference.defaults;
    }
    return AccentPreference(mode: AccentMode.preset, preset: preset.name);
  }
  return AccentPreference.defaults;
}

/// Resolves the seed colour for one brightness.
///
/// [dynamicScheme] is the system (Monet) scheme for that brightness, or null
/// when the platform cannot provide one (non-Android, pre-Android 12, or the
/// OS has not answered yet). Monet falls back to the stored preset, then to
/// null — which makes `buildAppTheme` use the brand default.
Color? resolveAccentColor(
  AccentPreference preference,
  ColorScheme? dynamicScheme,
) {
  if (preference.mode == AccentMode.monet && dynamicScheme != null) {
    return dynamicScheme.primary;
  }
  return AppAccentPresets.byName(preference.preset)?.color;
}

/// Selected accent preference; defaults to the brand palette, Monet off.
final AsyncNotifierProvider<AccentController, AccentPreference>
accentControllerProvider =
    AsyncNotifierProvider<AccentController, AccentPreference>(
      AccentController.new,
    );
