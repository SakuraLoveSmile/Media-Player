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
  int imageRequests = 0;
  bool revokeToken = false;
  String? lastAuthorizationHeader;
  Map<String, String>? lastItemsQuery;
  final List<String> requestLog = <String>[];

  /// 130 movies so paging can be exercised with 60-item pages.
  final List<Map<String, dynamic>> movieItems = List<Map<String, dynamic>>.generate(
    130,
    (index) => <String, dynamic>{
      'Id': 'movie-${index + 1}',
      'Name': 'Movie ${index + 1}',
      'Type': 'Movie',
      'RunTimeTicks': 6000000000,
    },
  );

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
    requestLog.add('${request.method} $path');

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
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
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

      if (request.method == 'GET' && path == '/Users/user-1/Items') {
        lastItemsQuery = request.uri.queryParameters;
        final parentId = request.uri.queryParameters['ParentId'];
        final start = int.tryParse(request.uri.queryParameters['StartIndex'] ?? '') ?? 0;
        final limit = int.tryParse(request.uri.queryParameters['Limit'] ?? '') ?? 60;
        final all = parentId == 'view-1' ? movieItems : const <Map<String, dynamic>>[];
        final slice = all.skip(start).take(limit).toList(growable: false);

        await _json(response, 200, <String, dynamic>{
          'Items': slice,
          'TotalRecordCount': all.length,
          'StartIndex': start,
        });
        return;
      }

      if (request.method == 'GET' && path.startsWith('/Users/user-1/Items/')) {
        final id = path.split('/').last;
        await _json(response, 200, <String, dynamic>{
          'Id': id,
          'Name': 'Detail $id',
          'Type': 'Movie',
          'MediaSources': <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 'source-1',
              'Container': 'mkv',
              'Bitrate': 12100000,
              'SupportsDirectPlay': true,
              'SupportsDirectStream': true,
              'DirectStreamUrl': '/videos/$id/stream.mkv?Static=true',
              'MediaStreams': <Map<String, dynamic>>[
                <String, dynamic>{'Type': 'Video', 'Index': 0, 'Codec': 'hevc'},
              ],
            },
          ],
        });
        return;
      }

      if (request.method == 'GET' && path == '/Shows/series-1/Seasons') {
        await _json(response, 200, <String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 'season-1',
              'Name': 'Season 1',
              'Type': 'Season',
              'SeriesId': 'series-1',
              'IndexNumber': 1,
            },
            <String, dynamic>{
              'Id': 'season-2',
              'Name': 'Season 2',
              'Type': 'Season',
              'SeriesId': 'series-1',
              'IndexNumber': 2,
            },
          ],
          'TotalRecordCount': 2,
        });
        return;
      }

      if (request.method == 'GET' && path == '/Shows/series-1/Episodes') {
        final seasonId = request.uri.queryParameters['SeasonId'];
        final all = <Map<String, dynamic>>[
          <String, dynamic>{
            'Id': 'ep-1',
            'Name': 'Episode 1',
            'Type': 'Episode',
            'SeriesId': 'series-1',
            'SeasonId': 'season-1',
            'IndexNumber': 1,
          },
          <String, dynamic>{
            'Id': 'ep-2',
            'Name': 'Episode 2',
            'Type': 'Episode',
            'SeriesId': 'series-1',
            'SeasonId': 'season-1',
            'IndexNumber': 2,
          },
          <String, dynamic>{
            'Id': 'ep-3',
            'Name': 'Episode 3',
            'Type': 'Episode',
            'SeriesId': 'series-1',
            'SeasonId': 'season-2',
            'IndexNumber': 1,
          },
        ];
        await _json(response, 200, <String, dynamic>{
          'Items': all.where((e) => seasonId == null || e['SeasonId'] == seasonId).toList(),
          'TotalRecordCount': all.length,
        });
        return;
      }

      if (request.method == 'GET' && path.startsWith('/Items/') && path.endsWith('/Images/Primary')) {
        imageRequests++;
        response.statusCode = 200;
        response.headers.contentType = ContentType('image', 'png');
        response.add(<int>[0x89, 0x50, 0x4E, 0x47]);
        await response.close();
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
