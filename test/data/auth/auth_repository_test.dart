import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
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

  Future<AuthRepository> buildRepository({String deviceId = 'device-1'}) async {
    final client = EmbyHttpClient(Dio(), deviceId: deviceId);
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
      deviceId: deviceId,
      deviceName: 'test device',
    );
  }

  ServerProfile profileFor(FakeEmbyServer target) => ServerProfile(
        serverId: '',
        name: 'Home',
        lanUrl: target.base,
      );

  setUp(() async {
    server = FakeEmbyServer();
    await server.start();
    kv = InMemoryKeyValueStore();
  });

  tearDown(() async {
    await server.stop();
  });

  test('login adopts the server id and persists the session', () async {
    final repository = await buildRepository();
    final session = await repository.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(server),
    );

    expect(session.userId, 'user-1');
    expect(session.userName, 'test');
    expect(session.deviceId, 'device-1');
    expect(await kv.read(TokenStore.key), server.token);

    final storedProfile = await ProfileStore(kv).read();
    expect(storedProfile?.serverId, 'server-1');
    expect(storedProfile?.lastGoodEndpoint, EndpointKind.lan);
    expect(
      server.lastAuthorizationHeader,
      contains('DeviceId="device-1"'),
    );
  });

  test('a bad password leaves no credentials behind', () async {
    final repository = await buildRepository();

    await expectLater(
      repository.login(
        username: 'test',
        password: 'wrong',
        profile: profileFor(server),
      ),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
    );

    expect(await kv.read(TokenStore.key), isNull);
    expect(await kv.read(SessionStore.key), isNull);
    expect(repository.current, isNull);
  });

  test('restore recovers the session from storage', () async {
    final first = await buildRepository();
    await first.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(server),
    );

    // Simulates an app restart: new objects, same storage.
    final second = await buildRepository();
    final restored = await second.restore();

    expect(restored, isNotNull);
    expect(restored!.userId, 'user-1');
    expect(restored.accessToken, server.token);
  });

  test('restore keeps credentials when the server is unreachable', () async {
    final first = await buildRepository();
    await first.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(server),
    );
    await server.stop();

    final second = await buildRepository();
    final restored = await second.restore();

    expect(restored, isNull);
    expect(await kv.read(TokenStore.key), server.token);
  });

  test('adoptAddress rejects an address from another server', () async {
    final repository = await buildRepository();
    await repository.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(server),
    );
    final stored = (await ProfileStore(kv).read())!;

    final other = FakeEmbyServer(serverId: 'server-2');
    await other.start();
    addTearDown(other.stop);

    await expectLater(
      repository.adoptAddress(
        profile: stored,
        kind: EndpointKind.wan,
        rawUrl: other.base,
      ),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.serverMismatch)),
    );

    final unchanged = await ProfileStore(kv).read();
    expect(unchanged?.wanUrl, isNull);
  });

  test('adoptAddress stores a matching address', () async {
    final repository = await buildRepository();
    await repository.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(server),
    );
    final stored = (await ProfileStore(kv).read())!;

    final sameServer = FakeEmbyServer(serverId: 'server-1');
    await sameServer.start();
    addTearDown(sameServer.stop);

    final updated = await repository.adoptAddress(
      profile: stored,
      kind: EndpointKind.wan,
      rawUrl: '${sameServer.base}/',
    );

    expect(updated.wanUrl, sameServer.base);
    expect((await ProfileStore(kv).read())?.wanUrl, sameServer.base);
    expect(updated.lanUrl, server.base);
  });

  test('a 401 on a business call logs out exactly once', () async {
    final repository = await buildRepository();
    await repository.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(server),
    );

    await expectLater(
      repository.authorizedGet(Uri.parse('${server.base}/expired')),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
    );

    expect(repository.current, isNull);
    expect(await kv.read(TokenStore.key), isNull);
    expect(await kv.read(SessionStore.key), isNull);
    expect(await ProfileStore(kv).read(), isNotNull);
    expect(server.expiredRequests, 1);
  });

  test('authorizedGet uses the token and returns the payload', () async {
    final repository = await buildRepository();
    await repository.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(server),
    );

    final views = await repository.authorizedGet(
      Uri.parse('${server.base}/Users/user-1/Views'),
    );

    expect(views['TotalRecordCount'], 1);
    expect(server.viewRequests, 1);
  });

  test('logout clears the session but keeps the profile', () async {
    final repository = await buildRepository();
    await repository.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(server),
    );
    final emissions = <Object?>[];
    final subscription = repository.session.listen(emissions.add);
    addTearDown(subscription.cancel);

    await repository.logout();
    await Future<void>.delayed(Duration.zero);

    expect(repository.current, isNull);
    expect(await kv.read(TokenStore.key), isNull);
    expect(await ProfileStore(kv).read(), isNotNull);
    expect(emissions, <Object?>[null]);
  });
}
