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

/// 播放器 settings (S33): playback interaction switches plus the audio/subtitle
/// language preferences that drive automatic track selection.
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
