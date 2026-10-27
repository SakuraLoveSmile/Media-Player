import 'dart:convert';
import 'dart:io';

/// Minimal Emby surface used by B3 tests (contract §1.3, §1.4, §2).
class FakeEmbyServer {
  FakeEmbyServer({
    this.serverId = 'server-1',
    this.serverName = 'Home',
    this.password = 'correct',
  });

  final String serverId;
  final String serverName;
  final String password;

  late HttpServer _server;

  int authRequests = 0;
  int viewRequests = 0;
  int expiredRequests = 0;
  String? lastAuthorizationHeader;

  String get base => 'http://127.0.0.1:${_server.port}';

  String get token => 'token-$serverId';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;

    try {
      if (request.method == 'GET' && path == '/System/Info/Public') {
        await _json(response, 200, <String, dynamic>{
          'Id': serverId,
          'ServerName': serverName,
          'Version': '4.10.1.0',
        });
        return;
      }

      if (request.method == 'POST' && path == '/Users/AuthenticateByName') {
        authRequests++;
        lastAuthorizationHeader =
            request.headers.value('X-Emby-Authorization');
        final body = await utf8.decoder.bind(request).join();
        final map = jsonDecode(body) as Map<String, dynamic>;
        final headerOk =
            lastAuthorizationHeader?.startsWith('MediaBrowser ') ?? false;

        if (map['Pw'] == password && headerOk) {
          await _json(response, 200, <String, dynamic>{
            'User': <String, dynamic>{'Id': 'user-1', 'Name': 'test'},
            'AccessToken': token,
            'ServerId': serverId,
          });
          return;
        }
        await _json(response, 401, <String, dynamic>{'error': 'bad login'});
        return;
      }

      if (request.method == 'GET' && path == '/Users/user-1/Views') {
        viewRequests++;
        if (request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        await _json(response, 200, <String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 'view-1',
              'Name': 'Movies',
              'CollectionType': 'movies',
            },
          ],
          'TotalRecordCount': 1,
        });
        return;
      }

      if (request.method == 'GET' && path == '/expired') {
        expiredRequests++;
        await _json(response, 401, <String, dynamic>{'error': 'expired'});
        return;
      }

      await _json(response, 404, <String, dynamic>{'error': 'not found'});
    } catch (_) {
      response.statusCode = 500;
      response.write('{"error":"fake server failure"}');
      await response.close();
    }
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
