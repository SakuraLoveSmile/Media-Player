import '../../../core/network/url_normalizer.dart';
import '../../models/json_read.dart';

/// One MoviePilot instance the app may talk to.
///
/// Unlike Emby there is no LAN/WAN resolver: MoviePilot is addressed by the
/// single base URL the user enters, and every request goes to that origin
/// (plan §10). The API token is an instance-level administrator key, so it is
/// never logged and never rendered.
class MoviePilotConfig {
  const MoviePilotConfig({required this.baseUrl, required this.apiToken});

  /// Tolerant parse. Returns null when either half is missing, so a partially
  /// written record can never produce a half-configured client.
  static MoviePilotConfig? fromJson(Map<String, dynamic> json) {
    final baseUrl = asString(json['baseUrl']);
    final apiToken = asString(json['apiToken']);
    if (baseUrl == null || apiToken == null) return null;
    return MoviePilotConfig(baseUrl: baseUrl, apiToken: apiToken);
  }

  /// Normalized base URL without a trailing slash, e.g. `http://nas:3002`.
  final String baseUrl;

  /// `X-API-KEY` value. Administrator scope: read-only use, never persisted
  /// anywhere but the key/value store.
  final String apiToken;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'baseUrl': baseUrl,
    'apiToken': apiToken,
  };

  /// Builds a config from raw user input, or null when either field is
  /// unusable. The URL is normalized exactly like an Emby address.
  static MoviePilotConfig? fromInput({
    required String rawBaseUrl,
    required String rawApiToken,
  }) {
    final baseUrl = UrlNormalizer.normalize(rawBaseUrl);
    final apiToken = rawApiToken.trim();
    if (baseUrl == null || apiToken.isEmpty) return null;
    return MoviePilotConfig(baseUrl: baseUrl, apiToken: apiToken);
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
  String toString() => 'MoviePilotConfig($baseUrl)';
}
