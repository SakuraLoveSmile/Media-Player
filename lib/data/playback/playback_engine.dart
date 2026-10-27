import 'package:flutter/widgets.dart';

import '../models/playback_plan.dart';

/// Player abstraction from contract §5; the playback page (F3) depends only
/// on this interface, never on the player package.
abstract interface class PlaybackEngine {
  /// Opens [plan] using its `url`, `headers` and `startAt`.
  Future<void> open(PlaybackPlan plan);

  /// Broadcast snapshot stream; safe to listen to more than once.
  Stream<PlaybackSnapshot> get state;

  /// Current value read synchronously.
  ///
  /// B5-6's `SessionReporter.started(..., position: () => ...)` needs the
  /// position at heartbeat time; caching it from [state] would add one more
  /// piece of mutable state for the same value.
  PlaybackSnapshot get snapshot;

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Future<void> selectAudioTrack(int index);
  Future<void> selectSubtitleTrack(int? index, {String? externalPath});

  /// §10.9 (b): the engine owns the render widget so features never import
  /// the player package.
  Widget createSurface();

  Future<void> dispose();
}

/// What the UI renders (contract §5).
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.playing = false,
    this.error,
  });

  final Duration position;
  final Duration duration;
  final bool buffering;
  final bool playing;
  final Object? error;

  PlaybackSnapshot copyWith({
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? playing,
    Object? error,
  }) {
    return PlaybackSnapshot(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffering: buffering ?? this.buffering,
      playing: playing ?? this.playing,
      error: error ?? this.error,
    );
  }
}
