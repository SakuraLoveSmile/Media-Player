import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/moviepilot_exception.dart';
import 'package:media_player/data/moviepilot/api/moviepilot_http_client.dart';
import 'package:media_player/data/moviepilot/api/mp_envelope.dart';

import '../../support/fake_moviepilot_server.dart';

void main() {
  late FakeMoviePilotServer server;
  late List<String> logs;
  late MoviePilotHttpClient client;

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${server.apiBase}$path').replace(queryParameters: query);

  setUp(() async {
    server = FakeMoviePilotServer();
    await server.start();
    logs = <String>[];
    client = MoviePilotHttpClient(Dio(), logSink: logs.add);
  });

  tearDown(() async {
    await server.stop();
  });

  group('MoviePilotHttpClient', () {
    test('sends X-API-KEY and accepts an enveloped reply', () async {
      final body = await client.getJson(
        uri('/media/search', <String, String>{'title': 'dune'}),
        apiToken: FakeMoviePilotServer().apiKey,
      );

      expect(server.lastApiKey, 'test-api-key');
      expect(server.lastQuery['/api/v1/media/search'], <String, String>{
        'title': 'dune',
      });
      expect(MpEnvelope.list(body), isEmpty);
    });

    test('accepts a bare list reply', () async {
      server.envelope = false;
      server.searchResults = <Map<String, dynamic>>[
        <String, dynamic>{'title': 'Dune'},
      ];

      final body = await client.getJson(
        uri('/media/search'),
        apiToken: 'test-api-key',
      );

      expect(MpEnvelope.list(body), hasLength(1));
    });

    test('posts a JSON body and unwraps the created id', () async {
      final body = await client.postJson(
        uri('/subscribe/'),
        apiToken: 'test-api-key',
        body: <String, dynamic>{'name': 'Dune', 'season': null},
      );

      expect(server.lastBody['/api/v1/subscribe/'], <String, dynamic>{
        'name': 'Dune',
        'season': null,
      });
      expect(MpEnvelope.object(body)['id'], 100);
    });

    test('deletes without a body', () async {
      final body = await client.deleteJson(
        uri('/subscribe/7'),
        apiToken: 'test-api-key',
      );

      expect(server.requestLog, contains('DELETE /api/v1/subscribe/7'));
      // v3 answers `{success: true, data: {}}`; the empty map is the payload.
      expect(MpEnvelope.object(body), isEmpty);
    });

    test('a 401 becomes unauthorized', () async {
      server.revokeToken = true;

      await expectLater(
        client.getJson(uri('/subscribe/'), apiToken: 'wrong'),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
    });

    test('a 403 (token without the admin role) is unauthorized too', () async {
      server.statusOverrides['/api/v1/subscribe/'] = 403;

      await expectLater(
        client.getJson(uri('/subscribe/'), apiToken: 'test-api-key'),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
    });

    test('a 500 becomes serverError carrying the server reason', () async {
      server.failingPaths.add('/api/v1/subscribe/');

      await expectLater(
        client.getJson(uri('/subscribe/'), apiToken: 'test-api-key'),
        throwsA(
          isA<MoviePilotException>()
              .having((e) => e.code, 'code', AppErrorCode.serverError)
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('logs the path but never the token or the query', () async {
      await client.getJson(
        uri('/media/search', <String, String>{'title': 'dune'}),
        apiToken: 'super-secret',
      );

      expect(logs, hasLength(1));
      expect(logs.single, startsWith('GET '));
      expect(logs.single, contains('/api/v1/media/search'));
      expect(logs.single, isNot(contains('dune')));
      expect(logs.single, isNot(contains('super-secret')));
    });

    test('a closed port becomes networkUnreachable', () async {
      final closed = MoviePilotHttpClient(Dio());

      await expectLater(
        closed.getJson(
          Uri.parse('http://127.0.0.1:1/api/v1/subscribe/'),
          apiToken: 't',
        ),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.networkUnreachable,
          ),
        ),
      );
    });

    test('a non-JSON body becomes serverError', () async {
      // `_decode` rejects a plain-string body that is not JSON.
      final closed = MoviePilotHttpClient(
        Dio(),
        defaultReceiveTimeout: const Duration(milliseconds: 200),
      );
      await expectLater(
        closed.getJson(
          Uri.parse('${server.base}/api/v1/not-json'),
          apiToken: 't',
        ),
        throwsA(isA<MoviePilotException>()),
      );
    });

    test('an empty body decodes to null', () async {
      server.envelope = false;
      server.downloads = <Map<String, dynamic>>[];

      final body = await client.getJson(
        uri('/download/'),
        apiToken: 'test-api-key',
      );

      expect(body, isA<List<Object?>>());
    });
  });

  group('MpEnvelope', () {
    test('unwraps the three v3 shapes', () {
      expect(
        MpEnvelope.list(<String, dynamic>{
          'success': true,
          'data': <Object?>[
            <String, dynamic>{'a': 1},
          ],
        }),
        hasLength(1),
      );
      expect(
        MpEnvelope.list(<Object?>[
          <String, dynamic>{'a': 1},
        ]),
        hasLength(1),
      );
      expect(
        MpEnvelope.list(<String, dynamic>{
          'data': <String, dynamic>{
            'list': <Object?>[
              <String, dynamic>{'a': 1},
            ],
            'total': 1,
          },
        }),
        hasLength(1),
      );
    });

    test('success:false raises with the server message', () {
      expect(
        () => MpEnvelope.unwrap(<String, dynamic>{
          'success': false,
          'message': '订阅已存在',
        }),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.message,
            'message',
            '订阅已存在',
          ),
        ),
      );
    });

    test('a null data payload is not a failure', () {
      expect(
        MpEnvelope.unwrap(<String, dynamic>{'success': true, 'data': null}),
        isNull,
      );
    });

    test('total reads the paged envelope', () {
      expect(
        MpEnvelope.total(<String, dynamic>{
          'data': <String, dynamic>{'list': <Object?>[], 'total': 7},
        }),
        7,
      );
      expect(MpEnvelope.total(<Object?>[]), isNull);
    });

    test('a malformed payload degrades to empty collections', () {
      expect(MpEnvelope.list(null), isEmpty);
      expect(MpEnvelope.list(<String, dynamic>{'unexpected': true}), isEmpty);
      expect(MpEnvelope.object(null), isEmpty);
    });
  });
}
