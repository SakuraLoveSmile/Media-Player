import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/network/endpoint_kind.dart';
import '../../core/network/url_normalizer.dart';
import '../api/emby_headers.dart';
import '../api/emby_http_client.dart';
import '../endpoints/endpoint_resolver.dart';
import '../models/auth_session.dart';
import '../models/json_read.dart';
import '../models/resolved_endpoint.dart';
import '../models/server_entry.dart';
import '../models/server_profile.dart';
import '../storage/key_value_store.dart';
import '../storage/profile_store.dart';
import '../storage/session_store.dart';
import '../storage/token_store.dart';
import 'api_session.dart';
import 'auth_service.dart';
import 'server_session_service.dart';

// Several private fields are initialized from named constructor parameters
// (the public `deviceId` getter is session-scoped, §10.9, and the scoped stores
// are rebuilt on switch). Named parameters cannot be private, so the lint's
// `this._field` fix does not compile here.
// ignore_for_file: prefer_initializing_formals

/// Login, session restore and logout (contract §1.4, §7, §10.5).
///
/// S20: the repository still owns the single active session, but that session
/// is now scoped to a server id. The `default` id reuses the original storage
/// keys, so existing single-session callers behave exactly as before; switching
/// servers rebuilds the scoped stores from [store].
class AuthRepository implements AuthService, ApiSession, ServerSessionService {
  AuthRepository({
    required this.client,
    required this.resolver,
    required TokenStore tokenStore,
    required SessionStore sessionStore,
    required ProfileStore profileStore,
    required String deviceId,
    KeyValueStore? store,
    this.clientName = AppConfig.clientName,
    this.deviceName = '',
    this.appVersion = AppConfig.appVersion,
  }) : _tokenStore = tokenStore,
       _sessionStore = sessionStore,
       _profileStore = profileStore,
       _store = store,
       _deviceId = deviceId;

  final EmbyHttpClient client;
  final EndpointResolver resolver;

  /// Raw backend used to rebuild the scoped stores when switching servers.
  /// Null in harnesses that only ever use the injected default-server stores.
  final KeyValueStore? _store;

  TokenStore _tokenStore;
  SessionStore _sessionStore;
  ProfileStore _profileStore;

  /// Stable id of this install; the public `deviceId` getter exposes the
  /// session's copy instead so it turns null on logout (contract §10.9).
  final String _deviceId;
  final String clientName;
  final String deviceName;
  final String appVersion;

  final StreamController<AuthSession?> _controller =
      StreamController<AuthSession?>.broadcast();

  AuthSession? _session;
  ResolvedEndpoint? _endpoint;

  /// Server whose credentials the scoped stores currently read/write (S20).
  String _serverId = defaultServerId;

  /// In-memory copy of the profile so playback can read the bitrate policy
  /// synchronously (contract §10.9). Kept in sync with [_endpoint].
  ServerProfile? _profile;

  @override
  AuthSession? get current => _session;

  @override
  Stream<AuthSession?> get session => _controller.stream;

  @override
  String get activeServerId => _serverId;

  @override
  void useServer(String serverId) {
    if (_serverId == serverId) return;
    _serverId = serverId;
    final store = _store;
    if (store == null) return;
    _tokenStore = TokenStore(store, serverId: serverId);
    _sessionStore = SessionStore(store, serverId: serverId);
    _profileStore = ProfileStore(store, serverId: serverId);
  }

  @override
  Future<AuthSession?> restoreServer(String serverId) {
    useServer(serverId);
    return restore();
  }

  @override
  Future<void> clearServer(String serverId) async {
    final store = _store;
    if (store == null) return;
    await TokenStore(store, serverId: serverId).delete();
    await SessionStore(store, serverId: serverId).delete();
    await ProfileStore(store, serverId: serverId).delete();
  }

  /// Endpoint used by the current session; all URLs must be derived from it.
  @override
  ResolvedEndpoint? get endpoint => _endpoint;

  @override
  String? get userId => _session?.userId;

  @override
  String? get accessToken => _session?.accessToken;

  /// From the session rather than the constructor argument so it turns null
  /// on logout (contract §10.9).
  @override
  String? get deviceId => _session?.deviceId;

  @override
  ServerProfile? get profile => _profile;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required ServerProfile profile,
  }) async {
    final endpoint = await resolver.resolve(profile, forceRefresh: true);

    final json = await client.postJson(
      endpoint.resolve('/Users/AuthenticateByName'),
      body: <String, String>{'Username': username, 'Pw': password},
      authorization: EmbyHeaders.authorizationValue(
        client: clientName,
        device: deviceName,
        deviceId: _deviceId,
        version: appVersion,
      ),
    );

    final accessToken = asString(json['AccessToken']);
    if (accessToken == null) {
      throw EmbyException(
        AppErrorCode.serverError,
        message: 'login response has no AccessToken',
      );
    }

    final user = asMap(json['User']);
    final userId = asString(user['Id']);
    if (userId == null) {
      throw EmbyException(
        AppErrorCode.serverError,
        message: 'login response has no User.Id',
      );
    }

    final responseServerId = asString(json['ServerId']) ?? endpoint.serverId;
    if (endpoint.serverId.isNotEmpty && responseServerId != endpoint.serverId) {
      throw EmbyException(
        AppErrorCode.serverMismatch,
        message: 'login response belongs to another server',
      );
    }

    final session = AuthSession(
      userId: userId,
      userName: asString(user['Name']) ?? username,
      accessToken: accessToken,
      deviceId: _deviceId,
    );

    await _tokenStore.write(accessToken);
    await _sessionStore.write(session);

    final storedProfile = profile.copyWith(
      serverId: responseServerId,
      lastGoodEndpoint: endpoint.kind,
    );
    await _profileStore.write(storedProfile);

    _endpoint = endpoint;
    _profile = storedProfile;
    _emit(session);
    return session;
  }

  @override
  Future<AuthSession?> restore() async {
    final profile = await _profileStore.read();
    final token = await _tokenStore.read();
    final meta = await _sessionStore.read();
    if (profile == null || token == null || meta == null) {
      _emit(null);
      return null;
    }

    try {
      _endpoint = await resolver.resolve(profile);
    } on EmbyException {
      // Unreachable server must not destroy stored credentials; the gate shows
      // the login screen and a later restore can still succeed.
      _endpoint = null;
      _emit(null);
      return null;
    }

    final session = meta.copyWith(accessToken: token);
    _profile = profile;
    _emit(session);
    return session;
  }

  @override
  Future<ServerProfile?> lastProfile() => _profileStore.read();

  @override
  Future<ServerProfile> adoptAddress({
    required ServerProfile profile,
    required EndpointKind kind,
    required String rawUrl,
  }) async {
    if (profile.serverId.isEmpty) {
      throw EmbyException(
        AppErrorCode.serverMismatch,
        message: 'profile has no server id yet',
      );
    }

    final normalized = UrlNormalizer.normalize(rawUrl);
    if (normalized == null) {
      throw ArgumentError.value(rawUrl, 'rawUrl', 'not an http(s) address');
    }

    final probeProfile = kind == EndpointKind.lan
        ? profile.copyWith(
            lanUrl: normalized,
            preference: EndpointPreference.lan,
          )
        : profile.copyWith(
            wanUrl: normalized,
            preference: EndpointPreference.wan,
          );

    final ResolvedEndpoint endpoint;
    try {
      endpoint = await resolver.resolve(probeProfile, forceRefresh: true);
    } on EmbyException catch (error) {
      if (error.failures.any((f) => f.code == AppErrorCode.serverMismatch)) {
        throw EmbyException(
          AppErrorCode.serverMismatch,
          message: 'address belongs to another server',
          failures: error.failures,
        );
      }
      rethrow;
    }

    final updated = kind == EndpointKind.lan
        ? profile.copyWith(lanUrl: endpoint.baseUrl)
        : profile.copyWith(wanUrl: endpoint.baseUrl);
    await _profileStore.write(updated);
    _profile = updated;
    return updated;
  }

  /// Performs an authenticated GET and logs out on 401 (contract §10.5).
  @override
  Future<Map<String, dynamic>> authorizedGet(Uri url) async {
    final session = _session;
    if (session == null) {
      throw EmbyException(AppErrorCode.unauthorized);
    }

    try {
      return await client.getJson(url, token: session.accessToken);
    } on EmbyException catch (error) {
      if (error.code == AppErrorCode.unauthorized) {
        await handleUnauthorized();
      }
      rethrow;
    }
  }

  /// Same contract as [authorizedGet], for the POST calls of §3.1 / §3.6.
  @override
  Future<Map<String, dynamic>> authorizedPost(Uri url, {Object? body}) async {
    final session = _session;
    if (session == null) {
      throw EmbyException(AppErrorCode.unauthorized);
    }

    try {
      return await client.postJson(url, body: body, token: session.accessToken);
    } on EmbyException catch (error) {
      if (error.code == AppErrorCode.unauthorized) {
        await handleUnauthorized();
      }
      rethrow;
    }
  }

  /// Same contract as [authorizedGet], for the DELETE calls of S8.
  @override
  Future<Map<String, dynamic>> authorizedDelete(Uri url) async {
    final session = _session;
    if (session == null) {
      throw EmbyException(AppErrorCode.unauthorized);
    }

    try {
      return await client.deleteJson(url, token: session.accessToken);
    } on EmbyException catch (error) {
      if (error.code == AppErrorCode.unauthorized) {
        await handleUnauthorized();
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() => handleUnauthorized();

  @override
  Future<void> handleUnauthorized() async {
    await _tokenStore.delete();
    await _sessionStore.delete();
    resolver.invalidate();
    _endpoint = null;
    _profile = null;
    _emit(null);
  }

  void _emit(AuthSession? session) {
    _session = session;
    if (!_controller.isClosed) _controller.add(session);
  }

  Future<void> dispose() => _controller.close();
}
