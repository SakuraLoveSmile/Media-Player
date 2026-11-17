import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// All credentials remain in this private service process, never in snapshots.
class WatchIdentity {
  const WatchIdentity({
    required this.userId,
    required this.serverId,
    required this.token,
    required this.name,
    this.isAdmin = false,
  });
  final String userId, serverId, token, name;
  final bool isAdmin;
  @override
  String toString() => 'WatchIdentity(<private>)';
}

class WatchMedia {
  const WatchMedia({
    required this.itemId,
    required this.mediaSourceId,
    required this.title,
    required this.type,
    required this.runTimeMs,
  });
  final String itemId, mediaSourceId, title, type;
  final int runTimeMs;
  Map<String, Object> toJson() => {
    'itemId': itemId,
    'mediaSourceId': mediaSourceId,
    'title': title,
    'type': type,
    'runTimeMs': runTimeMs,
  };
}

abstract interface class WatchAuthVerifier {
  Future<WatchIdentity> verify({
    required String token,
    required String userId,
    required String serverId,
  });
  Future<WatchMedia> media(
    WatchIdentity identity,
    String itemId,
    String? mediaSourceId,
  );
}

class WatchFailure implements Exception {
  const WatchFailure(this.code, this.message, [this.status = 400]);
  final String code, message;
  final int status;
  Map<String, String> toJson() => {'code': code, 'message': message};
  @override
  String toString() => 'WatchFailure($code)';
}

/// Only the configured Emby host receives credentials. Redirects are forbidden.
class EmbyWatchVerifier implements WatchAuthVerifier {
  EmbyWatchVerifier({required Uri baseUrl, required this.serverId})
    : baseUrl = _validBase(baseUrl);
  final Uri baseUrl;
  final String serverId;
  static Uri _validBase(Uri base) {
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('EMBY_URL must be an HTTP(S) base URL');
    }
    return Uri.parse(base.toString().replaceFirst(RegExp(r'/+$'), ''));
  }

  Future<Map<String, dynamic>> _request(
    WatchIdentity id,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = await http
          .openUrl(body == null ? 'GET' : 'POST', uri)
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.set('X-Emby-Token', id.token);
      request.headers.set('Accept', 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const WatchFailure('AUTH_INVALID', '登录已失效或无权访问', 401);
      }
      if (response.statusCode == 404) {
        throw const WatchFailure('ITEM_FORBIDDEN', '没有权限播放此影片', 403);
      }
      if (response.statusCode != 200) {
        throw const WatchFailure('EMBY_UNAVAILABLE', '媒体服务器暂不可用', 503);
      }
      final data = <int>[];
      await for (final bytes in response.timeout(const Duration(seconds: 5))) {
        if (data.length + bytes.length > 1024 * 1024) {
          throw const WatchFailure('EMBY_UNAVAILABLE', '媒体服务器响应过大', 503);
        }
        data.addAll(bytes);
      }
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return decoded;
    } on WatchFailure {
      rethrow;
    } catch (_) {
      throw const WatchFailure('EMBY_UNAVAILABLE', '媒体服务器暂不可用', 503);
    } finally {
      http.close(force: true);
    }
  }

  @override
  Future<WatchIdentity> verify({
    required String token,
    required String userId,
    required String serverId,
  }) async {
    if (serverId != this.serverId) {
      throw const WatchFailure('SERVER_NOT_ALLOWED', '此同步服务不支持当前媒体服务器', 403);
    }
    final candidate = WatchIdentity(
      userId: userId,
      serverId: serverId,
      token: token,
      name: '',
    );
    final user = await _request(candidate, '/Users/Me');
    if (user['Id'] != userId ||
        user['Id'] is! String ||
        user['Name'] is! String) {
      throw const WatchFailure('AUTH_INVALID', '登录身份不匹配', 401);
    }
    final policy = user['Policy'];
    return WatchIdentity(
      userId: userId,
      serverId: serverId,
      token: token,
      name: user['Name'] as String,
      isAdmin: policy is Map && policy['IsAdministrator'] == true,
    );
  }

  @override
  Future<WatchMedia> media(
    WatchIdentity identity,
    String itemId,
    String? mediaSourceId,
  ) async {
    final item = await _request(
      identity,
      '/Users/${Uri.encodeComponent(identity.userId)}/Items/${Uri.encodeComponent(itemId)}',
    );
    if (item['CanPlay'] == false ||
        item['PlayAccess'] == 'None' ||
        !['Movie', 'Episode'].contains(item['Type'])) {
      throw const WatchFailure('ITEM_FORBIDDEN', '没有权限播放此影片', 403);
    }
    final info = await _request(
      identity,
      '/Items/${Uri.encodeComponent(itemId)}/PlaybackInfo',
      body: {
        'UserId': identity.userId,
        'IsPlayback': false,
        'AutoOpenLiveStream': false,
        'EnableDirectPlay': true,
        'EnableDirectStream': true,
        'EnableTranscoding': false,
        if (mediaSourceId != null) 'MediaSourceId': mediaSourceId,
        'DeviceProfile': {
          'Name': 'MediaPlayer watch permission',
          'DirectPlayProfiles': [
            {'Type': 'Video'},
            {'Type': 'Audio'},
          ],
        },
      },
    );
    final sources = info['MediaSources'];
    if (sources is! List) {
      throw const WatchFailure('ITEM_FORBIDDEN', '没有可直接播放的版本', 403);
    }
    final candidates = sources
        .whereType<Map>()
        .where((s) => mediaSourceId == null || s['Id'] == mediaSourceId)
        .where(
          (s) =>
              s['SupportsDirectPlay'] == true ||
              s['SupportsDirectStream'] == true,
        )
        .toList();
    if (candidates.isEmpty || candidates.first['Id'] is! String) {
      throw const WatchFailure('MEDIA_SOURCE_INVALID', '所选版本无法直接播放', 403);
    }
    final duration = item['RunTimeTicks'];
    if (duration is! num || !duration.isFinite || duration <= 0) {
      throw const WatchFailure('ITEM_FORBIDDEN', '影片时长不可用', 403);
    }
    return WatchMedia(
      itemId: itemId,
      mediaSourceId: candidates.first['Id'] as String,
      title: item['Name'] is String ? item['Name'] as String : '影片',
      type: item['Type'] as String,
      runTimeMs: duration ~/ 10000,
    );
  }
}

class WatchServerConfig {
  const WatchServerConfig({
    this.roomCapacity = 4,
    this.adminRoomCapacity = 20,
    this.maxRooms = 50,
    this.seatHoldMs = 60000,
    this.emptyRoomMs = 300000,
    this.waitTimeoutMs = 15000,
    this.roomLifetimeMs = 86400000,
    this.leadMs = 500,
    this.socketIdleMs = 30000,
    this.recheckMs = 600000,
    this.allowedOrigins = const <String>{},
  });
  final int roomCapacity, adminRoomCapacity, maxRooms, seatHoldMs, emptyRoomMs;
  final int waitTimeoutMs, roomLifetimeMs, leadMs, socketIdleMs, recheckMs;
  final Set<String> allowedOrigins;
}

class WatchServer {
  WatchServer({
    required this.verifier,
    this.config = const WatchServerConfig(),
    int Function()? clock,
  }) {
    final epoch = DateTime.now().millisecondsSinceEpoch;
    final watch = Stopwatch()..start();
    _now = clock ?? () => epoch + watch.elapsedMilliseconds;
    if (config.roomCapacity < 1 ||
        config.roomCapacity > 20 ||
        config.adminRoomCapacity < 1 ||
        config.adminRoomCapacity > 20 ||
        config.maxRooms < 1 ||
        config.maxRooms > 50) {
      throw ArgumentError('Invalid watch room limits');
    }
  }
  final WatchAuthVerifier verifier;
  final WatchServerConfig config;
  late final int Function() _now;
  final _random = Random.secure();
  final _rooms = <String, _Room>{};
  final _codes = <String, String>{};
  final _users = <String, String>{};
  final _tickets = <String, _Ticket>{};
  final _restRates = <String, _Window>{};
  final _sockets = <WebSocket>{};
  HttpServer? _http;
  Timer? _timer;
  bool _closed = false;
  int get port => _http!.port;
  Uri get baseUri => Uri.parse('http://127.0.0.1:$port/watch/v1');
  Future<HttpServer> start({InternetAddress? address, int port = 0}) async {
    if (_http != null) throw StateError('Already started');
    _http = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    _http!.listen((request) => unawaited(_handle(request)));
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
    return _http!;
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    for (final room in _rooms.values.toList()) {
      _end(room, 'service_stopped');
    }
    for (final socket in _sockets.toList()) {
      unawaited(socket.close(1001));
    }
    await _http?.close(force: true);
    _rooms.clear();
    _users.clear();
    _codes.clear();
    _tickets.clear();
    _restRates.clear();
  }

  String _randomKey([int bytes = 32]) => base64Url
      .encode(List.generate(bytes, (_) => _random.nextInt(256)))
      .replaceAll('=', '');
  String _code() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String code;
    do {
      code = List.generate(
        6,
        (_) => alphabet[_random.nextInt(alphabet.length)],
      ).join();
    } while (_codes.containsKey(code));
    return code;
  }

  String _key(WatchIdentity identity) =>
      '${identity.serverId}\u0000${identity.userId}';
  bool _originAllowed(HttpRequest request) {
    final origin = request.headers.value('origin');
    return origin == null || config.allowedOrigins.contains(origin);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (!_originAllowed(request)) {
        throw const WatchFailure('ORIGIN_FORBIDDEN', '不允许的来源', 403);
      }
      final path = request.uri.path;
      if (request.uri.hasQuery) {
        throw const WatchFailure('INVALID_REQUEST', '不接受 URL 参数');
      }
      if (request.method == 'GET' && path == '/watch/v1/health') {
        return await _json(request, {'enabled': true, 'protocol': 1});
      }
      if (request.method == 'GET' &&
          path == '/watch/v1/socket' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        if (_sockets.length >= config.maxRooms * 20 + 50) {
          throw const WatchFailure('WATCH_CAPACITY', '服务连接已满', 503);
        }
        final socket = await WebSocketTransformer.upgrade(request);
        _socket(socket);
        return;
      }
      if (!path.startsWith('/watch/v1/rooms')) {
        throw const WatchFailure('NOT_FOUND', '接口不存在', 404);
      }
      final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      if (!_allow(_restRates, ip, 60, 60000)) {
        throw const WatchFailure('RATE_LIMITED', '请求过于频繁', 429);
      }
      final token = _header(request, 'X-Emby-Token');
      final userId = _header(request, 'X-Emby-User-Id');
      final serverId = _header(request, 'X-Emby-Server-Id');
      final identity = await verifier.verify(
        token: token,
        userId: userId,
        serverId: serverId,
      );
      if (_closed) throw const WatchFailure('WATCH_UNAVAILABLE', '服务正在关闭', 503);
      final body = request.method == 'POST'
          ? await _body(request)
          : <String, dynamic>{};
      if (path == '/watch/v1/rooms' && request.method == 'POST') {
        return await _create(request, identity, body);
      }
      if (path == '/watch/v1/rooms/join' && request.method == 'POST') {
        return await _join(request, identity, body);
      }
      final parts = path.split('/');
      if (parts.length != 5 && parts.length != 6) {
        throw const WatchFailure('NOT_FOUND', '接口不存在', 404);
      }
      final room = _rooms[parts[4]];
      if (room == null) throw const WatchFailure('ROOM_ENDED', '房间已结束', 404);
      final member = room.members.values
          .where((m) => _key(m.identity) == _key(identity))
          .firstOrNull;
      if (member == null) {
        throw const WatchFailure('NOT_MEMBER', '你不在这个房间', 403);
      }
      member.identity = identity;
      member.nextCheck = _now() + config.recheckMs;
      if (parts.length == 5 && request.method == 'GET') {
        return await _json(request, {
          'room': _snapshot(room),
          'memberId': member.id,
        });
      }
      if (request.method != 'POST' || parts.length != 6) {
        throw const WatchFailure('NOT_FOUND', '接口不存在', 404);
      }
      switch (parts[5]) {
        case 'ticket':
          final clientId = _string(body, 'clientId');
          return await _json(request, _entry(room, member, clientId));
        case 'leave':
          _remove(room, member, 'left');
          return await _json(request, {'left': true});
        case 'kick':
          _owner(room, member);
          final target = room.members[_string(body, 'memberId')];
          if (target == null || target.id == member.id) {
            throw const WatchFailure('INVALID_REQUEST', '无法移除此成员');
          }
          room.banned.add(_key(target.identity));
          _remove(room, target, 'kicked');
          return await _json(request, {'removed': true});
        case 'end':
          _owner(room, member);
          _end(room, 'room_ended');
          return await _json(request, {'ended': true});
        default:
          throw const WatchFailure('NOT_FOUND', '接口不存在', 404);
      }
    } on WatchFailure catch (error) {
      await _error(request, error);
    } catch (_) {
      await _error(request, const WatchFailure('INVALID_REQUEST', '请求无法处理'));
    }
  }

  String _header(HttpRequest request, String name) {
    final value = request.headers.value(name);
    if (value == null || value.isEmpty || value.length > 4096) {
      throw const WatchFailure('AUTH_REQUIRED', '请先登录媒体服务器', 401);
    }
    return value;
  }

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw const WatchFailure('INVALID_REQUEST', '请使用 JSON 请求');
    }
    final data = <int>[];
    await for (final bytes in request.timeout(const Duration(seconds: 5))) {
      if (data.length + bytes.length > 16384) {
        throw const WatchFailure('INVALID_REQUEST', '请求过大', 413);
      }
      data.addAll(bytes);
    }
    final decoded = jsonDecode(utf8.decode(data));
    if (decoded is! Map<String, dynamic>) {
      throw const WatchFailure('INVALID_REQUEST', '请求必须为对象');
    }
    return decoded;
  }

  String _string(Map data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty || value.length > 256) {
      throw const WatchFailure('INVALID_REQUEST', '请求字段无效');
    }
    return value;
  }

  String? _source(Map data) {
    final value = data['mediaSourceId'];
    return value == null ? null : _string(data, 'mediaSourceId');
  }

  int _position(Object? value, int max) {
    if (value is! int || value < 0 || value > max) {
      throw const WatchFailure('INVALID_REQUEST', '播放位置无效');
    }
    return value;
  }

  Future<void> _create(
    HttpRequest request,
    WatchIdentity identity,
    Map body,
  ) async {
    final clientId = _string(body, 'clientId');
    final key = _key(identity);
    if (_users.containsKey(key)) {
      throw const WatchFailure('ALREADY_IN_ROOM', '请先离开当前房间', 409);
    }
    if (_rooms.length >= config.maxRooms) {
      throw const WatchFailure('WATCH_CAPACITY', '房间数量已满', 503);
    }
    final media = await verifier.media(
      identity,
      _string(body, 'itemId'),
      _source(body),
    );
    final position = _position(body['positionMs'] ?? 0, media.runTimeMs);
    if (_closed || _users.containsKey(key)) {
      throw const WatchFailure('ALREADY_IN_ROOM', '请先离开当前房间', 409);
    }
    if (_rooms.length >= config.maxRooms) {
      throw const WatchFailure('WATCH_CAPACITY', '房间数量已满', 503);
    }
    final room = _Room(
      _randomKey(16),
      _code(),
      media,
      _now(),
      identity.isAdmin ? config.adminRoomCapacity : config.roomCapacity,
    );
    final member = _Member(_randomKey(16), identity, _now() + config.recheckMs);
    room.members[member.id] = member;
    room.owner = member.id;
    room.position = position;
    room.serverTime = _now();
    room.emptySince = _now();
    member.disconnectedAt = _now();
    _rooms[room.id] = room;
    _codes[room.code] = room.id;
    _users[key] = room.id;
    await _json(request, _entry(room, member, clientId));
  }

  Future<void> _join(
    HttpRequest request,
    WatchIdentity identity,
    Map body,
  ) async {
    final clientId = _string(body, 'clientId');
    final room = _rooms[_codes[_string(body, 'code').trim().toUpperCase()]];
    if (room == null) throw const WatchFailure('ROOM_ENDED', '房间已结束', 404);
    final key = _key(identity);
    if (room.banned.contains(key)) {
      throw const WatchFailure('KICKED', '你已被移出此房间', 403);
    }
    final existing = room.members.values
        .where((m) => _key(m.identity) == key)
        .firstOrNull;
    if (existing == null && _users.containsKey(key)) {
      throw const WatchFailure('ALREADY_IN_ROOM', '请先离开当前房间', 409);
    }
    if (existing == null && room.members.length >= room.capacity) {
      throw const WatchFailure('ROOM_FULL', '房间已满', 409);
    }
    final media = room.media;
    await verifier.media(identity, media.itemId, media.mediaSourceId);
    if (_rooms[room.id] != room) {
      throw const WatchFailure('ROOM_ENDED', '房间已结束', 404);
    }
    if (room.media != media) {
      throw const WatchFailure('ROOM_CHANGED', '影片已变化，请重新加入', 409);
    }
    if (existing != null) {
      if (room.members[existing.id] != existing) {
        throw const WatchFailure('NOT_MEMBER', '房间成员已变化，请重新加入', 409);
      }
      existing.identity = identity;
      return await _json(request, _entry(room, existing, clientId));
    }
    if (_users.containsKey(key)) {
      throw const WatchFailure('ALREADY_IN_ROOM', '请先离开当前房间', 409);
    }
    if (room.members.length >= room.capacity) {
      throw const WatchFailure('ROOM_FULL', '房间已满', 409);
    }
    if (room.banned.contains(key)) {
      throw const WatchFailure('KICKED', '你已被移出此房间', 403);
    }
    final member = _Member(_randomKey(16), identity, _now() + config.recheckMs);
    member.disconnectedAt = _now();
    room.members[member.id] = member;
    _users[key] = room.id;
    room.generation++;
    _broadcast(room);
    await _json(request, _entry(room, member, clientId));
  }

  Map<String, Object> _entry(_Room room, _Member member, String clientId) {
    if (_tickets.length >= 2000) {
      throw const WatchFailure('WATCH_CAPACITY', '连接凭证已满', 503);
    }
    final ticket = _randomKey();
    _tickets[ticket] = _Ticket(room.id, member.id, clientId, _now() + 30000);
    return {'room': _snapshot(room), 'memberId': member.id, 'ticket': ticket};
  }

  void _owner(_Room room, _Member member) {
    if (room.owner != member.id) {
      throw const WatchFailure('NOT_OWNER', '仅房主可以操作', 403);
    }
  }

  Future<void> _json(HttpRequest request, Map data) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.write(jsonEncode({'data': data}));
    await request.response.close();
  }

  Future<void> _error(HttpRequest request, WatchFailure failure) async {
    try {
      request.response.statusCode = failure.status;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(jsonEncode({'error': failure.toJson()}));
      await request.response.close();
    } catch (_) {
      /* The peer may already have disconnected. */
    }
  }

  bool _allow(Map<String, _Window> windows, String key, int count, int period) {
    final now = _now();
    final window = windows[key];
    if (window == null || now - window.start >= period) {
      windows[key] = _Window(now, 1);
      return true;
    }
    return ++window.count <= count;
  }

  Map<String, Object?> _snapshot(_Room room) => {
    'roomId': room.id,
    'code': room.code,
    'capacity': room.capacity,
    'ownerMemberId': room.owner,
    'media': room.media.toJson(),
    'playback': {
      'revision': room.revision,
      'state': room.state,
      'positionMs': room.position,
      'serverTime': room.serverTime,
      'waitingMemberIds': room.waiting.toList(),
    },
    'members': room.members.values
        .map(
          (m) => {
            'memberId': m.id,
            'name': m.identity.name,
            'role': m.id == room.owner ? 'owner' : 'member',
            'connected': m.socket != null,
            'status': m.status,
            'lagging': m.lagging,
          },
        )
        .toList(),
  };
  int _current(_Room room) => min(
    room.media.runTimeMs,
    room.position +
        (room.state == 'playing' ? max(0, _now() - room.serverTime) : 0),
  );
  void _send(WebSocket socket, Map data) {
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(jsonEncode(data));
    } on StateError {
      // close() can seal the sink before readyState reports closing.
    }
  }

  void _broadcast(_Room room) {
    for (final member in room.members.values) {
      final socket = member.socket;
      if (socket != null) {
        _send(socket, {
          'type': 'snapshot',
          'room': _snapshot(room),
          'memberId': member.id,
        });
      }
    }
  }

  void _socket(WebSocket socket) {
    _sockets.add(socket);
    _Room? room;
    _Member? member;
    final helloTimer = Timer(
      const Duration(seconds: 5),
      () => unawaited(socket.close(4401, 'hello required')),
    );
    final rates = <String, _Window>{};
    socket.listen(
      (event) {
        if (event is! String || utf8.encode(event).length > 32768) {
          unawaited(socket.close(1009, 'frame too large'));
          return;
        }
        String? requestId;
        try {
          final data = jsonDecode(event);
          if (data is! Map<String, dynamic>) throw const FormatException();
          if (data['type'] == 'command' &&
              data['requestId'] is String &&
              (data['requestId'] as String).length <= 256) {
            requestId = data['requestId'] as String;
          }
          if (member == null) {
            if (data['type'] != 'hello') throw const FormatException();
            final ticket = _tickets.remove(data['ticket']);
            if (ticket == null ||
                ticket.expires < _now() ||
                ticket.clientId != data['clientId']) {
              unawaited(socket.close(4401, 'invalid ticket'));
              return;
            }
            room = _rooms[ticket.roomId];
            member = room?.members[ticket.memberId];
            if (room == null || member == null) {
              unawaited(socket.close(4410, 'room ended'));
              return;
            }
            final old = member!.socket;
            member!.socket = socket;
            member!.lastMessage = _now();
            member!.disconnectedAt = null;
            member!.status = 'away';
            room!.emptySince = null;
            _tickets.removeWhere(
              (_, t) => t.roomId == room!.id && t.memberId == member!.id,
            );
            helloTimer.cancel();
            if (old != null) unawaited(old.close(4409, 'replaced'));
            _broadcast(room!);
            return;
          }
          if (member!.socket != socket ||
              _rooms[room!.id] != room ||
              room!.members[member!.id] != member) {
            return;
          }
          member!.lastMessage = _now();
          if (data['type'] != 'command' && !_allow(rates, 'other', 20, 1000)) {
            unawaited(socket.close(4408, 'rate limited'));
            return;
          }
          switch (data['type']) {
            case 'ping':
              if (data['clientTime'] is! int) throw const FormatException();
              _send(socket, {
                'type': 'pong',
                'clientTime': data['clientTime'],
                'serverTime': _now(),
              });
            case 'status':
              if (!_allow(rates, 'status', 20, 1000)) {
                throw const WatchFailure('RATE_LIMITED', '状态过于频繁', 429);
              }
              _status(room!, member!, data);
            case 'command':
              if (!_allow(rates, 'command', 10, 1000)) {
                throw const WatchFailure('RATE_LIMITED', '操作过于频繁', 429);
              }
              unawaited(_command(room!, member!, socket, data));
            default:
              throw const WatchFailure('INVALID_REQUEST', '消息类型无效');
          }
        } on WatchFailure catch (error) {
          _send(socket, {
            'type': 'error',
            if (requestId != null) 'requestId': requestId,
            ...error.toJson(),
          });
        } catch (_) {
          _send(socket, {
            'type': 'error',
            'code': 'INVALID_REQUEST',
            'message': '消息格式无效',
          });
        }
      },
      onDone: () {
        helloTimer.cancel();
        _sockets.remove(socket);
        if (member?.socket != socket || room == null) return;
        member!.socket = null;
        member!.disconnectedAt = _now();
        member!.status = 'away';
        room!.waiting.remove(member!.id);
        if (room!.members.values.every((m) => m.socket == null)) {
          room!.emptySince = _now();
        }
        _tryResume(room!);
        _broadcast(room!);
      },
      onError: (Object _) {
        unawaited(socket.close());
      },
    );
  }

  void _status(_Room room, _Member member, Map data) {
    final status = data['status'];
    const allowed = {
      'away',
      'loading',
      'ready',
      'playing',
      'paused',
      'buffering',
      'ended',
      'error',
    };
    if (!allowed.contains(status)) {
      throw const WatchFailure('INVALID_REQUEST', '状态无效');
    }
    final revision = data['revision'];
    if (status != 'away' && status != 'error') {
      if (revision is! int || revision > room.revision) {
        throw const WatchFailure('INVALID_REQUEST', '状态版本无效');
      }
      if (revision < room.revision) return;
    }
    final position = _position(data['positionMs'] ?? 0, room.media.runTimeMs);
    member.status = status as String;
    if (status == 'away' || status == 'error') {
      room.waiting.remove(member.id);
      member.bufferSince = null;
    }
    if (room.state == 'waiting' && status == 'ready') {
      room.waiting.remove(member.id);
      member.lagging = false;
    } else if (room.state == 'waiting' &&
        (status == 'loading' || status == 'buffering')) {
      // A ready participant may start buffering again while others load.
      // Keep the original deadline so an unstable peer cannot extend it.
      room.waiting.add(member.id);
    }
    if (room.state == 'playing' && status == 'buffering') {
      member.bufferSince ??= _now();
      member.bufferPosition = position;
      if (_now() - member.bufferSince! >= 1500) {
        if (_now() - member.lastBuffer >= 30000) {
          member.lastBuffer = _now();
          _wait(room, min(position, _current(room)));
        } else {
          member.lagging = true;
        }
      }
    } else if (status != 'buffering') {
      member.bufferSince = null;
    }
    _tryResume(room);
    _broadcast(room);
  }

  Future<void> _command(
    _Room room,
    _Member member,
    WebSocket socket,
    Map data,
  ) async {
    String? requestId;
    try {
      requestId = _string(data, 'requestId');
      if (data['revision'] != room.revision) {
        throw const WatchFailure('STALE_REVISION', '房间状态已变化，请重试', 409);
      }
      final action = data['action'];
      switch (action) {
        case 'pause':
          room.position = data['positionMs'] == null
              ? _current(room)
              : _position(data['positionMs'], room.media.runTimeMs);
          room.state = 'paused';
          room.serverTime = _now();
          room.waiting.clear();
          room.revision++;
        case 'play':
          member.status = 'loading';
          _wait(room, _current(room));
        case 'seek':
          final position = _position(data['positionMs'], room.media.runTimeMs);
          if (room.state == 'paused') {
            room.position = position;
            room.serverTime = _now();
            room.revision++;
          } else {
            _wait(room, position);
          }
        case 'changeItem':
          if (room.changing) {
            throw const WatchFailure('CHANGE_IN_PROGRESS', '正在更换影片', 409);
          }
          room.changing = true;
          final revision = room.revision, generation = room.generation;
          final members = room.members.values.toList();
          try {
            final media = await verifier.media(
              member.identity,
              _string(data, 'itemId'),
              _source(data),
            );
            for (final other in members) {
              if (other != member) {
                await verifier.media(
                  other.identity,
                  media.itemId,
                  media.mediaSourceId,
                );
              }
            }
            if (_rooms[room.id] != room ||
                room.members[member.id] != member ||
                member.socket != socket) {
              throw const WatchFailure('ROOM_ENDED', '房间或成员已离开', 404);
            }
            if (room.revision != revision || room.generation != generation) {
              throw const WatchFailure('STALE_REVISION', '房间状态已变化，请重试', 409);
            }
            room.media = media;
            for (final m in room.members.values) {
              if (m.socket != null && m.status != 'away') m.status = 'loading';
            }
            member.status = 'loading';
            _wait(room, 0);
          } finally {
            room.changing = false;
          }
        default:
          throw const WatchFailure('INVALID_REQUEST', '操作无效');
      }
      if (member.socket == socket) {
        _send(socket, {'type': 'ack', 'requestId': requestId});
      }
      _broadcast(room);
      // Give viewers the waiting snapshot before settling an empty ready set.
      scheduleMicrotask(() => _tryResume(room));
    } on WatchFailure catch (error) {
      _send(socket, {
        'type': 'error',
        'requestId': requestId,
        ...error.toJson(),
      });
      if (error.code == 'STALE_REVISION') _broadcast(room);
    } catch (_) {
      _send(socket, {
        'type': 'error',
        'requestId': requestId,
        'code': 'WATCH_UNAVAILABLE',
        'message': '操作暂不可用',
      });
    }
  }

  void _wait(_Room room, int position) {
    room.position = position;
    room.serverTime = _now();
    room.state = 'waiting';
    room.revision++;
    room.waitDeadline = _now() + config.waitTimeoutMs;
    room.waiting.clear();
    for (final member in room.members.values) {
      member.bufferSince = null;
      if (member.socket != null &&
          member.status != 'away' &&
          member.status != 'error') {
        room.waiting.add(member.id);
        member.status = 'loading';
      }
    }
  }

  void _tryResume(_Room room) {
    if (room.state != 'waiting' || _rooms[room.id] != room) return;
    if (room.waiting.isNotEmpty && _now() < room.waitDeadline) return;
    if (room.waiting.isNotEmpty) {
      for (final id in room.waiting) {
        room.members[id]?.lagging = true;
      }
      room.waiting.clear();
    }
    room.state = 'playing';
    room.serverTime = _now() + config.leadMs;
    room.revision++;
    _broadcast(room);
  }

  void _remove(_Room room, _Member member, String reason) {
    if (room.members.remove(member.id) != member) return;
    _users.remove(_key(member.identity));
    _tickets.removeWhere(
      (_, t) => t.memberId == member.id && t.roomId == room.id,
    );
    room.waiting.remove(member.id);
    room.generation++;
    final socket = member.socket;
    member.socket = null;
    if (socket != null) {
      _send(socket, {'type': 'closed', 'reason': reason});
      unawaited(socket.close(4410, reason));
    }
    if (room.members.isEmpty) {
      _end(room, 'room_ended');
      return;
    }
    if (room.owner == member.id) {
      room.owner =
          (room.members.values.where((m) => m.socket != null).firstOrNull ??
                  room.members.values.first)
              .id;
    }
    _tryResume(room);
    _broadcast(room);
  }

  void _end(_Room room, String reason) {
    if (_rooms.remove(room.id) != room) return;
    _codes.remove(room.code);
    for (final member in room.members.values) {
      _users.remove(_key(member.identity));
      final socket = member.socket;
      member.socket = null;
      if (socket != null) {
        _send(socket, {'type': 'closed', 'reason': reason});
        unawaited(socket.close(4410, reason));
      }
    }
    _tickets.removeWhere((_, t) => t.roomId == room.id);
    room.members.clear();
  }

  /// Public deterministic sweep for isolated expiry and buffering tests.
  void tick() {
    if (_closed) return;
    final now = _now();
    _tickets.removeWhere((_, t) => t.expires < now);
    _restRates.removeWhere((_, w) => now - w.start > 60000);
    for (final room in _rooms.values.toList()) {
      if (now - room.created >= config.roomLifetimeMs ||
          (room.emptySince != null &&
              now - room.emptySince! >= config.emptyRoomMs)) {
        _end(room, 'room_ended');
        continue;
      }
      for (final member in room.members.values.toList()) {
        if (member.socket != null &&
            now - member.lastMessage >= config.socketIdleMs) {
          unawaited(member.socket!.close(4408, 'idle'));
        }
        if (room.emptySince == null &&
            member.disconnectedAt != null &&
            now - member.disconnectedAt! >= config.seatHoldMs) {
          _remove(room, member, 'seat_expired');
          continue;
        }
        if (member.bufferSince != null &&
            room.state == 'playing' &&
            now - member.bufferSince! >= 1500) {
          if (now - member.lastBuffer >= 30000) {
            member.lastBuffer = now;
            _wait(room, min(member.bufferPosition, _current(room)));
            _broadcast(room);
          } else {
            member.lagging = true;
          }
        }
        if (!member.checking && now >= member.nextCheck) {
          member.checking = true;
          unawaited(_recheck(room, member));
        }
      }
      _tryResume(room);
      if (now - room.lastBroadcast >= 5000) {
        room.lastBroadcast = now;
        _broadcast(room);
      }
    }
  }

  Future<void> _recheck(_Room room, _Member member) async {
    final credential = member.identity;
    try {
      final identity = await verifier.verify(
        token: credential.token,
        userId: credential.userId,
        serverId: credential.serverId,
      );
      if (_rooms[room.id] == room &&
          room.members[member.id] == member &&
          identical(member.identity, credential)) {
        member.identity = identity;
        member.nextCheck = _now() + config.recheckMs;
      }
    } on WatchFailure catch (error) {
      if (!identical(member.identity, credential)) return;
      if (error.status == 401 || error.status == 403) {
        _remove(room, member, 'auth_expired');
      } else {
        member.nextCheck = _now() + 30000;
      }
    } catch (_) {
      member.nextCheck = _now() + 30000;
    } finally {
      member.checking = false;
    }
  }
}

class _Room {
  _Room(this.id, this.code, this.media, this.created, this.capacity);
  final String id, code;
  final int created, capacity;
  WatchMedia media;
  String? owner;
  final members = <String, _Member>{};
  final banned = <String>{};
  final waiting = <String>{};
  int revision = 0,
      position = 0,
      serverTime = 0,
      waitDeadline = 0,
      generation = 0,
      lastBroadcast = 0;
  int? emptySince;
  String state = 'paused';
  bool changing = false;
}

class _Member {
  _Member(this.id, this.identity, this.nextCheck);
  final String id;
  WatchIdentity identity;
  int nextCheck;
  WebSocket? socket;
  String status = 'away';
  bool lagging = false, checking = false;
  int lastMessage = 0, lastBuffer = -30000, bufferPosition = 0;
  int? disconnectedAt, bufferSince;
}

class _Ticket {
  _Ticket(this.roomId, this.memberId, this.clientId, this.expires);
  final String roomId, memberId, clientId;
  final int expires;
}

class _Window {
  _Window(this.start, this.count);
  final int start;
  int count;
}
