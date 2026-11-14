import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:path_provider/path_provider.dart';

import '../../app/screenshot_settings.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';

/// 截图 settings (S42): the capture-time behaviour and where files land.
class ScreenshotSettingsPage extends ConsumerWidget {
  const ScreenshotSettingsPage({super.key, this.directoryLabel});

  /// Absolute folder shown under the explainer; null hides the row.
  final String? directoryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<ScreenshotSettings> async = ref.watch(
      screenshotSettingsControllerProvider,
    );
    final ScreenshotSettings settings =
        async.value ?? const ScreenshotSettings();
    final bool loading = async.isLoading;
    final ScreenshotSettingsController controller = ref.read(
      screenshotSettingsControllerProvider.notifier,
    );

    return AppPage(
      title: '截图',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('screenshot-settings-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          AppSection(
            header: '截图',
            footer: '设置只影响之后在播放页触发的截图',
            children: <Widget>[
              SwitchListTile(
                key: const Key('settings-screenshot-pause'),
                secondary: Icon(
                  Icons.pause_circle_outline,
                  color: palette.primary,
                ),
                title: const Text('截图时暂停视频'),
                subtitle: const Text('先暂停再截取画面，完成后自动继续播放'),
                value: settings.pauseWhileCapturing,
                onChanged: loading
                    ? null
                    : (bool value) async {
                        final ScaffoldMessengerState messenger =
                            ScaffoldMessenger.of(context);
                        try {
                          await controller.setPauseWhileCapturing(value);
                        } catch (_) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('保存失败，请稍后重试')),
                          );
                        }
                      },
              ),
            ],
          ),
          FutureBuilder<String?>(
            future: _screenshotDirectoryLabel(),
            builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
              final String? label = snapshot.data;
              if (label == null) return const SizedBox.shrink();
              return AppSection(
                header: '保存位置',
                children: <Widget>[
                  ListTile(
                    key: const Key('settings-screenshot-dir'),
                    leading: Icon(
                      Icons.folder_outlined,
                      color: palette.primary,
                    ),
                    title: Text(label),
                    subtitle: const Text('截图以 PNG 保存；分享、去黑边与水印暂未支持'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// `documents/screenshots`, the folder the player writes screenshots into.
Future<String?> _screenshotDirectoryLabel() async {
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/screenshots';
  } catch (_) {
    return null;
  }
}
