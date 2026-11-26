import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The standalone service is intentionally outside the Flutter package graph.
// ignore: avoid_relative_lib_imports
import '../../../services/watch_together/lib/watch_server.dart';

class _Verifier implements WatchAuthVerifier {
  final denied = <String>{};
  final invalid = <String>{};
  Completer<void>? mediaGate;
  Completer<void>? verifyGate;
  int calls = 0;
  @override
  Future<WatchIdentity> verify({
    required String token,
    required String userId,
    required String serverId,
  }) async {
    final gate = verifyGate;
    verifyGate = null;
    final rejected = token != 'token-$userId' || invalid.contains(userId);
    if (gate != null) await gate.future;
    if (serverId != 'server') {
      throw const WatchFailure('SERVER_NOT_ALLOWED', '服务器不匹配', 403);
    }
    if (rejected) {
      throw const WatchFailure('AUTH_INVALID', '登录失效', 401);
    }
    return WatchIdentity(
      userId: userId,
      serverId: serverId,
      token: token,
      name: userId == 'admin' ? '管理员' : '用户昵称',
      isAdmin: userId == 'admin',
    );
  }

  @override
  Future<WatchMedia> media(
    WatchIdentity identity,
    String itemId,
    String? source,
  ) async {
    calls++;
    final gate = mediaGate;
    if (gate != null) await gate.future;
    if (denied.contains('${identity.userId}:$itemId') ||
        itemId == 'forbidden') {
      throw const WatchFailure('ITEM_FORBIDDEN', '无播放权限', 403);
    }
    if (source != null && source != 's1' && source != 's2') {
      throw const WatchFailure('MEDIA_SOURCE_INVALID', '版本无效', 403);
    }
    return WatchMedia(
      itemId: itemId,
      mediaSourceId: source ?? 's1',
      title: '服务端影片标题',
      type: itemId == 'episode' ? 'Episode' : 'Movie',
      runTimeMs: 60000,
    );
  }
}

class _Response {
  _Response(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
  Map<String, dynamic> get data => body['data'] as Map<String, dynamic>;
  String? get code => (body['error'] as Map?)?['code'] as String?;
}

class _Peer {
  _Peer(this.socket) {
    socket.listen(
      (event) =>
          messages.add(jsonDecode(event as String) as Map<String, dynamic>),
      onDone: () => closed.complete(socket.closeCode),
      onError: (Object _) {},
    );
  }
  final WebSocket socket;
  final messages = <Map<String, dynamic>>[];
  final closed = Completer<int?>();
  void send(Map<String, dynamic> data) => socket.add(jsonEncode(data));
  Future<Map<String, dynamic>> wait(
    bool Function(Map<String, dynamic>) test,
  ) async {
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(end)) {
      final found = messages.where(test).firstOrNull;
      if (found != null) return found;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail(
      'Expected socket event; received ${messages.map((m) => m['type']).toList()}',
    );
  }

  Future<Map<String, dynamic>> snapshot(int revision, {String? state}) => wait(
    (m) =>
        m['type'] == 'snapshot' &&
        (m['room']['playback']['revision'] as int) >= revision &&
        (state == null || m['room']['playback']['state'] == state),
  );
  Future<void> close() async {
    await socket.close();
    await closed.future;
  }
}

class _Upstream {
  _Upstream(this.server, this.handler) {
    server.listen((request) async {
      seen.add('${request.method} ${request.uri.path}?${request.uri.query}');
      await handler(request);
    });
  }
  final HttpServer server;
  final Future<void> Function(HttpRequest) handler;
  final seen = <String>[];

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> close() => server.close(force: true);
}

Future<_Upstream> _startUpstream(
  Future<void> Function(HttpRequest) handler,
) async => _Upstream(
  await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  handler,
);

Future<void> _jsonResponse(HttpRequest request, Map<String, dynamic> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<void> _movieUpstream(
  HttpRequest request,
  List<Map<String, dynamic>> playbackBodies,
) async {
  if (request.uri.path == '/Users/Me') {
    return _jsonResponse(request, {
      'Id': 'u',
      'Name': 'member',
      'Policy': {'IsAdministrator': false},
    });
  }
  if (request.uri.path.endsWith('/PlaybackInfo')) {
    playbackBodies.add(
      jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>,
    );
    return _jsonResponse(request, {
      'MediaSources': [
        {'Id': 's1', 'SupportsDirectPlay': true},
      ],
    });
  }
  return _jsonResponse(request, {
    'Id': 'movie',
    'Name': 'test',
    'Type': 'Movie',
    'RunTimeTicks': 600000000,
    'CanPlay': true,
    'MediaSources': [
      {'Id': 's1', 'SupportsDirectPlay': true},
    ],
  });
}

Future<WatchFailure> _failureOf(Future<Object?> future) async {
  try {
    await future;
  } on WatchFailure catch (error) {
    return error;
  }
  fail('Expected a WatchFailure');
}

void main() {
  late _Verifier verifier;
  late WatchServer server;
  late HttpClient http;
  late int now;
  final peers = <_Peer>[];
  Future<_Response> request(
    String path, {
    String user = 'u1',
    String? token,
    String serverId = 'server',
    String method = 'POST',
    Map<String, dynamic>? body,
    String? origin,
    bool anonymous = false,
  }) async {
    final req = await http.openUrl(method, Uri.parse('${server.baseUri}$path'));
    req.followRedirects = false;
    if (!anonymous) {
      req.headers.set('X-Emby-Token', token ?? 'token-$user');
      req.headers.set('X-Emby-User-Id', user);
      req.headers.set('X-Emby-Server-Id', serverId);
    }
    if (origin != null) req.headers.set('Origin', origin);
    if (method == 'POST') {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body ?? {}));
    }
    final res = await req.close();
    return _Response(
      res.statusCode,
      jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>,
    );
  }

  Future<_Response> create({
    String user = 'u1',
    String item = 'movie',
    String source = 's1',
  }) => request(
    '/rooms',
    user: user,
    body: {
      'clientId': 'client-$user',
      'itemId': item,
      'mediaSourceId': source,
      'positionMs': 0,
    },
  );
  Future<_Peer> connect(
    Map<String, dynamic> entry, {
    String user = 'u1',
    String? client,
  }) async {
    final ws = await WebSocket.connect(
      '${server.baseUri.toString().replaceFirst('http:', 'ws:')}/socket',
    );
    final peer = _Peer(ws);
    peers.add(peer);
    peer.send({
      'type': 'hello',
      'ticket': entry['ticket'],
      'clientId': client ?? 'client-$user',
    });
    await peer.wait((m) => m['type'] == 'snapshot');
    return peer;
  }

  Future<void> command(
    _Peer peer,
    int revision,
    String action, {
    String id = 'cmd',
    int? position,
    String? item,
  }) async {
    peer.send({
      'type': 'command',
      'requestId': id,
      'revision': revision,
      'action': action,
      'positionMs': ?position,
      'itemId': ?item,
    });
    await peer.wait(
      (m) =>
          m['requestId'] == id && (m['type'] == 'ack' || m['type'] == 'error'),
    );
  }

  void status(_Peer peer, int revision, String value, {int position = 0}) =>
      peer.send({
        'type': 'status',
        'revision': revision,
        'status': value,
        'positionMs': position,
      });

  setUp(() async {
    now = 1000000;
    verifier = _Verifier();
    http = HttpClient();
    server = WatchServer(verifier: verifier, clock: () => now);
    await server.start();
  });
  tearDown(() async {
    for (final peer in peers) {
      await peer.socket.close();
    }
    peers.clear();
    http.close(force: true);
    await server.close();
  });

  test('health is anonymous; identity, server, origin and URL credentials rejected', () async {
    final health = await request('/health', method: 'GET', anonymous: true);
    expect(health.data, {'enabled': true, 'protocol': 1});
    expect((await request('/rooms', anonymous: true)).status, 401);
    expect((await create(source: 'unknown')).code, 'MEDIA_SOURCE_INVALID');
    expect(
      (await request(
        '/rooms',
        token: 'fake',
        body: {'clientId': 'c', 'itemId': 'movie'},
      )).status,
      401,
    );
    expect((await request('/rooms', serverId: 'other')).status, 403);
    expect(
      (await request(
        '/health',
        method: 'GET',
        origin: 'https://untrusted.example',
      )).status,
      403,
    );
    expect((await request('/health?token=secret', method: 'GET')).status, 400);
  });

  test('media metadata is server authoritative and room snapshots exclude credentials', () async {
    final result = await create(source: 's2');
    expect(result.status, 200);
    final room = result.data['room'] as Map;
    expect(room['code'], matches(RegExp(r'^[A-Z2-9]{6}$')));
    expect(room['media']['mediaSourceId'], 's2');
    expect(room['media']['title'], '服务端影片标题');
    final encoded = jsonEncode(room);
    expect(encoded, isNot(contains('token-')));
    expect(encoded, isNot(contains('userId')));
    expect(encoded, isNot(contains('serverId')));
    expect((await create()).code, 'ALREADY_IN_ROOM');
    expect(
      (await request(
        '/rooms/${room['roomId']}',
        method: 'GET',
        user: 'u2',
      )).status,
      403,
    );
    final admin = await create(user: 'admin');
    expect(admin.data['room']['capacity'], 20);
  });

  test('capacity and rejoin preserve access checks without moving a user from another room', () async {
    final first = (await create()).data;
    final code = first['room']['code'];
    for (var i = 2; i <= 4; i++) {
      expect(
        (await request(
          '/rooms/join',
          user: 'u$i',
          body: {'clientId': 'client-u$i', 'code': code},
        )).status,
        200,
      );
    }
    expect(
      (await request(
        '/rooms/join',
        user: 'u5',
        body: {'clientId': 'client-u5', 'code': code},
      )).code,
      'ROOM_FULL',
    );
    final other = (await create(user: 'u6')).data;
    expect(
      (await request(
        '/rooms/join',
        user: 'u6',
        body: {'clientId': 'client-u6', 'code': code},
      )).code,
      'ALREADY_IN_ROOM',
    );
    expect(
      (await request(
        '/rooms/${other['room']['roomId']}',
        user: 'u6',
        method: 'GET',
      )).status,
      200,
    );
    verifier.denied.add('u1:movie');
    expect(
      (await request(
        '/rooms/join',
        body: {'clientId': 'client-u1', 'code': code},
      )).code,
      'ITEM_FORBIDDEN',
    );
  });

  test('an expired ticket cannot connect or expose room state', () async {
    final first = (await create()).data;
    now += 30001;
    final socket = await WebSocket.connect(
      '${server.baseUri.toString().replaceFirst('http:', 'ws:')}/socket',
    );
    socket.add(
      jsonEncode({
        'type': 'hello',
        'ticket': first['ticket'],
        'clientId': 'client-u1',
      }),
    );
    final events = await socket.toList();
    expect(events, isEmpty);
    expect(socket.closeCode, 4401);
  });

  test('command rate errors retain request identity and noncommand traffic is bounded', () async {
    final first = (await create()).data;
    final a = await connect(first);
    for (var i = 0; i < 11; i++) {
      a.send({
        'type': 'command',
        'requestId': 'limited-$i',
        'revision': 0,
        'action': 'pause',
      });
    }
    expect(
      (await a.wait((m) => m['requestId'] == 'limited-10'))['code'],
      'RATE_LIMITED',
    );
    for (var i = 0; i < 21; i++) {
      a.send({'type': 'ping', 'clientTime': i});
    }
    expect(await a.closed.future.timeout(const Duration(seconds: 4)), 4408);
  });

  test('two peers wait for readiness and share pause/seek while stale command is rejected', () async {
    final first = (await create()).data;
    final second = (await request(
      '/rooms/join',
      user: 'u2',
      body: {'clientId': 'client-u2', 'code': first['room']['code']},
    )).data;
    final a = await connect(first), b = await connect(second, user: 'u2');
    status(a, 0, 'ready');
    status(b, 0, 'ready');
    await b.wait(
      (m) =>
          m['type'] == 'snapshot' &&
          (m['room']['members'] as List).every((v) => v['status'] == 'ready'),
    );
    await command(a, 0, 'play', id: 'play');
    final waiting = await b.snapshot(1, state: 'waiting');
    expect(waiting['room']['playback']['waitingMemberIds'], hasLength(2));
    status(a, 1, 'ready');
    await a.wait(
      (m) =>
          m['type'] == 'snapshot' &&
          m['room']['playback']['state'] == 'waiting' &&
          (m['room']['playback']['waitingMemberIds'] as List).length == 1,
    );
    status(b, 1, 'ready');
    final playing = await b.snapshot(2, state: 'playing');
    expect(playing['room']['playback']['serverTime'], now + 500);
    await command(b, 2, 'pause', id: 'pause', position: 9000);
    final paused = await a.snapshot(3, state: 'paused');
    expect(paused['room']['playback']['positionMs'], 9000);
    await command(a, 2, 'seek', id: 'stale', position: 30000);
    expect(
      (await a.wait((m) => m['requestId'] == 'stale'))['code'],
      'STALE_REVISION',
    );
    await command(a, 3, 'seek', id: 'seek', position: 12000);
    expect(
      (await b.snapshot(4, state: 'paused'))['room']['playback']['positionMs'],
      12000,
    );
  });

  test(
    'a ready peer buffering again remains in the original readiness barrier',
    () async {
      final first = (await create()).data;
      final second = (await request(
        '/rooms/join',
        user: 'u2',
        body: {'clientId': 'client-u2', 'code': first['room']['code']},
      )).data;
      final a = await connect(first), b = await connect(second, user: 'u2');
      status(a, 0, 'ready');
      status(b, 0, 'ready');
      await b.wait(
        (m) =>
            m['type'] == 'snapshot' &&
            (m['room']['members'] as List).every((v) => v['status'] == 'ready'),
      );
      await command(a, 0, 'play', id: 'barrier');
      status(a, 1, 'ready');
      await a.wait(
        (m) =>
            m['type'] == 'snapshot' &&
            (m['room']['playback']['waitingMemberIds'] as List).length == 1,
      );
      now += 10000;
      status(a, 1, 'buffering');
      await a.wait(
        (m) =>
            m['type'] == 'snapshot' &&
            m['room']['playback']['revision'] == 1 &&
            (m['room']['members'] as List).any(
              (v) => v['status'] == 'buffering',
            ),
      );
      status(b, 1, 'ready');
      final snapshot = await b.wait(
        (m) =>
            m['type'] == 'snapshot' &&
            m['room']['playback']['revision'] == 1 &&
            m['room']['members'][0]['status'] == 'buffering' &&
            m['room']['members'][1]['status'] == 'ready',
      );
      expect(snapshot['room']['playback']['state'], 'waiting');
      expect(snapshot['room']['playback']['waitingMemberIds'], [
        first['memberId'],
      ]);
      now += 5001;
      server.tick();
      final playing = await b.snapshot(2, state: 'playing');
      expect(playing['room']['members'][0]['lagging'], true);
    },
  );

  test('change item checks every member and preserves current media on denied access', () async {
    final first = (await create()).data;
    final second = (await request(
      '/rooms/join',
      user: 'u2',
      body: {'clientId': 'client-u2', 'code': first['room']['code']},
    )).data;
    final a = await connect(first);
    await connect(second, user: 'u2');
    verifier.denied.add('u2:episode');
    await command(a, 0, 'changeItem', id: 'denied', item: 'episode');
    expect(
      (await a.wait((m) => m['requestId'] == 'denied'))['code'],
      'ITEM_FORBIDDEN',
    );
    var snapshot = await request(
      '/rooms/${first['room']['roomId']}',
      method: 'GET',
    );
    expect(snapshot.data['room']['media']['itemId'], 'movie');
    expect(snapshot.data['room']['playback']['revision'], 0);
    verifier.denied.clear();
    await command(a, 0, 'changeItem', id: 'change', item: 'episode');
    snapshot = await request(
      '/rooms/${first['room']['roomId']}',
      method: 'GET',
    );
    expect(snapshot.data['room']['media']['itemId'], 'episode');
    expect(snapshot.data['room']['playback']['state'], 'waiting');
  });

  test(
    'in-flight media authorization rechecks revision before commit',
    () async {
      final first = (await create()).data;
      final a = await connect(first);
      verifier.mediaGate = Completer<void>();
      a.send({
        'type': 'command',
        'requestId': 'change',
        'revision': 0,
        'action': 'changeItem',
        'itemId': 'episode',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await command(a, 0, 'pause', id: 'pause');
      verifier.mediaGate!.complete();
      expect(
        (await a.wait((m) => m['requestId'] == 'change'))['code'],
        'STALE_REVISION',
      );
      final snapshot = await request(
        '/rooms/${first['room']['roomId']}',
        method: 'GET',
      );
      expect(snapshot.data['room']['media']['itemId'], 'movie');
    },
  );

  test(
    'owner management bans kicked identity and denies non-owner ending',
    () async {
      final first = (await create()).data;
      final second = (await request(
        '/rooms/join',
        user: 'u2',
        body: {'clientId': 'client-u2', 'code': first['room']['code']},
      )).data;
      final a = await connect(first), b = await connect(second, user: 'u2');
      final room = first['room']['roomId'];
      expect((await request('/rooms/$room/end', user: 'u2')).code, 'NOT_OWNER');
      expect(
        (await request(
          '/rooms/$room/kick',
          body: {'memberId': second['memberId']},
        )).status,
        200,
      );
      expect((await b.wait((m) => m['type'] == 'closed'))['reason'], 'kicked');
      expect(
        (await request(
          '/rooms/join',
          user: 'u2',
          body: {'clientId': 'client-u2', 'code': first['room']['code']},
        )).code,
        'KICKED',
      );
      expect((await request('/rooms/$room/end')).status, 200);
      expect(
        (await a.wait((m) => m['type'] == 'closed'))['reason'],
        'room_ended',
      );
      expect((await request('/rooms/$room', method: 'GET')).code, 'ROOM_ENDED');
    },
  );

  test(
    'a replaced socket cannot commit an earlier asynchronous change',
    () async {
      final first = (await create()).data;
      final a = await connect(first);
      verifier.mediaGate = Completer<void>();
      a.send({
        'type': 'command',
        'requestId': 'replace-change',
        'revision': 0,
        'action': 'changeItem',
        'itemId': 'episode',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final renewed = (await request(
        '/rooms/${first['room']['roomId']}/ticket',
        body: {'clientId': 'client-u1'},
      )).data;
      await connect(renewed);
      expect(await a.closed.future, 4409);
      verifier.mediaGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final room = (await request(
        '/rooms/${first['room']['roomId']}',
        method: 'GET',
      )).data['room'];
      expect(room['media']['itemId'], 'movie');
    },
  );

  test('ticket is single-use, bound to client; replacement preserves member identity', () async {
    final first = (await create()).data;
    final a = await connect(first);
    final room = first['room']['roomId'];
    final renewed = (await request(
      '/rooms/$room/ticket',
      body: {'clientId': 'client-u1'},
    )).data;
    final b = await connect(renewed);
    expect(await a.closed.future, 4409);
    expect(
      (await b.wait((m) => m['type'] == 'snapshot'))['memberId'],
      first['memberId'],
    );
    final invalid = await WebSocket.connect(
      '${server.baseUri.toString().replaceFirst('http:', 'ws:')}/socket',
    );
    invalid.add(
      jsonEncode({
        'type': 'hello',
        'ticket': renewed['ticket'],
        'clientId': 'client-u1',
      }),
    );
    await invalid.drain<void>();
    expect(invalid.closeCode, 4401);
    final ticket = (await request(
      '/rooms/$room/ticket',
      body: {'clientId': 'right'},
    )).data['ticket'];
    final wrong = await WebSocket.connect(
      '${server.baseUri.toString().replaceFirst('http:', 'ws:')}/socket',
    );
    wrong.add(
      jsonEncode({'type': 'hello', 'ticket': ticket, 'clientId': 'wrong'}),
    );
    await wrong.drain<void>();
    expect(wrong.closeCode, 4401);
  });

  test(
    'away removes one wait participant and does not pause remaining viewer',
    () async {
      final first = (await create()).data;
      final second = (await request(
        '/rooms/join',
        user: 'u2',
        body: {'clientId': 'client-u2', 'code': first['room']['code']},
      )).data;
      final a = await connect(first), b = await connect(second, user: 'u2');
      status(a, 0, 'ready');
      status(b, 0, 'ready');
      await b.wait(
        (m) =>
            m['type'] == 'snapshot' &&
            (m['room']['members'] as List).every((v) => v['status'] == 'ready'),
      );
      await command(a, 0, 'play', id: 'play');
      status(a, 1, 'ready');
      status(b, 1, 'away');
      await a.snapshot(2, state: 'playing');
      status(b, 2, 'away');
      final room = (await request(
        '/rooms/${first['room']['roomId']}',
        method: 'GET',
      )).data['room'];
      expect(room['playback']['state'], 'playing');
    },
  );

  test('wait timeout marks lagging, all-disconnected room expires', () async {
    final first = (await create()).data;
    final a = await connect(first);
    await command(a, 0, 'play', id: 'play');
    now += 15001;
    server.tick();
    final playing = await a.snapshot(2, state: 'playing');
    expect(playing['room']['members'].single['lagging'], true);
    await a.close();
    now += 300001;
    server.tick();
    expect(
      (await request('/rooms/${first['room']['roomId']}', method: 'GET')).code,
      'ROOM_ENDED',
    );
  });

  test(
    'seat retained while others online then owner transfers on expiry',
    () async {
      final first = (await create()).data;
      final second = (await request(
        '/rooms/join',
        user: 'u2',
        body: {'clientId': 'client-u2', 'code': first['room']['code']},
      )).data;
      final a = await connect(first), b = await connect(second, user: 'u2');
      await a.close();
      var room = (await request(
        '/rooms/${first['room']['roomId']}',
        user: 'u2',
        method: 'GET',
      )).data['room'];
      expect(room['members'], hasLength(2));
      now += 60001;
      // Keep b alive so the seat expiry is not conflated with socket idle.
      b.send({'type': 'ping', 'clientTime': now});
      await b.wait((m) => m['type'] == 'pong' && m['clientTime'] == now);
      server.tick();
      room = (await request(
        '/rooms/${first['room']['roomId']}',
        user: 'u2',
        method: 'GET',
      )).data['room'];
      expect(room['members'], hasLength(1));
      expect(room['ownerMemberId'], second['memberId']);
    },
  );

  test(
    'continuous buffering waits once; auth recheck removes expired token',
    () async {
      final first = (await create()).data;
      final a = await connect(first);
      await command(a, 0, 'play', id: 'play');
      status(a, 1, 'ready');
      await a.snapshot(2, state: 'playing');
      status(a, 2, 'buffering', position: 1000);
      await a.wait(
        (m) =>
            m['type'] == 'snapshot' &&
            m['room']['members'].single['status'] == 'buffering',
      );
      now += 1501;
      server.tick();
      await a.snapshot(3, state: 'waiting');
      status(a, 3, 'ready');
      await a.snapshot(4, state: 'playing');
      verifier.invalid.add('u1');
      now += 600001;
      a.send({'type': 'ping', 'clientTime': now});
      await a.wait((m) => m['type'] == 'pong' && m['clientTime'] == now);
      server.tick();
      expect(
        (await a.wait((m) => m['type'] == 'closed'))['reason'],
        'auth_expired',
      );
    },
  );

  test('Emby verifier uses configured upstream and checks true token identity and version', () async {
    final seen = <String>[];
    var redirect = false;
    final emby = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    emby.listen((req) async {
      seen.add(
        '${req.method} ${req.uri.path} ${req.headers.value('X-Emby-Token')}',
      );
      if (redirect) {
        req.response.statusCode = 302;
        req.response.headers.set('Location', 'http://127.0.0.1:1/leak');
      } else {
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/Users/Me') {
          req.response.write(
            jsonEncode({
              'Id': 'u',
              'Name': 'member',
              'Policy': {'IsAdministrator': true},
            }),
          );
        } else if (req.uri.path.endsWith('/PlaybackInfo')) {
          final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
          expect(body['EnableTranscoding'], false);
          expect(body['MediaSourceId'], anyOf('s2', isNull));
          req.response.write(
            jsonEncode({
              'MediaSources': [
                {'Id': 'unplayable', 'SupportsDirectPlay': false},
                {'Id': 's2', 'SupportsDirectPlay': true},
              ],
            }),
          );
        } else {
          req.response.write(
            jsonEncode({
              'Id': 'movie',
              'Name': 'test',
              'Type': 'Movie',
              'RunTimeTicks': 600000000,
              'CanPlay': true,
            }),
          );
        }
      }
      await req.response.close();
    });
    addTearDown(() => emby.close(force: true));
    final real = EmbyWatchVerifier(
      baseUrl: Uri.parse('http://127.0.0.1:${emby.port}'),
      serverId: 'server',
    );
    final identity = await real.verify(
      token: 'private-token',
      userId: 'u',
      serverId: 'server',
    );
    expect(identity.isAdmin, true);
    final media = await real.media(identity, 'movie', 's2');
    expect(media.mediaSourceId, 's2');
    expect((await real.media(identity, 'movie', null)).mediaSourceId, 's2');
    await expectLater(
      real.verify(token: 'private-token', userId: 'other', serverId: 'server'),
      throwsA(isA<WatchFailure>()),
    );
    redirect = true;
    await expectLater(
      real.verify(token: 'private-token', userId: 'u', serverId: 'server'),
      throwsA(isA<WatchFailure>()),
    );
    expect(seen, everyElement(endsWith('private-token')));
  });

  test(
    'a stale token recheck cannot remove newly authenticated membership',
    () async {
      final first = (await create()).data;
      final a = await connect(first);
      now += 600001;
      a.send({'type': 'ping', 'clientTime': now});
      await a.wait((m) => m['type'] == 'pong' && m['clientTime'] == now);
      verifier.invalid.add('u1');
      final gate = verifier.verifyGate = Completer<void>();
      server.tick();
      verifier.invalid.clear();
      expect(
        (await request(
          '/rooms/${first['room']['roomId']}',
          method: 'GET',
        )).status,
        200,
      );
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        (await request(
          '/rooms/${first['room']['roomId']}',
          method: 'GET',
        )).status,
        200,
      );
      expect(a.closed.isCompleted, false);
    },
  );
  test('Emby verifier reports EMBY_TIMEOUT when the upstream stalls', () async {
    final upstream = await _startUpstream((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _jsonResponse(request, {
        'Id': 'u',
        'Name': 'member',
        'Policy': {'IsAdministrator': false},
      });
    });
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(
      baseUrl: upstream.url,
      serverId: 'server',
      timeout: const Duration(milliseconds: 100),
    );
    final failure = await _failureOf(
      real.verify(token: 'private-token', userId: 'u', serverId: 'server'),
    );
    expect(failure.code, 'EMBY_TIMEOUT');
    expect(failure.status, 503);
  });

  test('Emby verifier reports EMBY_UPSTREAM_ERROR for upstream errors', () async {
    final upstream = await _startUpstream((request) async {
      request.response.statusCode = 500;
      await _jsonResponse(request, {'error': 'boom'});
    });
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(
      baseUrl: upstream.url,
      serverId: 'server',
    );
    final failure = await _failureOf(
      real.verify(token: 'private-token', userId: 'u', serverId: 'server'),
    );
    expect(failure.code, 'EMBY_UPSTREAM_ERROR');
    expect(failure.status, 502);
  });

  test('Emby verifier reports EMBY_CONFIG when /Users/Me is missing', () async {
    final upstream = await _startUpstream((request) async {
      request.response.statusCode = 404;
      await _jsonResponse(request, {'error': 'missing'});
    });
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(
      baseUrl: upstream.url,
      serverId: 'server',
    );
    final failure = await _failureOf(
      real.verify(token: 'private-token', userId: 'u', serverId: 'server'),
    );
    expect(failure.code, 'EMBY_CONFIG');
    expect(failure.status, 503);
  });

  test('Emby verifier keeps item 404 as ITEM_FORBIDDEN', () async {
    final upstream = await _startUpstream((request) async {
      if (request.uri.path == '/Users/Me') {
        await _jsonResponse(request, {
          'Id': 'u',
          'Name': 'member',
          'Policy': {'IsAdministrator': false},
        });
        return;
      }
      request.response.statusCode = 404;
      await _jsonResponse(request, {'error': 'missing'});
    });
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(
      baseUrl: upstream.url,
      serverId: 'server',
    );
    final identity = await real.verify(
      token: 'private-token',
      userId: 'u',
      serverId: 'server',
    );
    final failure = await _failureOf(real.media(identity, 'movie', null));
    expect(failure.code, 'ITEM_FORBIDDEN');
    expect(failure.status, 403);
    expect(
      upstream.seen.where((r) => r.contains('Fields=MediaSources')),
      hasLength(1),
    );
  });

  test('Emby verifier skips PlaybackInfo for an advertised source', () async {
    final playbackBodies = <Map<String, dynamic>>[];
    final upstream = await _startUpstream(
      (request) => _movieUpstream(request, playbackBodies),
    );
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(
      baseUrl: upstream.url,
      serverId: 'server',
    );
    final identity = await real.verify(
      token: 'private-token',
      userId: 'u',
      serverId: 'server',
    );
    final media = await real.media(identity, 'movie', null);
    expect(media.mediaSourceId, 's1');
    expect(playbackBodies, isEmpty);
    expect(upstream.seen.any((r) => r.contains('PlaybackInfo')), false);
    expect(
      upstream.seen.where((r) => r.contains('Fields=MediaSources')),
      hasLength(1),
    );
  });

  test('Emby verifier negotiates when a source is requested', () async {
    final playbackBodies = <Map<String, dynamic>>[];
    final upstream = await _startUpstream(
      (request) => _movieUpstream(request, playbackBodies),
    );
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(
      baseUrl: upstream.url,
      serverId: 'server',
    );
    final identity = await real.verify(
      token: 'private-token',
      userId: 'u',
      serverId: 'server',
    );
    final media = await real.media(identity, 'movie', 's1');
    expect(media.mediaSourceId, 's1');
    expect(playbackBodies, hasLength(1));
    expect(playbackBodies.single['EnableTranscoding'], false);
    expect(playbackBodies.single['MediaSourceId'], 's1');
    expect(upstream.seen.any((r) => r.contains('PlaybackInfo')), true);
  });

  test('Emby verifier reports EMBY_BAD_RESPONSE for malformed JSON', () async {
    final upstream = await _startUpstream((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('not-json');
      await request.response.close();
    });
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(
      baseUrl: upstream.url,
      serverId: 'server',
    );
    final failure = await _failureOf(
      real.verify(token: 'private-token', userId: 'u', serverId: 'server'),
    );
    expect(failure.code, 'EMBY_BAD_RESPONSE');
    expect(failure.status, 502);
  });

  test('Emby verifier rejects an oversized upstream response', () async {
    final upstream = await _startUpstream((request) async {
      request.response.headers.contentType = ContentType.json;
      // A well-formed object that still exceeds the 1MiB read budget.
      request.response.write('{"Id":"u","Pad":"');
      request.response.write('x' * (1024 * 1024 + 1));
      request.response.write('"}');
      await request.response.close();
    });
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(baseUrl: upstream.url, serverId: 'server');
    final failure = await _failureOf(
      real.verify(token: 'private-token', userId: 'u', serverId: 'server'),
    );
    expect(failure.code, 'EMBY_BAD_RESPONSE');
    expect(failure.status, 502);
  });

  test('Emby verifier reports EMBY_UNREACHABLE when the upstream is down', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final real = EmbyWatchVerifier(
      baseUrl: Uri.parse('http://127.0.0.1:$port'),
      serverId: 'server',
      timeout: const Duration(milliseconds: 500),
    );
    final failure = await _failureOf(
      real.verify(token: 'private-token', userId: 'u', serverId: 'server'),
    );
    expect(failure.code, 'EMBY_UNREACHABLE');
    expect(failure.status, 503);
  });

  test('Emby failures never expose the upstream URL or token', () async {
    final upstream = await _startUpstream((request) async {
      request.response.statusCode = 500;
      await _jsonResponse(request, {'error': 'boom'});
    });
    addTearDown(upstream.close);
    final real = EmbyWatchVerifier(
      baseUrl: upstream.url,
      serverId: 'server',
    );
    final failure = await _failureOf(
      real.verify(token: 'private-token', userId: 'u', serverId: 'server'),
    );
    expect(failure.toJson().keys.toSet(), {'code', 'message'});
    expect(failure.message.contains('127.0.0.1'), false);
    expect(failure.message.contains('private-token'), false);
    expect(failure.message.contains('http'), false);
  });
}
