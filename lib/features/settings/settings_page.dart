import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/admin_providers.dart';
import '../../app/feedback_config.dart';
import '../../app/feedback_orb_settings.dart';
import '../../app/general_settings.dart';
import '../../app/update_channel_settings.dart';
import '../../app/update_providers.dart';
import '../../core/config/app_config.dart';
import '../../core/router/app_routes.dart';
import '../../data/update/update_models.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_dialog.dart';
import '../../ui/app_page.dart';
import '../../ui/servers_section.dart';
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
    final AsyncValue<FeedbackOrbSettings>? feedbackSettings = feedbackEnabled
        ? ref.watch(feedbackOrbSettingsProvider)
        : null;
    // Tiles that only apply to one launcher follow the current choice; while the
    // stored value is still loading the defaults (beam) decide, so the list never
    // flashes between both variants.
    final FeedbackLauncherStyle launcherStyle =
        feedbackSettings?.value?.launcherStyle ??
        FeedbackOrbSettings.defaults.launcherStyle;

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
            children: <Widget>[
              ListTile(
                key: const Key('settings-appearance'),
                leading: Icon(Icons.tune, color: palette.primary),
                title: const Text('外观'),
                subtitle: const Text('主题、导航栏与动画'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: palette.outline,
                  size: 20,
                ),
                onTap: () => context.push(AppRoutes.settingsAppearance),
              ),
            ],
          ),
          AppSection(
            header: '本地媒体',
            children: <Widget>[
              ListTile(
                key: const Key('settings-offline'),
                leading: Icon(
                  Icons.download_done_rounded,
                  color: palette.primary,
                ),
                title: const Text('下载与离线媒体'),
                subtitle: const Text('管理下载、暂停与继续，断网播放本地副本'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.offline),
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
                  leading: Icon(Icons.ads_click, color: palette.primary),
                  title: const Text('反馈入口'),
                  subtitle: Text(
                    _feedbackSettingsSubtitle(
                      feedbackSettings,
                      (FeedbackOrbSettings s) =>
                          '当前：${_launcherStyleLabel(s.launcherStyle)}',
                    ),
                  ),
                  trailing:
                      _feedbackSettingsTrailing(feedbackSettings) ??
                      Icon(
                        Icons.chevron_right,
                        color: palette.outline,
                        size: 20,
                      ),
                  onTap: feedbackSettings == null
                      ? null
                      : () => unawaited(
                          _pickLauncherStyle(context, ref, feedbackSettings),
                        ),
                ),
                ListTile(
                  leading: Icon(Icons.gesture, color: palette.secondary),
                  title: const Text('唤醒方式'),
                  subtitle: Text(
                    _feedbackSettingsSubtitle(
                      feedbackSettings,
                      (FeedbackOrbSettings s) =>
                          '当前：${_wakeGesturesLabel(s.wakeGestures)}',
                    ),
                  ),
                  trailing:
                      _feedbackSettingsTrailing(feedbackSettings) ??
                      Icon(
                        Icons.chevron_right,
                        color: palette.outline,
                        size: 20,
                      ),
                  onTap: feedbackSettings == null
                      ? null
                      : () => unawaited(
                          _pickWakeGestures(context, ref, feedbackSettings),
                        ),
                ),
                if (launcherStyle == FeedbackLauncherStyle.beam)
                  ListTile(
                    leading: Icon(Icons.waves, color: palette.tertiary),
                    title: const Text('唤醒动效'),
                    subtitle: Text(
                      _feedbackSettingsSubtitle(
                        feedbackSettings,
                        (FeedbackOrbSettings s) =>
                            '当前：${_wakeVisualLabel(s.wakeVisual)}',
                      ),
                    ),
                    trailing:
                        _feedbackSettingsTrailing(feedbackSettings) ??
                        Icon(
                          Icons.chevron_right,
                          color: palette.outline,
                          size: 20,
                        ),
                    onTap: feedbackSettings == null
                        ? null
                        : () => unawaited(
                            _pickWakeVisual(context, ref, feedbackSettings),
                          ),
                  ),
                if (launcherStyle == FeedbackLauncherStyle.orb) ...<Widget>[
                  ListTile(
                    leading: Icon(
                      Icons.circle_outlined,
                      color: palette.tertiary,
                    ),
                    title: const Text('灵感球样式'),
                    subtitle: Text(
                      _feedbackSettingsSubtitle(
                        feedbackSettings,
                        (FeedbackOrbSettings s) =>
                            '当前：${_idleStyleLabel(s.idleStyle)}',
                      ),
                    ),
                    trailing:
                        _feedbackSettingsTrailing(feedbackSettings) ??
                        Icon(
                          Icons.chevron_right,
                          color: palette.outline,
                          size: 20,
                        ),
                    onTap: feedbackSettings == null
                        ? null
                        : () => unawaited(
                            _pickOrbIdleStyle(context, ref, feedbackSettings),
                          ),
                  ),
                  ListTile(
                    leading: Icon(Icons.auto_awesome, color: palette.primary),
                    title: const Text('唤醒效果'),
                    subtitle: Text(
                      _feedbackSettingsSubtitle(
                        feedbackSettings,
                        (FeedbackOrbSettings s) =>
                            '当前：${s.orbEntrance.label}',
                      ),
                    ),
                    trailing:
                        _feedbackSettingsTrailing(feedbackSettings) ??
                        Icon(
                          Icons.chevron_right,
                          color: palette.outline,
                          size: 20,
                        ),
                    onTap: feedbackSettings == null
                        ? null
                        : () => unawaited(
                            _pickOrbEntrance(context, ref, feedbackSettings),
                          ),
                  ),
                ],
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
          AppSection(
            header: '一起看',
            children: <Widget>[
              ListTile(
                key: const Key('settings-watch-together'),
                leading: Icon(Icons.groups_outlined, color: palette.primary),
                title: const Text('一起看'),
                subtitle: const Text('创建或加入房间，同步播放影片'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.watchTogether),
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

  String _feedbackSettingsSubtitle(
    AsyncValue<FeedbackOrbSettings>? async,
    String Function(FeedbackOrbSettings) describe,
  ) {
    if (async == null) return '';
    if (async.isLoading) return '读取中…';
    final FeedbackOrbSettings? value = async.value;
    if (value == null) return '读取失败，点击重试';
    return describe(value);
  }

  Widget? _feedbackSettingsTrailing(AsyncValue<FeedbackOrbSettings>? async) {
    if (async == null || !async.isLoading) return null;
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  /// 通用单选对话框：每项是 (值, 标题, 说明)，选中后返回该值。
  Future<T?> _pickChoice<T>(
    BuildContext context, {
    required String title,
    required String description,
    required T current,
    required List<(T, String, String)> entries,
  }) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return showAppDialog<T>(
      context: context,
      builder: (BuildContext dialogContext) => AppDialog(
        title: title,
        maxWidth: 360,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (T value, String label, String hint) in entries)
              _ChoiceRow(
                selected: current == value,
                title: label,
                subtitle: hint,
                palette: palette,
                onTap: () => Navigator.of(dialogContext).pop(value),
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
  }

  Future<void> _pickLauncherStyle(
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
    final FeedbackLauncherStyle? selected =
        await _pickChoice<FeedbackLauncherStyle>(
          context,
          title: '反馈入口',
          description: '两种入口都可以用唤醒方式打开；面板内的设置已隐藏，反馈设置都在这里。',
          current: current.launcherStyle,
          entries: const <(FeedbackLauncherStyle, String, String)>[
            (
              FeedbackLauncherStyle.beam,
              '光束唤醒',
              '平时没有入口：双指长按或快捷键唤起，先圈出问题位置再填表',
            ),
            (
              FeedbackLauncherStyle.orb,
              '灵感球',
              '右侧常驻玻璃球：点一下反馈，拖到问题处松手后进入局部圈选',
            ),
          ],
        );
    if (selected == null || selected == current.launcherStyle) return;
    if (!context.mounted) return;
    await _saveFeedbackSettings(
      context,
      ref
          .read(feedbackOrbSettingsProvider.notifier)
          .setLauncherStyle(selected),
    );
  }

  Future<void> _pickWakeVisual(
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
    final FeedbackWakeVisual? selected = await _pickChoice<FeedbackWakeVisual>(
      context,
      title: '唤醒动效',
      description: '光束唤醒后、圈选前的动效，只在「光束唤醒」入口下生效。',
      current: current.wakeVisual,
      entries: const <(FeedbackWakeVisual, String, String)>[
        (
          FeedbackWakeVisual.ripple,
          '水波纹（默认）',
          '水波从两指中点向外扩散，画面在波峰处轻轻折动',
        ),
        (
          FeedbackWakeVisual.aurora,
          '波光',
          '冰青、暖黄与粉紫的柔光从指尖铺开，在屏幕边缘淡出',
        ),
      ],
    );
    if (selected == null || selected == current.wakeVisual) return;
    if (!context.mounted) return;
    await _saveFeedbackSettings(
      context,
      ref.read(feedbackOrbSettingsProvider.notifier).setWakeVisual(selected),
    );
  }

  Future<void> _pickOrbEntrance(
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
    final FeedbackOrbEntrance? selected =
        await _pickChoice<FeedbackOrbEntrance>(
          context,
          title: '唤醒效果',
          description: '用唤醒手势呼出灵感球时播放的入场动画，最后的球体相同。',
          current: current.orbEntrance,
          entries: <(FeedbackOrbEntrance, String, String)>[
            for (final FeedbackOrbEntrance entrance
                in FeedbackOrbEntrance.values)
              (entrance, entrance.label, _orbEntranceDescription(entrance)),
          ],
        );
    if (selected == null || selected == current.orbEntrance) return;
    if (!context.mounted) return;
    await _saveFeedbackSettings(
      context,
      ref.read(feedbackOrbSettingsProvider.notifier).setOrbEntrance(selected),
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
        await _pickChoice<FeedbackOrbIdleStyle>(
          context,
          title: '灵感球样式',
          description: '闲置 5 秒后的样子；选择「隐藏」时用唤醒手势呼出。',
          current: current.idleStyle,
          entries: <(FeedbackOrbIdleStyle, String, String)>[
            for (final FeedbackOrbIdleStyle style in FeedbackOrbIdleStyle.values)
              (style, _idleStyleLabel(style), _idleStyleDescription(style)),
          ],
        );
    if (selected == null || selected == current.idleStyle) return;
    if (!context.mounted) return;
    await _saveFeedbackSettings(
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
                      title: '唤醒方式',
                      maxWidth: 360,
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '可同时开启，只在当前 App 内生效。光束唤醒会先圈选问题位置，灵感球会先浮出球体。',
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
    await _saveFeedbackSettings(
      context,
      ref.read(feedbackOrbSettingsProvider.notifier).setWakeGestures(selected),
    );
  }

  Future<void> _saveFeedbackSettings(
    BuildContext context,
    Future<void> save,
  ) async {
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

String _launcherStyleLabel(FeedbackLauncherStyle style) {
  return switch (style) {
    FeedbackLauncherStyle.beam => '光束唤醒',
    FeedbackLauncherStyle.orb => '灵感球',
  };
}

String _wakeVisualLabel(FeedbackWakeVisual visual) {
  return switch (visual) {
    FeedbackWakeVisual.ripple => '水波纹',
    FeedbackWakeVisual.aurora => '波光',
  };
}

String _orbEntranceDescription(FeedbackOrbEntrance entrance) {
  return switch (entrance) {
    FeedbackOrbEntrance.bead => '小玻璃珠从略扁的形状长大，轻轻回弹',
    FeedbackOrbEntrance.join => '两颗珠沿两指连线合拢，连成一颗玻璃球',
    FeedbackOrbEntrance.reveal => '斜弧从左上扫过球面，逐渐露出折射',
    FeedbackOrbEntrance.dent => '页面局部先内凹，再从凹面过渡到凸面',
    FeedbackOrbEntrance.turn => '倾斜的窄镜转向正面，映出球后的内容',
    FeedbackOrbEntrance.drop => '水滴向右上提起，留在触点的细尾收回',
    FeedbackOrbEntrance.corners => '四个取景角连成圆缘，球心开始折射',
  };
}

String _wakeGesturesLabel(Set<FeedbackWakeGesture> gestures) {
  if (gestures.isEmpty) return '已关闭';
  return <String>[
    for (final FeedbackWakeGesture gesture in FeedbackWakeGesture.values)
      if (gestures.contains(gesture)) gesture.title,
  ].join('、');
}
