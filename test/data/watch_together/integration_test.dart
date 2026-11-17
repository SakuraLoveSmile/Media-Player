import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/api_session.dart';
import 'package:media_player/data/models/resolved_endpoint.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/watch_together/watch_together_client.dart';

// The standalone service deliberately lives outside the Flutter package lib/.
// ignore: avoid_relative_lib_imports
import '../../../services/watch_together/lib/watch_server.dart' as service;

class _Session implements ApiSession {
  _Session(this.userId) : accessToken = 'token-$userId';
  @override
  String? userId;
  @override
  String? accessToken;
  @override
  ResolvedEndpoint? endpoint = ResolvedEndpoint(
    baseUrl: 'http://127.0.0.1:1',
    kind: EndpointKind.lan,
    serverId: 'server',
    resolvedAt: DateTime(2026),
  );
  @override
  String? get deviceId => 'fixture-device';
  @override
  ServerProfile? get profile =>
      const ServerProfile(serverId: 'server', name: 'Fixture');
  @override
  Future<Map<String, dynamic>> authorizedGet(Uri url) =>
      throw StateError('Room transport must not call the client Emby API');
  @override
  Future<Map<String, dynamic>> authorizedPost(Uri url, {Object? body}) =>
      throw StateError('Room transport must not call the client Emby API');
  @override
  Future<Map<String, dynamic>> authorizedDelete(Uri url) =>
      throw StateError('Room transport must not call the client Emby API');
}

class _Verifier implements service.WatchAuthVerifier {
  final denied = <String>{};
  final verified = <String>[];
  @override
  Future<service.WatchIdentity> verify({
    required String token,
    required String userId,
    required String serverId,
  }) async {
    if (serverId != 'server' || token != 'token-$userId') {
      throw const service.WatchFailure('AUTH_INVALID', '登录失效', 401);
    }
    verified.add(userId);
    return service.WatchIdentity(
      token: token,
      userId: userId,
      serverId: serverId,
      name: '昵称$userId',
    );
  }

  @override
  Future<service.WatchMedia> media(
    service.WatchIdentity identity,
    String itemId,
    String? mediaSourceId,
  ) async {
    if (denied.contains('${identity.userId}:$itemId')) {
      throw const service.WatchFailure('ITEM_FORBIDDEN', '无播放权限', 403);
    }
    if (mediaSourceId != null &&
        mediaSourceId != 'source-a' &&
        mediaSourceId != 'source-b') {
      throw const service.WatchFailure('MEDIA_SOURCE_INVALID', '版本无效', 403);
    }
    return service.WatchMedia(
      itemId: itemId,
      mediaSourceId: mediaSourceId ?? 'source-a',
      title: '服务端标题$itemId',
      type: 'Movie',
      runTimeMs: 60000,
    );
  }
}

Future<void> _until(bool Function() predicate, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late service.WatchServer server;
  late _Verifier verifier;
  late WatchTogetherClient owner;
  late WatchTogetherClient guest;
  late _Session ownerSession;
  late _Session guestSession;
  late InMemoryKeyValueStore ownerStore;
  late InMemoryKeyValueStore guestStore;
  final clients = <WatchTogetherClient>[];

  Future<WatchTogetherClient> client(
    _Session session,
    InMemoryKeyValueStore store,
  ) async {
    final result = WatchTogetherClient(session: session, store: store);
    clients.add(result);
    await result.initialize();
    await result.configure(server.baseUri);
    return result;
  }

  Future<void> pair() async {
    await owner.create(itemId: 'movie', mediaSourceId: 'source-b');
    await guest.join(owner.room!.code);
    await _until(
      () => owner.room!.members.length == 2 && guest.connected,
      'both room members',
    );
  }

  Future<void> loadingBoth() async {
    owner.reportStatus('loading');
    guest.reportStatus('loading');
    await _until(
      () => owner.room!.members.every((m) => m.status == 'loading'),
      'both loading statuses',
    );
  }

  Future<void> readyBoth() async {
    owner.reportStatus('ready');
    guest.reportStatus('ready');
    await _until(
      () =>
          owner.room!.playback.state == 'playing' &&
          guest.room!.playback.state == 'playing' &&
          owner.room!.playback.revision == guest.room!.playback.revision,
      'shared playing snapshot',
    );
  }

  setUp(() async {
    verifier = _Verifier();
    server = service.WatchServer(verifier: verifier);
    await server.start();
    ownerSession = _Session('owner');
    guestSession = _Session('guest');
    ownerStore = InMemoryKeyValueStore();
    guestStore = InMemoryKeyValueStore();
    owner = await client(ownerSession, ownerStore);
    guest = await client(guestSession, guestStore);
  });
  tearDown(() async {
    for (final entry in clients) {
      entry.dispose();
    }
    clients.clear();
    await server.close();
  });

  test(
    'two real clients share version, readiness, pause, seek and away',
    () async {
      await pair();
      expect(owner.isOwner, isTrue);
      expect(guest.isOwner, isFalse);
      expect(guest.room!.media.mediaSourceId, 'source-b');
      expect(guest.room!.media.title, '服务端标题movie');
      expect(verifier.verified, containsAll(['owner', 'guest']));

      await loadingBoth();
      await owner.command('play');
      await _until(
        () => guest.room!.playback.state == 'waiting',
        'guest readiness barrier',
      );
      expect(owner.room!.playback.waitingMemberIds, hasLength(2));
      owner.reportStatus('ready');
      await _until(
        () => guest.room!.playback.waitingMemberIds.length == 1,
        'one ready participant',
      );
      expect(guest.room!.playback.state, 'waiting');
      await readyBoth();
      final anchor = owner.room!.playback.serverTime;
      expect(guest.room!.playback.serverTime, anchor);
      expect(anchor, greaterThan(owner.serverNowMs));

      await guest.command('pause', positionMs: 4200);
      await _until(
        () => owner.room!.playback.state == 'paused',
        'guest pause at owner',
      );
      expect(owner.room!.playback.positionMs, 4200);
      await owner.command('seek', positionMs: 12000);
      await _until(
        () => guest.room!.playback.positionMs == 12000,
        'paused seek at guest',
      );
      expect(guest.room!.playback.state, 'paused');
      await guest.command('play');
      await _until(
        () => owner.room!.playback.state == 'waiting',
        'second readiness barrier',
      );
      await readyBoth();
      final revision = owner.room!.playback.revision;
      guest.reportStatus('away');
      await _until(
        () => owner.room!.members.any(
          (m) => m.memberId == guest.memberId && m.status == 'away',
        ),
        'away participant',
      );
      expect(owner.room!.playback.state, 'playing');
      expect(owner.room!.playback.revision, revision);
    },
  );

  test(
    'concurrent controls reject one stale revision without replay',
    () async {
      await pair();
      final revision = owner.room!.playback.revision;
      Future<Object> result(Future<void> command) => command.then<Object>(
        (_) => 'accepted',
        onError: (Object error) => error,
      );
      final results = await Future.wait([
        result(owner.command('pause', positionMs: 1000)),
        result(guest.command('seek', positionMs: 2000)),
      ]);
      expect(results.where((r) => r == 'accepted'), hasLength(1));
      expect(
        results.whereType<WatchTogetherException>().single.code,
        'STALE_REVISION',
      );
      await _until(
        () => guest.room!.playback.revision == revision + 1,
        'latest conflict snapshot',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(owner.room!.playback.revision, revision + 1);
      expect(guest.room!.playback.revision, revision + 1);
    },
  );

  test(
    'changeItem checks every member and commits one common version',
    () async {
      await pair();
      await loadingBoth();
      verifier.denied.add('guest:restricted');
      final revision = owner.room!.playback.revision;
      await expectLater(
        owner.changeItem(itemId: 'restricted', mediaSourceId: 'source-a'),
        throwsA(
          isA<WatchTogetherException>().having(
            (e) => e.code,
            'code',
            'ITEM_FORBIDDEN',
          ),
        ),
      );
      expect(owner.room!.media.itemId, 'movie');
      expect(guest.room!.media.mediaSourceId, 'source-b');
      expect(owner.room!.playback.revision, revision);
      await guest.changeItem(itemId: 'next', mediaSourceId: 'source-a');
      await _until(
        () => owner.room!.media.itemId == 'next',
        'new media at owner',
      );
      expect(guest.room!.media.itemId, 'next');
      expect(owner.room!.media.mediaSourceId, 'source-a');
      expect(owner.room!.playback.positionMs, 0);
      expect(owner.room!.playback.state, 'waiting');
      await readyBoth();
    },
  );

  test('owner alone manages kick, ban and room termination', () async {
    await pair();
    final code = owner.room!.code;
    await expectLater(
      guest.kick(owner.memberId!),
      throwsA(
        isA<WatchTogetherException>().having(
          (e) => e.code,
          'code',
          'NOT_OWNER',
        ),
      ),
    );
    await owner.kick(guest.memberId!);
    await _until(() => guest.room == null, 'kicked client clears room');
    expect(guest.connected, isFalse);
    expect(guest.reconnecting, isFalse);
    await expectLater(
      guest.join(code),
      throwsA(
        isA<WatchTogetherException>().having((e) => e.code, 'code', 'KICKED'),
      ),
    );
    await owner.end();
    expect(owner.room, isNull);
    expect(owner.connected, isFalse);
    await expectLater(
      guest.join(code),
      throwsA(
        isA<WatchTogetherException>().having(
          (e) => e.code,
          'code',
          'ROOM_ENDED',
        ),
      ),
    );
  });

  test(
    'leave transfers ownership and end clears the remaining client',
    () async {
      await pair();
      await owner.leave();
      await _until(() => guest.isOwner, 'ownership transfer');
      expect(guest.room!.members, hasLength(1));
      expect(owner.room, isNull);
      await guest.end();
      expect(guest.room, isNull);
      expect(guest.reconnecting, isFalse);
    },
  );

  test('restart restores room without credentials and changed account cannot control it', () async {
    await pair();
    final saved = await guestStore.read(WatchTogetherClient.recoveryKey);
    expect(saved, isNotNull);
    expect(saved, isNot(contains('token-')));
    expect(saved, isNot(contains('ticket')));
    final roomId = guest.room!.roomId;
    guest.dispose();
    final restored = await client(guestSession, guestStore);
    await restored.restore();
    expect(restored.connected, isTrue);
    expect(restored.room!.roomId, roomId);
    expect(restored.room!.members, hasLength(2));
    expect(
      restored.room!.members
          .singleWhere((m) => m.memberId == restored.memberId)
          .status,
      'away',
    );

    guestSession.userId = 'another';
    guestSession.accessToken = 'token-another';
    await expectLater(
      restored.command('pause'),
      throwsA(
        isA<WatchTogetherException>().having(
          (e) => e.code,
          'code',
          'SESSION_CHANGED',
        ),
      ),
    );
    expect(restored.room, isNull);
    expect(restored.connected, isFalse);
    expect(await guestStore.read(WatchTogetherClient.recoveryKey), isNull);
    expect(verifier.verified, isNot(contains('another')));
    expect(owner.room!.playback.state, 'paused');
  });
}
