import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/network/endpoint_kind.dart';
import '../api/device_profile.dart';
import '../api/emby_headers.dart';
import '../auth/api_session.dart';
import '../models/json_read.dart';
import '../models/media_source.dart';
import '../models/playback_plan.dart';
import '../models/resolved_endpoint.dart';
import 'playback_options.dart';
import 'playback_service.dart';

/// PlaybackInfo negotiation and media URL generation (contract §3.1, §3.3,
/// §3.4).
///
/// Every URL is derived from the session's resolved endpoint, so one playback
/// session can never straddle LAN and WAN (contract §1.3, §10.3).
class PlaybackRepository implements PlaybackService {
  PlaybackRepository(this._session);

  final ApiSession _session;

  @override
  Future<PlaybackPlan> resolve(
    String itemId, {
    Duration startAt = Duration.zero,
  }) async {
    final endpoint = _session.endpoint;
    final token = _session.accessToken;
    final deviceId = _session.deviceId;
    // The plan embeds the token in both header and fallback URL, so all three
    // fields must exist before the first request (contract §3.4).
    if (endpoint == null ||
        token == null ||
        token.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty) {
      throw EmbyException(AppErrorCode.unauthorized);
    }

    final options = PlaybackOptions.forEndpoint(endpoint.kind, _session.profile);
    final requestUri = _uri('/Items/$itemId/PlaybackInfo', <String, String>{
      'UserId': _userId,
    });

    var json = await _session.authorizedPost(
      requestUri,
      body: _body(
        startAt,
        maxStreamingBitrate: options.maxStreamingBitrate,
        enableTranscoding: options.enableTranscoding,
      ),
    );
    var source = _firstSource(json);

    if (endpoint.kind == EndpointKind.lan && !_directCapable(source)) {
      // LAN requires a direct video stream; retry exactly once at the highest
      // bitrate with transcoding disabled (contract §3.3, §10.9 e). WAN may
      // transcode, so it never takes this path.
      json = await _session.authorizedPost(
        requestUri,
        body: _body(
          startAt,
          maxStreamingBitrate: PlaybackOptions.unrestrictedBitrate,
          enableTranscoding: false,
        ),
      );
      source = _firstSource(json);
      if (!_directCapable(source)) {
        throw EmbyException(
          AppErrorCode.directPlayDenied,
          endpointKind: endpoint.kind,
        );
      }
    }

    return _plan(
      itemId: itemId,
      source: source,
      endpoint: endpoint,
      token: token,
      deviceId: deviceId,
      startAt: startAt,
    );
  }

  Map<String, dynamic> _body(
    Duration startAt, {
    required int maxStreamingBitrate,
    required bool enableTranscoding,
  }) {
    return <String, dynamic>{
      'UserId': _userId,
      'StartTimeTicks': startAt.inMicroseconds * 10,
      'IsPlayback': true,
      'AutoOpenLiveStream': true,
      'MaxStreamingBitrate': maxStreamingBitrate,
      'EnableDirectPlay': true,
      'EnableDirectStream': true,
      'EnableTranscoding': enableTranscoding,
      'DeviceProfile': kDeviceProfile,
    };
  }

  /// Takes the first version; multi-version selection is out of scope
  /// (contract §2). Emby 4.10.1 only sends `PlaySessionId` at the response top
  /// level (contract §3.1).
  MediaSource _firstSource(Map<String, dynamic> json) {
    final sources = asMapList(json['MediaSources']);
    if (sources.isEmpty) {
      throw EmbyException(AppErrorCode.playbackUnsupported);
    }
    return MediaSource.fromJson(
      sources.first,
      topLevelPlaySessionId: asString(json['PlaySessionId']),
    );
  }

  static bool _directCapable(MediaSource source) =>
      source.supportsDirectPlay || source.supportsDirectStream;

  PlaybackPlan _plan({
    required String itemId,
    required MediaSource source,
    required ResolvedEndpoint endpoint,
    required String token,
    required String deviceId,
    required Duration startAt,
  }) {
    final directStreamUrl = source.directStreamUrl;
    final String url;
    final PlaybackMode mode;

    if (source.supportsDirectPlay && directStreamUrl != null) {
      // Contract §3.4 (1): the server already encoded item, source, user and
      // token here; only the origin may be prepended.
      url = _absolute(endpoint, directStreamUrl);
      mode = PlaybackMode.direct;
    } else if (source.supportsDirectPlay || source.supportsDirectStream) {
      // Contract §3.4 (2): header auth is preferred by the player, the URL
      // keeps `api_key` so playback still works when headers are dropped.
      url = endpoint.resolve('/Videos/$itemId/stream').replace(
        queryParameters: <String, String>{
          'Static': 'true',
          'MediaSourceId': source.id,
          'DeviceId': deviceId,
          'api_key': token,
        },
      ).toString();
      mode = PlaybackMode.direct;
    } else {
      final transcodingUrl = source.transcodingUrl;
      if (transcodingUrl == null) {
        throw EmbyException(
          AppErrorCode.playbackUnsupported,
          endpointKind: endpoint.kind,
        );
      }
      url = _withApiKey(_absolute(endpoint, transcodingUrl), token);
      mode = PlaybackMode.transcode;
    }

    return PlaybackPlan(
      itemId: itemId,
      mode: mode,
      endpointKind: endpoint.kind,
      url: url,
      headers: <String, String>{EmbyHeaders.token: token},
      mediaSourceId: source.id,
      // An absent id is passed through as empty rather than failing playback;
      // B5-6 will report the gap instead (contract §3.6).
      playSessionId: source.playSessionId ?? '',
      startAt: startAt,
    );
  }

  /// Prepends the endpoint origin to a server-relative media URL. The query is
  /// copied verbatim: re-parsing and re-encoding could alter the token or the
  /// server's own choices (contract §3.4).
  static String _absolute(ResolvedEndpoint endpoint, String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return url.startsWith('/')
        ? '${endpoint.baseUrl}$url'
        : '${endpoint.baseUrl}/$url';
  }

  /// Appends `api_key` only when absent, leaving the existing query untouched
  /// (contract §3.4).
  static String _withApiKey(String url, String token) {
    final uri = Uri.parse(url);
    if (uri.queryParameters.containsKey('api_key')) return url;
    final separator = uri.hasQuery ? '&' : '?';
    return '$url${separator}api_key=${Uri.encodeQueryComponent(token)}';
  }

  String get _userId {
    final id = _session.userId;
    if (id == null || id.isEmpty) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    return id;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final endpoint = _session.endpoint;
    if (endpoint == null) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    final uri = endpoint.resolve(path);
    return query == null ? uri : uri.replace(queryParameters: query);
  }
}
