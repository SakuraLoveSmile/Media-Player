import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_settings.dart';
import '../../data/playback/playback_settings.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';

/// 播放/缓存 settings (S13): the hardware-decode default plus demuxer cache
/// sizing. Values persist under [PlaybackSettings.storageKey], the same key the
/// player controller reads at open, so edits apply to the next playback.
class PlaybackSettingsSection extends ConsumerWidget {
  const PlaybackSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<PlaybackSettings> async = ref.watch(
      playbackSettingsControllerProvider,
    );
    final PlaybackSettings settings = async.value ?? const PlaybackSettings();
    final bool loading = async.isLoading;
    final PlaybackSettingsController notifier = ref.read(
      playbackSettingsControllerProvider.notifier,
    );

    return AppSection(
      header: '播放/缓存',
      footer: '硬解与缓存设置在下次播放时生效',
      children: <Widget>[
        SwitchListTile(
          key: const Key('settings-hwdec'),
          secondary: Icon(Icons.memory, color: palette.primary),
          title: const Text('硬件解码'),
          subtitle: const Text('默认开启；遇到兼容问题可关闭'),
          value: settings.hwdecEnabled,
          onChanged: loading
              ? null
              : (bool value) => _save(context, notifier.setHwdecEnabled(value)),
        ),
        _NumberField(
          fieldKey: 'settings-cache-secs',
          label: '缓存时长',
          hint: '提前缓存的秒数',
          unit: '秒',
          value: settings.cacheSecs,
          enabled: !loading,
          onSubmit: (int secs) => _save(context, notifier.setCacheSecs(secs)),
        ),
        _NumberField(
          fieldKey: 'settings-demuxer-max-mb',
          label: '缓存上限',
          hint: '解复用器缓存大小',
          unit: 'MB',
          value: settings.demuxerMaxBytes ~/ (1024 * 1024),
          enabled: !loading,
          onSubmit: (int mb) =>
              _save(context, notifier.setDemuxerMaxBytes(mb * 1024 * 1024)),
        ),
      ],
    );
  }

  /// Persists a change; a write failure keeps the old value and warns.
  Future<void> _save(BuildContext context, Future<void> save) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await save;
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
    }
  }
}

/// A positive-integer field that saves on submit. Re-keyed on the persisted
/// value so a successful save refreshes the text without a manual controller.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.unit,
    required this.value,
    required this.enabled,
    required this.onSubmit,
  });

  final String fieldKey;
  final String label;
  final String hint;
  final String unit;
  final int value;
  final bool enabled;
  final ValueChanged<int> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key(fieldKey),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: TextFormField(
        key: ValueKey<String>('$fieldKey-$value'),
        initialValue: '$value',
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: unit,
        ),
        onFieldSubmitted: (String raw) {
          final int? parsed = int.tryParse(raw.trim());
          if (parsed == null || parsed <= 0) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('请输入正整数')));
            return;
          }
          onSubmit(parsed);
        },
      ),
    );
  }
}
