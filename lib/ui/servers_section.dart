import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/servers.dart';
import '../core/router/app_routes.dart';
import '../data/models/server_entry.dart';
import 'app_loader.dart';
import 'app_page.dart';

/// 服务器 list (S20/S28): shared by the settings section and the /servers page.
///
/// List the saved servers, highlight the active one and offer 切换 / 添加 / 删除. Names and addresses are non-secret; credentials stay
/// in the secure per-server stores. Switching restores the target session or
/// routes to its login; adding opens the login flow for a brand-new entry.
class ServerSettingsSection extends ConsumerWidget {
  const ServerSettingsSection({super.key, this.userName});

  /// Current user shown on the active card (S55); null hides it.
  final String? userName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<ServersState> async = ref.watch(serversControllerProvider);
    final ServersState state = async.value ?? ServersState.empty;

    return AppSection(
      header: '服务器',
      footer: '切换会恢复该服务器的登录状态；未登录的服务器需要重新登录',
      children: <Widget>[
        // S79: while the directory is still resolving, say so instead of
        // showing a section that looks like it has no servers.
        if (state.servers.isEmpty && async.isLoading)
          const ListTile(
            key: Key('settings-server-loading'),
            leading: SizedBox.square(
              dimension: 22,
              child: AppLoader(size: 22),
            ),
            title: Text('正在加载服务器…'),
          ),
        if (state.servers.isEmpty && !async.isLoading)
          ListTile(
            key: const Key('settings-server-empty'),
            leading: Icon(Icons.dns_outlined, color: palette.outline),
            title: const Text('暂无保存的服务器'),
            subtitle: const Text('添加一台 Emby 服务器开始使用'),
          ),
        for (final ServerEntry entry in state.servers)
          _ServerTile(
            entry: entry,
            active: entry.id == state.activeId,
            userName: userName,
            online: state.online[entry.id],
            palette: palette,
            onSwitch: () => unawaited(_switch(context, ref, entry.id)),
            onDelete: () => unawaited(_delete(context, ref, entry.id)),
          ),
        ListTile(
          key: const Key('settings-server-add'),
          leading: Icon(Icons.add_circle_outline, color: palette.primary),
          title: const Text('添加服务器'),
          subtitle: const Text('连接另一台 Emby 服务器'),
          trailing: Icon(Icons.chevron_right, color: palette.outline, size: 20),
          onTap: () => context.go(AppRoutes.loginAdd()),
        ),
      ],
    );
  }

  Future<void> _switch(BuildContext context, WidgetRef ref, String id) async {
    final session = await ref
        .read(serversControllerProvider.notifier)
        .switchTo(id);
    if (!context.mounted) return;
    context.go(session == null ? AppRoutes.loginFor(id) : AppRoutes.home);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? newActive = await ref
        .read(serversControllerProvider.notifier)
        .remove(id);
    if (!context.mounted) return;
    if (newActive != null) {
      // The active server was removed; re-run the restore-first gate so the app
      // lands on another server's session or its login screen.
      context.go(AppRoutes.startup);
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('已删除服务器')));
    }
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.entry,
    required this.active,
    required this.userName,
    required this.palette,
    this.online,
    required this.onSwitch,
    required this.onDelete,
  });

  final ServerEntry entry;
  final bool active;
  final String? userName;
  final ColorScheme palette;

  /// S64: reachability of this server; null while unknown.
  final bool? online;
  final VoidCallback onSwitch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String title = entry.name.isEmpty ? entry.addressLabel : entry.name;
    final String address = entry.addressLabel;
    final String user = userName ?? '';
    final String subtitle = !active
        ? address
        : user.isEmpty
        ? '$address · 当前'
        : '$address · 当前 · $user';
    return ListTile(
      key: Key('server-${entry.id}'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            active ? Icons.check_circle : Icons.dns_outlined,
            color: active ? palette.primary : palette.outline,
          ),
          if (online != null) ...<Widget>[
            const SizedBox(width: 6),
            Container(
              key: Key('server-online-${entry.id}'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online! ? const Color(0xFF4CAF50) : palette.outline,
              ),
            ),
          ],
        ],
      ),
      title: Text(
        title,
        style: TextStyle(
          color: palette.onSurface,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextButton(
            key: Key('server-switch-${entry.id}'),
            onPressed: onSwitch,
            child: const Text('切换'),
          ),
          IconButton(
            key: Key('server-delete-${entry.id}'),
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            color: palette.outline,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
