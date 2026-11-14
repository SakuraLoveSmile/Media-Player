import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/appearance_settings.dart';
import 'package:media_player/app/playback_settings.dart';
import 'package:media_player/app/screenshot_settings.dart';
import 'package:media_player/app/subtitle_style_settings.dart';
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
    expect(find.text('悬浮胶囊'), findsWidgets);

    await tester.tap(find.byKey(const Key('appearance-nav-standard')));
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

    expect(find.byKey(const Key('appearance-loader-dots')), findsOneWidget);
    await tester.tap(find.byKey(const Key('appearance-loader-dots')));
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

  testWidgets('the language chips persist track prefs (S33)', (tester) async {
    final store = InMemoryKeyValueStore();
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
