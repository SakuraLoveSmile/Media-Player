import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/danmaku_settings.dart';
import '../../data/danmaku/danmaku_settings.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';

/// 弹幕 settings (S36): the defaults every playback starts from. The in-player
/// sheet still edits the same blob for session-level tweaks.
class DanmakuSettingsPage extends ConsumerWidget {
  const DanmakuSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<DanmakuSettings> async = ref.watch(
      danmakuSettingsControllerProvider,
    );
    final DanmakuSettings settings = async.value ?? const DanmakuSettings();
    final bool loading = async.isLoading;
    final DanmakuSettingsController controller = ref.read(
      danmakuSettingsControllerProvider.notifier,
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
      title: '弹幕',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('danmaku-settings-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          AppSection(
            header: '弹幕',
            footer: '来自 DandanPlay；默认关闭，下次播放生效',
            children: <Widget>[
              SwitchListTile(
                key: const Key('danmaku-settings-enabled'),
                secondary: Icon(Icons.chat_outlined, color: palette.primary),
                title: const Text('启用弹幕'),
                subtitle: const Text('播放时自动匹配并加载弹幕'),
                value: settings.enabled,
                onChanged: loading
                    ? null
                    : (bool value) =>
                          unawaited(save(controller.setEnabled(value))),
              ),
              _slider(
                context,
                key: const Key('danmaku-settings-density'),
                label: '密度',
                value: '${(settings.density * 100).round()}%',
                current: settings.density,
                min: 0.1,
                max: 1,
                divisions: 9,
                enabled: !loading,
                onChanged: (double value) =>
                    unawaited(save(controller.setDensity(value))),
              ),
              _slider(
                context,
                key: const Key('danmaku-settings-opacity'),
                label: '不透明度',
                value: '${(settings.opacity * 100).round()}%',
                current: settings.opacity,
                min: 0.1,
                max: 1,
                divisions: 9,
                enabled: !loading,
                onChanged: (double value) =>
                    unawaited(save(controller.setOpacity(value))),
              ),
              _slider(
                context,
                key: const Key('danmaku-settings-speed'),
                label: '速度',
                value: '${settings.speed}x',
                current: settings.speed,
                min: 0.5,
                max: 2,
                divisions: 6,
                enabled: !loading,
                onChanged: (double value) =>
                    unawaited(save(controller.setSpeed(value))),
              ),
              SwitchListTile(
                key: const Key('danmaku-settings-full-area'),
                secondary: Icon(Icons.aspect_ratio, color: palette.primary),
                title: const Text('全屏显示'),
                subtitle: const Text('关闭时弹幕只出现在上半屏，给字幕留出空间'),
                value: settings.fullArea,
                onChanged: loading
                    ? null
                    : (bool value) =>
                          unawaited(save(controller.setFullArea(value))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slider(
    BuildContext context, {
    required Key key,
    required String label,
    required String value,
    required double current,
    required double min,
    required double max,
    required int divisions,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      key: key,
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
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: palette.onSurface,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          Slider(
            value: current.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
