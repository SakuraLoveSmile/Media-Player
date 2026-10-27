import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/api/emby_headers.dart';

void main() {
  late HttpServer server;
  late String base;
  late List<String> logs;
  final receivedHeaders = <HttpHeaders>[];

  EmbyHttpClient buildClient({Duration? timeout}) {
    return EmbyHttpClient(
      dio: Dio(),
      deviceId: 'device-1',
      logSink: logs.add,
      defaultConnectTimeout: timeout ?? const Duration(seconds: 5),
      defaultReceiveTimeout: timeout ?? const Duration(seconds: 5),
    );
  }

  setUp(() async {
    logs = <String>[];
    receivedHeaders.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';

    server.listen((request) async {
      receivedHeaders.add(request.headers);
      final path = request.uri.path;
      final response = request.response;

      switch (path) {
        case '/json':
          response.headers.contentType = ContentType.json;
          response.write('{"Id":"server-1","ServerName":"Home"}');
        case '/redirect':
          response.statusCode = HttpStatus.found;
          response.headers.set(HttpHeaders.locationHeader, '/json');
        case '/htmlish':
          response.headers.contentType = ContentType.html;
          response.write('<html>not json</html>');
        case '/empty':
          response.statusCode = HttpStatus.noContent;
        case '/slow':
          await Future<void>.delayed(const Duration(seconds: 5));
        default:
          response.statusCode = switch (path) {
            '/401' => 401,
            '/403' => 403,
            '/404' => 404,
            '/500' => 500,
            _ => 418,
          };
          response.write('{"error":"status"}');
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('sends device id and token headers', () async {
    final json = await buildClient()
        .getJson(Uri.parse('$base/json'), token: 'secret-token');

    expect(json['Id'], 'server-1');
    final headers = receivedHeaders.single;
    expect(headers.value(EmbyHeaders.deviceId), 'device-1');
    expect(headers.value(EmbyHeaders.token), 'secret-token');
  });

  test('follows a 302 redirect to the real payload', () async {
    final json = await buildClient().getJson(Uri.parse('$base/redirect'));

    expect(json['ServerName'], 'Home');
    expect(receivedHeaders.length, 2);
  });

  test('posts a JSON body with an authorization header', () async {
    await buildClient().postJson(
      Uri.parse('$base/json'),
      body: <String, String>{'Username': 'u', 'Pw': 'p'},
      authorization: EmbyHeaders.authorizationValue(
        client: 'MediaPlayer',
        device: 'macos host',
        deviceId: 'device-1',
        version: '0.1.0',
      ),
    );

    final headers = receivedHeaders.last;
    expect(
      headers.value(EmbyHeaders.authorization),
      'MediaBrowser Client="MediaPlayer", Device="macos host", '
      'DeviceId="device-1", Version="0.1.0"',
    );
    expect(headers.contentType?.mimeType, 'application/json');
  });

  test('maps HTTP status codes', () async {
    final client = buildClient();
    final expectations = <String, AppErrorCode>{
      '/401': AppErrorCode.unauthorized,
      '/403': AppErrorCode.forbidden,
      '/404': AppErrorCode.notFound,
      '/500': AppErrorCode.serverError,
    };

    for (final entry in expectations.entries) {
      await expectLater(
        client.getJson(Uri.parse('$base${entry.key}')),
        throwsA(isA<EmbyException>()
            .having((e) => e.code, 'code', entry.value)),
        reason: entry.key,
      );
    }
  });

  test('maps non-JSON bodies to serverError', () async {
    await expectLater(
      buildClient().getJson(Uri.parse('$base/htmlish')),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.serverError)),
    );
  });

  test('treats an empty body as an empty map', () async {
    final json = await buildClient().getJson(Uri.parse('$base/empty'));
    expect(json, isEmpty);
  });

  test('maps a receive timeout to networkUnreachable', () async {
    final client = EmbyHttpClient(
      dio: Dio(),
      deviceId: 'device-1',
      defaultConnectTimeout: const Duration(milliseconds: 300),
      defaultReceiveTimeout: const Duration(milliseconds: 300),
    );

    await expectLater(
      client.getJson(Uri.parse('$base/slow')),
      throwsA(isA<EmbyException>().having(
        (e) => e.code,
        'code',
        AppErrorCode.networkUnreachable,
      )),
    );
  });

  test('maps a closed port to networkUnreachable', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = probe.port;
    await probe.close();

    await expectLater(
      buildClient().getJson(Uri.parse('http://127.0.0.1:$closedPort/json')),
      throwsA(isA<EmbyException>().having(
        (e) => e.code,
        'code',
        AppErrorCode.networkUnreachable,
      )),
    );
  });

  test('logs the path without query, token or api_key', () async {
    await buildClient().getJson(
      Uri.parse('$base/json?api_key=secret-token&MediaSourceId=1'),
      token: 'secret-token',
    );

    expect(logs, isNotEmpty);
    final joined = logs.join('\n');
    expect(joined, contains('/json'));
    expect(joined, isNot(contains('api_key')));
    expect(joined, isNot(contains('secret-token')));
    expect(joined, isNot(contains('MediaSourceId')));
  });
}
