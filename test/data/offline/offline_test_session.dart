import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/api_session.dart';
import 'package:media_player/data/models/resolved_endpoint.dart';
import 'package:media_player/data/models/server_profile.dart';

class OfflineTestSession implements ApiSession {
  OfflineTestSession(String base)
    : endpoint = ResolvedEndpoint(
        baseUrl: base,
        kind: EndpointKind.lan,
        serverId: 'server',
        resolvedAt: DateTime(2026),
      );
  bool allowed = true;
  bool? canDownload = true;
  void Function(Uri)? onGet;
  int size = 12;
  int jsonCalls = 0;
  String protocol = 'File';
  String container = 'mkv';
  @override
  ResolvedEndpoint? endpoint;
  @override
  String? userId = 'user';
  @override
  String? accessToken = 'secret-token';
  @override
  String? get deviceId => 'device';
  @override
  ServerProfile? get profile =>
      const ServerProfile(serverId: 'server', name: 'Test server');
  @override
  Future<Map<String, dynamic>> authorizedGet(Uri url) async {
    jsonCalls++;
    onGet?.call(url);
    return url.path.endsWith('/Items/movie')
        ? {
            'Id': 'movie',
            'Type': 'Movie',
            'CanDownload': canDownload,
            'MediaSources': [
              {
                'Id': 'source',
                'Container': container,
                'Protocol': protocol,
                'Size': size,
              },
            ],
          }
        : {
            'Policy': {'EnableContentDownloading': allowed},
          };
  }

  @override
  Future<Map<String, dynamic>> authorizedPost(Uri url, {Object? body}) async =>
      {};
  @override
  Future<Map<String, dynamic>> authorizedDelete(Uri url) async => {};
}
