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
    this.selectionSeriesId,
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
  final String? selectionSeriesId;
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
    Object? selectionSeriesId = _unset,
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
      selectionSeriesId: identical(selectionSeriesId, _unset)
          ? this.selectionSeriesId
          : selectionSeriesId as String?,
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
  }) : _itemId = itemId,
       _library = library,
       _playback = playback,
       _engine = engine,
       _reporter = reporter,
       _probeDelay = probeDelay,
       _delay = delay ?? Future<void>.delayed;

  /// Contract §10.9 d: resume only past this much playback.
  static const Duration _resumeThreshold = Duration(seconds: 10);

  /// How long playback may stay stuck before an engine error line becomes the
  /// visible "播放失败" copy. mpv logs errors for trouble it recovers from
  /// (retried range requests, skipped frames), so the line alone proves
  /// nothing; a frozen position is the evidence.
  static const Duration _failureGrace = Duration(seconds: 2);

  /// The same window while the engine is filling its buffer. A network stall
  /// is expected to recover, so it only becomes copy once it looks permanent.
  static const Duration _bufferingFailureGrace = Duration(seconds: 20);

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
  Timer? _failureWatch;
  Duration? _failurePosition;
  bool _failureWaitedBuffer = false;
  bool _userPaused = false;
  Widget? _surface;
  Duration _lastTrustedPosition = Duration.zero;
  Future<void>? _stopFuture;
  bool _stopped = false;
  bool _disposed = false;

  PlayerState get state => _state;

  Duration get _reportPosition => _lastTrustedPosition;

  /// The engine owns the render widget (contract §10.9 b). Cached so the
  /// platform view is created once instead of on every rebuild.
  Widget get surface => _surface ??= _engine.createSurface();

  Future<void> load() async {
    if (_disposed || _stopped || _state.loading) return;

    _cancelFailureWatch();
    _failurePosition = null;
    _userPaused = false;
    _set(
      _state.copyWith(
        loading: true,
        error: null,
        unsupported: false,
        selectionSeriesId: null,
        unauthorized: false,
      ),
    );

    try {
      final item = await _library.item(_itemId);
      if (_disposed || _stopped) return;
      _set(_state.copyWith(itemName: item.name, duration: item.duration));

      // Picking an episode belongs to the series page, so stop before
      // negotiating: /PlaybackInfo on a series id has no playable source.
      if (item.type == 'Series') {
        _set(
          _state.copyWith(
            loading: false,
            unsupported: true,
            selectionSeriesId: item.id,
            error: '请选择分集后播放',
          ),
        );
        return;
      }

      // Contract §10.9 d: > 10 s and not finished resumes, everything else
      // starts from zero.
      final userData = item.userData;
      final resume = !userData.played && userData.position > _resumeThreshold;
      final startAt = resume ? userData.position : Duration.zero;

      final plan = await _playback.resolve(_itemId, startAt: startAt);
      if (_disposed || _stopped) return;
      _plan = plan;

      await _ticks?.cancel();
      if (_disposed || _stopped) return;
      // Reset at open (including a genuine zero start); uncommanded zero
      // snapshots may be teardown noise. A completed ready-state seek below
      // explicitly accepts zero, so seeking to the beginning is not lost.
      _lastTrustedPosition = startAt;
      _ticks = _engine.state.listen(_onSnapshot);

      await _engine.open(plan);
      if (_disposed || _stopped) return;
      _set(
        _state.copyWith(
          loading: false,
          ready: true,
          position: startAt,
          resumedFrom: resume ? startAt : null,
        ),
      );

      // Heartbeats and final reports share the teardown-safe position.
      await _reporter.started(plan, startAt, position: () => _reportPosition);

      unawaited(_confirmDirect(plan));
    } catch (error) {
      // Nothing may escape into the widget tree; §6 codes and anything else
      // both end up as mapped copy.
      _fail(error);
    }
  }

  Future<void> togglePlayPause() async {
    final plan = _plan;
    if (_disposed || _stopped || !_state.ready || plan == null) return;

    final wasPlaying = _state.playing;
    // The engine reporting `playing: false` also means "stopped by a dead
    // stream", so only this flag tells the failure check that the user asked
    // for the pause.
    _userPaused = wasPlaying;
    if (wasPlaying) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
    if (_disposed || _stopped) return;
    // Flipped eagerly so the button reacts; the engine stream stays
    // authoritative and overwrites this on the next snapshot.
    _set(_state.copyWith(playing: !wasPlaying));

    // Contract §10.9 c: pause / resume reports immediately, next to the
    // 10 s heartbeat.
    await _reporter.progress(plan, _reportPosition, paused: wasPlaying);
  }

  Future<void> seekTo(Duration position) async {
    final plan = _plan;
    if (_disposed || _stopped || !_state.ready || plan == null) return;

    await _engine.seekTo(position);
    if (_disposed || _stopped) return;
    _lastTrustedPosition = position;
    _set(_state.copyWith(position: position));

    // Contract §10.9 c: a finished seek reports immediately.
    await _reporter.progress(plan, _reportPosition, paused: !_state.playing);
  }

  /// [zeroToOne] is the slider value; [PlaybackEngine.setVolume] takes the
  /// player's own 0–100 scale, so the conversion lives here and nowhere else.
  Future<void> setVolume(double zeroToOne) async {
    if (_disposed || _stopped) return;
    final level = zeroToOne.clamp(0.0, 1.0);
    await _engine.setVolume(level * 100);
  }

  void _onSnapshot(PlaybackSnapshot snapshot) {
    if (_disposed || _stopped) return;
    // Captured on every snapshot, never throttled: stop() reports this value
    // and Android tears the surface down before the page can read it again.
    if (snapshot.position > Duration.zero) {
      _lastTrustedPosition = snapshot.position;
    }
    final previous = _state;
    final progressed = snapshot.position > previous.position;

    // A moved position proves the player survived whatever it logged, so a
    // banner left over from an earlier stall must not outlive the recovery.
    if (progressed) _dismissFailure();

    _set(
      _state.copyWith(
        position: snapshot.position,
        // The engine reports a zero duration until the demuxer read it; keep
        // the runtime from the detail response until then.
        duration: snapshot.duration > Duration.zero
            ? snapshot.duration
            : previous.duration,
        buffering: snapshot.buffering,
        playing: snapshot.playing,
      ),
    );

    // Engine errors are opaque objects, so they never reach the UI as text;
    // the copy below is fixed (contract §6). The line is only a hint though:
    // mpv keeps playing after most of them, so a stall has to confirm it.
    if (snapshot.error != null) {
      _noteFailure();
    } else if (!progressed &&
        _failurePosition != null &&
        _failureWatch == null) {
      // A paused claim gets its window re-armed by the next snapshot, once
      // the player is expected to move again.
      _armFailureWatch();
    }
  }

  /// Starts (or reuses) the claim that an engine error line broke playback.
  void _noteFailure() {
    // Claimed before `ready` too: a source that cannot be opened often only
    // shows up as an error line, and [_confirmFailure] waits for the load to
    // finish before it says anything.
    if (_failurePosition != null) return;
    _failurePosition = _lastTrustedPosition;
    _failureWaitedBuffer = false;
    _armFailureWatch();
  }

  void _armFailureWatch([Duration window = _failureGrace]) {
    _failureWatch?.cancel();
    _failureWatch = Timer(window, _confirmFailure);
  }

  void _cancelFailureWatch() {
    _failureWatch?.cancel();
    _failureWatch = null;
  }

  void _confirmFailure() {
    _failureWatch = null;
    final claim = _failurePosition;
    if (_disposed || _stopped || claim == null) return;

    // Frames arrived between the error line and this check: mpv recovered, so
    // the user must not be told playback failed.
    if (_lastTrustedPosition != claim) {
      if (_dismissFailure()) notifyListeners();
      return;
    }
    // Negotiation is still running, so there is nothing to say yet.
    if (_state.loading) {
      _armFailureWatch();
      return;
    }
    // The load path already owns the copy on screen.
    if (_state.error != null) {
      _failurePosition = null;
      return;
    }
    // The user asked for the pause; it waits for the resume snapshot instead
    // of polling.
    if (_userPaused) return;
    // Reaching the end of the runtime is not a failure either.
    final total = _state.duration;
    if (total > Duration.zero &&
        _state.position >= total - const Duration(seconds: 1)) {
      _failurePosition = null;
      return;
    }
    if (_state.buffering && !_failureWaitedBuffer) {
      // Filling the buffer is normal; only a buffer that never fills is a
      // failure, and that one gets the longer window.
      _failureWaitedBuffer = true;
      _armFailureWatch(_bufferingFailureGrace);
      return;
    }

    _failurePosition = null;
    _set(_state.copyWith(error: '播放失败，请重试'));
  }

  /// Drops the pending claim and any banner it produced; true when the screen
  /// actually showed one.
  bool _dismissFailure() {
    _cancelFailureWatch();
    _failurePosition = null;
    _failureWaitedBuffer = false;
    if (_state.error == null || !_state.ready) return false;
    _state = _state.copyWith(error: null);
    return true;
  }

  Future<void> _confirmDirect(PlaybackPlan plan) async {
    await _delay(_probeDelay);
    if (_disposed || _stopped) return;

    // Contract §10.9 f: /Sessions is the only source of the verdict, and it
    // stays null when the server did not say.
    final confirmed = await _playback.confirmDirect(plan);
    if (_disposed || _stopped) return;
    _plan = confirmed;
    _set(
      _state.copyWith(
        videoDirect: confirmed.videoDirect,
        audioTranscoded: confirmed.audioTranscoded,
      ),
    );
  }

  void _fail(Object error) {
    final unauthorized =
        error is EmbyException && error.code == AppErrorCode.unauthorized;
    _set(
      _state.copyWith(
        loading: false,
        ready: false,
        error: playerErrorMessage(error),
        unauthorized: unauthorized,
      ),
    );
  }

  void _set(PlayerState state) {
    if (_disposed || _stopped) return;
    _state = state;
    notifyListeners();
  }

  /// Repeated callers share the pending final report (contract §10.9 c).
  Future<void> stop() {
    if (_stopped) return _stopFuture ?? Future<void>.value();

    _cancelFailureWatch();
    _failurePosition = null;
    final plan = _plan;
    _stopFuture = plan == null
        ? Future<void>.value()
        : _reporter.stopped(plan, _reportPosition);
    _stopped = true;
    return _stopFuture!;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // Fallback for teardown without the page's awaited exit path.
    unawaited(stop());
    _cancelFailureWatch();
    unawaited(_ticks?.cancel());
    _ticks = null;
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
