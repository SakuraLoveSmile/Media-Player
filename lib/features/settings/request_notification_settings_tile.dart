import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/request_notification_settings.dart';
import '../../data/notifications/local_notification_sink.dart';

/// Settings entry for the 求片 notifications.
///
/// Two independent switches because the two channels can be blocked separately
/// by the OS: a user whose system notifications are denied can keep the in-app
/// banner without being told "notifications are on" while nothing appears.
class RequestNotificationSwitchTile extends ConsumerWidget {
  const RequestNotificationSwitchTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<RequestNotificationSettings> async = ref.watch(
      requestNotificationSettingsProvider,
    );
    final RequestNotificationSettings? settings = async.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          key: const Key('settings-request-notify-system'),
          leading: Icon(
            Icons.notifications_active_outlined,
            color: palette.primary,
          ),
          title: const Text('系统通知'),
          subtitle: Text(
            settings == null
                ? (async.hasError ? '读取失败，点击重试' : '读取中…')
                : (settings.system ? '求片入库时弹出系统通知' : '已关闭，只在应用内提示'),
          ),
          trailing: settings == null
              ? (async.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null)
              : Switch.adaptive(
                  value: settings.system,
                  onChanged: (bool value) =>
                      unawaited(_toggle(context, ref, system: value)),
                ),
          onTap: settings == null && async.hasError
              ? () => ref.invalidate(requestNotificationSettingsProvider)
              : null,
        ),
        ListTile(
          key: const Key('settings-request-notify-inapp'),
          leading: Icon(Icons.campaign_outlined, color: palette.tertiary),
          title: const Text('应用内横幅'),
          subtitle: Text(
            settings == null
                ? ''
                : (settings.inApp ? '在任何页面顶部提示，点一下进入我的求片' : '已关闭'),
          ),
          trailing: settings == null
              ? null
              : Switch.adaptive(
                  value: settings.inApp,
                  onChanged: (bool value) =>
                      unawaited(_toggle(context, ref, inApp: value)),
                ),
        ),
      ],
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref, {
    bool? inApp,
    bool? system,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    // Turning the system channel on is the moment to ask the OS, not at
    // startup: a permission prompt before the user asked for anything is how
    // apps get a permanent denial.
    if (system == true && LocalRequestNotificationSink.isSupportedPlatform) {
      try {
        await LocalRequestNotificationSink().requestPermission();
      } catch (error) {
        debugPrint('[request] 通知权限申请失败：$error');
      }
    }
    try {
      await ref
          .read(requestNotificationSettingsProvider.notifier)
          .set(inApp: inApp, system: system);
    } on RequestNotificationSettingsException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
