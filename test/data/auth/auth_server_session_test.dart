import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/models/server_entry.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

import '../../support/fake_emby_server.dart';

void main() {
  late FakeEmbyServer serverA;
  late FakeEmbyServer serverB;
  late InMemoryKeyValueStore kv;

  AuthRepository buildRepository() {
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
      store: kv,
      deviceId: 'device-1',
      deviceName: 'test device',
    );
  }

  ServerProfile profileFor(FakeEmbyServer target, String name) =>
      ServerProfile(serverId: '', name: name, lanUrl: target.base);

  setUp(() async {
    serverA = FakeEmbyServer(serverId: 'server-a', serverName: 'A');
    serverB = FakeEmbyServer(serverId: 'server-b', serverName: 'B');
    await serverA.start();
    await serverB.start();
    kv = InMemoryKeyValueStore();
  });

  tearDown(() async {
    await serverA.stop();
    await serverB.stop();
  });

  test('the default server keeps using the legacy credential keys', () async {
    final repo = buildRepository();
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverA, 'A'),
    );

    expect(repo.activeServerId, defaultServerId);
    expect(await kv.read(TokenStore.key), serverA.token);
    expect(await kv.read('${TokenStore.key}.$defaultServerId'), isNull);
  });

  test('login under a second server id writes suffixed keys', () async {
    final repo = buildRepository();
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverA, 'A'),
    );

    repo.useServer('b');
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverB, 'B'),
    );

    expect(repo.activeServerId, 'b');
    expect(await kv.read('${TokenStore.key}.b'), serverB.token);
    expect(await kv.read('${SessionStore.key}.b'), isNotNull);
    expect(await kv.read('${ProfileStore.key}.b'), isNotNull);
    // The default server's credentials are untouched.
    expect(await kv.read(TokenStore.key), serverA.token);
  });

  test('restoreServer recovers each server session independently', () async {
    final repo = buildRepository();
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverA, 'A'),
    );
    repo.useServer('b');
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverB, 'B'),
    );

    final a = await repo.restoreServer(defaultServerId);
    expect(a?.accessToken, serverA.token);
    expect(repo.activeServerId, defaultServerId);
    expect(repo.profile?.lanUrl, serverA.base);

    final b = await repo.restoreServer('b');
    expect(b?.accessToken, serverB.token);
    expect(repo.activeServerId, 'b');
    expect(repo.profile?.lanUrl, serverB.base);
  });

  test('a fresh repository restores the last active server', () async {
    final first = buildRepository();
    await first.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverA, 'A'),
    );
    first.useServer('b');
    await first.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverB, 'B'),
    );

    // Simulates an app restart pointed at server 'b'.
    final second = buildRepository();
    final restored = await second.restoreServer('b');
    expect(restored?.accessToken, serverB.token);
  });

  test('restoreServer returns null for a server with no session', () async {
    final repo = buildRepository();
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverA, 'A'),
    );

    expect(await repo.restoreServer('never-logged-in'), isNull);
    expect(repo.current, isNull);
    // The default session is still stored.
    expect(await kv.read(TokenStore.key), serverA.token);
  });

  test('clearServer removes only that server credentials', () async {
    final repo = buildRepository();
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverA, 'A'),
    );
    repo.useServer('b');
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverB, 'B'),
    );

    await repo.clearServer('b');

    expect(await kv.read('${TokenStore.key}.b'), isNull);
    expect(await kv.read('${SessionStore.key}.b'), isNull);
    expect(await kv.read('${ProfileStore.key}.b'), isNull);
    expect(await repo.restoreServer('b'), isNull);
    // Default survives.
    expect(
      (await repo.restoreServer(defaultServerId))?.accessToken,
      serverA.token,
    );
  });

  test('logout clears only the active server session', () async {
    final repo = buildRepository();
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverA, 'A'),
    );
    repo.useServer('b');
    await repo.login(
      username: 'test',
      password: 'correct',
      profile: profileFor(serverB, 'B'),
    );

    await repo.logout();

    expect(repo.current, isNull);
    expect(await kv.read('${TokenStore.key}.b'), isNull);
    expect(await kv.read(TokenStore.key), serverA.token);
  });
}
