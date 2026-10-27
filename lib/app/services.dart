import '../data/api/emby_http_client.dart';
import '../data/auth/auth_service.dart';
import '../data/endpoints/endpoint_resolver.dart';

/// Everything the app needs once storage, HTTP and auth are wired.
class AppServices {
  const AppServices({
    required this.auth,
    this.client,
    this.resolver,
    this.deviceId = '',
  });

  final AuthService auth;
  final EmbyHttpClient? client;
  final EndpointResolver? resolver;
  final String deviceId;
}
