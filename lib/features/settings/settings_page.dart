import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/feedback_config.dart';
import '../../app/update_providers.dart';
import '../../core/config/app_config.dart';
import 'update_dialog.dart';

/// Settings: about, manual update check and the optional feedback entry.
///
/// The route itself is registered by the app shell, so this page never
/// touches navigation on its own.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateStatus = ref.watch(
      updateControllerProvider.select((state) => state.status),
    );
    final checking = updateStatus == UpdateStatus.checking;
    final packageInfo = ref.watch(appVersionProvider).value;
    final version = packageInfo == null
        ? AppConfig.appVersion
        : '${packageInfo.version}+${packageInfo.buildNumber}';
    // The entry point only exists while the feedback service is configured.
    final feedbackEnabled = ref.watch(feedbackServiceConfigProvider) != null;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: <Widget>[
          const _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text(AppConfig.appName),
            subtitle: Text('版本 $version'),
          ),
          const Divider(height: 1),
          ListTile(
            enabled: !checking,
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('检查更新'),
            subtitle: checking ? const Text('检查中…') : null,
            trailing: checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: checking
                ? null
                : () => unawaited(_checkForUpdate(context, ref)),
          ),
          const Divider(height: 1),
          if (feedbackEnabled) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('问题反馈'),
              onTap: () => unawaited(
                ref.read(feedbackControllerProvider).captureAndOpen(),
              ),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Runs one check, then reports the outcome. `check()` itself ignores
  /// concurrent taps, so the UI can stay simple here.
  Future<void> _checkForUpdate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(updateControllerProvider.notifier).check();
    if (!context.mounted) return;

    final state = ref.read(updateControllerProvider);
    switch (state.status) {
      case UpdateStatus.available:
        await showUpdateDialog(context);
      case UpdateStatus.error:
        messenger.showSnackBar(
          SnackBar(content: Text(state.errorMessage ?? '检查更新失败，请稍后重试')),
        );
      case UpdateStatus.idle:
        messenger.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      case UpdateStatus.checking:
      case UpdateStatus.downloading:
      case UpdateStatus.downloaded:
      case UpdateStatus.installing:
        break;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
