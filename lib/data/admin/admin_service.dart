import '../models/admin_info.dart';

/// Read-only Emby admin queries (S24).
///
/// Declared separately from [AdminRepository] so the admin page can be tested
/// with a fake and never touches HTTP. Deliberately no mutating operations:
/// no user/library deletion, no restart/shutdown, no library refresh.
abstract interface class AdminService {
  /// Whether the signed-in user carries `Policy.IsAdministrator`.
  ///
  /// The session model does not store the policy, so this reads
  /// `GET /Users/{userId}`. False when logged out.
  Future<bool> isAdmin();

  /// `GET /System/Info`: name, version, OS and pending-restart flag.
  Future<AdminSystemInfo> systemInfo();

  /// `GET /Users`: id, name, admin flag and last login of every user.
  Future<List<AdminUser>> users();

  /// `GET /Sessions`: who is connected from which client/device, and what
  /// they are playing right now.
  Future<List<AdminSessionInfo>> sessions();
}
