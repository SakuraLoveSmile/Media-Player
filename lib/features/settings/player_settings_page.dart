import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_settings.dart';
import '../../app/track_prefs_settings.dart';
import '../../data/playback/playback_settings.dart';
import '../../data/playback/track_prefs.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';
import 'playback_settings_section.dart';

/// 播放器 settings (S33): playback interaction switches, the playback/cache
/// partition migrated from the first-level settings page, plus the
/// audio/subtitle language preferences that drive automatic track selection.
class PlayerSettingsPage extends ConsumerWidget {
  const PlayerSettingsPage({super.key});

  static const List<(String, String)> _languages = <(String, String)>[
    ('', '自动'),
    ('chi', '中文'),
    ('eng', '英语'),
    ('jpn', '日语'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<PlaybackSettings> async = ref.watch(
      playbackSettingsControllerProvider,
    );
    final PlaybackSettings settings = async.value ?? const PlaybackSettings();
    final bool loading = async.isLoading;
    final PlaybackSettingsController playback = ref.read(
      playbackSettingsControllerProvider.notifier,
    );
    final TrackPrefs prefs =
        ref.watch(trackPrefsSettingsControllerProvider).value ??
        const TrackPrefs();
    final TrackPrefsSettingsController tracks = ref.read(
      trackPrefsSettingsControllerProvider.notifier,
    );

    return AppPage(
      title: '播放器',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('player-settings-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          AppSection(
            header: '交互',
            footer: '下次播放生效',
            children: <Widget>[
              SwitchListTile(
                key: const Key('settings-seek-on-drag'),
                secondary: Icon(Icons.fast_forward, color: palette.primary),
                title: const Text('拖拽进度条时快速跳转'),
                subtitle: const Text('拖动时画面跟随进度，而不是松手后才跳转'),
                value: settings.seekOnDrag,
                onChanged: loading
                    ? null
                    : (bool value) => unawaited(
                        _save(context, playback.setSeekOnDrag(value)),
                      ),
              ),
              SwitchListTile(
                key: const Key('settings-auto-play-next'),
                secondary: Icon(Icons.skip_next, color: palette.primary),
                title: const Text('自动连播下一集'),
                subtitle: const Text('当前集播放结束后自动开始下一集'),
                value: settings.autoPlayNext,
                onChanged: loading
                    ? null
                    : (bool value) => unawaited(
                        _save(context, playback.setAutoPlayNext(value)),
                      ),
              ),
            ],
          ),
          _SeekStepSection(
            settings: settings,
            loading: loading,
            onBack: (int seconds) =>
                _save(context, playback.setSeekBackSeconds(seconds)),
            onForward: (int seconds) =>
                _save(context, playback.setSeekForwardSeconds(seconds)),
          ),
          const PlaybackSettingsSection(),
          _LanguageSection(
            header: '音轨语言',
            keyPrefix: 'settings-audio-lang',
            selected: prefs.audioLanguage,
            onSelect: (String code) =>
                _save(context, tracks.setAudioLanguage(code)),
          ),
          _LanguageSection(
            header: '字幕语言',
            keyPrefix: 'settings-subtitle-lang',
            selected: prefs.subtitleLanguage,
            onSelect: (String code) =>
                _save(context, tracks.setSubtitleLanguage(code)),
          ),
        ],
      ),
    );
  }

  static Future<void> _save(BuildContext context, Future<void> save) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await save;
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
    }
  }
}

/// S80: back / forward jump length, one chip row per direction. Each direction
/// is chosen independently; the presets are fixed so the transport buttons can
/// pick a matching icon and label.
class _SeekStepSection extends StatelessWidget {
  const _SeekStepSection({
    required this.settings,
    required this.loading,
    required this.onBack,
    required this.onForward,
  });

  final PlaybackSettings settings;
  final bool loading;
  final ValueChanged<int> onBack;
  final ValueChanged<int> onForward;

  @override
  Widget build(BuildContext context) {
    return AppSection(
      header: '快进/快退',
      footer: '下次打开播放器生效',
      children: <Widget>[
        _SeekStepRow(
          keyPrefix: 'settings-seek-back',
          title: '后退步长',
          subtitle: '点击播放器「后退」按钮时跳过的时长',
          selected: settings.seekBackSeconds,
          loading: loading,
          onSelect: onBack,
          icon: Icons.fast_rewind,
        ),
        _SeekStepRow(
          keyPrefix: 'settings-seek-forward',
          title: '前进步长',
          subtitle: '点击播放器「前进」按钮时跳过的时长',
          selected: settings.seekForwardSeconds,
          loading: loading,
          onSelect: onForward,
          icon: Icons.fast_forward,
        ),
      ],
    );
  }
}

/// One direction's chip row: 5 / 10 / 15 / 30 / 60 s.
class _SeekStepRow extends StatelessWidget {
  const _SeekStepRow({
    required this.keyPrefix,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.loading,
    required this.onSelect,
    required this.icon,
  });

  final String keyPrefix;
  final String title;
  final String subtitle;
  final int selected;
  final bool loading;
  final ValueChanged<int> onSelect;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 20, color: palette.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final int seconds in PlaybackSettings.seekStepPresets)
                ChoiceChip(
                  key: Key('$keyPrefix-$seconds'),
                  label: Text('$seconds 秒'),
                  selected: selected == seconds,
                  onSelected: loading ? null : (_) => onSelect(seconds),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One language chip row (自动 / 中文 / 英语 / 日语).
class _LanguageSection extends StatelessWidget {
  const _LanguageSection({
    required this.header,
    required this.keyPrefix,
    required this.selected,
    required this.onSelect,
  });

  final String header;
  final String keyPrefix;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return AppSection(
      header: header,
      footer: '自动表示保留服务器/播放器默认轨道',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final (String code, String label)
                  in PlayerSettingsPage._languages)
                ChoiceChip(
                  key: Key('$keyPrefix-${code.isEmpty ? 'auto' : code}'),
                  label: Text(label),
                  selected: selected == code,
                  onSelected: (_) => onSelect(code),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
