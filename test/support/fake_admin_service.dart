import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/admin/admin_service.dart';
import 'package:media_player/data/models/admin_info.dart';

/// Configurable read-only admin double for controller/widget tests (S24).
class FakeAdminService implements AdminService {
  FakeAdminService({
    this.admin = true,
    AdminSystemInfo? systemInfo,
    List<AdminUser>? userList,
    List<AdminSessionInfo>? sessionList,
    this.failure,
  }) : systemInfoResult =
           systemInfo ??
           const AdminSystemInfo(
             serverName: 'Home',
             version: '4.10.1.0',
             operatingSystem: 'Linux',
           ),
       userList = userList ?? const <AdminUser>[],
       sessionList = sessionList ?? const <AdminSessionInfo>[];

  /// Answer of [isAdmin]; flip to model a non-admin session.
  bool admin;
  AdminSystemInfo systemInfoResult;
  List<AdminUser> userList;
  List<AdminSessionInfo> sessionList;

  /// When set, every call throws it instead of succeeding.
  EmbyException? failure;

  int isAdminCalls = 0;
  int systemInfoCalls = 0;
  int usersCalls = 0;
  int sessionsCalls = 0;

  @override
  Future<bool> isAdmin() async {
    isAdminCalls++;
    final EmbyException? error = failure;
    if (error != null) throw error;
    return admin;
  }

  @override
  Future<AdminSystemInfo> systemInfo() async {
    systemInfoCalls++;
    final EmbyException? error = failure;
    if (error != null) throw error;
    return systemInfoResult;
  }

  @override
  Future<List<AdminUser>> users() async {
    usersCalls++;
    final EmbyException? error = failure;
    if (error != null) throw error;
    return userList;
  }

  @override
  Future<List<AdminSessionInfo>> sessions() async {
    sessionsCalls++;
    final EmbyException? error = failure;
    if (error != null) throw error;
    return sessionList;
  }
}
