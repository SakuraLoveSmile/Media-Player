import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Screenshot preferences (S42), persisted as one JSON blob.
class ScreenshotSettings {
  const ScreenshotSettings({this.pauseWhileCapturing = false});

  static const String storageKey = 'player.screenshot.v1';

  factory ScreenshotSettings.fromJson(Map<String, dynamic> json) {
    return ScreenshotSettings(
      pauseWhileCapturing: json['pauseWhileCapturing'] as bool? ?? false,
    );
  }

  /// Yamby's 截图时暂停视频 (default off there as well).
  final bool pauseWhileCapturing;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'pauseWhileCapturing': pauseWhileCapturing,
  };

  ScreenshotSettings copyWith({bool? pauseWhileCapturing}) {
    return ScreenshotSettings(
      pauseWhileCapturing: pauseWhileCapturing ?? this.pauseWhileCapturing,
    );
  }
}

/// Key/value store backing the screenshot preferences.
final FutureProvider<KeyValueStore?> screenshotSettingsStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

class ScreenshotSettingsController extends AsyncNotifier<ScreenshotSettings> {
  @override
  Future<ScreenshotSettings> build() async {
    final KeyValueStore? store = await ref.watch(
      screenshotSettingsStoreProvider.future,
    );
    if (store == null) return const ScreenshotSettings();
    try {
      final String? raw = await store.read(ScreenshotSettings.storageKey);
      if (raw == null || raw.isEmpty) return const ScreenshotSettings();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const ScreenshotSettings();
      return ScreenshotSettings.fromJson(decoded);
    } catch (_) {
      return const ScreenshotSettings();
    }
  }

  Future<void> setPauseWhileCapturing(bool enabled) async {
    final ScreenshotSettings next = (state.value ?? const ScreenshotSettings())
        .copyWith(pauseWhileCapturing: enabled);
    final KeyValueStore? store = await ref.read(
      screenshotSettingsStoreProvider.future,
    );
    if (store != null) {
      await store.write(
        ScreenshotSettings.storageKey,
        jsonEncode(next.toJson()),
      );
    }
    if (!ref.mounted) return;
    state = AsyncData<ScreenshotSettings>(next);
  }
}

final AsyncNotifierProvider<ScreenshotSettingsController, ScreenshotSettings>
screenshotSettingsControllerProvider =
    AsyncNotifierProvider<ScreenshotSettingsController, ScreenshotSettings>(
      ScreenshotSettingsController.new,
    );
