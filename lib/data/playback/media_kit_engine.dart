import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/playback_plan.dart';
import 'playback_engine.dart';

/// media_kit implementation of [PlaybackEngine] (contract §5).
///
/// This is the only file allowed to mention media_kit types: `tool/
/// check_layering.sh` keeps them out of `lib/features` (§10.9 b).
class MediaKitEngine implements PlaybackEngine {
  MediaKitEngine() {
    // Same wiring as the verified M0 spike (spike/windows_smoke).
    _player = Player();
    _controller = VideoController(_player);
    _states = StreamController<PlaybackSnapshot>.broadcast();
    _bind<Duration>(
      _player.stream.position,
      (s, v) => s.copyWith(position: v),
    );
    _bind<Duration>(
      _player.stream.duration,
      (s, v) => s.copyWith(duration: v),
    );
    _bind<bool>(
      _player.stream.buffering,
      (s, v) => s.copyWith(buffering: v),
    );
    _bind<bool>(
      _player.stream.playing,
      (s, v) => s.copyWith(playing: v),
    );
    _bind<String>(
      _player.stream.error,
      // The raw mpv line can embed the media URL, `api_key` included, and mpv
      // reaches this stream from `stream`/`tcp:`/`file` log prefixes. Only the
      // failure class crosses the boundary (contract §10.6).
      (s, _) => s.copyWith(error: const _PlaybackFailure()),
    );
  }

  late final Player _player;
  late final VideoController _controller;
  late final StreamController<PlaybackSnapshot> _states;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  bool _disposed = false;

  @override
  Stream<PlaybackSnapshot> get state => _states.stream;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<void> open(PlaybackPlan plan) async {
    // Resume through `Media.start` rather than open-then-seek: mpv applies
    // `start` while loading, so no seek can race the demuxer (contract §10.9 d).
    final media = Media(
      plan.url,
      httpHeaders: plan.headers,
      start: plan.startAt > Duration.zero ? plan.startAt : null,
    );
    // A new item must not inherit the previous item's position or error, and
    // copyWith cannot clear `error`.
    _snapshot = const PlaybackSnapshot();
    _emit();
    await _player.open(media, play: true);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> selectAudioTrack(int index) async {
    final tracks = _player.state.tracks.audio;
    // Out of range is a no-op, not an error (§5 only asks for selection).
    if (index < 0 || index >= tracks.length) return;
    await _player.setAudioTrack(tracks[index]);
  }

  @override
  Future<void> selectSubtitleTrack(int? index, {String? externalPath}) async {
    if (externalPath != null) {
      // media_kit 1.2.6 exposes the external-file factory as `uri` (the M0
      // spike used it); B6 mounts downloaded subtitle files through this.
      await _player.setSubtitleTrack(SubtitleTrack.uri(externalPath));
      return;
    }
    if (index == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final tracks = _player.state.tracks.subtitle;
    if (index < 0 || index >= tracks.length) return;
    await _player.setSubtitleTrack(tracks[index]);
  }

  @override
  Widget createSurface() => Video(controller: _controller);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _states.close();
    await _player.dispose();
  }

  void _bind<T>(
    Stream<T> source,
    PlaybackSnapshot Function(PlaybackSnapshot snapshot, T value) update,
  ) {
    _subscriptions.add(source.listen((value) {
      _snapshot = update(_snapshot, value);
      _emit();
    }));
  }

  void _emit() {
    if (_states.isClosed) return;
    _states.add(_snapshot);
  }
}

/// Redacted stand-in for an mpv error line: the raw text can carry the media
/// URL and token, so the UI only gets the failure class (contract §6, §10.6).
class _PlaybackFailure {
  const _PlaybackFailure();

  @override
  String toString() => 'playback failed';
}
