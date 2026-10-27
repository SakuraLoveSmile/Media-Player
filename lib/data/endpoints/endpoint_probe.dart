import '../api/emby_http_client.dart';

/// One `System/Info/Public` probe (contract §1.3).
abstract interface class EndpointProbe {
  /// Returns the advertised server id, or `null` when the response is not a
  /// usable Emby payload.
  Future<String?> fetchServerId(String base, {required Duration timeout});
}

class HttpEndpointProbe implements EndpointProbe {
  HttpEndpointProbe(this._client);

  final EmbyHttpClient _client;

  @override
  Future<String?> fetchServerId(String base, {required Duration timeout}) async {
    final json = await _client.getJson(
      Uri.parse('$base/System/Info/Public'),
      timeout: timeout,
    );
    final id = json['Id'];
    return id is String && id.isNotEmpty ? id : null;
  }
}
