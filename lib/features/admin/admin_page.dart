import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/admin_providers.dart';
import '../../data/admin/admin_service.dart';
import '../../data/models/admin_info.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loader.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';
import 'admin_controller.dart';

/// Read-only server administration (S24): 服务器信息, 用户 and 活跃会话.
///
/// The settings entry is admin-only, but the route itself is guarded too: the
/// controller re-checks `isAdmin` on every load, so direct navigation by a
/// non-admin session renders 无权限 instead of data. No mutating actions.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  AdminController? _controller;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final AdminService? service = await ref.read(adminServiceProvider.future);
      if (!mounted) return;
      if (service == null) {
        setState(() => _fatal = '服务器管理不可用');
        return;
      }
      final AdminController controller = AdminController(service)
        ..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '服务器管理加载失败，请稍后重试');
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AdminController? controller = _controller;
    final AdminState? state = controller?.state;
    return AppPage(
      title: '服务器管理',
      onBack: () => context.pop(),
      actions: <Widget>[
        AppIconButton(
          key: const Key('admin-refresh'),
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: controller == null
              ? null
              : () => unawaited(controller.load()),
        ),
      ],
      child: _body(controller, state),
    );
  }

  Widget _body(AdminController? controller, AdminState? state) {
    final String? fatal = _fatal;
    if (fatal != null) {
      return _MessageCard(icon: Icons.error_outline, title: fatal);
    }
    if (controller == null || state == null) {
      return const AppLoadingView();
    }
    if (state.forbidden) {
      return const _MessageCard(
        key: Key('admin-forbidden'),
        icon: Icons.lock_outline,
        title: '无权限',
        message: '仅管理员可以访问服务器管理',
      );
    }
    if (state.error != null) {
      return _MessageCard(
        key: const Key('admin-error'),
        icon: Icons.cloud_off_outlined,
        title: state.error!,
        action: AppButton(
          key: const Key('admin-retry'),
          label: '重试',
          variant: AppButtonVariant.tinted,
          onPressed: () => unawaited(controller.load()),
        ),
      );
    }
    if (state.loading && !state.loaded) {
      return const AppLoadingView();
    }
    return _content(state);
  }

  Widget _content(AdminState state) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AdminSystemInfo? info = state.systemInfo;
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: <Widget>[
        AppSection(
          header: '服务器信息',
          footer: info != null && info.hasPendingRestart ? '服务器有等待重启的更新' : null,
          children: <Widget>[
            ListTile(
              leading: Icon(Icons.dns_outlined, color: palette.primary),
              title: const Text('服务器名称'),
              subtitle: Text(
                info == null || info.serverName.isEmpty
                    ? '未知'
                    : info.serverName,
              ),
            ),
            ListTile(
              leading: Icon(Icons.tag_outlined, color: palette.primary),
              title: const Text('版本'),
              subtitle: Text(
                info == null || info.version.isEmpty ? '未知' : info.version,
              ),
            ),
            ListTile(
              leading: Icon(Icons.memory_outlined, color: palette.primary),
              title: const Text('操作系统'),
              subtitle: Text(
                info == null || info.operatingSystem.isEmpty
                    ? '未知'
                    : info.operatingSystem,
              ),
            ),
          ],
        ),
        AppSection(
          header: '用户',
          children: <Widget>[
            if (state.users.isEmpty)
              const ListTile(title: Text('没有用户'))
            else
              for (final AdminUser user in state.users)
                _UserRow(user: user, palette: palette),
          ],
        ),
        AppSection(
          header: '活跃会话',
          children: <Widget>[
            if (state.sessions.isEmpty)
              const ListTile(title: Text('当前没有活跃会话'))
            else
              for (final AdminSessionInfo session in state.sessions)
                _SessionRow(session: session, palette: palette),
          ],
        ),
      ],
    );
  }
}

/// One user row: name, an admin badge and the last login time.
class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.palette});

  final AdminUser user;
  final ColorScheme palette;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        user.isAdministrator
            ? Icons.admin_panel_settings_outlined
            : Icons.person_outline,
        color: palette.primary,
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              user.name.isEmpty ? '未命名用户' : user.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (user.isAdministrator) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            AppTag(label: '管理员', color: palette.primary, dense: true),
          ],
        ],
      ),
      subtitle: Text(_lastLoginLabel(user.lastLoginDate)),
    );
  }
}

/// One session row: user, client/device and what is playing right now.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.palette});

  final AdminSessionInfo session;
  final ColorScheme palette;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? nowPlaying = session.nowPlayingName;
    return ListTile(
      leading: Icon(Icons.devices_outlined, color: palette.primary),
      title: Text(session.userName.isEmpty ? '未知用户' : session.userName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_deviceLabel(session)),
          if (nowPlaying != null)
            Text(
              '正在播放：$nowPlaying · ${_positionLabel(session.positionTicks)}',
              style: text.bodySmall!.copyWith(color: palette.primary),
            )
          else
            const Text('空闲'),
        ],
      ),
    );
  }
}

/// A centered status card (无权限 / load failure), mirroring the empty states
/// of the 求片 pages.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: AppCard(
          radius: AppRadii.cardLarge,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 32, color: palette.outline),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.titleMedium!.copyWith(color: palette.onSurface),
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: text.bodySmall!.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _lastLoginLabel(DateTime? date) {
  if (date == null) return '从未登录';
  final DateTime local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '上次登录：${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _deviceLabel(AdminSessionInfo session) {
  final List<String> parts = <String>[
    if (session.client.isNotEmpty) session.client,
    if (session.deviceName.isNotEmpty) session.deviceName,
  ];
  return parts.isEmpty ? '未知设备' : parts.join(' · ');
}

/// Ticks → `h:mm:ss`, the same shape the home dashboard uses.
String _positionLabel(int ticks) {
  final Duration total = Duration(microseconds: ticks ~/ 10);
  final String minutes = total.inMinutes
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  final String seconds = total.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  if (total.inHours > 0) {
    return '${total.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
