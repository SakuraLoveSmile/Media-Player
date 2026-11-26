import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/accent_settings.dart';
import 'package:media_player/app/appearance_settings.dart';
import 'package:media_player/app/playback_settings.dart';
import 'package:media_player/app/screenshot_settings.dart';
import 'package:media_player/app/subtitle_style_settings.dart';
import 'package:media_player/app/theme_mode_settings.dart';
import 'package:media_player/app/track_prefs_settings.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/data/playback/playback_settings.dart';
import 'package:media_player/data/playback/track_prefs.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/settings/mpv_settings_page.dart';
import 'package:media_player/features/settings/appearance_page.dart';
import 'package:media_player/features/settings/player_settings_page.dart';
import 'package:media_player/features/settings/screenshot_settings_page.dart';
import 'package:media_player/ui/theme/app_theme.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    Widget page,
    InMemoryKeyValueStore store,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackSettingsStoreProvider.overrideWith((ref) async => store),
          trackPrefsStoreProvider.overrideWith((ref) async => store),
          subtitleStyleStoreProvider.overrideWith((ref) async => store),
          appearanceSettingsStoreProvider.overrideWith((ref) async => store),
          themeModeStoreProvider.overrideWith((ref) async => store),
          accentStoreProvider.overrideWith((ref) async => store),
        ],
        child: MaterialApp(theme: buildAppTheme(Brightness.dark), home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the appearance nav style persists (S62)', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, const AppearancePage(), store);

    expect(find.byKey(const Key('appearance-page')), findsOneWidget);
    final Finder standard = find.byKey(const Key('appearance-nav-standard'));
    // The 主题 section pushes the nav picker below the fold.
    await tester.scrollUntilVisible(
      standard,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('悬浮胶囊'), findsWidgets);

    await tester.tap(standard);
    await tester.pumpAndSettle();

    final Map<String, dynamic> json = jsonDecode(
      (await store.read(AppearanceSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['floatingNav'], false);
    expect(find.text('标准底栏'), findsWidgets);
  });

  testWidgets('the auto-hide nav switch persists (S63)', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, const AppearancePage(), store);

    final Finder toggle = find.byKey(const Key('appearance-nav-auto-hide'));
    // The page grew with the loader picker, so the switch sits below the fold.
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final Map<String, dynamic> json = jsonDecode(
      (await store.read(AppearanceSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['autoHideNav'], false);
  });

  testWidgets('the loader style persists and switches (S66)', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, const AppearancePage(), store);

    final Finder dots = find.byKey(const Key('appearance-loader-dots'));
    // The 主题 section pushes the loader picker below the fold.
    await tester.scrollUntilVisible(
      dots,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(dots, findsOneWidget);
    await tester.tap(dots);
    await tester.pumpAndSettle();

    final Map<String, dynamic> json = jsonDecode(
      (await store.read(AppearanceSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['loaderStyle'], 'dots');
  });

  testWidgets('the list animation switch persists (S67)', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, const AppearancePage(), store);

    final Finder toggle = find.byKey(const Key('appearance-list-animation'));
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final Map<String, dynamic> json = jsonDecode(
      (await store.read(AppearanceSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['listAnimation'], false);
  });

  testWidgets('the interaction switches persist (S33)', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, const PlayerSettingsPage(), store);

    await tester.tap(find.byKey(const Key('settings-seek-on-drag')));
    await tester.pumpAndSettle();
    Map<String, dynamic> json = jsonDecode(
      (await store.read(PlaybackSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['seekOnDrag'], true);

    await tester.tap(find.byKey(const Key('settings-auto-play-next')));
    await tester.pumpAndSettle();
    json = jsonDecode(
      (await store.read(PlaybackSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['autoPlayNext'], false);
  });

  testWidgets('the 快进/快退 chips persist each direction (S80)', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPage(tester, const PlayerSettingsPage(), store);

    // The section sits right after 交互.
    expect(find.text('快进/快退'), findsOneWidget);
    final double interactionTop = tester.getTopLeft(find.text('交互')).dy;
    final double seekTop = tester.getTopLeft(find.text('快进/快退')).dy;
    final double playbackTop = tester.getTopLeft(find.text('播放/缓存')).dy;
    expect(interactionTop, lessThan(seekTop));
    expect(seekTop, lessThan(playbackTop));

    // Every preset is offered for both directions, defaulting to 10 s.
    for (final int seconds in PlaybackSettings.seekStepPresets) {
      expect(find.byKey(Key('settings-seek-back-$seconds')), findsOneWidget);
      expect(find.byKey(Key('settings-seek-forward-$seconds')), findsOneWidget);
    }
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-seek-back-10')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-seek-forward-10')))
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('settings-seek-back-5')));
    await tester.pumpAndSettle();
    Map<String, dynamic> json = jsonDecode(
      (await store.read(PlaybackSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['seekBackSeconds'], 5);
    // The other direction keeps its value.
    expect(json['seekForwardSeconds'], 10);

    await tester.tap(find.byKey(const Key('settings-seek-forward-60')));
    await tester.pumpAndSettle();
    json = jsonDecode(
      (await store.read(PlaybackSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['seekBackSeconds'], 5);
    expect(json['seekForwardSeconds'], 60);
  });

  testWidgets('reopening the 快进/快退 page shows the stored choices (S80)', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await store.write(
      PlaybackSettings.storageKey,
      jsonEncode(
        const PlaybackSettings(
          seekBackSeconds: 30,
          seekForwardSeconds: 15,
        ).toJson(),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPage(tester, const PlayerSettingsPage(), store);

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-seek-back-30')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-seek-forward-15')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-seek-back-10')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-seek-forward-60')))
          .selected,
      isFalse,
    );
  });

  testWidgets('a failed seek-step write keeps the old choice and warns (S80)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPage(tester, const PlayerSettingsPage(), _ThrowingStore());

    await tester.tap(find.byKey(const Key('settings-seek-back-30')));
    await tester.pumpAndSettle();

    expect(find.text('保存失败，请稍后重试'), findsOneWidget);
    // The in-memory state is untouched, so 10 s stays selected.
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-seek-back-10')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-seek-back-30')))
          .selected,
      isFalse,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  /// The 播放/缓存 partition now sits below 交互, so the migrated cases render
  /// the page on a tall canvas and reset the surface afterwards.
  Future<void> pumpPlayer(
    WidgetTester tester,
    InMemoryKeyValueStore store,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPage(tester, const PlayerSettingsPage(), store);
  }

  /// The 播放/缓存 number fields re-key on their value, so locate them through
  /// the stable wrapper key.
  Finder field(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextFormField),
  );

  testWidgets('the playback section shows persisted values', (tester) async {
    final store = InMemoryKeyValueStore();
    await store.write(
      PlaybackSettings.storageKey,
      jsonEncode(
        const PlaybackSettings(
          hwdecEnabled: false,
          cacheSecs: 45,
          demuxerMaxBytes: 200 * 1024 * 1024,
        ).toJson(),
      ),
    );
    await pumpPlayer(tester, store);

    expect(find.text('播放/缓存'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('settings-hwdec')))
          .value,
      isFalse,
    );
    expect(
      tester.widget<TextFormField>(field('settings-cache-secs')).initialValue,
      '45',
    );
    expect(
      tester
          .widget<TextFormField>(field('settings-demuxer-max-mb'))
          .initialValue,
      '200',
    );

    // The partition was migrated into this page and must stay between 交互 and
    // 音轨语言.
    final double interactionTop = tester.getTopLeft(find.text('交互')).dy;
    final double playbackTop = tester.getTopLeft(find.text('播放/缓存')).dy;
    final double audioTop = tester.getTopLeft(find.text('音轨语言')).dy;
    expect(interactionTop, lessThan(playbackTop));
    expect(playbackTop, lessThan(audioTop));
  });

  testWidgets('the hwdec switch persists the choice', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPlayer(tester, store);

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('settings-hwdec')))
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('settings-hwdec')));
    await tester.pumpAndSettle();

    final raw = await store.read(PlaybackSettings.storageKey);
    expect(jsonDecode(raw!)['hwdecEnabled'], isFalse);
  });

  testWidgets('cache fields persist on submit', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPlayer(tester, store);

    await tester.ensureVisible(field('settings-cache-secs'));
    await tester.enterText(field('settings-cache-secs'), '60');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      jsonDecode((await store.read(PlaybackSettings.storageKey))!)['cacheSecs'],
      60,
    );

    await tester.ensureVisible(field('settings-demuxer-max-mb'));
    await tester.enterText(field('settings-demuxer-max-mb'), '256');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      jsonDecode(
        (await store.read(PlaybackSettings.storageKey))!,
      )['demuxerMaxBytes'],
      256 * 1024 * 1024,
    );
  });

  testWidgets('a non-positive cache value warns and does not write', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpPlayer(tester, store);

    await tester.ensureVisible(field('settings-cache-secs'));
    await tester.enterText(field('settings-cache-secs'), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('请输入正整数'), findsOneWidget);
    expect(await store.read(PlaybackSettings.storageKey), isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the language chips persist track prefs (S33)', (tester) async {
    final store = InMemoryKeyValueStore();
    // The 播放/缓存 partition pushes both language rows below the test viewport,
    // so render on a tall canvas.
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPage(tester, const PlayerSettingsPage(), store);

    await tester.tap(find.byKey(const Key('settings-audio-lang-chi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-subtitle-lang-jpn')));
    await tester.pumpAndSettle();

    final String? raw = await store.read(TrackPrefs.storageKey);
    final TrackPrefs prefs = TrackPrefs.fromJson(
      jsonDecode(raw!) as Map<String, dynamic>,
    );
    expect(prefs.audioLanguage, 'chi');
    expect(prefs.subtitleLanguage, 'jpn');
  });

  testWidgets('the screenshot pause switch persists (S42)', (tester) async {
    final store = InMemoryKeyValueStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          screenshotSettingsStoreProvider.overrideWith((ref) async => store),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: const ScreenshotSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('screenshot-settings-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-screenshot-pause')));
    await tester.pumpAndSettle();

    final Map<String, dynamic> json = jsonDecode(
      (await store.read(ScreenshotSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['pauseWhileCapturing'], true);
  });
  testWidgets('the mpv audio and subtitle defaults persist (S41)', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, const MpvSettingsPage(), store);

    await tester.tap(find.byKey(const Key('settings-force-stereo')));
    await tester.pumpAndSettle();
    final Map<String, dynamic> json = jsonDecode(
      (await store.read(PlaybackSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['forceStereo'], false);

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-sub-border')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.descendant(
        of: find.byKey(const Key('settings-sub-border')),
        matching: find.byType(Slider),
      ),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    final SubtitleStyle style = SubtitleStyle.fromJson(
      jsonDecode((await store.read(SubtitleStyle.storageKey))!)
          as Map<String, dynamic>,
    );
    expect(style.borderSize, lessThan(3.0));
    expect(style.borderSize, greaterThanOrEqualTo(0.0));
  });
  testWidgets('the mpv switches persist the advanced flags (S33)', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, const MpvSettingsPage(), store);

    await tester.tap(find.byKey(const Key('settings-adv-gpu-next')));
    await tester.pumpAndSettle();
    final Map<String, dynamic> json = jsonDecode(
      (await store.read(PlaybackSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['gpuNext'], true);
  });
}

/// A store whose writes always fail, to exercise the save-failure snackbar.
class _ThrowingStore extends InMemoryKeyValueStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('disk full');
  }
}
