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
import '../models/server_profile.dart';
import '../storage/profile_store.dart';
import '../storage/session_store.dart';
import '../storage/token_store.dart';
import 'auth_service.dart';

/// Login, session restore and logout (contract §1.4, §7, §10.5).
class AuthRepository implements AuthService {
  AuthRepository({
    required this.client,
    required this.resolver,
    required this.tokenStore,
    required this.sessionStore,
    required this.profileStore,
    required this.deviceId,
    this.clientName = AppConfig.clientName,
    this.deviceName = '',
    this.appVersion = AppConfig.appVersion,
  });

  final EmbyHttpClient client;
  final EndpointResolver resolver;
  final TokenStore tokenStore;
  final SessionStore sessionStore;
  final ProfileStore profileStore;
  final String deviceId;
  final String clientName;
  final String deviceName;
  final String appVersion;

  final StreamController<AuthSession?> _controller =
      StreamController<AuthSession?>.broadcast();

  AuthSession? _session;
  ResolvedEndpoint? _endpoint;

  @override
  AuthSession? get current => _session;

  @override
  Stream<AuthSession?> get session => _controller.stream;

  /// Endpoint used by the current session; all URLs must be derived from it.
  ResolvedEndpoint? get endpoint => _endpoint;

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
        deviceId: deviceId,
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
      deviceId: deviceId,
    );

    await tokenStore.write(accessToken);
    await sessionStore.write(session);

    final storedProfile = profile.copyWith(
      serverId: responseServerId,
      lastGoodEndpoint: endpoint.kind,
    );
    await profileStore.write(storedProfile);

    _endpoint = endpoint;
    _emit(session);
    return session;
  }

  @override
  Future<AuthSession?> restore() async {
    final profile = await profileStore.read();
    final token = await tokenStore.read();
    final meta = await sessionStore.read();
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
    _emit(session);
    return session;
  }

  @override
  Future<ServerProfile?> lastProfile() => profileStore.read();

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
    await profileStore.write(updated);
    return updated;
  }

  /// Performs an authenticated GET and logs out on 401 (contract §10.5).
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

  @override
  Future<void> logout() => handleUnauthorized();

  @override
  Future<void> handleUnauthorized() async {
    await tokenStore.delete();
    await sessionStore.delete();
    resolver.invalidate();
    _endpoint = null;
    _emit(null);
  }

  void _emit(AuthSession? session) {
    _session = session;
    if (!_controller.isClosed) _controller.add(session);
  }

  Future<void> dispose() => _controller.close();
}
