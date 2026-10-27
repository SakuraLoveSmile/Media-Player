import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/models/playback_plan.dart';
import '../../data/playback/playback_engine.dart';
import '../../data/playback/playback_service.dart';
import '../../data/playback/session_reporter.dart';

// The constructor exposes public names (`itemId`, `library`, ...) while the
// fields stay private, the same trade-off as `AuthRepository.deviceId`.
// ignore_for_file: prefer_initializing_formals

class PlayerState {
  const PlayerState({
    this.itemName = '',
    this.loading = false,
    this.ready = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.playing = false,
    this.resumedFrom,
    this.videoDirect,
    this.audioTranscoded = false,
    this.error,
    this.unsupported = false,
    this.unauthorized = false,
  });

  final String itemName;

  /// Detail fetch plus negotiation are one visible step for the user.
  final bool loading;
  final bool ready;
  final Duration position;
  final Duration duration;
  final bool buffering;
  final bool playing;

  /// Non-null when playback started from a stored position (contract §10.9 d),
  /// which the UI has to state explicitly.
  final Duration? resumedFrom;

  /// Null means "not confirmed yet"; never guessed from the URL shape
  /// (contract §10.9 f).
  final bool? videoDirect;
  final bool audioTranscoded;

  /// Already mapped to user-facing Chinese text; raw exceptions never reach
  /// the screen (contract §6).
  final String? error;

  /// The item cannot be played as-is, e.g. a series needs an episode first.
  final bool unsupported;
  final bool unauthorized;

  static const Object _unset = Object();

  PlayerState copyWith({
    String? itemName,
    bool? loading,
    bool? ready,
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? playing,
    Object? resumedFrom = _unset,
    Object? videoDirect = _unset,
    bool? audioTranscoded,
    Object? error = _unset,
    bool? unsupported,
    bool? unauthorized,
  }) {
    return PlayerState(
      itemName: itemName ?? this.itemName,
      loading: loading ?? this.loading,
      ready: ready ?? this.ready,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffering: buffering ?? this.buffering,
      playing: playing ?? this.playing,
      resumedFrom: identical(resumedFrom, _unset)
          ? this.resumedFrom
          : resumedFrom as Duration?,
      videoDirect: identical(videoDirect, _unset)
          ? this.videoDirect
          : videoDirect as bool?,
      audioTranscoded: audioTranscoded ?? this.audioTranscoded,
      error: identical(error, _unset) ? this.error : error as String?,
      unsupported: unsupported ?? this.unsupported,
      unauthorized: unauthorized ?? this.unauthorized,
    );
  }
}

/// Drives one playback session: resume, negotiation, engine and reporting
/// (contract §3.4, §3.6, §10.9).
///
/// Engine and reporter are injected per instance because each playback owns
/// exactly one of them (libmpv instance / "already stopped" flag).
class PlayerController extends ChangeNotifier {
  PlayerController({
    required String itemId,
    required LibraryService library,
    required PlaybackService playback,
    required PlaybackEngine engine,
    required PlaybackReporter reporter,
    Duration probeDelay = const Duration(seconds: 3),
    Future<void> Function(Duration)? delay,
  })  : _itemId = itemId,
        _library = library,
        _playback = playback,
        _engine = engine,
        _reporter = reporter,
        _probeDelay = probeDelay,
        _delay = delay ?? Future<void>.delayed;

  /// Contract §10.9 d: resume only past this much playback.
  static const Duration _resumeThreshold = Duration(seconds: 10);

  final String _itemId;
  final LibraryService _library;
  final PlaybackService _playback;
  final PlaybackEngine _engine;
  final PlaybackReporter _reporter;
  final Duration _probeDelay;
  final Future<void> Function(Duration) _delay;

  PlayerState _state = const PlayerState();
  PlaybackPlan? _plan;
  StreamSubscription<PlaybackSnapshot>? _ticks;
  Widget? _surface;
  bool _disposed = false;

  PlayerState get state => _state;

  /// The engine owns the render widget (contract §10.9 b). Cached so the
  /// platform view is created once instead of on every rebuild.
  Widget get surface => _surface ??= _engine.createSurface();

  Future<void> load() async {
    if (_disposed || _state.loading) return;

    _set(_state.copyWith(
      loading: true,
      error: null,
      unsupported: false,
      unauthorized: false,
    ));

    try {
      final item = await _library.item(_itemId);
      if (_disposed) return;
      _set(_state.copyWith(itemName: item.name, duration: item.duration));

      // Picking an episode belongs to the detail page, so stop before
      // negotiating: /PlaybackInfo on a series id has no playable source.
      if (item.type == 'Series') {
        _set(_state.copyWith(
          loading: false,
          unsupported: true,
          error: '剧集需要先选择分集（详情页尚未实现）',
        ));
        return;
      }

      // Contract §10.9 d: > 10 s and not finished resumes, everything else
      // starts from zero.
      final userData = item.userData;
      final resume =
          !userData.played && userData.position > _resumeThreshold;
      final startAt = resume ? userData.position : Duration.zero;

      final plan = await _playback.resolve(_itemId, startAt: startAt);
      if (_disposed) return;
      _plan = plan;

      await _ticks?.cancel();
      _ticks = _engine.state.listen(_onSnapshot);

      await _engine.open(plan);
      if (_disposed) return;
      _set(_state.copyWith(
        loading: false,
        ready: true,
        position: startAt,
        resumedFrom: resume ? startAt : null,
      ));

      // The heartbeat polls the engine instead of this state so a report can
      // never lag a frame behind (contract §3.6).
      await _reporter.started(
        plan,
        startAt,
        position: () => _engine.snapshot.position,
      );

      unawaited(_confirmDirect(plan));
    } catch (error) {
      // Nothing may escape into the widget tree; §6 codes and anything else
      // both end up as mapped copy.
      _fail(error);
    }
  }

  Future<void> togglePlayPause() async {
    final plan = _plan;
    if (_disposed || !_state.ready || plan == null) return;

    final wasPlaying = _state.playing;
    if (wasPlaying) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
    if (_disposed) return;
    // Flipped eagerly so the button reacts; the engine stream stays
    // authoritative and overwrites this on the next snapshot.
    _set(_state.copyWith(playing: !wasPlaying));

    // Contract §10.9 c: pause / resume reports immediately, next to the
    // 10 s heartbeat.
    await _reporter.progress(
      plan,
      _engine.snapshot.position,
      paused: wasPlaying,
    );
  }

  Future<void> seekTo(Duration position) async {
    final plan = _plan;
    if (_disposed || !_state.ready || plan == null) return;

    await _engine.seekTo(position);
    if (_disposed) return;
    _set(_state.copyWith(position: position));

    // Contract §10.9 c: a finished seek reports immediately.
    await _reporter.progress(plan, position, paused: !_state.playing);
  }

  /// [zeroToOne] is the slider value; [PlaybackEngine.setVolume] takes the
  /// player's own 0–100 scale, so the conversion lives here and nowhere else.
  Future<void> setVolume(double zeroToOne) async {
    if (_disposed) return;
    final level = zeroToOne.clamp(0.0, 1.0);
    await _engine.setVolume(level * 100);
  }

  void _onSnapshot(PlaybackSnapshot snapshot) {
    _set(_state.copyWith(
      position: snapshot.position,
      // The engine reports a zero duration until the demuxer read it; keep
      // the runtime from the detail response until then.
      duration: snapshot.duration > Duration.zero
          ? snapshot.duration
          : _state.duration,
      buffering: snapshot.buffering,
      playing: snapshot.playing,
      // Engine errors are opaque objects; the UI gets fixed copy, never a
      // toString (contract §6).
      error: snapshot.error == null ? _state.error : '播放失败，请重试',
    ));
  }

  Future<void> _confirmDirect(PlaybackPlan plan) async {
    await _delay(_probeDelay);
    if (_disposed) return;

    // Contract §10.9 f: /Sessions is the only source of the verdict, and it
    // stays null when the server did not say.
    final confirmed = await _playback.confirmDirect(plan);
    if (_disposed) return;
    _plan = confirmed;
    _set(_state.copyWith(
      videoDirect: confirmed.videoDirect,
      audioTranscoded: confirmed.audioTranscoded,
    ));
  }

  void _fail(Object error) {
    final unauthorized =
        error is EmbyException && error.code == AppErrorCode.unauthorized;
    _set(_state.copyWith(
      loading: false,
      ready: false,
      error: playerErrorMessage(error),
      unauthorized: unauthorized,
    ));
  }

  void _set(PlayerState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  /// Idempotent: the back gesture and the widget teardown both land here, and
  /// `Stopped` must be sent exactly once (contract §10.9 c).
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    unawaited(_ticks?.cancel());
    _ticks = null;

    final plan = _plan;
    if (plan != null) {
      unawaited(_reporter.stopped(plan, _engine.snapshot.position));
    }
    unawaited(_engine.dispose());
    super.dispose();
  }
}

/// Maps a data-layer failure to playback copy (contract §6).
String playerErrorMessage(Object error) {
  final code = error is EmbyException ? error.code : null;
  return switch (code) {
    AppErrorCode.unauthorized => '登录已过期，请重新登录',
    AppErrorCode.forbidden => '没有播放该内容的权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.notFound => '内容不存在或已被移除',
    AppErrorCode.directPlayDenied => '服务器拒绝直连播放',
    AppErrorCode.playbackUnsupported => '这个片源无法播放',
    AppErrorCode.transcodeFailed => '服务器转码失败，请稍后重试',
    AppErrorCode.subtitleFailed => '字幕加载失败',
    _ => '播放失败，请重试',
  };
}
