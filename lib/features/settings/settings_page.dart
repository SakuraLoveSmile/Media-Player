import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/feedback_config.dart';
import '../../app/feedback_orb_settings.dart';
import '../../app/update_providers.dart';
import '../../app/update_channel_settings.dart';
import '../../core/config/app_config.dart';
import '../../data/update/update_models.dart';
import 'update_dialog.dart';

/// Settings: about, manual update check, and the optional feedback entries.
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
    final channel = ref.watch(updateChannelControllerProvider).value ??
        UpdateChannel.stable;
    final packageInfo = ref.watch(appVersionProvider).value;
    final version = packageInfo == null
        ? AppConfig.appVersion
        : '${packageInfo.version}+${packageInfo.buildNumber}';
    // The feedback entries only exist while the feedback service is configured.
    final feedbackEnabled = ref.watch(feedbackServiceConfigProvider) != null;
    final AsyncValue<FeedbackOrbSettings>? orbSettings = feedbackEnabled
        ? ref.watch(feedbackOrbSettingsProvider)
        : null;

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
          const ListTile(
            leading: Icon(Icons.new_releases_outlined),
            title: Text('更新渠道'),
            subtitle: Text('正式版只接收正式发布；预览版还包含预发布构建'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<UpdateChannel>(
              segments: const <ButtonSegment<UpdateChannel>>[
                ButtonSegment<UpdateChannel>(
                  value: UpdateChannel.stable,
                  label: Text('正式版'),
                ),
                ButtonSegment<UpdateChannel>(
                  value: UpdateChannel.preview,
                  label: Text('预览版'),
                ),
              ],
              selected: <UpdateChannel>{channel},
              onSelectionChanged: checking
                  ? null
                  : (Set<UpdateChannel> selection) => unawaited(
                        _selectChannel(context, ref, selection.first),
                      ),
            ),
          ),
          ListTile(
            enabled: !checking,
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('检查更新'),
            subtitle: checking
                ? const Text('检查中…')
                : Text('渠道：${channel.label}'),
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
            const _SectionHeader(title: '反馈'),
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('问题反馈'),
              subtitle: const Text('截图并描述问题，提交到反馈服务'),
              onTap: () => unawaited(
                ref.read(feedbackControllerProvider).captureAndOpen(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.circle_outlined),
              title: const Text('灵感球样式'),
              subtitle: Text(_orbSettingsSubtitle(orbSettings, (settings) {
                return '当前：${_idleStyleLabel(settings.idleStyle)}';
              })),
              trailing: _orbSettingsTrailing(orbSettings),
              onTap: orbSettings == null
                  ? null
                  : () => unawaited(
                        _pickOrbIdleStyle(context, ref, orbSettings),
                      ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.gesture),
              title: const Text('唤醒灵感球'),
              subtitle: Text(_orbSettingsSubtitle(orbSettings, (settings) {
                return '当前：${_wakeGesturesLabel(settings.wakeGestures)}';
              })),
              trailing: _orbSettingsTrailing(orbSettings),
              onTap: orbSettings == null
                  ? null
                  : () => unawaited(
                        _pickWakeGestures(context, ref, orbSettings),
                      ),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Persists the channel preference; failures keep the previous selection.
  Future<void> _selectChannel(
    BuildContext context,
    WidgetRef ref,
    UpdateChannel channel,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(updateChannelControllerProvider.notifier)
          .setChannel(channel);
    } on UpdateChannelSettingsException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
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

  String _orbSettingsSubtitle(
    AsyncValue<FeedbackOrbSettings>? async,
    String Function(FeedbackOrbSettings) describe,
  ) {
    if (async == null) return '';
    if (async.isLoading) return '读取中…';
    final FeedbackOrbSettings? value = async.value;
    if (value == null) return '读取失败，点击重试';
    return describe(value);
  }

  Widget? _orbSettingsTrailing(AsyncValue<FeedbackOrbSettings>? async) {
    if (async == null || !async.isLoading) return null;
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Future<void> _pickOrbIdleStyle(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<FeedbackOrbSettings> async,
  ) async {
    if (async.hasError) {
      ref.invalidate(feedbackOrbSettingsProvider);
      return;
    }
    final FeedbackOrbSettings? current = async.value;
    if (current == null) return;
    final FeedbackOrbIdleStyle? selected =
        await showDialog<FeedbackOrbIdleStyle>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('灵感球样式'),
        children: <Widget>[
          for (final FeedbackOrbIdleStyle style
              in FeedbackOrbIdleStyle.values)
            ListTile(
              leading: Icon(
                current.idleStyle == style
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(_idleStyleLabel(style)),
              subtitle: Text(_idleStyleDescription(style)),
              onTap: () => Navigator.of(dialogContext).pop(style),
            ),
        ],
      ),
    );
    if (selected == null || selected == current.idleStyle) return;
    if (!context.mounted) return;
    await _saveOrbSettings(
      context,
      ref.read(feedbackOrbSettingsProvider.notifier).setIdleStyle(selected),
    );
  }

  Future<void> _pickWakeGestures(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<FeedbackOrbSettings> async,
  ) async {
    if (async.hasError) {
      ref.invalidate(feedbackOrbSettingsProvider);
      return;
    }
    final FeedbackOrbSettings? current = async.value;
    if (current == null) return;
    final Set<FeedbackWakeGesture> draft = <FeedbackWakeGesture>{
      ...current.wakeGestures,
    };
    final Set<FeedbackWakeGesture>? selected =
        await showDialog<Set<FeedbackWakeGesture>>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('唤醒灵感球'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('默认关闭；只在 App 内生效，松手后再拖球截图。'),
                    ),
                    const SizedBox(height: 8),
                    for (final FeedbackWakeGesture gesture
                        in FeedbackWakeGesture.values)
                      CheckboxListTile(
                        value: draft.contains(gesture),
                        onChanged: (bool? enabled) {
                          setState(() {
                            if (enabled == true) {
                              draft.add(gesture);
                            } else {
                              draft.remove(gesture);
                            }
                          });
                        },
                        title: Text(gesture.title),
                        subtitle: Text(gesture.description),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(Set.of(draft)),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected == null) return;
    if (!context.mounted) return;
    await _saveOrbSettings(
      context,
      ref.read(feedbackOrbSettingsProvider.notifier).setWakeGestures(selected),
    );
  }

  Future<void> _saveOrbSettings(BuildContext context, Future<void> save) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await save;
    } on FeedbackOrbSettingsException catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

String _idleStyleLabel(FeedbackOrbIdleStyle style) {
  return switch (style) {
    FeedbackOrbIdleStyle.handle => '小把手',
    FeedbackOrbIdleStyle.edge => '球体贴边',
    FeedbackOrbIdleStyle.hidden => '隐藏',
  };
}

String _idleStyleDescription(FeedbackOrbIdleStyle style) {
  return switch (style) {
    FeedbackOrbIdleStyle.handle => '闲置后收成右侧小把手',
    FeedbackOrbIdleStyle.edge => '闲置后贴边显示半个球',
    FeedbackOrbIdleStyle.hidden => '闲置时隐藏入口；完整球与唤醒手势仍可用',
  };
}

String _wakeGesturesLabel(Set<FeedbackWakeGesture> gestures) {
  if (gestures.isEmpty) return '已关闭';
  return <String>[
    for (final FeedbackWakeGesture gesture in FeedbackWakeGesture.values)
      if (gestures.contains(gesture)) gesture.title,
  ].join('、');
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
