import 'dart:convert';

import '../../models/json_read.dart';

/// One MoviePilot instance the app is signed in to.
///
/// The app authenticates with the user's own MoviePilot account (求片 S16) and
/// keeps only the bearer token the server issued. The password is used once, at
/// login, and never stored: unlike the instance API key this replaces, the
/// token carries the login's own expiry and is revoked with the account.
class MoviePilotConfig {
  const MoviePilotConfig({
    required this.baseUrl,
    required this.username,
    required this.accessToken,
    this.expiresAt,
  });

  /// Tolerant parse. Returns null when any half is missing, so a partially
  /// written record can never produce a half-configured client.
  static MoviePilotConfig? fromJson(Map<String, dynamic> json) {
    final baseUrl = asString(json['baseUrl']);
    final username = asString(json['username']);
    final accessToken = asString(json['accessToken']);
    if (baseUrl == null || username == null || accessToken == null) return null;
    return MoviePilotConfig(
      baseUrl: baseUrl,
      username: username,
      accessToken: accessToken,
      expiresAt: _parseExpiry(json['expiresAt']),
    );
  }

  /// Normalized base URL without a trailing slash, e.g. `http://nas:3002`.
  final String baseUrl;

  /// The MoviePilot account the token belongs to; safe to show and log.
  final String username;

  /// `Authorization: Bearer` value. Only ever persisted in the key/value
  /// store, never rendered or logged.
  final String accessToken;

  /// When [accessToken] stops working, read from its `exp` claim. Null when the
  /// server issued a token without one; the next request then decides.
  final DateTime? expiresAt;

  /// True once the token is past its expiry. Checked before every request so an
  /// expired session is reported without a guaranteed 401 round trip.
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => <String, dynamic>{
    'baseUrl': baseUrl,
    'username': username,
    'accessToken': accessToken,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };

  /// Reads the expiry out of a JWT without verifying it: the signature is the
  /// server's business, the client only needs to know when to ask for a new
  /// login. Anything unexpected reads as "unknown", never as a failure.
  static DateTime? expiryFromAccessToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final exp = payload['exp'];
      final seconds = switch (exp) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value),
        _ => null,
      };
      if (seconds == null || seconds <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      );
    } on FormatException {
      return null;
    }
  }

  static DateTime? _parseExpiry(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Resolves an API path such as `/api/v1/subscribe/` against [baseUrl],
  /// keeping any reverse-proxy sub-path the user entered.
  Uri resolve(String path, [Map<String, String>? query]) {
    final root = Uri.parse(baseUrl);
    final basePath = root.path.endsWith('/')
        ? root.path.substring(0, root.path.length - 1)
        : root.path;
    final uri = root.replace(path: '$basePath$path', queryParameters: query);
    return uri;
  }

  /// Never includes the token, so it is safe for logs and error messages.
  @override
  String toString() => 'MoviePilotConfig($baseUrl, $username)';
}
