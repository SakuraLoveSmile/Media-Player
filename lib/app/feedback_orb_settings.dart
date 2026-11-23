import 'dart:convert';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Storage keys for the host-managed feedback preferences (feedback_widget
/// >= 0.11.0). The values are host-owned: the widget only renders them and
/// reports in-panel changes through its callbacks.
const String feedbackLauncherStyleStorageKey = 'feedback.launcher_style.v1';
const String feedbackWakeVisualStorageKey = 'feedback.wake_visual.v1';
const String feedbackOrbEntranceStorageKey = 'feedback.orb_entrance.v1';
const String feedbackOrbIdleStorageKey = 'feedback.orb_idle_style.v1';
const String feedbackWakeGesturesStorageKey = 'feedback.wake_gestures.v1';

/// Host-managed feedback preferences shown on the settings page.
///
/// Every field is handed to [FeedbackWidget] as a value, so the component's own
/// settings page never renders these choices (the layer also sets
/// `hideSettings`).
class FeedbackOrbSettings {
  const FeedbackOrbSettings({
    this.launcherStyle = FeedbackLauncherStyle.beam,
    this.wakeVisual = FeedbackWakeVisual.ripple,
    this.orbEntrance = FeedbackOrbEntrance.bead,
    this.idleStyle = FeedbackOrbIdleStyle.handle,
    this.wakeGestures = const <FeedbackWakeGesture>{
      FeedbackWakeGesture.twoFingerHold,
    },
  });

  /// Defaults mirror the component's own 0.11.0 defaults: beam wake with the
  /// ripple effect and the two-finger long press, plus a collapsed orb handle.
  static const FeedbackOrbSettings defaults = FeedbackOrbSettings();

  /// 光束唤醒 or 灵感球; rendered instead of the component's own choice.
  final FeedbackLauncherStyle launcherStyle;

  /// Ripple / aurora wake animation (only used by the beam launcher).
  final FeedbackWakeVisual wakeVisual;

  /// Entrance animation played when a wake gesture summons the orb.
  final FeedbackOrbEntrance orbEntrance;

  /// Idle (collapsed) orb style; only meaningful for the orb launcher.
  final FeedbackOrbIdleStyle idleStyle;

  /// Wake gestures; an empty set disables gesture summoning.
  final Set<FeedbackWakeGesture> wakeGestures;

  FeedbackOrbSettings copyWith({
    FeedbackLauncherStyle? launcherStyle,
    FeedbackWakeVisual? wakeVisual,
    FeedbackOrbEntrance? orbEntrance,
    FeedbackOrbIdleStyle? idleStyle,
    Set<FeedbackWakeGesture>? wakeGestures,
  }) {
    return FeedbackOrbSettings(
      launcherStyle: launcherStyle ?? this.launcherStyle,
      wakeVisual: wakeVisual ?? this.wakeVisual,
      orbEntrance: orbEntrance ?? this.orbEntrance,
      idleStyle: idleStyle ?? this.idleStyle,
      wakeGestures: wakeGestures ?? this.wakeGestures,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FeedbackOrbSettings &&
        other.launcherStyle == launcherStyle &&
        other.wakeVisual == wakeVisual &&
        other.orbEntrance == orbEntrance &&
        other.idleStyle == idleStyle &&
        _sameGestures(other.wakeGestures, wakeGestures);
  }

  @override
  int get hashCode => Object.hash(
    launcherStyle,
    wakeVisual,
    orbEntrance,
    idleStyle,
    Object.hashAll(FeedbackWakeGesture.values.where(wakeGestures.contains)),
  );

  static bool _sameGestures(
    Set<FeedbackWakeGesture> a,
    Set<FeedbackWakeGesture> b,
  ) => a.length == b.length && a.containsAll(b);
}

/// Raised when the host preferences cannot be persisted.
class FeedbackOrbSettingsException implements Exception {
  const FeedbackOrbSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Key/value store backing the feedback preferences.
///
/// Reads the store created once by [bootstrapProvider] so the app never opens a
/// second credential backend. Tests override it with an in-memory store.
final FutureProvider<KeyValueStore?> feedbackOrbStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Loads and persists the host-managed feedback preferences.
///
/// Storage errors while loading fall back to [FeedbackOrbSettings.defaults] so
/// the settings page stays usable; write errors surface as
/// [FeedbackOrbSettingsException] and keep the previous value.
class FeedbackOrbSettingsController extends AsyncNotifier<FeedbackOrbSettings> {
  @override
  Future<FeedbackOrbSettings> build() async {
    final KeyValueStore? store = await ref.watch(
      feedbackOrbStoreProvider.future,
    );
    if (store == null) return FeedbackOrbSettings.defaults;
    return FeedbackOrbSettings(
      launcherStyle: _decodeEnum(
        await _readQuietly(store, feedbackLauncherStyleStorageKey),
        FeedbackLauncherStyle.values,
        FeedbackOrbSettings.defaults.launcherStyle,
      ),
      wakeVisual: _decodeEnum(
        await _readQuietly(store, feedbackWakeVisualStorageKey),
        FeedbackWakeVisual.values,
        FeedbackOrbSettings.defaults.wakeVisual,
      ),
      orbEntrance: _decodeEnum(
        await _readQuietly(store, feedbackOrbEntranceStorageKey),
        FeedbackOrbEntrance.values,
        FeedbackOrbSettings.defaults.orbEntrance,
      ),
      idleStyle: _decodeEnum(
        await _readQuietly(store, feedbackOrbIdleStorageKey),
        FeedbackOrbIdleStyle.values,
        FeedbackOrbSettings.defaults.idleStyle,
      ),
      wakeGestures: _decodeWakeGestures(
        await _readQuietly(store, feedbackWakeGesturesStorageKey),
      ),
    );
  }

  Future<void> setLauncherStyle(FeedbackLauncherStyle style) async {
    final FeedbackOrbSettings current =
        state.value ?? FeedbackOrbSettings.defaults;
    if (current.launcherStyle == style) return;
    await _persist(
      feedbackLauncherStyleStorageKey,
      style.name,
      (FeedbackOrbSettings latest) => latest.copyWith(launcherStyle: style),
    );
  }

  Future<void> setWakeVisual(FeedbackWakeVisual visual) async {
    final FeedbackOrbSettings current =
        state.value ?? FeedbackOrbSettings.defaults;
    if (current.wakeVisual == visual) return;
    await _persist(
      feedbackWakeVisualStorageKey,
      visual.name,
      (FeedbackOrbSettings latest) => latest.copyWith(wakeVisual: visual),
    );
  }

  Future<void> setOrbEntrance(FeedbackOrbEntrance entrance) async {
    final FeedbackOrbSettings current =
        state.value ?? FeedbackOrbSettings.defaults;
    if (current.orbEntrance == entrance) return;
    await _persist(
      feedbackOrbEntranceStorageKey,
      entrance.name,
      (FeedbackOrbSettings latest) => latest.copyWith(orbEntrance: entrance),
    );
  }

  Future<void> setIdleStyle(FeedbackOrbIdleStyle style) async {
    final FeedbackOrbSettings current =
        state.value ?? FeedbackOrbSettings.defaults;
    if (current.idleStyle == style) return;
    await _persist(
      feedbackOrbIdleStorageKey,
      style.name,
      (FeedbackOrbSettings latest) => latest.copyWith(idleStyle: style),
    );
  }

  Future<void> setWakeGestures(Set<FeedbackWakeGesture> gestures) async {
    final FeedbackOrbSettings current =
        state.value ?? FeedbackOrbSettings.defaults;
    final Set<FeedbackWakeGesture> normalized = <FeedbackWakeGesture>{
      for (final FeedbackWakeGesture gesture in FeedbackWakeGesture.values)
        if (gestures.contains(gesture)) gesture,
    };
    if (current.wakeGestures.length == normalized.length &&
        current.wakeGestures.containsAll(normalized)) {
      return;
    }
    await _persist(
      feedbackWakeGesturesStorageKey,
      jsonEncode(<String>[
        for (final FeedbackWakeGesture gesture in FeedbackWakeGesture.values)
          if (normalized.contains(gesture)) gesture.id,
      ]),
      (FeedbackOrbSettings latest) => latest.copyWith(wakeGestures: normalized),
    );
  }

  Future<void> toggleWakeGesture(
    FeedbackWakeGesture gesture, {
    required bool enabled,
  }) async {
    final FeedbackOrbSettings current =
        state.value ?? FeedbackOrbSettings.defaults;
    final Set<FeedbackWakeGesture> next = <FeedbackWakeGesture>{
      ...current.wakeGestures,
    };
    if (enabled) {
      next.add(gesture);
    } else {
      next.remove(gesture);
    }
    await setWakeGestures(next);
  }

  Future<void> _persist(
    String key,
    String value,
    FeedbackOrbSettings Function(FeedbackOrbSettings latest) update,
  ) async {
    final KeyValueStore? store = await ref.read(
      feedbackOrbStoreProvider.future,
    );
    if (store == null) {
      throw const FeedbackOrbSettingsException('本机存储不可用，设置未保存');
    }
    try {
      await store.write(key, value);
    } catch (_) {
      throw const FeedbackOrbSettingsException('保存失败，请稍后重试');
    }
    if (!ref.mounted) return;
    final FeedbackOrbSettings latest =
        state.value ?? FeedbackOrbSettings.defaults;
    state = AsyncData<FeedbackOrbSettings>(update(latest));
  }

  static Future<String?> _readQuietly(KeyValueStore store, String key) async {
    try {
      return await store.read(key);
    } catch (_) {
      return null;
    }
  }
}

T _decodeEnum<T extends Enum>(String? raw, List<T> values, T fallback) {
  final String? name = raw?.trim();
  for (final T candidate in values) {
    if (candidate.name == name) return candidate;
  }
  return fallback;
}

Set<FeedbackWakeGesture> _decodeWakeGestures(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return FeedbackOrbSettings.defaults.wakeGestures;
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const <FeedbackWakeGesture>{};
    final Set<String> ids = decoded.whereType<String>().toSet();
    return <FeedbackWakeGesture>{
      for (final FeedbackWakeGesture gesture in FeedbackWakeGesture.values)
        if (ids.contains(gesture.id)) gesture,
    };
  } on FormatException {
    return const <FeedbackWakeGesture>{};
  }
}

final AsyncNotifierProvider<FeedbackOrbSettingsController, FeedbackOrbSettings>
feedbackOrbSettingsProvider =
    AsyncNotifierProvider<FeedbackOrbSettingsController, FeedbackOrbSettings>(
      FeedbackOrbSettingsController.new,
    );
