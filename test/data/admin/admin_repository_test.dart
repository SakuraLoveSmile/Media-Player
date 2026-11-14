import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/admin/admin_repository.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
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
  late AdminRepository admin;

  setUp(() async {
    server = FakeEmbyServer();
    await server.start();
    kv = InMemoryKeyValueStore();
    final client = EmbyHttpClient(Dio(), deviceId: 'device-1');
    final resolver = EndpointResolver(
      HttpEndpointProbe(client),
      lanTimeout: const Duration(seconds: 1),
      wanTimeout: const Duration(seconds: 1),
    );
    auth = AuthRepository(
      client: client,
      resolver: resolver,
      tokenStore: TokenStore(kv),
      sessionStore: SessionStore(kv),
      profileStore: ProfileStore(kv),
      deviceId: 'device-1',
      deviceName: 'test',
    );
    await auth.login(
      username: 'test',
      password: 'correct',
      profile: ServerProfile(serverId: '', name: 'Home', lanUrl: server.base),
    );
    admin = AdminRepository(auth);
  });

  tearDown(() async {
    await auth.dispose();
    await server.stop();
  });

  group('systemInfo', () {
    test('parses name, version, OS and pending restart', () async {
      server.systemInfoResponse = <String, dynamic>{
        'ServerName': 'NAS',
        'Version': '4.9.0.50',
        'OperatingSystem': 'Windows',
        'HasPendingRestart': true,
      };

      final info = await admin.systemInfo();

      expect(info.serverName, 'NAS');
      expect(info.version, '4.9.0.50');
      expect(info.operatingSystem, 'Windows');
      expect(info.hasPendingRestart, isTrue);
      expect(server.requestLog, contains('GET /System/Info'));
    });

    test('defaults missing fields instead of crashing', () async {
      server.systemInfoResponse = <String, dynamic>{};

      final info = await admin.systemInfo();

      expect(info.serverName, '');
      expect(info.version, '');
      expect(info.operatingSystem, '');
      expect(info.hasPendingRestart, isFalse);
    });

    test('a revoked token maps to unauthorized', () async {
      server.revokeToken = true;

      await expectLater(
        admin.systemInfo(),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
    });

    test('a server failure maps to serverError', () async {
      server.systemInfoStatus = 500;

      await expectLater(
        admin.systemInfo(),
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

  group('users', () {
    test('parses id, name, admin flag and last login', () async {
      server.usersResponse = <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'u-1',
          'Name': 'alice',
          'Policy': <String, dynamic>{'IsAdministrator': true},
          'LastLoginDate': '2026-11-20T08:30:00.0000000Z',
        },
        <String, dynamic>{
          'Id': 'u-2',
          'Name': 'bob',
          'Policy': <String, dynamic>{'IsAdministrator': false},
        },
      ];

      final users = await admin.users();

      expect(users, hasLength(2));
      expect(users[0].id, 'u-1');
      expect(users[0].name, 'alice');
      expect(users[0].isAdministrator, isTrue);
      expect(users[0].lastLoginDate, DateTime.utc(2026, 11, 20, 8, 30));
      expect(users[1].name, 'bob');
      expect(users[1].isAdministrator, isFalse);
      expect(users[1].lastLoginDate, isNull);
      expect(server.requestLog, contains('GET /Users'));
    });

    test('tolerates a missing policy and blank names', () async {
      server.usersResponse = <Map<String, dynamic>>[
        <String, dynamic>{'Id': 'u-3'},
      ];

      final users = await admin.users();

      expect(users.single.id, 'u-3');
      expect(users.single.name, '');
      expect(users.single.isAdministrator, isFalse);
      expect(users.single.lastLoginDate, isNull);
    });

    test('a server failure maps to serverError', () async {
      server.usersStatus = 500;

      await expectLater(
        admin.users(),
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

  group('sessions', () {
    test('parses user, client, device, now playing and position', () async {
      server.sessionsResponse = <Map<String, dynamic>>[
        <String, dynamic>{
          'UserName': 'alice',
          'Client': 'Yamby',
          'DeviceName': 'Pixel 9',
          'NowPlayingItem': <String, dynamic>{'Name': 'Dune', 'Type': 'Movie'},
          'PlayState': <String, dynamic>{'PositionTicks': 600000000},
        },
        <String, dynamic>{
          'UserName': 'bob',
          'Client': 'Emby Web',
          'DeviceName': 'Chrome',
        },
      ];

      final sessions = await admin.sessions();

      expect(sessions, hasLength(2));
      expect(sessions[0].userName, 'alice');
      expect(sessions[0].client, 'Yamby');
      expect(sessions[0].deviceName, 'Pixel 9');
      expect(sessions[0].nowPlayingName, 'Dune');
      expect(sessions[0].positionTicks, 600000000);
      expect(sessions[0].isPlaying, isTrue);
      // An idle session carries no NowPlayingItem and no position.
      expect(sessions[1].nowPlayingName, isNull);
      expect(sessions[1].positionTicks, 0);
      expect(sessions[1].isPlaying, isFalse);
      expect(server.requestLog, contains('GET /Sessions'));
    });

    test('an episode reads as series · episode', () async {
      server.sessionsResponse = <Map<String, dynamic>>[
        <String, dynamic>{
          'UserName': 'alice',
          'NowPlayingItem': <String, dynamic>{
            'Name': 'Episode 3',
            'SeriesName': 'Severance',
            'Type': 'Episode',
          },
          // Numeric strings appear on some Emby versions.
          'PlayState': <String, dynamic>{'PositionTicks': '123'},
        },
      ];

      final sessions = await admin.sessions();

      expect(sessions.single.nowPlayingName, 'Severance · Episode 3');
      expect(sessions.single.positionTicks, 123);
    });
  });

  group('isAdmin', () {
    test('reads Policy.IsAdministrator of the session user', () async {
      expect(await admin.isAdmin(), isTrue);
      expect(server.requestLog, contains('GET /Users/user-1'));
    });

    test('a non-admin policy reads false', () async {
      server.currentUserResponse = <String, dynamic>{
        'Id': 'user-1',
        'Name': 'test',
        'Policy': <String, dynamic>{'IsAdministrator': false},
      };

      expect(await admin.isAdmin(), isFalse);
    });

    test('a missing policy reads false', () async {
      server.currentUserResponse = <String, dynamic>{'Id': 'user-1'};

      expect(await admin.isAdmin(), isFalse);
    });

    test('logged out reads false without a request', () async {
      await auth.logout();
      final int before = server.requestLog.length;

      expect(await admin.isAdmin(), isFalse);
      expect(server.requestLog.length, before);
    });
  });
}
