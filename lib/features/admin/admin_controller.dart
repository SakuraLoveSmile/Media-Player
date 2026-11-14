import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/admin/admin_service.dart';
import '../../data/models/admin_info.dart';

/// Immutable snapshot of the admin page (S24).
class AdminState {
  const AdminState({
    this.loading = false,
    this.loaded = false,
    this.forbidden = false,
    this.systemInfo,
    this.users = const <AdminUser>[],
    this.sessions = const <AdminSessionInfo>[],
    this.error,
  });

  final bool loading;

  /// True once at least one load attempt finished, so the spinner is not
  /// shown forever after a failure.
  final bool loaded;

  /// The signed-in user is not an administrator: the page shows 无权限 and
  /// no admin data is requested at all.
  final bool forbidden;

  final AdminSystemInfo? systemInfo;
  final List<AdminUser> users;
  final List<AdminSessionInfo> sessions;
  final String? error;

  static const Object _unset = Object();

  AdminState copyWith({
    bool? loading,
    bool? loaded,
    bool? forbidden,
    Object? systemInfo = _unset,
    List<AdminUser>? users,
    List<AdminSessionInfo>? sessions,
    Object? error = _unset,
  }) {
    return AdminState(
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      forbidden: forbidden ?? this.forbidden,
      systemInfo: identical(systemInfo, _unset)
          ? this.systemInfo
          : systemInfo as AdminSystemInfo?,
      users: users ?? this.users,
      sessions: sessions ?? this.sessions,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

/// Drives the read-only admin page (S24).
///
/// Every load re-checks `isAdmin` first, so a demoted account (or a switched
/// server with a non-admin session) can never render admin data. A generation
/// counter discards answers that arrive after a newer load started.
class AdminController extends ChangeNotifier {
  AdminController(this._service);

  final AdminService _service;

  AdminState _state = const AdminState();
  bool _disposed = false;
  int _seq = 0;

  AdminState get state => _state;

  /// Loads the admin snapshot: gate first, then system info, users and
  /// sessions in parallel.
  Future<void> load() async {
    final int seq = ++_seq;
    _set(_state.copyWith(loading: true, error: null, forbidden: false));
    try {
      final bool admin = await _service.isAdmin();
      if (_disposed || seq != _seq) return;
      if (!admin) {
        _set(
          _state.copyWith(
            loading: false,
            loaded: true,
            forbidden: true,
            systemInfo: null,
            users: const <AdminUser>[],
            sessions: const <AdminSessionInfo>[],
          ),
        );
        return;
      }
      final (
        AdminSystemInfo info,
        List<AdminUser> users,
        List<AdminSessionInfo> sessions,
      ) = await (
        _service.systemInfo(),
        _service.users(),
        _service.sessions(),
      ).wait;
      if (_disposed || seq != _seq) return;
      _set(
        _state.copyWith(
          loading: false,
          loaded: true,
          systemInfo: info,
          users: users,
          sessions: sessions,
        ),
      );
    } on EmbyException catch (error) {
      if (_disposed || seq != _seq) return;
      _set(
        _state.copyWith(
          loading: false,
          loaded: true,
          error: adminErrorMessage(error.code),
        ),
      );
    } catch (_) {
      if (_disposed || seq != _seq) return;
      _set(_state.copyWith(loading: false, loaded: true, error: '加载失败，请稍后重试'));
    }
  }

  void _set(AdminState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Maps a data-layer failure to admin copy (contract §6).
String adminErrorMessage(AppErrorCode code) {
  return switch (code) {
    AppErrorCode.unauthorized => '登录已过期，请重新登录',
    AppErrorCode.forbidden => '没有管理员权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    _ => '加载失败，请稍后重试',
  };
}
