import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/servers.dart';
import '../../core/router/app_routes.dart';
import '../../ui/app_bottom_nav.dart';
import '../../ui/app_page.dart';
import '../../ui/servers_section.dart';

/// Saved-server management (S28/S55), opened from the home header's server
/// icon. Reuses the settings section so switching, adding and removing servers
/// has exactly one implementation; the current user is shown on the active
/// card and 添加 gets its own floating button, like Yamby.
class ServersPage extends ConsumerStatefulWidget {
  const ServersPage({super.key});

  @override
  ConsumerState<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends ConsumerState<ServersPage> {
  @override
  void initState() {
    super.initState();
    // S64: one reachability pass per visit, after the list has loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_probe());
    });
  }

  Future<void> _probe() async {
    try {
      await ref.read(serversControllerProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await ref.read(serversControllerProvider.notifier).probeOnline();
  }

  @override
  Widget build(BuildContext context) {
    final String userName =
        ref.watch(bootstrapProvider).value?.auth.current?.userName ?? '';
    return AppPage(
      title: '服务器',
      onBack: () => context.pop(),
      floatingActionButton: FloatingActionButton(
        key: const Key('servers-add-fab'),
        tooltip: '添加服务器',
        onPressed: () => context.go(AppRoutes.loginAdd()),
        child: const Icon(Icons.add),
      ),
      // S76: Yamby keeps its capsule nav on the servers page too.
      bottomNavigationBar: const AppBottomNav(current: AppNavDestination.home),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: <Widget>[ServerSettingsSection(userName: userName)],
      ),
    );
  }
}
