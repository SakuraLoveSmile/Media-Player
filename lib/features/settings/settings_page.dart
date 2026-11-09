import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/feedback_config.dart';
import '../../app/feedback_orb_settings.dart';
import '../../app/update_channel_settings.dart';
import '../../app/update_providers.dart';
import '../../core/config/app_config.dart';
import '../../core/router/app_routes.dart';
import '../../data/update/update_models.dart';
import '../../ui/glass/glass_controls.dart';
import '../../ui/glass/glass_shell.dart';
import '../../ui/glass/glass_surface.dart';
import '../../ui/glass/glass_theme.dart';
import '../../ui/glass/glass_tokens.dart';
import 'moviepilot_config_dialog.dart';
import 'update_dialog.dart';

/// Settings: about, manual update check, and the optional feedback entries.
///
/// The route itself is registered by the app shell, so this page never
/// touches navigation on its own.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GlassPalette palette = context.glass;
    final UpdateStatus updateStatus = ref.watch(
      updateControllerProvider.select((UpdateState state) => state.status),
    );
    final bool checking = updateStatus == UpdateStatus.checking;
    final UpdateChannel channel =
        ref.watch(updateChannelControllerProvider).value ?? UpdateChannel.stable;
    final packageInfo = ref.watch(appVersionProvider).value;
    final String version = packageInfo == null
        ? AppConfig.appVersion
        : '${packageInfo.version}+${packageInfo.buildNumber}';
    // The feedback entries only exist while the feedback service is configured.
    final bool feedbackEnabled =
        ref.watch(feedbackServiceConfigProvider) != null;
    final AsyncValue<FeedbackOrbSettings>? orbSettings = feedbackEnabled
        ? ref.watch(feedbackOrbSettingsProvider)
        : null;

    return GlassPage(
      title: '设置',
      onBack: () => context.pop(),
      child: ListView(
        padding: const EdgeInsets.only(
          top: GlassHeaderMetrics.expandedHeight,
          bottom: GlassSpacing.xxxl,
        ),
        children: <Widget>[
          GlassSection(
            header: '关于',
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.info_outline, color: palette.tint),
                title: const Text(AppConfig.appName),
                subtitle: Text('版本 $version'),
              ),
              ListTile(
                leading: Icon(
                  Icons.new_releases_outlined,
                  color: palette.tint,
                ),
                title: const Text('更新渠道'),
                subtitle: const Text('正式版只接收正式发布；预览版还包含预发布构建'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GlassSpacing.lg,
                  0,
                  GlassSpacing.lg,
                  GlassSpacing.sm,
                ),
                child: SegmentedButton<UpdateChannel>(
                  key: const Key('settings-update-channel'),
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
                leading: Icon(
                  Icons.system_update_outlined,
                  color: palette.tint,
                ),
                title: const Text('检查更新'),
                subtitle: checking
                    ? const Text('检查中…')
                    : Text('渠道：${channel.label}'),
                trailing: checking
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(palette.tint),
                        ),
                      )
                    : Icon(
                        Icons.chevron_right,
                        color: palette.tertiaryLabel,
                        size: 20,
                      ),
                onTap: checking
                    ? null
                    : () => unawaited(_checkForUpdate(context, ref)),
              ),
            ],
          ),
          GlassSection(
            header: '求片',
            children: <Widget>[
              const MoviePilotSettingsTile(),
              ListTile(
                key: const Key('settings-request-page'),
                leading: Icon(Icons.add_task, color: palette.green),
                title: const Text('求片'),
                subtitle: const Text('搜索库里没有的影片，提交给 MoviePilot 下载'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.tertiaryLabel,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.request),
              ),
              ListTile(
                key: const Key('settings-my-requests'),
                leading: Icon(
                  Icons.downloading_outlined,
                  color: palette.indigo,
                ),
                title: const Text('我的求片'),
                subtitle: const Text('查看每个求片走到哪一步'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.tertiaryLabel,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.myRequests),
              ),
            ],
          ),
          if (feedbackEnabled) ...<Widget>[
            GlassSection(
              header: '反馈',
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.feedback_outlined, color: palette.orange),
                  title: const Text('问题反馈'),
                  subtitle: const Text('截图并描述问题，提交到反馈服务'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: palette.tertiaryLabel,
                    size: 20,
                  ),
                  onTap: () => unawaited(
                    ref.read(feedbackControllerProvider).captureAndOpen(),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.circle_outlined, color: palette.purple),
                  title: const Text('灵感球样式'),
                  subtitle: Text(
                    _orbSettingsSubtitle(orbSettings, (FeedbackOrbSettings s) {
                      return '当前：${_idleStyleLabel(s.idleStyle)}';
                    }),
                  ),
                  trailing: _orbSettingsTrailing(orbSettings) ??
                      Icon(
                        Icons.chevron_right,
                        color: palette.tertiaryLabel,
                        size: 20,
                      ),
                  onTap: orbSettings == null
                      ? null
                      : () => unawaited(
                            _pickOrbIdleStyle(context, ref, orbSettings),
                          ),
                ),
                ListTile(
                  leading: Icon(Icons.gesture, color: palette.teal),
                  title: const Text('唤醒灵感球'),
                  subtitle: Text(
                    _orbSettingsSubtitle(orbSettings, (FeedbackOrbSettings s) {
                      return '当前：${_wakeGesturesLabel(s.wakeGestures)}';
                    }),
                  ),
                  trailing: _orbSettingsTrailing(orbSettings) ??
                      Icon(
                        Icons.chevron_right,
                        color: palette.tertiaryLabel,
                        size: 20,
                      ),
                  onTap: orbSettings == null
                      ? null
                      : () => unawaited(
                            _pickWakeGestures(context, ref, orbSettings),
                          ),
                ),
              ],
            ),
          ],
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
    final GlassPalette palette = context.glass;
    final FeedbackOrbIdleStyle? selected =
        await showGlassDialog<FeedbackOrbIdleStyle>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        title: '灵感球样式',
        maxWidth: 340,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final FeedbackOrbIdleStyle style
                in FeedbackOrbIdleStyle.values)
              _ChoiceRow(
                selected: current.idleStyle == style,
                title: _idleStyleLabel(style),
                subtitle: _idleStyleDescription(style),
                palette: palette,
                onTap: () => Navigator.of(dialogContext).pop(style),
              ),
          ],
        ),
        actions: <Widget>[
          GlassButton(
            label: '取消',
            variant: GlassButtonVariant.plain,
            onPressed: () => Navigator.of(dialogContext).pop(),
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
    final GlassPalette palette = context.glass;
    final Set<FeedbackWakeGesture> draft = <FeedbackWakeGesture>{
      ...current.wakeGestures,
    };
    final Set<FeedbackWakeGesture>? selected =
        await showGlassDialog<Set<FeedbackWakeGesture>>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            void Function(VoidCallback) setState,
          ) {
            return GlassDialog(
              title: '唤醒灵感球',
              maxWidth: 360,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '默认关闭；只在 App 内生效，松手后再拖球截图。',
                    style: GlassType.footnote.copyWith(
                      color: palette.secondaryLabel,
                    ),
                  ),
                  const SizedBox(height: GlassSpacing.md),
                  for (final FeedbackWakeGesture gesture
                      in FeedbackWakeGesture.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: GlassSpacing.sm),
                      child: _GestureRow(
                        selected: draft.contains(gesture),
                        title: gesture.title,
                        subtitle: gesture.description,
                        palette: palette,
                        onTap: () {
                          setState(() {
                            if (draft.contains(gesture)) {
                              draft.remove(gesture);
                            } else {
                              draft.add(gesture);
                            }
                          });
                        },
                      ),
                    ),
                ],
              ),
              actions: <Widget>[
                GlassButton(
                  label: '取消',
                  variant: GlassButtonVariant.plain,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                GlassButton(
                  label: '保存',
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(Set<FeedbackWakeGesture>.of(draft)),
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

/// A single tappable option row inside a glass dialog.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final GlassPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GlassSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.circle,
              color: selected ? palette.tint : palette.tertiaryLabel,
              size: 20,
            ),
            const SizedBox(width: GlassSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: GlassType.body.copyWith(color: palette.label),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GlassType.caption1.copyWith(
                      color: palette.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GestureRow extends StatelessWidget {
  const _GestureRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final GlassPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassSurface(
        radius: GlassRadii.control,
        blur: 12,
        tintColor: selected ? palette.tint : palette.fill,
        tintOpacity: selected ? 0.18 : 0.1,
        shadow: false,
        border: false,
        padding: const EdgeInsets.symmetric(
          horizontal: GlassSpacing.md,
          vertical: GlassSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              color: selected ? palette.tint : palette.tertiaryLabel,
              size: 18,
            ),
            const SizedBox(width: GlassSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: GlassType.subheadline.copyWith(
                      color: palette.label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GlassType.caption1.copyWith(
                      color: palette.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
