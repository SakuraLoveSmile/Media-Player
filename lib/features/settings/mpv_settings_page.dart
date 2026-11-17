import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_settings.dart';
import '../../app/subtitle_style_settings.dart';
import '../../data/playback/playback_engine.dart';
import '../../data/playback/playback_settings.dart';
import '../../data/playback/mpv_config.dart';
import '../../ui/app_dialog.dart';
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
          const _MpvQualitySection(),
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

class _MpvQualitySection extends ConsumerStatefulWidget {
  const _MpvQualitySection();

  @override
  ConsumerState<_MpvQualitySection> createState() => _MpvQualitySectionState();
}

class _MpvQualitySectionState extends ConsumerState<_MpvQualitySection> {
  bool _saving = false;

  Future<void> _save(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('画质设置保存失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(playbackSettingsControllerProvider);
    final settings = async.value ?? const PlaybackSettings();
    final controller = ref.read(playbackSettingsControllerProvider.notifier);
    final disabled = async.isLoading || _saving;
    return AppSection(
      header: '画质预设与自定义配置',
      footer: '下次播放生效。使用 MPV 内置缩放与颜色选项；不含参考项目的 GLSL 着色器或 AI 补帧。去色带开关仍由下方设置控制。',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final preset in MpvQualityPreset.values)
                ChoiceChip(
                  key: Key('mpv-preset-${preset.name}'),
                  label: Text(preset.label),
                  selected: settings.mpvQualityPreset == preset,
                  onSelected: disabled
                      ? null
                      : (_) => unawaited(
                          _save(() => controller.setMpvQuality(preset: preset)),
                        ),
                ),
            ],
          ),
        ),
        ListTile(
          key: const Key('mpv-config-edit'),
          leading: const Icon(Icons.edit_note),
          title: const Text('编辑自定义画质配置'),
          subtitle: Text(
            settings.mpvCustomConfig.trim().isEmpty
                ? '逐行校验；自定义值覆盖所选预设'
                : '已保存自定义配置，覆盖所选预设',
          ),
          trailing: const Icon(Icons.chevron_right),
          enabled: !disabled,
          onTap: () => showAppDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _MpvConfigEditor(
              initial: settings.mpvCustomConfig,
              onSave: (source) =>
                  controller.setMpvQuality(customConfig: source),
            ),
          ),
        ),
        ListTile(
          key: const Key('mpv-config-reset'),
          leading: const Icon(Icons.restore),
          title: const Text('恢复默认画质'),
          subtitle: const Text('重置画质预设并清除自定义配置'),
          enabled: !disabled,
          onTap: () async {
            final confirmed = await showAppDialog<bool>(
              context: context,
              builder: (context) => AppDialog(
                title: '恢复默认画质？',
                message: '已保存的自定义画质配置将被清除。其他播放设置不受影响。',
                actions: <Widget>[
                  FilledButton(
                    key: const Key('mpv-config-reset-confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('恢复默认'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                ],
              ),
            );
            if (confirmed == true && mounted) {
              await _save(controller.resetMpvQuality);
            }
          },
        ),
      ],
    );
  }
}

class _MpvConfigEditor extends StatefulWidget {
  const _MpvConfigEditor({required this.initial, required this.onSave});
  final String initial;
  final Future<void> Function(String) onSave;

  @override
  State<_MpvConfigEditor> createState() => _MpvConfigEditorState();
}

class _MpvConfigEditorState extends State<_MpvConfigEditor> {
  late final TextEditingController _text;
  late MpvConfigResult _result;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial);
    _result = MpvConfig.parse(widget.initial);
    _text.addListener(_validate);
  }

  void _validate() => setState(() {
    _result = MpvConfig.parse(_text.text);
    _status = null;
  });

  @override
  void dispose() {
    _text.removeListener(_validate);
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_result.isValid || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_text.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _status = '保存失败，配置仍保留在编辑器中');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: '自定义画质配置',
      maxWidth: 680,
      content: SizedBox(
        width: 600,
        height: MediaQuery.sizeOf(context).height * 0.42,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('每行 选项=值，支持 # 注释。仅允许内置画质选项；脚本、路径、profile 和播放控制项会被拒绝。'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('mpv-config-input'),
                controller: _text,
                enabled: !_saving,
                minLines: 6,
                maxLines: 12,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '# 示例\nscale=ewa_lanczossharp\nscale-antiring=0.7',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_result.isValid)
                Text(
                  '校验通过 · ${_result.properties.length} 个自定义选项',
                  key: const Key('mpv-config-valid'),
                ),
              for (final issue in _result.issues)
                Text(
                  issue.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_status != null) Text(_status!),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        FilledButton(
          key: const Key('mpv-config-save'),
          onPressed: _result.isValid && !_saving ? _save : null,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
        TextButton(
          key: const Key('mpv-config-copy-ai'),
          onPressed: _saving
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(text: MpvConfig.aiPrompt(_text.text)),
                  );
                  if (mounted) setState(() => _status = '配置与修改规则已复制，可粘贴给 AI');
                },
          child: const Text('复制给 AI'),
        ),
        TextButton(
          onPressed: _saving ? null : () => _text.clear(),
          child: const Text('清空自定义配置'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
