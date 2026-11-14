import '../models/auth_session.dart';

/// Per-server session surface (S20), kept separate from [AuthService] so the
/// existing single-session callers and their fakes stay untouched.
///
/// `AuthRepository` implements this alongside `AuthService`/`ApiSession`; the
/// multi-server UI reaches it through a cast, and widget tests inject a fake.
/// The single active session remains the source of truth for the connection.
abstract interface class ServerSessionService {
  /// Id of the server the active session belongs to (`default` for the legacy
  /// single-server install).
  String get activeServerId;

  /// Points subsequent login/restore at [serverId] without touching storage.
  /// Used before logging in to a newly added server.
  void useServer(String serverId);

  /// Restores the session stored for [serverId], making it the active one.
  /// Returns null when that server has no session or is unreachable, so the UI
  /// can route to its login screen.
  Future<AuthSession?> restoreServer(String serverId);

  /// Deletes the stored credentials for [serverId] (used when removing a saved
  /// server). Other servers are unaffected.
  Future<void> clearServer(String serverId);
}
