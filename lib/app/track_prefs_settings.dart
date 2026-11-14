import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/playback/track_prefs.dart';
import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Key/value store backing the track language preferences (S33).
final FutureProvider<KeyValueStore?> trackPrefsStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Loads and persists the app-wide audio/subtitle language preferences.
///
/// The player controller reads the same [TrackPrefs.storageKey] when it opens,
/// so edits here drive the next playback's automatic track match. Explicit
/// picks made during playback stay session-only and are not written back.
class TrackPrefsSettingsController extends AsyncNotifier<TrackPrefs> {
  @override
  Future<TrackPrefs> build() async {
    final KeyValueStore? store = await ref.watch(
      trackPrefsStoreProvider.future,
    );
    if (store == null) return const TrackPrefs();
    try {
      final String? raw = await store.read(TrackPrefs.storageKey);
      if (raw == null || raw.isEmpty) return const TrackPrefs();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const TrackPrefs();
      return TrackPrefs.fromJson(decoded);
    } catch (_) {
      return const TrackPrefs();
    }
  }

  Future<void> _persist(TrackPrefs next) async {
    final KeyValueStore? store = await ref.read(trackPrefsStoreProvider.future);
    if (store != null) {
      await store.write(TrackPrefs.storageKey, jsonEncode(next.toJson()));
    }
    if (!ref.mounted) return;
    state = AsyncData<TrackPrefs>(next);
  }

  TrackPrefs get _current => state.value ?? const TrackPrefs();

  Future<void> setAudioLanguage(String code) =>
      _persist(_current.copyWith(audioLanguage: code));

  Future<void> setSubtitleLanguage(String code) =>
      _persist(_current.copyWith(subtitleLanguage: code));
}

final AsyncNotifierProvider<TrackPrefsSettingsController, TrackPrefs>
trackPrefsSettingsControllerProvider =
    AsyncNotifierProvider<TrackPrefsSettingsController, TrackPrefs>(
      TrackPrefsSettingsController.new,
    );
