import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_settings.dart';
import '../../app/subtitle_style_settings.dart';
import '../../data/playback/playback_engine.dart';
import '../../data/playback/playback_settings.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';

/// MPV 播放器 settings (S33): the advanced video chain options that used to live
/// only inside the in-player sheet. Writes the same [PlaybackSettings.storageKey]
/// the player reads at open.
class MpvSettingsPage extends ConsumerWidget {
  const MpvSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<PlaybackSettings> async = ref.watch(
      playbackSettingsControllerProvider,
    );
    final PlaybackSettings settings = async.value ?? const PlaybackSettings();
    final bool loading = async.isLoading;
    final PlaybackSettingsController controller = ref.read(
      playbackSettingsControllerProvider.notifier,
    );
    final SubtitleStyle style =
        ref.watch(subtitleStyleSettingsControllerProvider).value ??
        const SubtitleStyle();
    final SubtitleStyleSettingsController styleController = ref.read(
      subtitleStyleSettingsControllerProvider.notifier,
    );

    Future<void> save(Future<void> write) async {
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      try {
        await write;
      } catch (_) {
        messenger.showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
      }
    }

    return AppPage(
      title: 'MPV 播放器',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('mpv-settings-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          AppSection(
            header: '视频输出',
            footer: '下次播放生效；异常时保持默认即可',
            children: <Widget>[
              SwitchListTile(
                key: const Key('settings-adv-gpu-next'),
                secondary: Icon(Icons.auto_awesome, color: palette.primary),
                title: const Text('GPU-Next 渲染'),
                subtitle: const Text('使用 gpu-next 视频输出，关闭恢复默认'),
                value: settings.gpuNext,
                onChanged: loading
                    ? null
                    : (bool value) => unawaited(
                        save(controller.setAdvancedVideo(gpuNext: value)),
                      ),
              ),
              SwitchListTile(
                key: const Key('settings-adv-deband'),
                secondary: Icon(Icons.gradient, color: palette.primary),
                title: const Text('去色带'),
                subtitle: const Text('减少色彩断层，略微增加性能开销'),
                value: settings.deband,
                onChanged: loading
                    ? null
                    : (bool value) => unawaited(
                        save(controller.setAdvancedVideo(deband: value)),
                      ),
              ),
              SwitchListTile(
                key: const Key('settings-adv-yuv420'),
                secondary: Icon(Icons.monitor, color: palette.primary),
                title: const Text('强制 YUV420P'),
                subtitle: const Text('画面输出异常时的兼容性选项'),
                value: settings.yuv420,
                onChanged: loading
                    ? null
                    : (bool value) => unawaited(
                        save(controller.setAdvancedVideo(yuv420: value)),
                      ),
              ),
            ],
          ),
          AppSection(
            header: '音频',
            footer: '下次播放生效',
            children: <Widget>[
              SwitchListTile(
                key: const Key('settings-force-stereo'),
                secondary: Icon(Icons.headphones, color: palette.primary),
                title: const Text('强制输出立体声'),
                subtitle: const Text('把多声道音轨下混为立体声'),
                value: settings.forceStereo,
                onChanged: loading
                    ? null
                    : (bool value) =>
                          unawaited(save(controller.setForceStereo(value))),
              ),
            ],
          ),
          AppSection(
            header: '字幕',
            footer: '下次播放生效；播放页的字幕样式面板会覆盖本次播放',
            children: <Widget>[
              _StyleSlider(
                sliderKey: 'settings-sub-border',
                label: '字幕描边',
                value: style.borderSize.toStringAsFixed(1),
                current: style.borderSize,
                max: 8,
                enabled: !loading,
                onChanged: (double value) =>
                    unawaited(save(styleController.setBorderSize(value))),
              ),
              _StyleSlider(
                sliderKey: 'settings-sub-shadow',
                label: '字幕阴影偏移',
                value: style.shadowOffset.toStringAsFixed(1),
                current: style.shadowOffset,
                max: 8,
                enabled: !loading,
                onChanged: (double value) =>
                    unawaited(save(styleController.setShadowOffset(value))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled slider used by the MPV page's subtitle defaults.
class _StyleSlider extends StatelessWidget {
  const _StyleSlider({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.current,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String sliderKey;
  final String label;
  final String value;
  final double current;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      key: Key(sliderKey),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: palette.onSurface),
              ),
            ],
          ),
          Slider(
            value: current.clamp(0.0, max),
            max: max,
            divisions: 8,
            label: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
