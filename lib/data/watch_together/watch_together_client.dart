import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../auth/api_session.dart';
import '../storage/key_value_store.dart';
import 'models.dart';
export 'models.dart';

/// Coordinates room metadata only. Video URLs and playback remain with Emby.
class WatchTogetherClient extends ChangeNotifier {
  WatchTogetherClient({
    required ApiSession session,
    required KeyValueStore store,
    // Keep credential-bearing dependencies private.
    // ignore: prefer_initializing_formals
  }) : _session = session,
       // ignore: prefer_initializing_formals
       _store = store;
  final ApiSession _session;
  final KeyValueStore _store;
  static const serviceKey = 'watchTogether.service.v1';
  static const recoveryKey = 'watchTogether.recovery.v1';
  static const clientIdKey = 'watchTogether.clientId.v1';
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  final _socketHttp = _SocketHttpClient();
  final Stopwatch _clock = Stopwatch()..start();
  final int _epoch = DateTime.now().millisecondsSinceEpoch;
  final _samples = <(int, int)>[];
  String? _clientId;
  Uri? _baseUrl;
  WatchRoom? _room;
  String? _memberId;
  String? _error;
  _Identity? _bound;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _messages;
  Timer? _heartbeat, _watchdog, _reconnect, _identityWatch;
  int _generation = 0, _attempt = 0, _lastMessage = 0;
  bool _connected = false, _reconnecting = false, _disposed = false;
  int? _openingGeneration;
  bool get _opening => _openingGeneration != null;
  final _pending = <String, Completer<void>>{};
  Future<void> _recoveryWrites = Future<void>.value();

  Future<void> _persistRecovery(Future<void> Function() write) {
    final result = _recoveryWrites.then((_) => write());
    _recoveryWrites = result.catchError((Object _) {});
    return result;
  }

  int get _now => _epoch + _clock.elapsedMilliseconds;
  Uri? get baseUrl => _baseUrl;
  WatchRoom? get room => _room;
  String? get memberId => _memberId;
  bool get connected => _connected;
  bool get reconnecting => _reconnecting;
  String? get error => _error;
  bool get isOwner => _room != null && _room!.ownerMemberId == _memberId;
  int get serverNowMs =>
      _now +
      (_samples.isEmpty
          ? 0
          : (_samples.toList()..sort((a, b) => a.$1.compareTo(b.$1))).first.$2);
  static String _random() => base64UrlEncode(
    List<int>.generate(24, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  Future<void> initialize() async {
    _clientId = await _store.read(clientIdKey);
    if (_clientId == null || _clientId!.isEmpty) {
      _clientId = _random();
      await _store.write(clientIdKey, _clientId!);
    }
    final saved = await _store.read(serviceKey);
    if (saved != null) {
      try {
        _baseUrl = _normalize(Uri.parse(saved));
      } catch (_) {
        _error = '一起看服务地址无效，请重新配置';
      }
    }
    _identityWatch ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_bound != null && !_bound!.matches(_session)) {
        unawaited(sessionChanged());
      }
    });
    _notify();
  }

  static Uri _normalize(Uri uri) {
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['http', 'https'].contains(uri.scheme)) {
      throw const WatchTogetherException(
        'INVALID_URL',
        '请输入不含账号或参数的 HTTP(S) 服务地址',
      );
    }
    final ip = InternetAddress.tryParse(uri.host);
    final bytes = ip?.rawAddress;
    final privateV4 =
        bytes != null &&
        bytes.length == 4 &&
        (bytes[0] == 10 ||
            (bytes[0] == 192 && bytes[1] == 168) ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31));
    final privateV6 =
        bytes != null &&
        bytes.length == 16 &&
        ((bytes[0] & 0xfe) == 0xfc ||
            (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80));
    final private =
        uri.host == 'localhost' ||
        uri.host.endsWith('.local') ||
        ip?.isLoopback == true ||
        privateV4 ||
        privateV6;
    if (uri.scheme == 'http' && !private) {
      throw const WatchTogetherException('INSECURE_URL', '公网一起看服务必须使用 HTTPS');
    }
    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isEmpty) {
      path = '/watch/v1';
    }
    return uri.replace(path: path);
  }

  Future<void> configure(Uri? url) async {
    final next = url == null ? null : _normalize(url);
    if (next == _baseUrl) {
      return;
    }
    ++_generation;
    _openingGeneration = null;
    if (_room != null) {
      await leave();
    }
    _disconnect();
    _bound = null;
    _room = null;
    _memberId = null;
    _error = null;
    _baseUrl = next;
    _samples.clear();
    await _persistRecovery(() => _store.delete(recoveryKey));
    if (next == null) {
      await _store.delete(serviceKey);
    } else {
      await _store.write(serviceKey, next.toString());
    }
    _notify();
  }

  _Identity _identity() {
    final endpoint = _session.endpoint;
    final user = _session.userId, token = _session.accessToken;
    if (endpoint == null || user == null || token == null || token.isEmpty) {
      throw const WatchTogetherException('AUTH_REQUIRED', '请先登录 Emby 后使用一起看');
    }
    return _Identity(endpoint.serverId, user, token, endpoint.baseUrl);
  }

  Uri _uri(String path) {
    final base = _baseUrl;
    if (base == null) {
      throw const WatchTogetherException('SERVICE_REQUIRED', '请先配置一起看服务地址');
    }
    return base.replace(path: '${base.path}$path');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    _Identity? identity,
  }) async {
    final who = identity ?? _identity();
    final uri = _uri(path);
    try {
      final request = await _http
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 8));
      if (!who.matches(_session)) {
        request.abort();
        throw const WatchTogetherException('SESSION_CHANGED', '登录会话已变更，请重新加入');
      }
      request.followRedirects = false;
      request.headers.set('X-Emby-Token', who.token);
      request.headers.set('X-Emby-User-Id', who.user);
      request.headers.set('X-Emby-Server-Id', who.server);
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      var length = 0;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        length += chunk.length;
        if (length > 131072) {
          throw const FormatException();
        }
        bytes.addAll(chunk);
      }
      if (!who.matches(_session)) {
        throw const WatchTogetherException('SESSION_CHANGED', '登录会话已变更，请重新加入');
      }
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final error = decoded['error'] as Map<String, dynamic>?;
        final code = error?['code'] as String? ?? 'REQUEST_FAILED';
        throw WatchTogetherException(code, _message(code));
      }
      return decoded['data'] as Map<String, dynamic>;
    } on WatchTogetherException {
      rethrow;
    } catch (_) {
      throw const WatchTogetherException('UNAVAILABLE', '无法连接一起看服务，请检查地址与网络');
    }
  }

  Future<void> _health() async {
    // Uses the same authenticated transport; health itself is public.
    final data = await _request('GET', '/health');
    if (data['enabled'] != true || data['protocol'] != 1) {
      throw const WatchTogetherException('PROTOCOL', '一起看服务不可用或协议不兼容');
    }
  }

  Future<void> create({
    required String itemId,
    String? mediaSourceId,
    int positionMs = 0,
  }) => _enter('/rooms', {
    'itemId': itemId,
    'mediaSourceId': mediaSourceId,
    'positionMs': positionMs,
  });
  Future<void> join(String code) =>
      _enter('/rooms/join', {'code': code.trim().toUpperCase()});
  Future<void> _enter(String path, Map<String, dynamic> body) async {
    if (_room != null) {
      throw const WatchTogetherException('ALREADY_IN_ROOM', '请先离开当前房间');
    }
    if (_opening) {
      throw const WatchTogetherException('BUSY', '正在连接，请稍候');
    }
    final generation = ++_generation;
    _openingGeneration = generation;
    try {
      final identity = _identity();
      _bound = identity;
      if (_clientId == null) {
        await initialize();
      }
      if (generation != _generation || _disposed) return;
      await _health();
      if (generation != _generation || _disposed) return;
      final data = await _request(
        'POST',
        path,
        body: {...body, 'clientId': _clientId},
        identity: identity,
      );
      if (generation != _generation || _disposed) {
        return;
      }
      _bound = identity;
      _error = null;
      _accept(data);
      await _saveRecovery();
      if (generation != _generation || _disposed) return;
      await _connect(data['ticket'] as String, generation);
    } on WatchTogetherException catch (e) {
      if (generation == _generation) {
        _error = e.message;
        _notify();
      }
      rethrow;
    } finally {
      if (_openingGeneration == generation) _openingGeneration = null;
    }
  }

  Future<void> restore() async {
    if (_baseUrl == null || _opening || _room != null) {
      return;
    }
    final generation = ++_generation;
    _openingGeneration = generation;
    try {
      final saved = await _store.read(recoveryKey);
      if (saved == null || generation != _generation || _disposed) return;
      final json = jsonDecode(saved) as Map<String, dynamic>;
      final who = _identity();
      if (json['server'] != who.server ||
          json['user'] != who.user ||
          json['service'] != _baseUrl.toString()) {
        await _persistRecovery(() => _store.delete(recoveryKey));
        return;
      }
      _bound = who;
      final data = await _request(
        'POST',
        '/rooms/${Uri.encodeComponent(json['roomId'] as String)}/ticket',
        body: {'clientId': _clientId},
        identity: who,
      );
      if (generation != _generation || _disposed) {
        return;
      }
      _accept(data);
      await _connect(data['ticket'] as String, generation);
    } on WatchTogetherException catch (e) {
      if (generation != _generation) {
        return;
      }
      _error = e.message;
      if ([
        'ROOM_ENDED',
        'NOT_MEMBER',
        'AUTH_INVALID',
        'AUTH_REQUIRED',
        'SESSION_CHANGED',
      ].contains(e.code)) {
        await _clearRoom();
      }
      _notify();
    } catch (_) {
      if (generation == _generation) {
        await _persistRecovery(() => _store.delete(recoveryKey));
      }
    } finally {
      if (_openingGeneration == generation) _openingGeneration = null;
    }
  }

  void _accept(Map<String, dynamic> data) {
    final next = WatchRoom.fromJson(data['room'] as Map<String, dynamic>);
    if (_room != null &&
        next.roomId == _room!.roomId &&
        next.playback.revision < _room!.playback.revision) {
      return;
    }
    _room = next;
    if (data['memberId'] is String) {
      _memberId = data['memberId'] as String;
    }
    _notify();
  }

  Future<void> _saveRecovery() async {
    final who = _bound, current = _room;
    if (who == null || current == null) {
      return;
    }
    final saved = jsonEncode({
      'server': who.server,
      'user': who.user,
      'roomId': current.roomId,
      'service': _baseUrl.toString(),
    });
    await _persistRecovery(() => _store.write(recoveryKey, saved));
  }

  Future<void> _connect(String ticket, int generation) async {
    try {
      await _connectSocket(ticket, generation);
    } catch (_) {
      if (generation == _generation && !_disposed && _room != null) {
        await _closeSocket();
        if (generation == _generation) _lost(null);
      }
      throw const WatchTogetherException('DISCONNECTED', '一起看连接已断开，正在重连');
    }
  }

  Future<void> _connectSocket(String ticket, int generation) async {
    await _closeSocket();
    if (generation != _generation || _disposed) return;
    final uri = _uri('/socket');
    final opening = WebSocket.connect(
      uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString(),
      customClient: _socketHttp,
    );
    late WebSocket socket;
    try {
      socket = await opening.timeout(const Duration(seconds: 8));
    } catch (_) {
      // timeout() does not cancel a handshake. Dispose a late socket instead
      // of retaining an unowned connection after reconnect/leave.
      unawaited(
        opening
            .then((lateSocket) async {
              await lateSocket.close();
            })
            .catchError((Object _) {}),
      );
      rethrow;
    }
    if (_disposed ||
        generation != _generation ||
        _bound?.matches(_session) != true) {
      await socket.close();
      return;
    }
    _socket = socket;
    final hello = Completer<void>();
    _messages = socket.listen(
      (value) {
        if (generation != _generation || _socket != socket) {
          return;
        }
        _lastMessage = _now;
        try {
          if (value is! String || value.length > 32768) {
            throw const FormatException();
          }
          final json = jsonDecode(value) as Map<String, dynamic>;
          switch (json['type']) {
            case 'snapshot':
              _accept(json);
              _connected = true;
              _reconnecting = false;
              _attempt = 0;
              _error = null;
              if (!hello.isCompleted) {
                hello.complete();
              }
              _notify();
            case 'pong':
              final sent = (json['clientTime'] as num).toInt(),
                  server = (json['serverTime'] as num).toInt();
              final rtt = _now - sent;
              if (rtt >= 0 && rtt < 30000) {
                _samples.add((rtt, server - (sent + rtt ~/ 2)));
                if (_samples.length > 8) {
                  _samples.removeAt(0);
                }
              }
            case 'ack':
              _pending.remove(json['requestId'])?.complete();
            case 'error':
              final code = json['code'] as String? ?? 'REQUEST_FAILED';
              final error = WatchTogetherException(code, _message(code));
              _error = error.message;
              _pending.remove(json['requestId'])?.completeError(error);
              _notify();
            case 'closed':
              _error = _closedMessage(json['reason'] as String?);
              _terminal();
          }
        } catch (_) {
          _error = '一起看服务返回无效消息';
          unawaited(socket.close(1002));
        }
      },
      onError: (Object error) {
        if (!hello.isCompleted) {
          hello.completeError(
            const WatchTogetherException('DISCONNECTED', '一起看连接已断开'),
          );
        }
      },
      onDone: () {
        if (!hello.isCompleted) {
          hello.completeError(
            const WatchTogetherException('DISCONNECTED', '一起看连接已断开'),
          );
        }
        if (generation == _generation && _socket == socket) {
          _lost(socket.closeCode);
        }
      },
    );
    socket.add(
      jsonEncode({'type': 'hello', 'ticket': ticket, 'clientId': _clientId}),
    );
    _lastMessage = _now;
    await hello.future.timeout(const Duration(seconds: 6));
    if (generation != _generation || _socket != socket) {
      return;
    }
    _ping();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _ping());
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_now - _lastMessage > 30000) {
        unawaited(socket.close());
      }
    });
  }

  bool _send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return false;
    try {
      socket.add(jsonEncode(message));
      return true;
    } on StateError {
      unawaited(_closeSocket());
      _lost(null);
      return false;
    }
  }

  void _ping() {
    _send({'type': 'ping', 'clientTime': _now});
  }

  void _lost(int? closeCode) {
    _connected = false;
    _heartbeat?.cancel();
    _watchdog?.cancel();
    _socket = null;
    _failPending();
    if ([4401, 4409, 4410].contains(closeCode)) {
      _error = closeCode == 4409
          ? '此账号已在另一台设备进入房间'
          : closeCode == 4410
          ? '已离开房间或房间已结束'
          : '一起看登录已失效';
      _terminal();
      return;
    }
    if (_room == null || _disposed) {
      _notify();
      return;
    }
    _reconnecting = true;
    _error = '连接中断，正在重新连接';
    _notify();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnect?.isActive == true || _disposed || _room == null) {
      return;
    }
    final seconds = [1, 2, 4, 8][min(_attempt++, 3)];
    _reconnect = Timer(Duration(seconds: seconds), () async {
      final generation = _generation, who = _bound, current = _room;
      if (who == null || current == null) {
        return;
      }
      if (!who.matches(_session)) {
        await sessionChanged();
        return;
      }
      try {
        final data = await _request(
          'POST',
          '/rooms/${Uri.encodeComponent(current.roomId)}/ticket',
          body: {'clientId': _clientId},
          identity: who,
        );
        if (generation != _generation || _disposed) {
          return;
        }
        _accept(data);
        await _connect(data['ticket'] as String, generation);
      } on WatchTogetherException catch (e) {
        if (generation != _generation) {
          return;
        }
        if ([
          'ROOM_ENDED',
          'NOT_MEMBER',
          'AUTH_INVALID',
          'SESSION_CHANGED',
          'KICKED',
        ].contains(e.code)) {
          _error = e.message;
          _terminal();
        } else {
          _scheduleReconnect();
        }
      } catch (_) {
        if (generation == _generation) {
          _scheduleReconnect();
        }
      }
    });
  }

  Future<void> command(String action, {int? positionMs}) =>
      _sendCommand(action, {'positionMs': ?positionMs});
  Future<void> changeItem({required String itemId, String? mediaSourceId}) =>
      _sendCommand('changeItem', {
        'itemId': itemId,
        'mediaSourceId': mediaSourceId,
      });
  Future<void> _sendCommand(String action, Map<String, dynamic> values) async {
    if (!_connected || _room == null || _socket == null) {
      throw const WatchTogetherException('DISCONNECTED', '房间尚未连接，请稍候');
    }
    if (_bound?.matches(_session) != true) {
      await sessionChanged();
      throw const WatchTogetherException('SESSION_CHANGED', '登录会话已变更');
    }
    final id = _random(), done = Completer<void>();
    _pending[id] = done;
    final sent = _send({
      'type': 'command',
      'requestId': id,
      'revision': _room!.playback.revision,
      'action': action,
      ...values,
    });
    if (!sent && _pending.remove(id) != null && !done.isCompleted) {
      done.completeError(
        const WatchTogetherException('DISCONNECTED', '一起看连接已断开'),
      );
    }
    try {
      await done.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const WatchTogetherException('TIMEOUT', '操作响应超时，请查看最新房间状态后再操作');
    } finally {
      _pending.remove(id);
    }
  }

  void reportStatus(String status, {int positionMs = 0}) {
    if (!_connected || _room == null || _bound?.matches(_session) != true) {
      return;
    }
    _send({
      'type': 'status',
      'revision': _room!.playback.revision,
      'status': status,
      'positionMs': positionMs,
    });
  }

  Future<void> leave() async {
    final current = _room;
    final who = _bound;
    ++_generation;
    _disconnect();
    await _clearRoom();
    if (current != null && who?.matches(_session) == true) {
      try {
        await _request(
          'POST',
          '/rooms/${Uri.encodeComponent(current.roomId)}/leave',
          body: {},
          identity: who,
        );
      } catch (_) {
        _error = '已断开本机连接；服务端座位将在断线期限后释放';
        _notify();
      }
    }
  }

  Future<void> kick(String memberId) async {
    final current = _room;
    if (current == null) {
      return;
    }
    await _request(
      'POST',
      '/rooms/${Uri.encodeComponent(current.roomId)}/kick',
      body: {'memberId': memberId},
      identity: _bound,
    );
  }

  Future<void> end() async {
    final current = _room;
    final generation = _generation;
    if (current == null) {
      return;
    }
    await _request(
      'POST',
      '/rooms/${Uri.encodeComponent(current.roomId)}/end',
      body: {},
      identity: _bound,
    );
    // A delayed response belongs to the room that issued it. Leaving or
    // joining another room while it is in flight must not close the new room.
    if (!_disposed &&
        generation == _generation &&
        _room?.roomId == current.roomId) {
      await leave();
    }
  }

  Future<void> sessionChanged() async {
    if (_bound?.matches(_session) == true) return;
    // Auth restoration emits before room restoration; retain recovery for that
    // same logged-in identity until restore() can validate it.
    if (_bound == null &&
        _room == null &&
        _session.accessToken != null &&
        _session.userId != null &&
        _session.endpoint != null) {
      return;
    }
    ++_generation;
    _disconnect();
    _error = '登录会话已变更，请重新加入一起看';
    await _clearRoom();
  }

  Future<void> _clearRoom() async {
    _room = null;
    _memberId = null;
    _bound = null;
    await _persistRecovery(() => _store.delete(recoveryKey));
    _notify();
  }

  void _terminal() {
    ++_generation;
    _disconnect();
    unawaited(_clearRoom().catchError((Object _) {}));
  }

  Future<void> _closeSocket() async {
    // Detach synchronously: a prior close must never capture a newer socket
    // after awaiting subscription cancellation.
    final messages = _messages, old = _socket;
    _messages = null;
    _socket = null;
    _connected = false;
    _heartbeat?.cancel();
    _watchdog?.cancel();
    try {
      await messages?.cancel();
      await old?.close();
    } catch (_) {
      // Closing an already broken transport needs no recovery action.
    }
  }

  void _disconnect() {
    _reconnect?.cancel();
    _reconnecting = false;
    _connected = false;
    unawaited(_closeSocket());
    _failPending();
  }

  void _failPending() {
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          const WatchTogetherException('DISCONNECTED', '一起看连接已断开'),
        );
      }
    }
    _pending.clear();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    ++_generation;
    _identityWatch?.cancel();
    _disconnect();
    _http.close(force: true);
    _socketHttp.close(force: true);
    super.dispose();
  }
}

class _Identity {
  const _Identity(this.server, this.user, this.token, this.endpoint);
  final String server, user, token, endpoint;
  bool matches(ApiSession session) =>
      session.endpoint?.serverId == server &&
      session.endpoint?.baseUrl == endpoint &&
      session.userId == user &&
      session.accessToken == token;
}

String _closedMessage(String? reason) => switch (reason) {
  'kicked' => '你已被移出房间',
  'auth_expired' => '一起看登录已失效',
  'replaced' => '此账号已在另一台设备进入房间',
  _ => '房间已结束',
};
String _message(String code) => switch (code) {
  'AUTH_REQUIRED' || 'AUTH_INVALID' => '一起看登录已失效，请重新登录',
  'ROOM_ENDED' => '房间已结束',
  'ROOM_FULL' => '房间已满',
  'ALREADY_IN_ROOM' => '请先离开当前房间，再创建或加入其他房间',
  'ITEM_FORBIDDEN' => '有成员没有权限播放此影片或版本',
  'MEDIA_SOURCE_INVALID' => '所选版本不可播放',
  'STALE_REVISION' => '房间状态已变化，请按最新状态重新操作',
  'NOT_OWNER' => '仅房主可以执行此操作',
  'KICKED' => '你已被移出此房间',
  'SERVER_NOT_ALLOWED' => '当前服务器与一起看服务不匹配',
  'NOT_MEMBER' => '你已不在此房间',
  'RATE_LIMITED' => '操作太频繁，请稍后再试',
  _ => '一起看操作失败，请稍后重试',
};

/// WebSocket.connect uses only openUrl on its custom client. Keep its upgrade
/// handshake on the configured origin, just like authenticated REST requests.
class _SocketHttpClient implements HttpClient {
  final HttpClient _delegate = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await _delegate.openUrl(method, url);
    request.followRedirects = false;
    return request;
  }

  @override
  void close({bool force = false}) => _delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
