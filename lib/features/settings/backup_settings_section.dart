import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/backup_settings.dart';
import '../../data/storage/backup_service.dart';
import '../../ui/app_page.dart';

/// 备份/还原 settings (S22): export the whitelisted preferences to a JSON file
/// and restore them back. Credentials are never included; the service owns the
/// whitelist. Some preferences only apply on the next launch or reload, so a
/// successful import says so rather than forcing a live repaint.
class BackupSettingsSection extends ConsumerWidget {
  const BackupSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<BackupService?> async = ref.watch(backupServiceProvider);
    final BackupService? service = async.value;
    final bool loading = async.isLoading;

    return AppSection(
      header: '备份/还原',
      footer: '仅备份偏好设置，不含账号凭据；部分设置在下次启动或刷新后生效',
      children: <Widget>[
        ListTile(
          key: const Key('settings-backup-export'),
          enabled: !loading && service != null,
          leading: Icon(Icons.upload_file_outlined, color: palette.primary),
          title: const Text('导出备份'),
          subtitle: const Text('将偏好设置保存为 JSON 文件'),
          trailing: _trailing(loading, palette),
          onTap: loading || service == null
              ? null
              : () => unawaited(_export(context, service)),
        ),
        ListTile(
          key: const Key('settings-backup-restore'),
          enabled: !loading && service != null,
          leading: Icon(Icons.download_outlined, color: palette.primary),
          title: const Text('导入备份'),
          subtitle: const Text('从 JSON 文件恢复偏好设置'),
          trailing: _trailing(loading, palette),
          onTap: loading || service == null
              ? null
              : () => unawaited(_restore(context, service)),
        ),
      ],
    );
  }

  Widget _trailing(bool loading, ColorScheme palette) {
    if (loading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(Icons.chevron_right, color: palette.outline, size: 20);
  }

  /// Exports then saves; a cancelled dialog stays silent, a failure warns.
  Future<void> _export(BuildContext context, BackupService service) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final bool saved = await service.exportToFile();
      if (!context.mounted || !saved) return;
      messenger.showSnackBar(const SnackBar(content: Text('备份已导出')));
    } on BackupException catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导出失败：${error.message}')));
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('导出失败，请稍后重试')));
    }
  }

  /// Opens then restores; a cancelled dialog stays silent, a bad file warns.
  Future<void> _restore(BuildContext context, BackupService service) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final bool restored = await service.importFromFile();
      if (!context.mounted || !restored) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('备份已导入，部分设置在下次启动或刷新后生效')),
      );
    } on BackupException catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败：${error.message}')));
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('导入失败，请稍后重试')));
    }
  }
}
