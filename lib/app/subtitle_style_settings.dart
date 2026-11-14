import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/playback/playback_engine.dart';
import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Key/value store backing the subtitle style defaults (S41).
final FutureProvider<KeyValueStore?> subtitleStyleStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Loads and persists the app-wide subtitle style, the same blob the player
/// controller reads at open. The in-player 字幕样式 sheet edits the same key.
class SubtitleStyleSettingsController extends AsyncNotifier<SubtitleStyle> {
  @override
  Future<SubtitleStyle> build() async {
    final KeyValueStore? store = await ref.watch(
      subtitleStyleStoreProvider.future,
    );
    if (store == null) return const SubtitleStyle();
    try {
      final String? raw = await store.read(SubtitleStyle.storageKey);
      if (raw == null || raw.isEmpty) return const SubtitleStyle();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const SubtitleStyle();
      return SubtitleStyle.fromJson(decoded);
    } catch (_) {
      return const SubtitleStyle();
    }
  }

  Future<void> _persist(SubtitleStyle next) async {
    final KeyValueStore? store = await ref.read(
      subtitleStyleStoreProvider.future,
    );
    if (store != null) {
      await store.write(SubtitleStyle.storageKey, jsonEncode(next.toJson()));
    }
    if (!ref.mounted) return;
    state = AsyncData<SubtitleStyle>(next);
  }

  SubtitleStyle get _current => state.value ?? const SubtitleStyle();

  Future<void> setBorderSize(double size) =>
      _persist(_current.copyWith(borderSize: size.clamp(0.0, 8.0)));

  Future<void> setShadowOffset(double offset) =>
      _persist(_current.copyWith(shadowOffset: offset.clamp(0.0, 8.0)));
}

final AsyncNotifierProvider<SubtitleStyleSettingsController, SubtitleStyle>
subtitleStyleSettingsControllerProvider =
    AsyncNotifierProvider<SubtitleStyleSettingsController, SubtitleStyle>(
      SubtitleStyleSettingsController.new,
    );
