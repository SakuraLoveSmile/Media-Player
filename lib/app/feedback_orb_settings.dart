import 'dart:convert';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Storage keys for the host-managed feedback orb preferences.
///
/// The values are host-owned: the widget only renders them and reports changes
/// through its callbacks (feedback_widget >= 0.8.4).
const String feedbackOrbIdleStorageKey = 'feedback.orb_idle_style.v1';
const String feedbackWakeGesturesStorageKey = 'feedback.wake_gestures.v1';

/// Host-managed feedback orb preferences shown on the settings page.
class FeedbackOrbSettings {
  const FeedbackOrbSettings({
    this.idleStyle = FeedbackOrbIdleStyle.handle,
    this.wakeGestures = const <FeedbackWakeGesture>{},
  });

  /// Defaults match the component's own defaults: a collapsed handle and no
  /// wake gesture.
  static const FeedbackOrbSettings defaults = FeedbackOrbSettings();

  final FeedbackOrbIdleStyle idleStyle;
  final Set<FeedbackWakeGesture> wakeGestures;

  FeedbackOrbSettings copyWith({
    FeedbackOrbIdleStyle? idleStyle,
    Set<FeedbackWakeGesture>? wakeGestures,
  }) {
    return FeedbackOrbSettings(
      idleStyle: idleStyle ?? this.idleStyle,
      wakeGestures: wakeGestures ?? this.wakeGestures,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FeedbackOrbSettings &&
        other.idleStyle == idleStyle &&
        _sameGestures(other.wakeGestures, wakeGestures);
  }

  @override
  int get hashCode => Object.hash(
        idleStyle,
        Object.hashAll(FeedbackWakeGesture.values.where(wakeGestures.contains)),
      );

  static bool _sameGestures(
    Set<FeedbackWakeGesture> a,
    Set<FeedbackWakeGesture> b,
  ) =>
      a.length == b.length && a.containsAll(b);
}

/// Raised when the host preferences cannot be persisted.
class FeedbackOrbSettingsException implements Exception {
  const FeedbackOrbSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Key/value store backing the feedback orb preferences.
///
/// Reads the store created once by [bootstrapProvider] so the app never opens a
/// second credential backend. Tests override it with an in-memory store.
final FutureProvider<KeyValueStore?> feedbackOrbStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
  final services = await ref.watch(bootstrapProvider.future);
  return services.store;
});

/// Loads and persists the host-managed orb style / wake gestures.
///
/// Storage errors while loading fall back to [FeedbackOrbSettings.defaults] so
/// the settings page stays usable; write errors surface as
/// [FeedbackOrbSettingsException] and keep the previous value.
class FeedbackOrbSettingsController extends AsyncNotifier<FeedbackOrbSettings> {
  @override
  Future<FeedbackOrbSettings> build() async {
    final KeyValueStore? store = await ref.watch(feedbackOrbStoreProvider.future);
    if (store == null) return FeedbackOrbSettings.defaults;
    return FeedbackOrbSettings(
      idleStyle: _decodeIdleStyle(await _readQuietly(store, feedbackOrbIdleStorageKey)),
      wakeGestures: _decodeWakeGestures(
        await _readQuietly(store, feedbackWakeGesturesStorageKey),
      ),
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
      jsonEncode(
        <String>[
          for (final FeedbackWakeGesture gesture in FeedbackWakeGesture.values)
            if (normalized.contains(gesture)) gesture.id,
        ],
      ),
      (FeedbackOrbSettings latest) =>
          latest.copyWith(wakeGestures: normalized),
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
    final KeyValueStore? store = await ref.read(feedbackOrbStoreProvider.future);
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

FeedbackOrbIdleStyle _decodeIdleStyle(String? raw) {
  for (final FeedbackOrbIdleStyle style in FeedbackOrbIdleStyle.values) {
    if (style.name == raw?.trim()) return style;
  }
  return FeedbackOrbIdleStyle.handle;
}

Set<FeedbackWakeGesture> _decodeWakeGestures(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <FeedbackWakeGesture>{};
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
