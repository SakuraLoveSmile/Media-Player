import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/servers.dart';
import '../core/router/app_routes.dart';
import '../data/models/server_entry.dart';
import 'app_loader.dart';
import 'app_page.dart';
import 'server_card.dart';
import 'server_dialogs.dart';

/// 服务器 list (S20/S28/S80): shared by the settings section and the /servers
/// page.
///
/// Each saved server is one Yamby-style card: the server glyph, the name, an
/// online dot and the optional user name / last-played time. Tapping a card
/// switches to that server; the trailing ⋮ opens the per-server menu (显示名称 /
/// 编辑 / 自定义图标 / 显示用户名 / 显示上次播放时间 / 添加备选地址 / 删除).
/// Names and addresses are non-secret; credentials stay in the secure
/// per-server stores, so switching restores the target session or routes to its
/// login.
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
      footer: '点按卡片切换服务器；切换会恢复该服务器的登录状态，未登录的服务器需要重新登录',
      children: <Widget>[
        // S79: while the directory is still resolving, say so instead of
        // showing a section that looks like it has no servers.
        if (state.servers.isEmpty && async.isLoading)
          const ListTile(
            key: Key('settings-server-loading'),
            leading: SizedBox.square(dimension: 22, child: AppLoader(size: 22)),
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
          ServerCard(
            entry: entry,
            active: entry.id == state.activeId,
            userName: userName,
            online: state.online[entry.id],
            onTap: () => unawaited(_switch(context, ref, entry.id)),
            onMenu: (BuildContext anchor) =>
                unawaited(_openMenu(context, ref, entry, state, anchor)),
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
    final ServersState current =
        ref.read(serversControllerProvider).value ?? ServersState.empty;
    if (current.activeId == id) return;
    final session = await ref.read(serversControllerProvider.notifier).switchTo(id);
    if (!context.mounted) return;
    context.go(session == null ? AppRoutes.loginFor(id) : AppRoutes.home);
  }

  /// The anchored ⋮ menu (S80), positioned under the button that opened it.
  Future<void> _openMenu(
    BuildContext context,
    WidgetRef ref,
    ServerEntry entry,
    ServersState state,
    BuildContext anchor,
  ) async {
    final RenderBox button = anchor.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final _ServerAction? action = await showMenu<_ServerAction>(
      context: context,
      position: position,
      items: <PopupMenuEntry<_ServerAction>>[
        _item(_ServerAction.rename, '显示名称', Icons.drive_file_rename_outline),
        _item(_ServerAction.edit, '编辑', Icons.edit_outlined),
        _item(_ServerAction.icon, '自定义图标', Icons.emoji_emotions_outlined),
        _item(
          _ServerAction.toggleUserName,
          '显示用户名',
          entry.showUserName ? Icons.check_circle : Icons.radio_button_unchecked,
        ),
        _item(
          _ServerAction.toggleLastPlayed,
          '显示上次播放时间',
          entry.showLastPlayed
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
        ),
        _item(
          _ServerAction.alternateAddress,
          '添加备选地址',
          Icons.alt_route_outlined,
        ),
        const PopupMenuDivider(),
        _item(_ServerAction.delete, '删除', Icons.delete_outline),
      ],
    );
    if (action == null || !context.mounted) return;

    final ServersController controller = ref.read(
      serversControllerProvider.notifier,
    );
    switch (action) {
      case _ServerAction.rename:
        final String? name = await showServerNameDialog(
          context,
          initial: entry.name,
        );
        if (name != null) await controller.rename(entry.id, name);
      case _ServerAction.edit:
        final ServerEntry? edited = await showServerEditDialog(
          context,
          entry: entry,
        );
        if (edited != null) {
          await controller.updateEntry(entry.id, (_) => edited);
        }
      case _ServerAction.icon:
        final String? icon = await showServerIconDialog(
          context,
          selected: entry.customIcon,
        );
        if (icon != null) {
          await controller.updateEntry(
            entry.id,
            (ServerEntry e) => e.copyWith(customIcon: icon),
          );
        }
      case _ServerAction.toggleUserName:
        await controller.updateEntry(
          entry.id,
          (ServerEntry e) => e.copyWith(showUserName: !e.showUserName),
        );
      case _ServerAction.toggleLastPlayed:
        await controller.updateEntry(
          entry.id,
          (ServerEntry e) => e.copyWith(showLastPlayed: !e.showLastPlayed),
        );
      case _ServerAction.alternateAddress:
        final ServerEntry? edited = await showServerEditDialog(
          context,
          entry: entry,
          addressOnly: true,
        );
        if (edited != null) {
          await controller.updateEntry(entry.id, (_) => edited);
        }
      case _ServerAction.delete:
        if (!context.mounted) return;
        await _delete(context, ref, entry.id);
    }
  }

  PopupMenuItem<_ServerAction> _item(
    _ServerAction action,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem<_ServerAction>(
      key: Key('server-action-${action.name}'),
      value: action,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
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

/// Rows of the per-server menu.
enum _ServerAction {
  rename,
  edit,
  icon,
  toggleUserName,
  toggleLastPlayed,
  alternateAddress,
  delete,
}
