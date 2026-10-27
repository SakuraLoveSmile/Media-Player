import '../models/resolved_endpoint.dart';
import '../models/server_profile.dart';

/// The authenticated slice of the session that repositories need.
///
/// Kept separate from `AuthService` so UI code cannot reach the token, while
/// data-layer repositories (library, playback) can build authorized URLs.
abstract interface class ApiSession {
  /// Null when logged out or when restore failed.
  ResolvedEndpoint? get endpoint;

  String? get userId;

  /// Access token; only used to build image/subtitle URLs. Never log it.
  String? get accessToken;

  /// Needed as the `DeviceId` query parameter of the playback fallback URL
  /// (contract §3.4); read from the session so it is null once logged out.
  String? get deviceId;

  /// Bitrate policy input (contract §3.3). Cached in memory because
  /// `AuthService.lastProfile()` is an async disk read and the playback path
  /// cannot await a disk read per request.
  ServerProfile? get profile;

  /// Performs a GET with `X-Emby-Token` and logs out on 401.
  Future<Map<String, dynamic>> authorizedGet(Uri url);

  /// Mirror of [authorizedGet] for POST; PlaybackInfo (§3.1) and the three
  /// session reports (§3.6) are all POST.
  Future<Map<String, dynamic>> authorizedPost(Uri url, {Object? body});
}
