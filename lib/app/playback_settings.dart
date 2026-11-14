import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/playback/playback_settings.dart';
import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// Key/value store backing the playback preferences (S13 / S16).
///
/// Reads the store created once by [bootstrapProvider] so the app never opens a
/// second backend. Tests override it with an in-memory store.
final FutureProvider<KeyValueStore?> playbackSettingsStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Loads and persists the app-wide playback engine preferences.
///
/// The player controller reads the same [PlaybackSettings.storageKey] at open,
/// so edits here apply to the next playback. Unreadable or corrupt values fall
/// back to the defaults; a write error propagates so the UI can warn and keep
/// the previous selection.
class PlaybackSettingsController extends AsyncNotifier<PlaybackSettings> {
  @override
  Future<PlaybackSettings> build() async {
    final KeyValueStore? store = await ref.watch(
      playbackSettingsStoreProvider.future,
    );
    if (store == null) return const PlaybackSettings();
    try {
      final String? raw = await store.read(PlaybackSettings.storageKey);
      if (raw == null) return const PlaybackSettings();
      return PlaybackSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PlaybackSettings();
    }
  }

  /// Persists [next] and applies it to the live state.
  Future<void> _persist(PlaybackSettings next) async {
    final KeyValueStore? store = await ref.read(
      playbackSettingsStoreProvider.future,
    );
    if (store != null) {
      await store.write(PlaybackSettings.storageKey, jsonEncode(next.toJson()));
    }
    if (!ref.mounted) return;
    state = AsyncData<PlaybackSettings>(next);
  }

  Future<void> setHwdecEnabled(bool enabled) =>
      _persist(_current.copyWith(hwdecEnabled: enabled));

  Future<void> setCacheSecs(int secs) =>
      _persist(_current.copyWith(cacheSecs: secs));

  Future<void> setDemuxerMaxBytes(int bytes) =>
      _persist(_current.copyWith(demuxerMaxBytes: bytes));

  /// S33: seek while dragging the progress bar.
  Future<void> setSeekOnDrag(bool enabled) =>
      _persist(_current.copyWith(seekOnDrag: enabled));

  /// S33: auto-advance to the next episode when one finishes.
  Future<void> setAutoPlayNext(bool enabled) =>
      _persist(_current.copyWith(autoPlayNext: enabled));

  /// S41: downmix to stereo (Yamby's 强制输出立体声).
  Future<void> setForceStereo(bool enabled) =>
      _persist(_current.copyWith(forceStereo: enabled));

  /// S23/S33: advanced mpv video switches (also edited from the player sheet).
  Future<void> setAdvancedVideo({bool? gpuNext, bool? deband, bool? yuv420}) =>
      _persist(
        _current.copyWith(gpuNext: gpuNext, deband: deband, yuv420: yuv420),
      );

  PlaybackSettings get _current => state.value ?? const PlaybackSettings();
}

/// App-wide playback engine preferences; defaults until the store loads.
final AsyncNotifierProvider<PlaybackSettingsController, PlaybackSettings>
playbackSettingsControllerProvider =
    AsyncNotifierProvider<PlaybackSettingsController, PlaybackSettings>(
      PlaybackSettingsController.new,
    );
