import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/app/theme_mode_settings.dart';
import 'package:media_player/app/update_providers.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/login/login_page.dart';
import 'package:media_player/features/settings/settings_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';

/// No stored session: the startup gate lands on the login page, which is the
/// cheapest route to the settings entry.
class _SignedOutAuth implements AuthService {
  @override
  AuthSession? get current => null;

  @override
  Stream<AuthSession?> get session => const Stream<AuthSession?>.empty();

  @override
  Future<AuthSession?> restore() async => null;

  @override
  Future<ServerProfile?> lastProfile() async => null;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required ServerProfile profile,
  }) => throw UnimplementedError();

  @override
  Future<ServerProfile> adoptAddress({
    required ServerProfile profile,
    required EndpointKind kind,
    required String rawUrl,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> handleUnauthorized() async {}
}

PackageInfo _packageInfo() => PackageInfo(
  appName: 'Media Player',
  packageName: 'dev.mediaplayer.media_player',
  version: '1.2.3',
  buildNumber: '4',
);

void main() {
  /// Pumps the real root widget so the assertions cover the app-wide wiring
  /// (MaterialApp.themeMode + the Material palette every page reads), not a
  /// settings-only harness.
  Future<void> pumpApp(WidgetTester tester, {KeyValueStore? store}) async {
    // The settings list holds four sections; a 600pt window would keep the
    // lower rows outside the lazy ListView's build range.
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: _SignedOutAuth(),
              library: FakeLibraryService(),
              posters: FakePosterCache(),
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
              store: store ?? InMemoryKeyValueStore(),
            ),
          ),
          appVersionProvider.overrideWith((ref) async => _packageInfo()),
          feedbackServiceConfigProvider.overrideWithValue(null),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('login-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  }

  Future<void> pickMode(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(Key('settings-theme-$name')));
    await tester.pumpAndSettle();
  }

  bool chipSelected(WidgetTester tester, String name) => tester
      .widget<ChoiceChip>(find.byKey(Key('settings-theme-$name')))
      .selected;

  ThemeMode? appThemeMode(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;

  ColorScheme pageScheme(WidgetTester tester, Type page) =>
      Theme.of(tester.element(find.byType(page))).colorScheme;

  Future<void> flushSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('a persisted mode is applied at startup, before settings opens', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await store.write(themeModeStorageKey, 'dark');
    await pumpApp(tester, store: store);

    expect(appThemeMode(tester), ThemeMode.dark);
    expect(pageScheme(tester, LoginPage).brightness, Brightness.dark);

    await openSettings(tester);
    expect(find.text('当前：深色'), findsOneWidget);
    expect(chipSelected(tester, 'dark'), isTrue);
    expect(chipSelected(tester, 'system'), isFalse);
    expect(chipSelected(tester, 'light'), isFalse);
  });

  testWidgets('defaults to 跟随系统 and shows all three theme choices', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);

    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('当前：跟随系统'), findsOneWidget);
    expect(chipSelected(tester, 'system'), isTrue);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(appThemeMode(tester), ThemeMode.system);
  });

  testWidgets(
    'tapping 深色 applies the dark Material palette app-wide and persists',
    (tester) async {
      final store = InMemoryKeyValueStore();
      await pumpApp(tester, store: store);
      await openSettings(tester);

      await pickMode(tester, 'dark');

      expect(await store.read(themeModeStorageKey), 'dark');
      expect(appThemeMode(tester), ThemeMode.dark);
      expect(find.text('当前：深色'), findsOneWidget);
      expect(chipSelected(tester, 'dark'), isTrue);
      final ColorScheme palette = pageScheme(tester, SettingsPage);
      expect(palette.brightness, Brightness.dark);
      expect(
        Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.dark,
      );

      // Leaving settings keeps the choice: the login page repaints dark too.
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(pageScheme(tester, LoginPage).brightness, Brightness.dark);
    },
  );

  testWidgets('tapping 浅色 switches back to the light Material palette', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpApp(tester, store: store);
    await openSettings(tester);

    await pickMode(tester, 'dark');
    await pickMode(tester, 'light');

    expect(await store.read(themeModeStorageKey), 'light');
    expect(appThemeMode(tester), ThemeMode.light);
    expect(find.text('当前：浅色'), findsOneWidget);
    expect(pageScheme(tester, SettingsPage).brightness, Brightness.light);
  });

  testWidgets('跟随系统 follows the platform brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final store = InMemoryKeyValueStore();
    await pumpApp(tester, store: store);
    await openSettings(tester);

    await pickMode(tester, 'dark');
    await pickMode(tester, 'system');

    expect(await store.read(themeModeStorageKey), 'system');
    expect(appThemeMode(tester), ThemeMode.system);
    expect(find.text('当前：跟随系统'), findsOneWidget);
    // The OS is dark, so following it must resolve to the dark Material palette.
    expect(pageScheme(tester, SettingsPage).brightness, Brightness.dark);
  });

  testWidgets('a failed write keeps the current palette and warns', (
    tester,
  ) async {
    await pumpApp(tester, store: _FailingWriteStore());
    await openSettings(tester);

    await pickMode(tester, 'dark');

    expect(find.textContaining('主题模式保存失败'), findsOneWidget);
    expect(appThemeMode(tester), ThemeMode.system);
    expect(chipSelected(tester, 'system'), isTrue);
    expect(find.text('当前：跟随系统'), findsOneWidget);

    await flushSnackBar(tester);
  });
}

class _FailingWriteStore extends InMemoryKeyValueStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('disk full');
  }
}
