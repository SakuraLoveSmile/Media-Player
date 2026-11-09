import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Programmable MoviePilot v3 surface for the 求片 tests (plan S2).
///
/// A real loopback server rather than a mocked client: the repository and the
/// HTTP client are exercised together, and the test can assert on the exact
/// query string and body the app produced. Every endpoint the feature uses is
/// here, plus the knobs needed to break it on purpose.
class FakeMoviePilotServer {
  FakeMoviePilotServer({this.apiKey = 'test-api-key'});

  final String apiKey;

  late HttpServer _server;

  /// `METHOD /path` for every request, in arrival order.
  final List<String> requestLog = <String>[];

  /// Last seen query per path, so a test can assert `mtype` (not `type`) or
  /// `media_source` without re-parsing the log.
  final Map<String, Map<String, String>> lastQuery =
      <String, Map<String, String>>{};

  /// Last seen raw body per path.
  final Map<String, Map<String, dynamic>> lastBody =
      <String, Map<String, dynamic>>{};

  /// `X-API-KEY` of the most recent request.
  String? lastApiKey;

  /// When false, endpoints answer with the bare payload instead of the
  /// `{success, data}` envelope, so both shapes stay covered.
  bool envelope = true;

  /// Paths (exact, or a prefix ending in `*`) that answer 500.
  final Set<String> failingPaths = <String>{};

  /// Status override per path, checked before [failingPaths].
  final Map<String, int> statusOverrides = <String, int>{};

  /// Reject every request with 401, like a rotated or revoked token.
  bool revokeToken = false;

  /// When set, requests to this path wait for it before replying, so a test
  /// can prove polling is serialized.
  String? holdPath;
  Future<void>? hold;

  /// `GET /media/search` reply.
  List<Map<String, dynamic>> searchResults = <Map<String, dynamic>>[];

  /// `GET /media/seasons` reply.
  List<Map<String, dynamic>> seasons = <Map<String, dynamic>>[];

  /// `GET /mediaserver/exists` reply: the `data` of the `{item: {...}}` map.
  /// Null means "not in the library".
  Map<String, dynamic>? existingItem;

  /// `GET /subscribe/` reply (active subscriptions).
  List<Map<String, dynamic>> subscribes = <Map<String, dynamic>>[];

  /// `GET /subscribe/history/{mtype}` reply.
  List<Map<String, dynamic>> subscribeHistory = <Map<String, dynamic>>[];

  /// Id handed back by `POST /subscribe/`.
  int createdSubscribeId = 100;

  /// `GET /download/` reply.
  List<Map<String, dynamic>> downloads = <Map<String, dynamic>>[];

  /// `GET /transfer/queue` reply.
  List<Map<String, dynamic>> transferQueue = <Map<String, dynamic>>[];

  /// `GET /history/transfer` reply.
  List<Map<String, dynamic>> transferHistory = <Map<String, dynamic>>[];

  String get base => 'http://127.0.0.1:${_server.port}';

  String get apiBase => '$base/api/v1';

  int requestsTo(String path) => requestLog.where((line) => line.endsWith(' $path')).length;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    final method = request.method;
    requestLog.add('$method $path');
    lastQuery[path] = request.uri.queryParameters;
    lastApiKey = request.headers.value('X-API-KEY');

    try {
      if (hold != null && holdPath != null && path.startsWith(holdPath!)) {
        await hold;
      }

      if (revokeToken) {
        await _reply(response, 401, <String, dynamic>{'detail': 'bad token'});
        return;
      }

      final override = _statusFor(path);
      if (override != null) {
        await _reply(response, override, <String, dynamic>{
          'detail': 'forced $override',
        });
        return;
      }

      final raw = await utf8.decoder.bind(request).join();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          lastBody[path] = Map<String, dynamic>.from(decoded);
        }
      }

      if (method == 'GET' && path == '/api/v1/media/search') {
        await _collection(response, searchResults);
        return;
      }
      if (method == 'GET' && path == '/api/v1/media/seasons') {
        await _collection(response, seasons);
        return;
      }
      if (method == 'GET' && path == '/api/v1/mediaserver/exists') {
        final item = existingItem ?? <String, dynamic>{};
        await _payload(response, <String, dynamic>{'item': item});
        return;
      }
      if (method == 'GET' && path == '/api/v1/subscribe/') {
        await _collection(response, subscribes);
        return;
      }
      if (method == 'POST' && path == '/api/v1/subscribe/') {
        await _payload(response, <String, dynamic>{'id': createdSubscribeId});
        return;
      }
      if (method == 'POST' && path.startsWith('/api/v1/subscribe/search/')) {
        await _payload(response, <String, dynamic>{});
        return;
      }
      if (method == 'DELETE' && path.startsWith('/api/v1/subscribe/')) {
        await _payload(response, <String, dynamic>{});
        return;
      }
      if (method == 'GET' && path.startsWith('/api/v1/subscribe/history/')) {
        await _collection(response, subscribeHistory);
        return;
      }
      if (method == 'GET' && path == '/api/v1/download/') {
        await _collection(response, downloads);
        return;
      }
      if (method == 'GET' && path == '/api/v1/transfer/queue') {
        await _collection(response, transferQueue);
        return;
      }
      if (method == 'GET' && path == '/api/v1/history/transfer') {
        // Paged shape: `{data: {list, total}}`.
        await _reply(response, 200, <String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'list': transferHistory,
            'total': transferHistory.length,
          },
        });
        return;
      }

      await _reply(response, 404, <String, dynamic>{'detail': 'not found'});
    } catch (_) {
      response.statusCode = 500;
      response.write('{"detail":"fake server failure"}');
      await response.close();
    }
  }

  int? _statusFor(String path) {
    final exact = statusOverrides[path];
    if (exact != null) return exact;
    for (final entry in statusOverrides.entries) {
      if (entry.key.endsWith('*') &&
          path.startsWith(entry.key.substring(0, entry.key.length - 1))) {
        return entry.value;
      }
    }
    if (failingPaths.contains(path)) return 500;
    for (final prefix in failingPaths) {
      if (prefix.endsWith('*') &&
          path.startsWith(prefix.substring(0, prefix.length - 1))) {
        return 500;
      }
    }
    return null;
  }

  /// Collection reply: bare list by default, `{success, data}` when the
  /// envelope switch is on.
  Future<void> _collection(
    HttpResponse response,
    List<Map<String, dynamic>> items,
  ) async {
    if (!envelope) {
      await _replyList(response, 200, items);
      return;
    }
    await _reply(response, 200, <String, dynamic>{
      'success': true,
      'data': items,
    });
  }

  Future<void> _payload(HttpResponse response, Map<String, dynamic> data) async {
    if (!envelope) {
      await _reply(response, 200, data);
      return;
    }
    await _reply(response, 200, <String, dynamic>{
      'success': true,
      'data': data,
    });
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

  Future<void> _replyList(
    HttpResponse response,
    int status,
    List<Map<String, dynamic>> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
