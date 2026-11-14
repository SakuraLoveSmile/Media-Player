import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/auth/server_session_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/server_entry.dart';
import 'package:media_player/data/models/server_profile.dart';

/// One recorded login call.
class ServerLoginCall {
  const ServerLoginCall({
    required this.username,
    required this.password,
    required this.profile,
    required this.serverId,
  });

  final String username;
  final String password;
  final ServerProfile profile;
  final String serverId;
}

/// Test double for the multi-server auth surface (S20).
///
/// Implements both [AuthService] and [ServerSessionService] so widget tests can
/// exercise switching/restoring per server without HTTP or storage. Sessions are
/// held in memory keyed by the directory server id; the secure-store keying is
/// covered separately by the repository unit tests.
class FakeServerAuth implements AuthService, ServerSessionService {
  FakeServerAuth({
    Map<String, AuthSession>? sessions,
    ServerProfile? lastStoredProfile,
    this.loginFailure,
    String activeServerId = defaultServerId,
  }) : _sessions = <String, AuthSession>{...?sessions},
       _lastProfile = lastStoredProfile,
       _activeId = activeServerId;

  final Map<String, AuthSession> _sessions;
  ServerProfile? _lastProfile;
  String _activeId;

  /// When set, [login] throws it instead of succeeding.
  final EmbyException? loginFailure;

  int loginAttempts = 0;
  ServerLoginCall? lastLogin;
  final List<String> restoredServers = <String>[];
  final List<String> clearedServers = <String>[];

  static const AuthSession sampleSession = AuthSession(
    userId: 'u1',
    userName: 'test',
    accessToken: 'token',
    deviceId: 'd1',
  );

  /// Seeds a stored session for [serverId] (simulates a prior login).
  void seedSession(String serverId, [AuthSession session = sampleSession]) {
    _sessions[serverId] = session;
  }

  @override
  String get activeServerId => _activeId;

  @override
  AuthSession? get current => _sessions[_activeId];

  @override
  Stream<AuthSession?> get session => const Stream<AuthSession?>.empty();

  @override
  void useServer(String serverId) {
    _activeId = serverId;
  }

  @override
  Future<AuthSession?> restore() async => _sessions[_activeId];

  @override
  Future<AuthSession?> restoreServer(String serverId) async {
    _activeId = serverId;
    restoredServers.add(serverId);
    return _sessions[serverId];
  }

  @override
  Future<void> clearServer(String serverId) async {
    _sessions.remove(serverId);
    clearedServers.add(serverId);
  }

  @override
  Future<ServerProfile?> lastProfile() async => _lastProfile;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required ServerProfile profile,
  }) async {
    loginAttempts++;
    lastLogin = ServerLoginCall(
      username: username,
      password: password,
      profile: profile,
      serverId: _activeId,
    );
    final error = loginFailure;
    if (error != null) throw error;
    final session = AuthSession(
      userId: 'u1',
      userName: username,
      accessToken: 'token-$_activeId',
      deviceId: 'd1',
    );
    _sessions[_activeId] = session;
    _lastProfile = profile.copyWith(serverId: 'emby-$_activeId');
    return session;
  }

  @override
  Future<ServerProfile> adoptAddress({
    required ServerProfile profile,
    required EndpointKind kind,
    required String rawUrl,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {
    _sessions.remove(_activeId);
  }

  @override
  Future<void> handleUnauthorized() async {
    _sessions.remove(_activeId);
  }
}
