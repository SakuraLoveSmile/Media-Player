import '../models/resolved_endpoint.dart';

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

  /// Performs a GET with `X-Emby-Token` and logs out on 401.
  Future<Map<String, dynamic>> authorizedGet(Uri url);
}
