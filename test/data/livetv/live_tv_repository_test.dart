import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/livetv/live_tv_repository.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

import '../../support/fake_emby_server.dart';

void main() {
  late FakeEmbyServer server;
  late InMemoryKeyValueStore kv;
  late AuthRepository auth;
  late LiveTvRepository liveTv;

  Future<AuthRepository> buildAuth() async {
    final client = EmbyHttpClient(Dio(), deviceId: 'device-1');
    final resolver = EndpointResolver(
      HttpEndpointProbe(client),
      lanTimeout: const Duration(seconds: 1),
      wanTimeout: const Duration(seconds: 1),
    );
    return AuthRepository(
      client: client,
      resolver: resolver,
      tokenStore: TokenStore(kv),
      sessionStore: SessionStore(kv),
      profileStore: ProfileStore(kv),
      deviceId: 'device-1',
      deviceName: 'test',
    );
  }

  setUp(() async {
    server = FakeEmbyServer();
    await server.start();
    kv = InMemoryKeyValueStore();
    auth = await buildAuth();
    await auth.login(
      username: 'test',
      password: 'correct',
      profile: ServerProfile(serverId: '', name: 'Home', lanUrl: server.base),
    );
    liveTv = LiveTvRepository(auth);
  });

  tearDown(() async {
    await auth.dispose();
    await server.stop();
  });

  group('channels (S21)', () {
    test('sends UserId, Fields and AddCurrentProgram', () async {
      server.liveTvChannels = <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'ch-1',
          'Name': 'CCTV-1',
          'Number': '1.1',
          'ImageTags': <String, dynamic>{'Primary': 'tag-1'},
        },
      ];

      final channels = await liveTv.channels();

      expect(channels, hasLength(1));
      final query = server.lastLiveTvChannelsQuery!;
      expect(query['UserId'], 'user-1');
      expect(query['AddCurrentProgram'], 'true');
      expect(query['Fields'], contains('CurrentProgram'));
      expect(query['Fields'], contains('ImageTags'));
      expect(query['Fields'], isNot(contains('MediaSources')));
      expect(server.requestLog, contains('GET /LiveTv/Channels'));
    });

    test('parses id, name, number, image tag and current program', () async {
      server.liveTvChannels = <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'ch-1',
          'Name': 'CCTV-1',
          'Number': '1.1',
          'ImageTags': <String, dynamic>{'Primary': 'tag-1'},
          'CurrentProgram': <String, dynamic>{
            'Id': 'prog-1',
            'Name': '新闻联播',
            'StartDate': '2024-01-01T19:00:00.0000000Z',
            'EndDate': '2024-01-01T19:30:00.0000000Z',
            'ChannelId': 'ch-1',
          },
        },
      ];

      final channel = (await liveTv.channels()).single;

      expect(channel.id, 'ch-1');
      expect(channel.name, 'CCTV-1');
      expect(channel.number, '1.1');
      expect(channel.imageTag, 'tag-1');
      final program = channel.currentProgram!;
      expect(program.id, 'prog-1');
      expect(program.name, '新闻联播');
      expect(program.channelId, 'ch-1');
      expect(program.startDate, DateTime.utc(2024, 1, 1, 19));
      expect(program.endDate, DateTime.utc(2024, 1, 1, 19, 30));
      expect(program.duration, const Duration(minutes: 30));
      // Halfway through the 30-minute program.
      expect(
        program.progressAt(DateTime.utc(2024, 1, 1, 19, 15)),
        closeTo(0.5, 0.0001),
      );
    });

    test('tolerates a numeric channel number and missing guide data', () async {
      server.liveTvChannels = <Map<String, dynamic>>[
        <String, dynamic>{'Id': 'ch-2', 'Name': 'No Guide', 'Number': 5},
      ];

      final channel = (await liveTv.channels()).single;

      expect(channel.number, '5');
      expect(channel.imageTag, isNull);
      expect(channel.currentProgram, isNull);
    });

    test('drops rows without an id and answers empty when none', () async {
      server.liveTvChannels = <Map<String, dynamic>>[
        <String, dynamic>{'Name': 'idless'},
      ];
      expect(await liveTv.channels(), isEmpty);

      server.liveTvChannels = <Map<String, dynamic>>[];
      expect(await liveTv.channels(), isEmpty);
    });

    test('a server error surfaces as an EmbyException', () async {
      server.liveTvStatus = 500;

      await expectLater(
        liveTv.channels(),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.serverError,
          ),
        ),
      );
    });

    test('a 404 (Live TV disabled) surfaces as notFound', () async {
      server.liveTvStatus = 404;

      await expectLater(
        liveTv.channels(),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.notFound,
          ),
        ),
      );
    });

    test('a revoked token clears the session', () async {
      server.revokeToken = true;

      await expectLater(
        liveTv.channels(),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
      expect(auth.current, isNull);
    });

    test('without a session it fails before any request', () async {
      await auth.logout();
      final callsBefore = server.requestLog.length;

      await expectLater(
        liveTv.channels(),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
      expect(server.requestLog.length, callsBefore);
    });
  });

  group('programs (S21)', () {
    test('sends UserId and ChannelIds and parses the guide', () async {
      server.liveTvPrograms = <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'prog-1',
          'Name': '新闻联播',
          'StartDate': '2024-01-01T19:00:00.0000000Z',
          'EndDate': '2024-01-01T19:30:00.0000000Z',
          'ChannelId': 'ch-1',
        },
        <String, dynamic>{
          'Id': 'prog-2',
          'Name': '焦点访谈',
          'StartDate': '2024-01-01T19:38:00.0000000Z',
          'EndDate': '2024-01-01T20:00:00.0000000Z',
          'ChannelId': 'ch-2',
        },
      ];

      final programs = await liveTv.programs(channelId: 'ch-1');

      expect(programs, hasLength(1));
      expect(programs.single.id, 'prog-1');
      expect(programs.single.name, '新闻联播');
      expect(programs.single.channelId, 'ch-1');
      expect(programs.single.startDate, DateTime.utc(2024, 1, 1, 19));
      expect(programs.single.endDate, DateTime.utc(2024, 1, 1, 19, 30));

      final query = server.lastLiveTvProgramsQuery!;
      expect(query['UserId'], 'user-1');
      expect(query['ChannelIds'], 'ch-1');
      expect(server.requestLog, contains('GET /LiveTv/Programs'));
    });

    test('omits ChannelIds when no channel is given', () async {
      server.liveTvPrograms = <Map<String, dynamic>>[
        <String, dynamic>{'Id': 'prog-1', 'Name': 'A', 'ChannelId': 'ch-1'},
        <String, dynamic>{'Id': 'prog-2', 'Name': 'B', 'ChannelId': 'ch-2'},
      ];

      final programs = await liveTv.programs();

      expect(programs, hasLength(2));
      expect(
        server.lastLiveTvProgramsQuery!.containsKey('ChannelIds'),
        isFalse,
      );
    });

    test('a missing or malformed date degrades to null', () async {
      server.liveTvPrograms = <Map<String, dynamic>>[
        <String, dynamic>{'Id': 'prog-1', 'Name': 'No dates'},
        <String, dynamic>{
          'Id': 'prog-2',
          'Name': 'Bad date',
          'StartDate': 'not-a-date',
        },
      ];

      final programs = await liveTv.programs();

      expect(programs.first.startDate, isNull);
      expect(programs.first.duration, isNull);
      expect(programs.first.progressAt(DateTime.now()), isNull);
      expect(programs.last.startDate, isNull);
    });

    test('a server error surfaces as an EmbyException', () async {
      server.liveTvStatus = 500;

      await expectLater(
        liveTv.programs(channelId: 'ch-1'),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.serverError,
          ),
        ),
      );
    });
  });

  group('channel image URL (S21)', () {
    test('carries size, tag, quality and api key', () async {
      final uri = liveTv.channelImageUrl('ch-1', tag: 'tag 1', maxWidth: 160);

      expect(uri, isNotNull);
      expect(uri!.path, '/Items/ch-1/Images/Primary');
      final query = uri.queryParameters;
      expect(query['maxWidth'], '160');
      expect(query['tag'], 'tag 1');
      expect(query['quality'], '90');
      expect(query['api_key'], server.token);
    });

    test('is null after logout', () async {
      await auth.logout();

      expect(liveTv.channelImageUrl('ch-1'), isNull);
    });
  });
}
