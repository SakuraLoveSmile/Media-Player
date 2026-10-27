import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/playback/playback_engine.dart';

/// Playback double for the page/controller tests of F3; no media_kit.
class FakePlaybackEngine implements PlaybackEngine {
  final List<PlaybackPlan> openedPlans = <PlaybackPlan>[];
  int playCalls = 0;
  int pauseCalls = 0;
  final List<Duration> seeks = <Duration>[];
  final List<double> volumes = <double>[];
  int disposeCalls = 0;

  /// When set, [open] throws it so tests can drive the error state.
  Object? openError;

  final StreamController<PlaybackSnapshot> _states =
      StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();

  @override
  Stream<PlaybackSnapshot> get state => _states.stream;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  /// Pushes [next] to listeners and makes it visible through [snapshot].
  void emit(PlaybackSnapshot next) {
    _snapshot = next;
    if (!_states.isClosed) _states.add(next);
  }

  @override
  Future<void> open(PlaybackPlan plan) async {
    openedPlans.add(plan);
    final error = openError;
    if (error != null) throw error;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> selectAudioTrack(int index) async {}

  @override
  Future<void> selectSubtitleTrack(int? index, {String? externalPath}) async {}

  @override
  Widget createSurface() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_states.isClosed) await _states.close();
  }
}
