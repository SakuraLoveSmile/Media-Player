import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/accent_settings.dart';
import '../../app/admin_providers.dart';
import '../../app/feedback_config.dart';
import '../../app/feedback_orb_settings.dart';
import '../../app/general_settings.dart';
import '../../app/theme_mode_settings.dart';
import '../../app/update_channel_settings.dart';
import '../../app/update_providers.dart';
import '../../core/config/app_config.dart';
import '../../core/router/app_routes.dart';
import '../../data/update/update_models.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_dialog.dart';
import '../../ui/app_page.dart';
import '../../ui/servers_section.dart';
import '../../ui/theme/app_accent.dart';
import '../../ui/theme/app_tokens.dart';
import 'backup_settings_section.dart';
import 'moviepilot_config_dialog.dart';
import 'playback_settings_section.dart';
import 'request_notification_settings_tile.dart';
import 'update_dialog.dart';

/// Settings: about, manual update check, and the optional feedback entries.
///
/// The route itself is registered by the app shell, so this page never
/// touches navigation on its own.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final UpdateStatus updateStatus = ref.watch(
      updateControllerProvider.select((UpdateState state) => state.status),
    );
    final bool checking = updateStatus == UpdateStatus.checking;
    final UpdateChannel channel =
        ref.watch(updateChannelControllerProvider).value ??
        UpdateChannel.stable;
    // App-wide appearance. The root MaterialApp watches the same provider, so
    // a tap here repaints every page without a restart.
    final AsyncValue<ThemeMode> themeModeAsync = ref.watch(
      themeModeControllerProvider,
    );
    final ThemeMode themeMode = themeModeAsync.value ?? ThemeMode.system;
    // App-wide accent (设置 → 外观 → 主题色). The root MaterialApp watches the
    // same provider, so a tap here re-tints every page without a restart.
    final AsyncValue<AccentPreference> accentAsync = ref.watch(
      accentControllerProvider,
    );
    final AccentPreference accent =
        accentAsync.value ?? AccentPreference.defaults;
    final packageInfo = ref.watch(appVersionProvider).value;
    final String version = packageInfo == null
        ? AppConfig.appVersion
        : '${packageInfo.version}+${packageInfo.buildNumber}';
    // The feedback entries only exist while the feedback service is configured.
    final bool feedbackEnabled =
        ref.watch(feedbackServiceConfigProvider) != null;
    // S24: the 管理 entry only exists for administrators. While the check is
    // still resolving (or failed) it stays hidden, never flashing into view.
    final bool isAdmin = ref.watch(isAdminProvider).value ?? false;
    // S32: 通用 preferences.
    final AsyncValue<bool> ignoreSslAsync = ref.watch(
      ignoreSslControllerProvider,
    );
    final bool ignoreSsl = ignoreSslAsync.value ?? false;
    final AsyncValue<FeedbackOrbSettings>? orbSettings = feedbackEnabled
        ? ref.watch(feedbackOrbSettingsProvider)
        : null;

    return AppPage(
      title: '设置',
      onBack: () => context.pop(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const ServerSettingsSection(),
          if (isAdmin)
            AppSection(
              header: '管理',
              children: <Widget>[
                ListTile(
                  key: const Key('settings-admin'),
                  leading: Icon(
                    Icons.admin_panel_settings_outlined,
                    color: palette.primary,
                  ),
                  title: const Text('服务器管理'),
                  subtitle: const Text('服务器信息、用户与活跃会话'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: palette.outline,
                    size: 20,
                  ),
                  onTap: () => context.push(AppRoutes.admin),
                ),
              ],
            ),
          AppSection(
            header: '外观',
            footer: '播放页始终使用深色，不受此设置影响',
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.contrast, color: palette.primary),
                title: const Text('主题模式'),
                subtitle: Text(
                  themeModeAsync.isLoading
                      ? '读取中…'
                      : '当前：${_themeModeLabel(themeMode)}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final ThemeMode mode in ThemeMode.values)
                      ChoiceChip(
                        key: Key('settings-theme-${mode.name}'),
                        label: Text(_themeModeLabel(mode)),
                        selected: themeMode == mode,
                        onSelected: themeModeAsync.isLoading
                            ? null
                            : (_) => unawaited(
                                _selectThemeMode(context, ref, mode),
                              ),
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: Icon(Icons.palette_outlined, color: palette.primary),
                title: const Text('主题色'),
                subtitle: Text(
                  accentAsync.isLoading ? '读取中…' : '当前：${_accentLabel(accent)}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final AppAccentPreset preset in AppAccentPresets.all)
                      ChoiceChip(
                        key: Key('settings-accent-${preset.name}'),
                        avatar: _AccentDot(color: preset.color),
                        label: Text(preset.label),
                        // While Monet is on the system colour wins, so no preset
                        // chip reads as selected; the stored preset is only the
                        // fallback for platforms without dynamic colour.
                        selected:
                            accent.mode != AccentMode.monet &&
                            (accent.preset ?? 'default') == preset.name,
                        onSelected: accentAsync.isLoading
                            ? null
                            : (_) => unawaited(
                                _selectAccent(context, ref, preset.name),
                              ),
                      ),
                  ],
                ),
              ),
              ListTile(
                key: const Key('settings-appearance'),
                leading: Icon(Icons.tune, color: palette.primary),
                title: const Text('外观'),
                subtitle: const Text('导航栏样式'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.settingsAppearance),
              ),
              SwitchListTile(
                key: const Key('settings-monet'),
                secondary: Icon(
                  Icons.auto_awesome_outlined,
                  color: palette.primary,
                ),
                title: const Text('跟随系统 (Monet)'),
                subtitle: const Text('Android 12+ 使用系统主题色；不可用时回退到上方主题色'),
                value: accent.mode == AccentMode.monet,
                onChanged: accentAsync.isLoading
                    ? null
                    : (bool enabled) =>
                          unawaited(_setMonet(context, ref, enabled)),
              ),
            ],
          ),
          const PlaybackSettingsSection(),
          AppSection(
            header: '求片',
            children: <Widget>[
              const MoviePilotSettingsTile(),
              ListTile(
                key: const Key('settings-request-page'),
                leading: Icon(Icons.add_task, color: Colors.green),
                title: const Text('求片'),
                subtitle: const Text('搜索库里没有的影片，提交给 MoviePilot 下载'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.request),
              ),
              ListTile(
                key: const Key('settings-my-requests'),
                leading: Icon(
                  Icons.downloading_outlined,
                  color: palette.secondary,
                ),
                title: const Text('我的求片'),
                subtitle: const Text('查看每个求片走到哪一步'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.myRequests),
              ),
              const RequestNotificationSwitchTile(),
            ],
          ),
          if (feedbackEnabled) ...<Widget>[
            AppSection(
              header: '反馈',
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.feedback_outlined, color: Colors.orange),
                  title: const Text('问题反馈'),
                  subtitle: const Text('截图并描述问题，提交到反馈服务'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: palette.outline,
                    size: 20,
                  ),
                  onTap: () => unawaited(
                    ref.read(feedbackControllerProvider).captureAndOpen(),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.circle_outlined, color: palette.tertiary),
                  title: const Text('灵感球样式'),
                  subtitle: Text(
                    _orbSettingsSubtitle(orbSettings, (FeedbackOrbSettings s) {
                      return '当前：${_idleStyleLabel(s.idleStyle)}';
                    }),
                  ),
                  trailing:
                      _orbSettingsTrailing(orbSettings) ??
                      Icon(
                        Icons.chevron_right,
                        color: palette.outline,
                        size: 20,
                      ),
                  onTap: orbSettings == null
                      ? null
                      : () => unawaited(
                          _pickOrbIdleStyle(context, ref, orbSettings),
                        ),
                ),
                ListTile(
                  leading: Icon(Icons.gesture, color: palette.secondary),
                  title: const Text('唤醒灵感球'),
                  subtitle: Text(
                    _orbSettingsSubtitle(orbSettings, (FeedbackOrbSettings s) {
                      return '当前：${_wakeGesturesLabel(s.wakeGestures)}';
                    }),
                  ),
                  trailing:
                      _orbSettingsTrailing(orbSettings) ??
                      Icon(
                        Icons.chevron_right,
                        color: palette.outline,
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
          const BackupSettingsSection(),
          AppSection(
            header: '通用',
            children: <Widget>[
              ListTile(
                key: const Key('settings-cache'),
                leading: Icon(
                  Icons.photo_library_outlined,
                  color: palette.primary,
                ),
                title: const Text('图片缓存'),
                subtitle: const Text('查看占用并清除本机海报与剧照'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.settingsCache),
              ),
              ListTile(
                key: const Key('settings-libraries'),
                leading: Icon(
                  Icons.video_library_outlined,
                  color: palette.primary,
                ),
                title: const Text('媒体库'),
                subtitle: const Text('隐藏不想看到的媒体库'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.settingsLibraries),
              ),
              SwitchListTile(
                key: const Key('settings-ignore-ssl'),
                secondary: Icon(Icons.lock_outline, color: palette.primary),
                title: const Text('忽略 SSL 证书错误'),
                subtitle: const Text('自签名证书服务器；重启后生效'),
                value: ignoreSsl,
                onChanged: ignoreSslAsync.isLoading
                    ? null
                    : (bool value) =>
                          unawaited(_setIgnoreSsl(context, ref, value)),
              ),
            ],
          ),

          AppSection(
            header: '媒体',
            children: <Widget>[
              ListTile(
                key: const Key('settings-live-tv'),
                leading: Icon(Icons.live_tv_outlined, color: palette.primary),
                title: const Text('电视直播'),
                subtitle: const Text('浏览服务器上的直播频道'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.liveTv),
              ),
              ListTile(
                key: const Key('settings-library'),
                leading: Icon(
                  Icons.video_library_outlined,
                  color: palette.primary,
                ),
                title: const Text('媒体库'),
                subtitle: const Text('按库浏览全部影片与剧集'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.library),
              ),
            ],
          ),
          AppSection(
            header: '播放器',
            children: <Widget>[
              ListTile(
                key: const Key('settings-player'),
                leading: Icon(
                  Icons.play_circle_outline,
                  color: palette.primary,
                ),
                title: const Text('播放器'),
                subtitle: const Text('交互、自动连播与音轨/字幕语言偏好'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.settingsPlayer),
              ),
              ListTile(
                key: const Key('settings-mpv'),
                leading: Icon(
                  Icons.movie_filter_outlined,
                  color: palette.primary,
                ),
                title: const Text('MPV 播放器'),
                subtitle: const Text('GPU-Next、去色带与像素格式'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.settingsMpv),
              ),
              ListTile(
                key: const Key('settings-screenshot'),
                leading: Icon(
                  Icons.photo_camera_outlined,
                  color: palette.primary,
                ),
                title: const Text('截图'),
                subtitle: const Text('截图时暂停视频与保存位置'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.settingsScreenshot),
              ),
              ListTile(
                key: const Key('settings-danmaku'),
                leading: Icon(
                  Icons.chat_bubble_outline,
                  color: palette.primary,
                ),
                title: const Text('弹幕'),
                subtitle: const Text('默认开关、密度、不透明度、速度与显示区域'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.settingsDanmaku),
              ),
            ],
          ),
          AppSection(
            header: '关于',
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.info_outline, color: palette.primary),
                title: const Text(AppConfig.appName),
                subtitle: Text('版本 $version'),
              ),
              ListTile(
                leading: Icon(
                  Icons.new_releases_outlined,
                  color: palette.primary,
                ),
                title: const Text('更新渠道'),
                subtitle: const Text('正式版只接收正式发布；预览版还包含预发布构建'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
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
                  color: palette.primary,
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            palette.primary,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.chevron_right,
                        color: palette.outline,
                        size: 20,
                      ),
                onTap: checking
                    ? null
                    : () => unawaited(_checkForUpdate(context, ref)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Persists the SSL preference; a failed write keeps the previous value.
  Future<void> _setIgnoreSsl(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ignoreSslControllerProvider.notifier).setEnabled(enabled);
      messenger.showSnackBar(
        SnackBar(content: Text(enabled ? '已开启，重启后生效' : '已关闭，重启后生效')),
      );
    } on GeneralSettingsException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
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

  /// Persists the appearance mode; failures keep the previous palette.
  Future<void> _selectThemeMode(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(themeModeControllerProvider.notifier).setMode(mode);
    } on ThemeModeSettingsException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Persists the accent preset; failures keep the previous colour.
  Future<void> _selectAccent(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accentControllerProvider.notifier).selectPreset(name);
    } on AccentSettingsException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Persists the Monet toggle; failures keep the previous colour.
  Future<void> _setMonet(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accentControllerProvider.notifier).setMonet(enabled);
    } on AccentSettingsException catch (error) {
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
    final ColorScheme palette = Theme.of(context).colorScheme;
    final FeedbackOrbIdleStyle? selected =
        await showAppDialog<FeedbackOrbIdleStyle>(
          context: context,
          builder: (BuildContext dialogContext) => AppDialog(
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
              AppButton(
                label: '取消',
                variant: AppButtonVariant.plain,
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
    final ColorScheme palette = Theme.of(context).colorScheme;
    final Set<FeedbackWakeGesture> draft = <FeedbackWakeGesture>{
      ...current.wakeGestures,
    };
    final Set<FeedbackWakeGesture>? selected =
        await showAppDialog<Set<FeedbackWakeGesture>>(
          context: context,
          builder: (BuildContext dialogContext) {
            return StatefulBuilder(
              builder:
                  (BuildContext context, void Function(VoidCallback) setState) {
                    return AppDialog(
                      title: '唤醒灵感球',
                      maxWidth: 360,
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '默认关闭；只在 App 内生效，松手后再拖球截图。',
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(color: palette.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          for (final FeedbackWakeGesture gesture
                              in FeedbackWakeGesture.values)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
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
                        AppButton(
                          label: '取消',
                          variant: AppButtonVariant.plain,
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                        AppButton(
                          label: '保存',
                          onPressed: () =>
                              Navigator.of(dialogContext)
                                  .pop(Set<FeedbackWakeGesture>.of(draft)),
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

/// A single tappable option row inside a Material dialog.
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
  final ColorScheme palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle : Icons.circle,
              color: selected ? palette.primary : palette.outline,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge!
                        .copyWith(color: palette.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: palette.onSurfaceVariant),
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
  final ColorScheme palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AppCard(
        radius: AppRadii.control,
        elevation: 0,
        color: selected
            ? palette.primary.withValues(alpha: 0.12)
            : palette.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? palette.primary : palette.outline,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: palette.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: palette.onSurfaceVariant),
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

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };
}

String _accentLabel(AccentPreference preference) {
  if (preference.mode == AccentMode.monet) return '跟随系统 (Monet)';
  return AppAccentPresets.byName(preference.preset)?.label ?? '默认';
}

/// A small colour swatch shown inside each accent preset chip.
class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
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
