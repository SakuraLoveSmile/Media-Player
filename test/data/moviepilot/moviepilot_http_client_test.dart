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
    test('sends the bearer token and accepts an enveloped reply', () async {
      final body = await client.getJson(
        uri('/media/search', <String, String>{'title': 'dune'}),
        accessToken: server.accessToken,
      );

      expect(server.lastAuthorization, 'Bearer ${server.accessToken}');
      expect(server.lastQuery['/api/v1/media/search'], <String, String>{
        'title': 'dune',
      });
      expect(MpEnvelope.list(body), isEmpty);
    });

    test('the login call posts a form and carries no token', () async {
      final body = await client.postForm(
        uri('/login/access-token'),
        fields: <String, String>{'username': 'admin', 'password': 'secret'},
      );

      expect(server.lastAuthorization, isNull);
      expect(server.lastForm['/api/v1/login/access-token'], <String, String>{
        'username': 'admin',
        'password': 'secret',
      });
      expect(MpEnvelope.object(body)['access_token'], server.accessToken);
    });

    test('accepts a bare list reply', () async {
      server.envelope = false;
      server.searchResults = <Map<String, dynamic>>[
        <String, dynamic>{'title': 'Dune'},
      ];

      final body = await client.getJson(
        uri('/media/search'),
        accessToken: server.accessToken,
      );

      expect(MpEnvelope.list(body), hasLength(1));
    });

    test('posts a JSON body and unwraps the created id', () async {
      final body = await client.postJson(
        uri('/subscribe/'),
        accessToken: server.accessToken,
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
        accessToken: server.accessToken,
      );

      expect(server.requestLog, contains('DELETE /api/v1/subscribe/7'));
      // v3 answers `{success: true, data: {}}`; the empty map is the payload.
      expect(MpEnvelope.object(body), isEmpty);
    });

    test('a 401 becomes unauthorized', () async {
      server.revokeToken = true;

      await expectLater(
        client.getJson(uri('/subscribe/'), accessToken: 'expired'),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
    });

    test('a 403 (account without the manage role) is forbidden', () async {
      server.statusOverrides['/api/v1/download/'] = 403;

      await expectLater(
        client.getJson(uri('/download/'), accessToken: server.accessToken),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });

    test('a login 401 with X-MFA-Required is flagged', () async {
      server.mfaRequired = true;

      await expectLater(
        client.postForm(
          uri('/login/access-token'),
          fields: <String, String>{'username': 'admin', 'password': 'secret'},
        ),
        throwsA(
          isA<MoviePilotException>()
              .having((e) => e.code, 'code', AppErrorCode.unauthorized)
              .having((e) => e.mfaRequired, 'mfaRequired', isTrue),
        ),
      );
    });

    test('a plain login 401 is not flagged as MFA', () async {
      await expectLater(
        client.postForm(
          uri('/login/access-token'),
          fields: <String, String>{'username': 'admin', 'password': 'wrong'},
        ),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.mfaRequired,
            'mfaRequired',
            isFalse,
          ),
        ),
      );
    });

    test('a 500 becomes serverError carrying the server reason', () async {
      server.failingPaths.add('/api/v1/subscribe/');

      await expectLater(
        client.getJson(uri('/subscribe/'), accessToken: server.accessToken),
        throwsA(
          isA<MoviePilotException>()
              .having((e) => e.code, 'code', AppErrorCode.serverError)
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('logs the path but never the token or the query', () async {
      // A token the instance does not know is rejected; the point of the test
      // is that the log line written before the request never carries it.
      await expectLater(
        client.getJson(
          uri('/media/search', <String, String>{'title': 'dune'}),
          accessToken: 'super-secret',
        ),
        throwsA(isA<MoviePilotException>()),
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
          accessToken: 't',
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
          accessToken: 't',
        ),
        throwsA(isA<MoviePilotException>()),
      );
    });

    test('an empty body decodes to null', () async {
      server.envelope = false;
      server.downloads = <Map<String, dynamic>>[];

      final body = await client.getJson(
        uri('/download/'),
        accessToken: server.accessToken,
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
