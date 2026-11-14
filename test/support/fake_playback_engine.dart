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
