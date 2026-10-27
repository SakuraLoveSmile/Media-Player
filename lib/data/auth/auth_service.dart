import '../../core/network/endpoint_kind.dart';
import '../models/auth_session.dart';
import '../models/server_profile.dart';

/// Session-facing surface consumed by the UI and by other repositories.
///
/// Declared separately from [AuthRepository] so widgets can be tested with a
/// fake and never touch HTTP or storage.
abstract interface class AuthService {
  AuthSession? get current;

  /// Emits the session on login/restore and `null` on logout or 401.
  Stream<AuthSession?> get session;

  Future<AuthSession> login({
    required String username,
    required String password,
    required ServerProfile profile,
  });

  Future<AuthSession?> restore();

  /// Last stored profile, used to prefill the login form (addresses only;
  /// never credentials). Null when nothing has been stored yet.
  Future<ServerProfile?> lastProfile();

  /// Adds or replaces one address; rejects a different server id with
  /// `serverMismatch` (contract §1.4).
  Future<ServerProfile> adoptAddress({
    required ServerProfile profile,
    required EndpointKind kind,
    required String rawUrl,
  });

  Future<void> logout();

  /// Called when a business request returns 401 (contract §10.5).
  Future<void> handleUnauthorized();
}
