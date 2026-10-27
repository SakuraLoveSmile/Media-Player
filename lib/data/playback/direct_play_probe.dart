import '../../core/errors/emby_exception.dart';
import '../api/emby_http_client.dart';
import '../auth/api_session.dart';
import '../models/json_read.dart';
import '../models/playback_plan.dart';

/// Reads Emby's own direct-play verdict after playback starts (contract §3.5,
/// §10.9 f).
///
/// The 3 s settle delay before calling [confirm] belongs to the playback page
/// controller (F3-1); this probe performs exactly one `GET /Sessions` when
/// asked, never sleeps, never retries and never throws.
class DirectPlayProbe {
  DirectPlayProbe(this._session, {LogSink? logSink})
      : _log = logSink ?? _discard;

  final ApiSession _session;
  final LogSink _log;

  static void _discard(String _) {}

  /// Fills in [PlaybackPlan.videoDirect] / [PlaybackPlan.audioTranscoded].
  ///
  /// Returns the plan unchanged (verdict still null) when the session is
  /// absent or the verdict fields are missing: guessing `true` is forbidden
  /// (contract §10.9 f).
  Future<PlaybackPlan> confirm(PlaybackPlan plan) async {
    final endpoint = _session.endpoint;
    final deviceId = _session.deviceId;
    if (endpoint == null || deviceId == null || deviceId.isEmpty) {
      _log('DEBUG direct-play probe skipped: no endpoint or device id');
      return plan;
    }

    final List<Map<String, dynamic>> sessions;
    try {
      final json = await _session.authorizedGet(endpoint.resolve('/Sessions'));
      // `GET /Sessions` is a bare array; the HTTP client normalises it into
      // the `Items` envelope (contract §3.5).
      sessions = asMapList(json['Items']);
    } catch (error) {
      // Network / parsing / 401 must not escape; 401 cleanup already ran
      // inside authorizedGet (contract §10.4, §10.9 f).
      final reason =
          error is EmbyException ? error.code.name : error.runtimeType;
      _log('DEBUG direct-play probe failed: $reason');
      return plan;
    }

    final session = _byDevice(sessions, deviceId);
    if (session == null) {
      _log('DEBUG direct-play probe: no session for this device');
      return plan;
    }

    final method = asString(asMap(session['PlayState'])['PlayMethod']);
    switch (method) {
      case 'DirectPlay':
      case 'DirectStream':
        // DirectStream copies the video and remuxes the container, so it
        // counts as video-direct (contract §3.5).
        return plan.copyWith(videoDirect: true, audioTranscoded: false);
      case 'Transcode':
        final isVideoDirect =
            asMap(session['TranscodingInfo'])['IsVideoDirect'];
        if (isVideoDirect is! bool) {
          _log('DEBUG direct-play probe: TranscodingInfo.IsVideoDirect missing');
          return plan;
        }
        // `transcodingReasons` keeps its empty list: the server field name is
        // still unverified (contract §3.4, §9).
        return plan.copyWith(
          videoDirect: isVideoDirect,
          audioTranscoded: true,
        );
      default:
        _log('DEBUG direct-play probe: PlayState.PlayMethod missing or unknown');
        return plan;
    }
  }

  static Map<String, dynamic>? _byDevice(
    List<Map<String, dynamic>> sessions,
    String deviceId,
  ) {
    for (final session in sessions) {
      if (asString(session['DeviceId']) == deviceId) return session;
    }
    return null;
  }
}
