import 'dart:convert';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/accent_settings.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/app/update_providers.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/login/login_page.dart';
import 'package:media_player/features/settings/appearance_page.dart';
import 'package:media_player/features/settings/settings_page.dart';
import 'package:media_player/ui/theme/app_accent.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';

/// No stored session: the startup gate lands on the login page, the cheapest
/// route to the settings entry.
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

/// The colour the mocked OS reports as the system (Monet) accent.
const int _systemAccent = 0xFF00AABB;

void main() {
  /// Pumps the real root widget so assertions cover the app-wide wiring
  /// (MaterialApp.theme seed + the Material palette every page reads), not a
  /// settings-only harness.
  Future<void> pumpApp(WidgetTester tester, {KeyValueStore? store}) async {
    // 设置 and its 外观 sub-page hold many sections; a tall surface keeps the
    // accent chips and the Monet switch inside the lazy ListView's build range.
    await tester.binding.setSurfaceSize(const Size(800, 2000));
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

  /// 外观 is one level below 设置: the theme and accent controls live there now.
  Future<void> openAppearance(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-appearance')));
    await tester.pumpAndSettle();
    expect(find.byType(AppearancePage), findsOneWidget);
  }

  /// Pops 外观 and re-asserts the settings level the palette is read from.
  Future<void> backToSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(AppearancePage), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  }

  Future<void> pickAccent(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(Key('settings-accent-$name')));
    await tester.pumpAndSettle();
  }

  Future<void> toggleMonet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-monet')));
    await tester.pumpAndSettle();
  }

  bool chipSelected(WidgetTester tester, String name) => tester
      .widget<ChoiceChip>(find.byKey(Key('settings-accent-$name')))
      .selected;

  bool monetOn(WidgetTester tester) => tester
      .widget<SwitchListTile>(find.byKey(const Key('settings-monet')))
      .value;

  Color appPrimary(WidgetTester tester) => tester
      .widget<MaterialApp>(find.byType(MaterialApp))
      .theme!
      .colorScheme
      .primary;

  ColorScheme pageScheme(WidgetTester tester, Type page) =>
      Theme.of(tester.element(find.byType(page))).colorScheme;

  Color seedPrimary(Color seed, [Brightness brightness = Brightness.light]) =>
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness).primary;

  /// Makes the OS report a dynamic accent through the dynamic_color channel.
  void mockSystemAccent(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DynamicColorPlugin.channel,
      (MethodCall call) async {
        if (call.method == 'getAccentColor') return _systemAccent;
        return null; // getCorePalette: fall through to the accent colour path.
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DynamicColorPlugin.channel,
        null,
      ),
    );
  }

  Future<void> flushSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to 默认 with Monet off and all six presets', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);
    await openAppearance(tester);

    expect(find.text('主题色'), findsOneWidget);
    expect(find.text('当前：默认'), findsOneWidget);
    expect(chipSelected(tester, 'default'), isTrue);
    expect(monetOn(tester), isFalse);
    for (final AppAccentPreset preset in AppAccentPresets.all) {
      expect(find.byKey(Key('settings-accent-${preset.name}')), findsOneWidget);
    }
    expect(appPrimary(tester), seedPrimary(appDefaultAccent));

    await backToSettings(tester);
  });

  testWidgets(
    'a persisted accent is applied at startup, before settings opens',
    (tester) async {
      final store = InMemoryKeyValueStore();
      await store.write(
        accentStorageKey,
        jsonEncode(<String, Object?>{'mode': 'preset', 'preset': 'purple'}),
      );
      await pumpApp(tester, store: store);

      expect(appPrimary(tester), seedPrimary(AppAccentPresets.purple.color));
      expect(
        pageScheme(tester, LoginPage).primary,
        seedPrimary(AppAccentPresets.purple.color),
      );

      await openSettings(tester);
      await openAppearance(tester);
      expect(find.text('当前：紫'), findsOneWidget);
      expect(chipSelected(tester, 'purple'), isTrue);
      expect(chipSelected(tester, 'default'), isFalse);

      await backToSettings(tester);
    },
  );

  testWidgets('tapping an accent chip re-tints the app and persists', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpApp(tester, store: store);
    await openSettings(tester);
    await openAppearance(tester);

    await pickAccent(tester, 'green');

    expect(jsonDecode((await store.read(accentStorageKey))!), <String, Object?>{
      'mode': 'preset',
      'preset': 'green',
    });
    final Color expected = seedPrimary(AppAccentPresets.green.color);
    expect(appPrimary(tester), expected);
    expect(find.text('当前：绿'), findsOneWidget);
    expect(chipSelected(tester, 'green'), isTrue);
    expect(chipSelected(tester, 'default'), isFalse);

    // 外观 covers 设置, so the settings palette is only readable again after
    // popping back one level.
    await backToSettings(tester);
    expect(pageScheme(tester, SettingsPage).primary, expected);

    // Leaving settings keeps the choice: the login page repaints too.
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(pageScheme(tester, LoginPage).primary, expected);
  });

  testWidgets('the Monet switch persists and reports the current label', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpApp(tester, store: store);
    await openSettings(tester);
    await openAppearance(tester);

    await toggleMonet(tester);

    expect(jsonDecode((await store.read(accentStorageKey))!), <String, Object?>{
      'mode': 'monet',
    });
    expect(monetOn(tester), isTrue);
    expect(find.text('当前：跟随系统 (Monet)'), findsOneWidget);
    // No preset chip reads as selected while Monet is on.
    for (final AppAccentPreset preset in AppAccentPresets.all) {
      expect(chipSelected(tester, preset.name), isFalse);
    }

    await toggleMonet(tester);
    expect(jsonDecode((await store.read(accentStorageKey))!), <String, Object?>{
      'mode': 'default',
    });
    expect(monetOn(tester), isFalse);

    await backToSettings(tester);
  });

  testWidgets('picking a preset while Monet is on leaves Monet', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpApp(tester, store: store);
    await openSettings(tester);
    await openAppearance(tester);

    await toggleMonet(tester);
    expect(monetOn(tester), isTrue);

    await pickAccent(tester, 'orange');
    expect(monetOn(tester), isFalse);
    expect(chipSelected(tester, 'orange'), isTrue);
    expect(appPrimary(tester), seedPrimary(AppAccentPresets.orange.color));
    expect(jsonDecode((await store.read(accentStorageKey))!), <String, Object?>{
      'mode': 'preset',
      'preset': 'orange',
    });

    await backToSettings(tester);
  });

  testWidgets(
    'non-Android falls back to the preset even when the OS reports a colour',
    (tester) async {
      mockSystemAccent(tester);

      final store = InMemoryKeyValueStore();
      await pumpApp(tester, store: store);
      await openSettings(tester);
      await openAppearance(tester);

      await pickAccent(tester, 'green');
      await toggleMonet(tester);

      // Monet is on and persisted, but macOS must keep the chosen preset.
      expect(monetOn(tester), isTrue);
      expect(
        jsonDecode((await store.read(accentStorageKey))!),
        <String, Object?>{'mode': 'monet', 'preset': 'green'},
      );
      expect(appPrimary(tester), seedPrimary(AppAccentPresets.green.color));
      expect(
        appPrimary(tester),
        isNot(seedPrimary(const Color(_systemAccent))),
      );

      await backToSettings(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('non-Android with no preset falls back to the brand default', (
    tester,
  ) async {
    mockSystemAccent(tester);

    final store = InMemoryKeyValueStore();
    await pumpApp(tester, store: store);
    await openSettings(tester);
    await openAppearance(tester);

    await toggleMonet(tester);

    expect(monetOn(tester), isTrue);
    expect(appPrimary(tester), seedPrimary(appDefaultAccent));

    await backToSettings(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Android applies the system Monet accent when enabled', (
    tester,
  ) async {
    mockSystemAccent(tester);

    final store = InMemoryKeyValueStore();
    await pumpApp(tester, store: store);
    await openSettings(tester);
    await openAppearance(tester);

    // Before enabling Monet the brand default still applies.
    expect(appPrimary(tester), seedPrimary(appDefaultAccent));

    await toggleMonet(tester);

    expect(monetOn(tester), isTrue);
    expect(appPrimary(tester), seedPrimary(const Color(_systemAccent)));

    // 外观 covers 设置, so the settings palette is only readable again after
    // popping back one level.
    await backToSettings(tester);
    expect(
      pageScheme(tester, SettingsPage).primary,
      seedPrimary(const Color(_systemAccent)),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'Android with Monet off keeps the preset despite a system colour',
    (tester) async {
      mockSystemAccent(tester);

      final store = InMemoryKeyValueStore();
      await pumpApp(tester, store: store);
      await openSettings(tester);
      await openAppearance(tester);

      await pickAccent(tester, 'pink');
      expect(appPrimary(tester), seedPrimary(AppAccentPresets.pink.color));
      expect(
        appPrimary(tester),
        isNot(seedPrimary(const Color(_systemAccent))),
      );

      await backToSettings(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('a failed write keeps the current accent and warns', (
    tester,
  ) async {
    await pumpApp(tester, store: _FailingWriteStore());
    await openSettings(tester);
    await openAppearance(tester);

    await pickAccent(tester, 'green');

    expect(find.textContaining('主题色保存失败'), findsOneWidget);
    expect(appPrimary(tester), seedPrimary(appDefaultAccent));
    expect(chipSelected(tester, 'default'), isTrue);
    expect(find.text('当前：默认'), findsOneWidget);

    await flushSnackBar(tester);
    await backToSettings(tester);
  });
}

class _FailingWriteStore extends InMemoryKeyValueStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('disk full');
  }
}
