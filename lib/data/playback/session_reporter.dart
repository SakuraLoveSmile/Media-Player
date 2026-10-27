import 'dart:async';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/logging/redact.dart';
import '../api/emby_http_client.dart';
import '../auth/api_session.dart';
import '../models/playback_plan.dart';
import '../models/resolved_endpoint.dart';

/// Session reporting used by the playback page (contract §3.6, §10.9 c).
abstract interface class PlaybackReporter {
  /// POST /Sessions/Playing and start the heartbeat (contract §3.6).
  ///
  /// [position] is the getter the heartbeat polls for the current position;
  /// the initial position is [initialPosition] because a Dart parameter and a
  /// named getter cannot share a name.
  Future<void> started(
    PlaybackPlan plan,
    Duration initialPosition, {
    required Duration Function() position,
  });

  /// Immediate progress report for pause / resume / seek / background.
  Future<void> progress(
    PlaybackPlan plan,
    Duration position, {
    required bool paused,
  });

  /// Final report; idempotent (contract §10.9 c).
  Future<void> stopped(PlaybackPlan plan, Duration position);
}

/// Emby session reporting with a serial queue, one retry and a heartbeat.
///
/// Every report goes through [_queue] so a stale `Progress` can never land
/// after a newer one (contract §10.9 c). Failures are logged once and never
/// rethrown: reporting must not block playback (contract §3.6).
class SessionReporter implements PlaybackReporter {
  SessionReporter(
    this._session, {
    Stream<void>? heartbeat,
    Future<void> Function(Duration)? delay,
    LogSink? logSink,
  })  : _heartbeat =
            heartbeat ?? Stream<void>.periodic(const Duration(seconds: 10)),
        _delay = delay ?? Future<void>.delayed,
        _log = logSink ?? _discard;

  static const Duration _retryBackoff = Duration(seconds: 2);
  static const String _playingPath = '/Sessions/Playing';
  static const String _progressPath = '/Sessions/Playing/Progress';
  static const String _stoppedPath = '/Sessions/Playing/Stopped';

  final ApiSession _session;
  final Stream<void> _heartbeat;
  final Future<void> Function(Duration) _delay;
  final LogSink _log;

  /// Snapshot taken at [started] so one playback session never straddles
  /// endpoints (contract §10.3).
  ResolvedEndpoint? _endpoint;
  StreamSubscription<void>? _ticks;
  Future<void> _queue = Future<void>.value();
  bool _stopped = false;

  static void _discard(String _) {}

  @override
  Future<void> started(
    PlaybackPlan plan,
    Duration initialPosition, {
    required Duration Function() position,
  }) {
    if (_stopped) return Future<void>.value();
    _endpoint = _session.endpoint;

    final first =
        _enqueue(() => _report(plan, _playingPath, initialPosition, paused: false));
    unawaited(_ticks?.cancel());
    _ticks = _heartbeat.listen((_) {
      if (_stopped) return;
      final at = position();
      unawaited(_enqueue(() => _report(plan, _progressPath, at, paused: false)));
    });
    return first;
  }

  @override
  Future<void> progress(
    PlaybackPlan plan,
    Duration position, {
    required bool paused,
  }) {
    if (_stopped) return Future<void>.value();
    return _enqueue(() => _report(plan, _progressPath, position, paused: paused));
  }

  @override
  Future<void> stopped(PlaybackPlan plan, Duration position) {
    if (_stopped) return Future<void>.value();
    _stopped = true;
    unawaited(_ticks?.cancel());
    _ticks = null;
    return _enqueue(() => _report(plan, _stoppedPath, position, paused: false));
  }

  /// Chains [task] behind every earlier report. The queue itself swallows
  /// errors so one bad report cannot block the rest; callers still see the
  /// task's own result.
  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _report(
    PlaybackPlan plan,
    String path,
    Duration position, {
    required bool paused,
  }) async {
    final body = _body(plan, position, paused: paused);
    try {
      await _post(path, body);
      return;
    } on EmbyException {
      // One retry after 2 s (contract §3.6).
    }
    await _delay(_retryBackoff);
    try {
      await _post(path, body);
    } on EmbyException catch (error) {
      _warn(path, error.code.name);
    }
  }

  Future<void> _post(String path, Map<String, dynamic> body) {
    final endpoint = _endpoint ?? _session.endpoint;
    if (endpoint == null) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    return _session.authorizedPost(endpoint.resolve(path), body: body);
  }

  /// Logs method + host + path only; query, token and response stay out
  /// (contract §10.6).
  void _warn(String path, String reason) {
    final endpoint = _endpoint;
    final target =
        endpoint == null ? path : redactUrl(endpoint.resolve(path).toString());
    _log('WARN POST $target failed: $reason');
  }

  Map<String, dynamic> _body(
    PlaybackPlan plan,
    Duration position, {
    required bool paused,
  }) {
    return <String, dynamic>{
      'ItemId': plan.itemId,
      'MediaSourceId': plan.mediaSourceId,
      'PlaySessionId': plan.playSessionId,
      'PositionTicks': position.inMicroseconds * 10,
      'IsPaused': paused,
      'PlayMethod':
          plan.mode == PlaybackMode.direct ? 'DirectPlay' : 'Transcode',
      'CanSeek': true,
    };
  }
}
