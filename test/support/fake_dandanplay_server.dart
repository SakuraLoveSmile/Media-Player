import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Programmable DandanPlay surface for the S17 弹幕 tests.
///
/// A real loopback server rather than a mocked client (same approach as
/// [FakeMoviePilotServer]): the repository and the HTTP client are exercised
/// together, and the test can assert on the exact query string the app
/// produced. DandanPlay is public, so there is no auth to fake.
class FakeDandanPlayServer {
  late HttpServer _server;

  /// `METHOD /path` for every request, in arrival order.
  final List<String> requestLog = <String>[];

  /// Last seen query per path, so a test can assert `anime` / `episode` /
  /// `withRelated` without re-parsing the log.
  final Map<String, Map<String, String>> lastQuery =
      <String, Map<String, String>>{};

  /// `GET /api/v2/search/episodes` reply: the `animes` array.
  List<Map<String, dynamic>> animes = <Map<String, dynamic>>[];

  /// `GET /api/v2/comment/{id}` reply per episode id: the `comments` array.
  Map<int, List<Map<String, dynamic>>> commentsByEpisode =
      <int, List<Map<String, dynamic>>>{};

  /// Paths (exact, or a prefix ending in `*`) that answer 500.
  final Set<String> failingPaths = <String>{};

  /// When true, every reply is a plain-text body instead of JSON.
  bool nonJson = false;

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final HttpResponse response = request.response;
    final String path = request.uri.path;
    requestLog.add('${request.method} $path');
    lastQuery[path] = request.uri.queryParameters;

    try {
      if (nonJson) {
        response.statusCode = 200;
        response.headers.contentType = ContentType.text;
        response.write('not json');
        await response.close();
        return;
      }

      final int? forced = _statusFor(path);
      if (forced != null) {
        await _reply(response, forced, <String, dynamic>{
          'error': 'forced $forced',
        });
        return;
      }

      if (request.method == 'GET' && path == '/api/v2/search/episodes') {
        await _reply(response, 200, <String, dynamic>{'animes': animes});
        return;
      }
      if (request.method == 'GET' && path.startsWith('/api/v2/comment/')) {
        final int? id = int.tryParse(path.split('/').last);
        await _reply(response, 200, <String, dynamic>{
          'comments': commentsByEpisode[id] ?? <Map<String, dynamic>>[],
        });
        return;
      }

      await _reply(response, 404, <String, dynamic>{'error': 'not found'});
    } catch (_) {
      response.statusCode = 500;
      response.write('{"error":"fake server failure"}');
      await response.close();
    }
  }

  int? _statusFor(String path) {
    if (failingPaths.contains(path)) return 500;
    for (final String prefix in failingPaths) {
      if (prefix.endsWith('*') &&
          path.startsWith(prefix.substring(0, prefix.length - 1))) {
        return 500;
      }
    }
    return null;
  }

  Future<void> _reply(
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

/// One `animes` entry with its `episodes`, in the wire shape.
Map<String, dynamic> fakeAnime(
  int animeId,
  String title,
  List<(int, String)> episodes,
) {
  return <String, dynamic>{
    'animeId': animeId,
    'animeTitle': title,
    'episodes': <Map<String, dynamic>>[
      for (final (int id, String name) in episodes)
        <String, dynamic>{'episodeId': id, 'episodeTitle': name},
    ],
  };
}

/// One `comments` entry: `p` is `"time,mode,color,size"`.
Map<String, dynamic> fakeComment(int cid, String p, String text) {
  return <String, dynamic>{'cid': cid, 'p': p, 'm': text, 's': 0};
}
