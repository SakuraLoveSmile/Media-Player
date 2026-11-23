import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/watch_together/watch_together_client.dart';

import '../offline/offline_test_session.dart';

Map<String, dynamic> roomJson({int revision = 1, String status = 'loading'}) =>
    {
      'roomId': 'room-1',
      'code': 'ABC123',
      'capacity': 8,
      'ownerMemberId': 'member-1',
      'media': {
        'itemId': 'movie',
        'mediaSourceId': 'source',
        'title': 'Movie',
        'type': 'Movie',
        'runTimeMs': 600000,
      },
      'playback': {
        'revision': revision,
        'state': 'paused',
        'positionMs': 10000,
        'serverTime': DateTime.now().millisecondsSinceEpoch,
        'waitingMemberIds': <String>[],
      },
      'members': [
        {
          'memberId': 'member-1',
          'name': 'Viewer',
          'role': 'owner',
          'connected': true,
          'status': status,
          'lagging': false,
        },
      ],
    };

Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class RoomServer {
  late HttpServer server;
  final sockets = <WebSocket>[];
  final urls = <String>[];
  final tokens = <String?>[];
  final commands = <Map<String, dynamic>>[];
  final hello = <Map<String, dynamic>>[];
  int tickets = 0;
  bool rejectCommand = false;
  bool redirect = false;
  Uri? socketRedirect;
  Completer<void>? entering;
  Completer<void>? ending;
  Map<String, dynamic> current = roomJson();
  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}');
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      urls.add(request.uri.toString());
      tokens.add(request.headers.value('X-Emby-Token'));
      if (request.uri.path.endsWith('/socket')) {
        if (socketRedirect != null) {
          request.response.statusCode = 302;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            socketRedirect.toString(),
          );
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((raw) {
          if (socket.readyState != WebSocket.open) return;
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          if (message['type'] == 'hello') {
            hello.add(message);
            socket.add(
              jsonEncode({
                'type': 'snapshot',
                'room': current,
                'memberId': 'member-1',
              }),
            );
          } else if (message['type'] == 'command') {
            commands.add(message);
            socket.add(
              jsonEncode({
                'type': rejectCommand ? 'error' : 'ack',
                'requestId': message['requestId'],
                if (rejectCommand) 'code': 'STALE_REVISION',
              }),
            );
          }
        });
        return;
      }
      await utf8.decoder.bind(request).join();
      Map<String, dynamic> data;
      if (request.uri.path.endsWith('/health')) {
        if (redirect) {
          request.response.statusCode = 302;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '${uri.toString()}/leak',
          );
        }
        data = {'enabled': true, 'protocol': 1};
      } else if (request.uri.path.endsWith('/end')) {
        await ending?.future;
        data = {};
      } else if (request.uri.path.endsWith('/leave')) {
        data = {};
      } else {
        if (request.uri.path.endsWith('/ticket')) tickets++;
        await entering?.future;
        data = {
          'room': current,
          'memberId': 'member-1',
          'ticket': 'opaque-ticket',
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': data}));
      await request.response.close();
    });
  }

  void snapshot(Map<String, dynamic> room) {
    current = room;
    for (final socket in sockets.where((s) => s.readyState == WebSocket.open)) {
      socket.add(
        jsonEncode({'type': 'snapshot', 'room': room, 'memberId': 'member-1'}),
      );
    }
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

class BlockingStore extends InMemoryKeyValueStore {
  final writing = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (key == WatchTogetherClient.recoveryKey) {
      if (!writing.isCompleted) writing.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

void main() {
  late RoomServer server;
  late OfflineTestSession session;
  late InMemoryKeyValueStore store;
  late WatchTogetherClient client;
  setUp(() async {
    server = RoomServer();
    await server.start();
    session = OfflineTestSession('https://emby.example');
    store = InMemoryKeyValueStore();
    client = WatchTogetherClient(session: session, store: store);
    await client.initialize();
    await client.configure(server.uri);
  });
  tearDown(() async {
    client.dispose();
    await server.close();
  });

  test('credentials stay in HTTP headers; recovery and socket URL contain no secret', () async {
    await client.create(itemId: 'movie', mediaSourceId: 'source');
    expect(client.connected, isTrue);
    expect(server.tokens.whereType<String>(), everyElement('secret-token'));
    expect(server.urls.join(), isNot(contains('secret-token')));
    expect(server.urls.join(), isNot(contains('opaque-ticket')));
    expect(server.hello.single['ticket'], 'opaque-ticket');
    final recovery = (await store.read(WatchTogetherClient.recoveryKey))!;
    expect(recovery, isNot(contains('secret-token')));
    expect(recovery, isNot(contains('opaque-ticket')));
    expect(jsonDecode(recovery)['roomId'], 'room-1');
  });

  test(
    'lower revisions are ignored but member updates at same revision apply',
    () async {
      await client.join('abc123');
      server.snapshot(roomJson(revision: 4));
      await eventually(() => client.room?.playback.revision == 4);
      server.snapshot(roomJson(revision: 3, status: 'away'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(client.room!.playback.revision, 4);
      server.snapshot(roomJson(revision: 4, status: 'ready'));
      await eventually(() => client.room?.members.single.status == 'ready');
    },
  );

  test('stale commands fail visibly without replay', () async {
    await client.join('ABC123');
    server.rejectCommand = true;
    await expectLater(
      client.command('play'),
      throwsA(
        isA<WatchTogetherException>().having(
          (e) => e.code,
          'code',
          'STALE_REVISION',
        ),
      ),
    );
    expect(server.commands, hasLength(1));
    expect(client.error, contains('状态已变化'));
  });

  test(
    'same identity notifications retain room; changed credentials clear it',
    () async {
      await client.join('ABC123');
      await client.sessionChanged();
      expect(client.room, isNotNull);
      session.accessToken = 'replacement-token';
      await client.sessionChanged();
      expect(client.room, isNull);
      expect(client.connected, isFalse);
      expect(await store.read(WatchTogetherClient.recoveryKey), isNull);
    },
  );

  test('leaving during a delayed join never restores room', () async {
    server.entering = Completer<void>();
    final joining = client.join('ABC123');
    await eventually(() => server.urls.any((u) => u.endsWith('/rooms/join')));
    await client.leave();
    server.entering!.complete();
    await joining;
    expect(client.room, isNull);
    expect(server.hello, isEmpty);
    expect(await store.read(WatchTogetherClient.recoveryKey), isNull);
  });

  test('leave serializes after an in-flight recovery write', () async {
    client.dispose();
    final blocked = BlockingStore();
    client = WatchTogetherClient(session: session, store: blocked);
    await client.initialize();
    await client.configure(server.uri);
    final joining = client.join('ABC123');
    await blocked.writing.future;
    final leaving = client.leave();
    blocked.release.complete();
    await Future.wait([joining, leaving]);
    expect(client.room, isNull);
    expect(await blocked.read(WatchTogetherClient.recoveryKey), isNull);
    expect(server.hello, isEmpty);
  });

  test('public HTTP, URL credentials and redirects are rejected', () async {
    await expectLater(
      client.configure(Uri.parse('http://10.attacker.example')),
      throwsA(isA<WatchTogetherException>()),
    );
    await expectLater(
      client.configure(Uri.parse('http://192.168.attacker.example')),
      throwsA(isA<WatchTogetherException>()),
    );
    await expectLater(
      client.configure(Uri.parse('http://example.com')),
      throwsA(isA<WatchTogetherException>()),
    );
    await expectLater(
      client.configure(Uri.parse('https://user:secret@example.com')),
      throwsA(isA<WatchTogetherException>()),
    );
    server.redirect = true;
    await expectLater(
      client.join('ABC123'),
      throwsA(isA<WatchTogetherException>()),
    );
    expect(server.urls, hasLength(1));
  });

  test(
    'changing service invalidates an in-flight join before using its ticket',
    () async {
      final other = RoomServer();
      await other.start();
      try {
        server.entering = Completer<void>();
        final joining = client.join('ABC123');
        await eventually(
          () => server.urls.any((u) => u.endsWith('/rooms/join')),
        );
        await client.configure(other.uri);
        server.entering!.complete();
        await joining;
        expect(client.room, isNull);
        expect(other.urls, isEmpty);
        expect(await store.read(WatchTogetherClient.recoveryKey), isNull);
        await client.join('ABC123');
        expect(other.hello, hasLength(1));
      } finally {
        await other.close();
      }
    },
  );

  test(
    'websocket redirect never sends a room ticket to another origin',
    () async {
      final other = RoomServer();
      await other.start();
      try {
        server.socketRedirect = other.uri.resolve('/watch/v1/socket');
        await expectLater(
          client.join('ABC123'),
          throwsA(isA<WatchTogetherException>()),
        );
        expect(other.urls, isEmpty);
        expect(other.hello, isEmpty);
        expect(client.reconnecting, isTrue);
        await client.leave();
      } finally {
        await other.close();
      }
    },
  );

  test(
    'same-identity auth restoration retains persisted room until restore',
    () async {
      await client.join('ABC123');
      client.dispose();
      client = WatchTogetherClient(session: session, store: store);
      await client.initialize();
      await client.sessionChanged();
      await client.restore();
      expect(client.room?.roomId, 'room-1');
      expect(client.connected, isTrue);
      expect(server.tickets, 1);
    },
  );

  test('changing account cancels an in-flight room request', () async {
    server.entering = Completer<void>();
    final joining = client.join('ABC123');
    await eventually(() => server.urls.any((u) => u.endsWith('/rooms/join')));
    session.userId = 'other-user';
    await client.sessionChanged();
    server.entering!.complete();
    await expectLater(joining, throwsA(isA<WatchTogetherException>()));
    expect(client.room, isNull);
    expect(server.hello, isEmpty);
    expect(await store.read(WatchTogetherClient.recoveryKey), isNull);
  });

  test('a delayed end response does not leave a newly joined room', () async {
    await client.join('ABC123');
    server.ending = Completer<void>();
    final ending = client.end();
    await eventually(() => server.urls.any((u) => u.endsWith('/room-1/end')));
    await client.leave();
    server.current = roomJson()..['roomId'] = 'room-2';
    await client.join('ABC123');
    expect(client.room?.roomId, 'room-2');
    server.ending!.complete();
    await ending;
    expect(client.room?.roomId, 'room-2');
    expect(client.connected, isTrue);
    expect(server.urls.where((u) => u.endsWith('/room-2/leave')), isEmpty);
  });

  test('replaced-device close ends room and does not reconnect', () async {
    await client.join('ABC123');
    await server.sockets.single.close(4409);
    await eventually(() => client.room == null);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(server.tickets, 0);
    expect(client.reconnecting, isFalse);
    expect(client.error, contains('另一台设备'));
  });

  test('legacy percent-encoded Chinese domain recovers as punycode', () async {
    const stored =
        'https://watch.%E4%B8%8A%E6%9D%89%E4%B9%9D%E6%9C%88.cn/watch/v1';
    await store.write(WatchTogetherClient.serviceKey, stored);
    client.dispose();
    client = WatchTogetherClient(session: session, store: store);
    await client.initialize();
    expect(client.error, isNull);
    final base = client.baseUrl.toString();
    expect(base, 'https://watch.xn--fhqths51enha.cn/watch/v1');
    expect(base, isNot(contains('%')));
    expect(client.baseUrl!.path, '/watch/v1');
  });

  test('Chinese domain is stored and requested as punycode', () async {
    await client.configure(Uri.parse('https://watch.上杉九月.cn'));
    final base = client.baseUrl!;
    expect(base.host, 'watch.xn--fhqths51enha.cn');
    expect(base.path, '/watch/v1');
    expect(base.toString(), 'https://watch.xn--fhqths51enha.cn/watch/v1');
    expect(base.toString(), isNot(contains('%')));
    expect(await store.read(WatchTogetherClient.serviceKey), base.toString());
  });

  test('public HTTP is still rejected for a Chinese domain', () async {
    await expectLater(
      client.configure(Uri.parse('http://watch.上杉九月.cn')),
      throwsA(
        isA<WatchTogetherException>().having(
          (e) => e.code,
          'code',
          'INSECURE_URL',
        ),
      ),
    );
    // The rejected address never replaces the working one.
    expect(client.baseUrl!.host, '127.0.0.1');
    expect(client.baseUrl!.path, '/watch/v1');
  });
}
