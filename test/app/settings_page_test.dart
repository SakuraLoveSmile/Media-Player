import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/feedback_orb_settings.dart';
import 'package:media_player/app/request_notification_settings.dart';
import 'package:media_player/app/update_channel_settings.dart';
import 'package:media_player/app/update_providers.dart';
import 'package:media_player/core/config/app_config.dart';
import 'package:media_player/data/update/update_installer.dart';
import 'package:media_player/data/update/update_models.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/update/update_service.dart';
import 'package:media_player/features/settings/settings_page.dart';
import 'package:media_player/features/settings/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

ThemeData _appTheme() =>
    ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF3F51B5));

PackageInfo _packageInfo() => PackageInfo(
  appName: 'Media Player',
  packageName: 'dev.mediaplayer.media_player',
  version: '1.2.3',
  buildNumber: '4',
);

/// Local fake that only answers `checkForUpdate`; the settings page never
/// downloads anything.
class FakeUpdateService extends UpdateService {
  AppRelease? release;
  Object? checkError;
  Completer<AppRelease?>? checkGate;
  int checkCalls = 0;

  final List<UpdateChannel> channels = <UpdateChannel>[];

  @override
  Future<AppRelease?> checkForUpdate({
    String? platform,
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    checkCalls++;
    channels.add(channel);
    final Completer<AppRelease?>? gate = checkGate;
    if (gate != null) return gate.future;
    final Object? error = checkError;
    if (error != null) throw error;
    return release;
  }

  @override
  Future<File> downloadUpdate(
    AppRelease release,
    ReleaseAsset asset, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) {
    throw UnimplementedError();
  }
}

class FakeUpdateInstaller extends UpdateInstaller {
  int installCalls = 0;
  int openPageCalls = 0;

  @override
  Future<void> installUpdate(File package, AppRelease release) async {
    installCalls++;
  }

  @override
  Future<void> openReleasePage(AppRelease release) async {
    openPageCalls++;
  }
}

AppRelease fakeRelease({String notes = '修复若干问题'}) {
  final List<String> names = <String>[
    'MediaPlayer-android.apk',
    'MediaPlayer-windows-x64.zip',
    'MediaPlayer-macos.zip',
  ];
  return AppRelease(
    version: '1.2.0',
    tagName: 'v1.2.0',
    notes: notes,
    pageUrl: Uri.parse('https://example.com/releases/tag/v1.2.0'),
    publishedAt: DateTime.utc(2026, 1, 2),
    assets: <ReleaseAsset>[
      for (final String name in names)
        ReleaseAsset(
          name: name,
          downloadUrl: Uri.parse('https://example.com/$name'),
          sizeBytes: 3 * 1024 * 1024,
          sha256: 'a' * 64,
        ),
    ],
    isPrerelease: false,
  );
}

void main() {
  late FakeUpdateService service;
  late FakeUpdateInstaller installer;

  setUp(() {
    service = FakeUpdateService();
    installer = FakeUpdateInstaller();
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    FeedbackServiceConfig? feedback,
    FeedbackController? feedbackController,
    Future<PackageInfo>? version,
    KeyValueStore? store,
  }) async {
    // The settings list now holds four sections (about, update, 求片, feedback).
    // A 600pt test window would keep the lower rows out of the lazy ListView's
    // build range, so use a phone-height surface.
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith(
            (ref) => version ?? Future<PackageInfo>.value(_packageInfo()),
          ),
          updateServiceProvider.overrideWithValue(service),
          updateInstallerProvider.overrideWithValue(installer),
          updatePlatformProvider.overrideWithValue('macos'),
          feedbackOrbStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          updateChannelStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          // The 求片 notification switches read the same app store; without an
          // override they would await the real bootstrap and never settle.
          requestNotificationStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          feedbackServiceConfigProvider.overrideWithValue(feedback),
          if (feedbackController != null)
            feedbackControllerProvider.overrideWithValue(feedbackController),
        ],
        child: MaterialApp(theme: _appTheme(), home: const SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> flushSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('switches the update channel and persists the choice', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpSettings(tester, store: store);

    expect(find.text('更新渠道'), findsOneWidget);
    expect(find.text('正式版'), findsWidgets);
    await tester.tap(find.widgetWithText(SegmentedButton<UpdateChannel>, '预览版'));
    await tester.pumpAndSettle();
    expect(await store.read(updateChannelStorageKey), 'preview');

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(service.channels, contains(UpdateChannel.preview));
  });

  testWidgets('renders the about section with the current version', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('Media Player'), findsOneWidget);
    expect(find.text('版本 1.2.3+4'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('falls back to the bundled version while the version loads', (
    tester,
  ) async {
    final Completer<PackageInfo> gate = Completer<PackageInfo>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete(_packageInfo());
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) => gate.future),
          updateServiceProvider.overrideWithValue(service),
          updateInstallerProvider.overrideWithValue(installer),
          updatePlatformProvider.overrideWithValue('macos'),
          feedbackOrbStoreProvider.overrideWith(
            (ref) async => InMemoryKeyValueStore(),
          ),
          requestNotificationStoreProvider.overrideWith(
            (ref) async => InMemoryKeyValueStore(),
          ),
          feedbackServiceConfigProvider.overrideWithValue(null),
        ],
        child: MaterialApp(theme: _appTheme(), home: const SettingsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('版本 ${AppConfig.appVersion}'), findsOneWidget);

    gate.complete(_packageInfo());
    await tester.pumpAndSettle();
    expect(find.text('版本 1.2.3+4'), findsOneWidget);
  });

  testWidgets('a check without a newer release reports the latest version', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(find.byType(UpdateDialog), findsNothing);

    await flushSnackBar(tester);
  });

  testWidgets('an available update opens the update dialog', (tester) async {
    service.release = fakeRelease();
    await pumpSettings(tester);

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(find.textContaining('v1.2.0'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('a failed check shows the error message', (tester) async {
    service.checkError = UpdateException('GitHub 请求受限，请稍后重试');
    await pumpSettings(tester);

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub 请求受限，请稍后重试'), findsOneWidget);
    expect(find.byType(UpdateDialog), findsNothing);

    await flushSnackBar(tester);
  });

  testWidgets('the check entry is disabled and labelled while checking', (
    tester,
  ) async {
    service.checkGate = Completer<AppRelease?>();
    await pumpSettings(tester);

    await tester.tap(find.text('检查更新'));
    await tester.pump();

    expect(find.text('检查中…'), findsOneWidget);
    final ListTile tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '检查更新'),
    );
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);

    // Tapping the disabled entry must not start a second check.
    await tester.tap(find.text('检查更新'), warnIfMissed: false);
    await tester.pump();
    expect(service.checkCalls, 1);

    service.checkGate!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('当前已是最新版本'), findsOneWidget);
    await flushSnackBar(tester);
  });

  testWidgets('the feedback entry is hidden when the service is disabled', (
    tester,
  ) async {
    await pumpSettings(tester, feedback: null);

    expect(find.text('问题反馈'), findsNothing);
  });

  testWidgets('the feedback entry is shown when configured and opens capture', (
    tester,
  ) async {
    final FeedbackController controller = FeedbackController();
    addTearDown(controller.dispose);

    await pumpSettings(
      tester,
      feedback: const FeedbackServiceConfig(
        apiBase: 'https://feedback.test',
        appId: 'dev.mediaplayer.media_player',
      ),
      feedbackController: controller,
    );

    expect(find.text('问题反馈'), findsOneWidget);

    await tester.tap(find.text('问题反馈'));
    await tester.pump();

    expect(controller.isOpen, isTrue);
  });
  testWidgets('orb settings only appear when feedback is configured', (
    tester,
  ) async {
    await pumpSettings(tester, feedback: null);
    expect(find.text('灵感球样式'), findsNothing);
    expect(find.text('唤醒灵感球'), findsNothing);

    await pumpSettings(
      tester,
      feedback: const FeedbackServiceConfig(
        apiBase: 'https://feedback.test',
        appId: 'dev.mediaplayer.media_player',
      ),
    );
    expect(find.text('灵感球样式'), findsOneWidget);
    expect(find.text('唤醒灵感球'), findsOneWidget);
    expect(find.text('当前：小把手'), findsOneWidget);
    expect(find.text('当前：已关闭'), findsOneWidget);
  });

  testWidgets('selecting a hidden orb style persists it', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpSettings(
      tester,
      feedback: const FeedbackServiceConfig(
        apiBase: 'https://feedback.test',
        appId: 'dev.mediaplayer.media_player',
      ),
      store: store,
    );

    await tester.tap(find.text('灵感球样式'));
    await tester.pumpAndSettle();
    expect(find.text('隐藏'), findsOneWidget);

    await tester.tap(find.text('隐藏'));
    await tester.pumpAndSettle();

    expect(find.text('当前：隐藏'), findsOneWidget);
    expect(await store.read(feedbackOrbIdleStorageKey), 'hidden');
  });

  testWidgets('selecting a wake gesture persists its stable id', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpSettings(
      tester,
      feedback: const FeedbackServiceConfig(
        apiBase: 'https://feedback.test',
        appId: 'dev.mediaplayer.media_player',
      ),
      store: store,
    );

    await tester.tap(find.text('唤醒灵感球'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('双指长按'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('当前：双指长按'), findsOneWidget);
    final raw = await store.read(feedbackWakeGesturesStorageKey);
    expect(jsonDecode(raw!), contains('two-finger-hold'));
  });

  testWidgets('a failed orb preference write keeps the old value and warns', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      feedback: const FeedbackServiceConfig(
        apiBase: 'https://feedback.test',
        appId: 'dev.mediaplayer.media_player',
      ),
      store: _ThrowingStore(),
    );

    await tester.tap(find.text('灵感球样式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏'));
    await tester.pumpAndSettle();

    expect(find.text('当前：小把手'), findsOneWidget);
    expect(find.text('保存失败，请稍后重试'), findsOneWidget);
  });
}

class _ThrowingStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('disk full');
  }

  @override
  Future<void> delete(String key) async {}
}
