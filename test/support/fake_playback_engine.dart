import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/playback/playback_engine.dart';

/// Playback double for the page/controller tests of F3; no media_kit.
class FakePlaybackEngine implements PlaybackEngine, PausedOpenEngine {
  final List<PlaybackPlan> openedPlans = <PlaybackPlan>[];
  int playCalls = 0;
  int pauseCalls = 0;
  final List<Duration> seeks = <Duration>[];
  final List<double> volumes = <double>[];
  final List<double> rates = <double>[];
  final List<double> subtitleMargins = <double>[];
  final List<bool> subtitleMarginModes = <bool>[];
  final List<int> audioTracks = <int>[];
  final List<int?> subtitleTracks = <int?>[];
  final List<String> externalSubtitlePaths = <String>[];
  final List<SubtitleStyle> subtitleStyles = <SubtitleStyle>[];
  PlaybackStats stats = const PlaybackStats();
  int statsCalls = 0;
  int disposeCalls = 0;

  /// S16 / S13 passthrough recordings.
  final List<int> rotations = <int>[];
  final List<String> aspectModes = <String>[];
  final List<bool> hwdecToggles = <bool>[];

  /// S41 强制立体声 calls in order.
  final List<bool> forceStereoToggles = <bool>[];
  final List<double> volumeMaxima = <double>[];
  final List<({int? cacheSecs, int? demuxerMaxBytes})> cacheConfigs =
      <({int? cacheSecs, int? demuxerMaxBytes})>[];
  final List<String> screenshotPaths = <String>[];

  /// S23 passthrough recordings, one entry per [setAdvancedVideo] call.
  final List<({bool gpuNext, bool deband, bool yuv420})> advancedVideo =
      <({bool gpuNext, bool deband, bool yuv420})>[];

  /// Whether each [setAdvancedVideo] call was allowed to switch the VO. The
  /// load pass must pass false (the Android surface is not attached yet).
  final List<bool> advancedApplyVo = <bool>[];

  /// When true, [takeScreenshot] reports failure (returns null).
  bool screenshotFails = false;

  /// When set, [open] throws it so tests can drive the error state.
  Object? openError;

  /// When set, [selectSubtitleTrack] throws it so tests can drive the
  /// non-fatal subtitle-mount failure path.
  Object? subtitleMountError;

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

  int pausedOpenCalls = 0;

  @override
  Future<void> openPaused(PlaybackPlan plan) async {
    pausedOpenCalls++;
    await open(plan);
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
  Future<void> setRate(double rate) async {
    rates.add(rate);
  }

  @override
  Future<void> selectAudioTrack(int index) async {
    audioTracks.add(index);
  }

  @override
  Future<void> selectSubtitleTrack(int? index, {String? externalPath}) async {
    final error = subtitleMountError;
    if (error != null) throw error;
    subtitleTracks.add(index);
    if (externalPath != null) externalSubtitlePaths.add(externalPath);
  }

  @override
  Future<void> setSubtitleBottomMargin(double pixels) async {
    subtitleMargins.add(pixels);
  }

  @override
  Future<void> setSubtitleMarginsEnabled(bool enabled) async {
    subtitleMarginModes.add(enabled);
  }

  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) async {
    subtitleStyles.add(style);
  }

  @override
  Future<PlaybackStats> readStats() async {
    statsCalls++;
    return stats;
  }

  @override
  Future<void> setVideoRotation(int degrees) async {
    rotations.add(degrees);
  }

  @override
  Future<void> setAspectMode(String mode) async {
    aspectModes.add(mode);
  }

  @override
  Future<void> setHwdecEnabled(bool enabled) async {
    hwdecToggles.add(enabled);
  }

  @override
  Future<void> setForceStereo(bool stereo) async {
    forceStereoToggles.add(stereo);
  }

  @override
  Future<void> setAdvancedVideo({
    required bool gpuNext,
    required bool deband,
    required bool yuv420,
    bool applyVo = true,
  }) async {
    advancedVideo.add((gpuNext: gpuNext, deband: deband, yuv420: yuv420));
    advancedApplyVo.add(applyVo);
  }

  @override
  Future<void> setVolumeMax(double percent) async {
    volumeMaxima.add(percent);
  }

  @override
  Future<void> setCacheConfig({int? cacheSecs, int? demuxerMaxBytes}) async {
    cacheConfigs.add((cacheSecs: cacheSecs, demuxerMaxBytes: demuxerMaxBytes));
  }

  @override
  Future<String?> takeScreenshot(String destPath) async {
    screenshotPaths.add(destPath);
    return screenshotFails ? null : destPath;
  }

  @override
  Widget createSurface() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_states.isClosed) await _states.close();
  }
}

/// S82 playback double whose [setRate] can be let through one write at a time.
///
/// The hold-to-boost queue is only observable if the engine stalls: with an
/// instant double the boost has already landed by the time the finger lifts, so
/// the release would never exercise the in-flight path. [holdRates] arms the
/// gate, [releaseRate] lets a specific write finish, and [rates] keeps the order
/// the engine really applied the writes in.
class GatedRateFakePlaybackEngine extends FakePlaybackEngine {
  /// Every rate the page asked for, in call order — including calls whose gate
  /// is still shut, so a skipped restore is visible.
  final List<double> rateRequests = <double>[];

  /// One gate per [setRate] call made while [holdingRates] was true.
  final List<Completer<void>> rateGates = <Completer<void>>[];

  /// Whether [setRate] waits for its gate before touching the engine.
  bool holdingRates = false;

  /// Armed gates that the test has not released yet.
  int get stalledRates => rateGates.where((g) => !g.isCompleted).length;

  @override
  Future<void> setRate(double rate) async {
    rateRequests.add(rate);
    if (holdingRates) {
      final Completer<void> gate = Completer<void>();
      rateGates.add(gate);
      await gate.future;
    }
    await super.setRate(rate);
  }

  /// Lets the [index]-th gated write through. The continuation runs on
  /// microtasks, so the caller pumps a frame to let the queue advance.
  void releaseRate(int index) => rateGates[index].complete();

  /// Releases the oldest write that is still stalled; false when the queue has
  /// no gate left to open.
  bool releaseNextRate() {
    final int index = rateGates.indexWhere(
      (Completer<void> gate) => !gate.isCompleted,
    );
    if (index < 0) return false;
    rateGates[index].complete();
    return true;
  }
}
