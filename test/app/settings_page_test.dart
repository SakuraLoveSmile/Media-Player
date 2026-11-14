import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/accent_settings.dart';
import 'package:media_player/app/admin_providers.dart';
import 'package:media_player/app/backup_settings.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/feedback_orb_settings.dart';
import 'package:media_player/app/general_settings.dart';
import 'package:media_player/app/hidden_libraries.dart';
import 'package:media_player/app/playback_settings.dart';
import 'package:media_player/app/request_notification_settings.dart';
import 'package:media_player/app/servers.dart';
import 'package:media_player/app/theme_mode_settings.dart';
import 'package:media_player/app/update_channel_settings.dart';
import 'package:media_player/app/update_providers.dart';
import 'package:media_player/core/config/app_config.dart';
import 'package:media_player/data/playback/playback_settings.dart';
import 'package:media_player/data/storage/backup_service.dart';
import 'package:media_player/data/update/update_installer.dart';
import 'package:media_player/data/update/update_models.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/update/update_service.dart';
import 'package:media_player/features/settings/settings_page.dart';
import 'package:media_player/features/settings/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/fake_backup_file_picker.dart';

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
    BackupService? backupService,
    bool isAdmin = false,
  }) async {
    // The settings list now holds six sections (about/update, appearance,
    // 播放/缓存, 求片, feedback, 备份/还原). A 600pt test window would keep the
    // lower rows out of the lazy ListView's build range, so use a tall
    // phone-height surface.
    await tester.binding.setSurfaceSize(const Size(800, 2000));
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
          // The 外观 selector reads the same app store.
          themeModeStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          // The 外观 accent chips + Monet switch read the same app store.
          accentStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          // The 播放/缓存 section reads the same app store.
          playbackSettingsStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          // The 服务器 section reads the same app store; without an override it
          // would await the real bootstrap and never settle.
          serverDirectoryStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          // The 求片 notification switches read the same app store; without an
          // override they would await the real bootstrap and never settle.
          requestNotificationStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          // The 备份/还原 section reads the same app store through a service;
          // without an override it would await the real bootstrap.
          backupServiceProvider.overrideWith(
            (ref) async =>
                backupService ??
                BackupService(
                  store ?? InMemoryKeyValueStore(),
                  FakeBackupFilePicker(),
                ),
          ),
          // S32 通用 reads the same app store for the SSL switch and the hidden
          // library list.
          generalSettingsStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          hiddenLibrariesStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          // S24: the 管理 entry gate; without an override it would await the
          // real bootstrap and never settle.
          isAdminProvider.overrideWith((ref) async => isAdmin),
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

  /// The 播放/缓存 number fields re-key on their value, so locate them through
  /// the stable wrapper key.
  Finder field(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextFormField),
  );

  /// S73: 关于 moved to the bottom of the list (Yamby order), so tests that
  /// assert on its rows have to scroll there first.
  Future<void> scrollToAbout(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('检查更新'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('switches the update channel and persists the choice', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpSettings(tester, store: store);
    await scrollToAbout(tester);

    expect(find.text('更新渠道'), findsOneWidget);
    expect(find.text('正式版'), findsWidgets);
    await tester.tap(
      find.widgetWithText(SegmentedButton<UpdateChannel>, '预览版'),
    );
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
    await scrollToAbout(tester);

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('Media Player'), findsOneWidget);
    expect(find.text('版本 1.2.3+4'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('falls back to the bundled version while the version loads', (
    tester,
  ) async {
    // S73: 关于 is the last section; a tall surface plus a scroll reaches it.
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
          themeModeStoreProvider.overrideWith(
            (ref) async => InMemoryKeyValueStore(),
          ),
          accentStoreProvider.overrideWith(
            (ref) async => InMemoryKeyValueStore(),
          ),
          playbackSettingsStoreProvider.overrideWith(
            (ref) async => InMemoryKeyValueStore(),
          ),
          serverDirectoryStoreProvider.overrideWith(
            (ref) async => InMemoryKeyValueStore(),
          ),
          backupServiceProvider.overrideWith(
            (ref) async =>
                BackupService(InMemoryKeyValueStore(), FakeBackupFilePicker()),
          ),
          isAdminProvider.overrideWith((ref) async => false),
          feedbackServiceConfigProvider.overrideWithValue(null),
        ],
        child: MaterialApp(theme: _appTheme(), home: const SettingsPage()),
      ),
    );
    await tester.pump();
    await scrollToAbout(tester);

    expect(find.text('版本 ${AppConfig.appVersion}'), findsOneWidget);

    gate.complete(_packageInfo());
    await tester.pumpAndSettle();
    expect(find.text('版本 1.2.3+4'), findsOneWidget);
  });

  testWidgets('a check without a newer release reports the latest version', (
    tester,
  ) async {
    await pumpSettings(tester);
    await scrollToAbout(tester);

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
    await scrollToAbout(tester);

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
    await scrollToAbout(tester);

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
    await scrollToAbout(tester);

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

  testWidgets('the admin entry is hidden for non-admins', (tester) async {
    await pumpSettings(tester, isAdmin: false);

    expect(find.byKey(const Key('settings-admin')), findsNothing);
    expect(find.text('服务器管理'), findsNothing);
    expect(find.text('管理'), findsNothing);
  });

  testWidgets('the admin entry is visible for admins', (tester) async {
    await pumpSettings(tester, isAdmin: true);

    expect(find.byKey(const Key('settings-admin')), findsOneWidget);
    expect(find.text('服务器管理'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
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

  testWidgets('通用 lists 图片缓存, 媒体库 and 忽略 SSL', (tester) async {
    await pumpSettings(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-cache')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('settings-cache')), findsOneWidget);
    expect(find.byKey(const Key('settings-libraries')), findsOneWidget);
    expect(find.byKey(const Key('settings-ignore-ssl')), findsOneWidget);
  });

  testWidgets('the 播放器 section offers the 弹幕 defaults (S36)', (tester) async {
    await pumpSettings(tester);

    final Finder mainList = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-danmaku')),
      300,
      scrollable: mainList,
    );
    expect(find.byKey(const Key('settings-danmaku')), findsOneWidget);
  });
  testWidgets('忽略 SSL persists and warns about the restart', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpSettings(tester, store: store);

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-ignore-ssl')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-ignore-ssl')));
    await tester.pumpAndSettle();

    expect(await store.read(ignoreSslStorageKey), 'true');
    expect(find.text('已开启，重启后生效'), findsOneWidget);
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

  testWidgets('the accent chips and Monet switch render and persist', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpSettings(tester, store: store);

    expect(find.text('主题色'), findsOneWidget);
    expect(find.text('当前：默认'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('settings-accent-default')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('settings-monet')))
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('settings-accent-green')));
    await tester.pumpAndSettle();
    expect(jsonDecode((await store.read(accentStorageKey))!), <String, Object?>{
      'mode': 'preset',
      'preset': 'green',
    });
    expect(find.text('当前：绿'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-monet')));
    await tester.pumpAndSettle();
    expect(jsonDecode((await store.read(accentStorageKey))!), <String, Object?>{
      'mode': 'monet',
      'preset': 'green',
    });
    expect(find.text('当前：跟随系统 (Monet)'), findsOneWidget);
  });

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
    await pumpSettings(tester, store: store);

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
  });

  testWidgets('the hwdec switch persists the choice', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpSettings(tester, store: store);

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
    await pumpSettings(tester, store: store);

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
    await pumpSettings(tester, store: store);

    await tester.ensureVisible(field('settings-cache-secs'));
    await tester.enterText(field('settings-cache-secs'), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('请输入正整数'), findsOneWidget);
    expect(await store.read(PlaybackSettings.storageKey), isNull);
    await flushSnackBar(tester);
  });

  testWidgets('export saves a JSON backup containing the whitelisted prefs', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await store.write('app.themeMode.v1', 'dark');
    await store.write(
      PlaybackSettings.storageKey,
      jsonEncode(const PlaybackSettings(cacheSecs: 45).toJson()),
    );
    // A credential planted in the same store must never reach the file.
    await store.write('mp.token.v1', 'super-secret-access-token');
    final picker = FakeBackupFilePicker();
    final service = BackupService(store, picker);
    await pumpSettings(tester, store: store, backupService: service);

    expect(find.text('备份/还原'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-backup-export')));
    await tester.pumpAndSettle();

    expect(picker.saveCalls, 1);
    final document =
        jsonDecode(utf8.decode(picker.savedBytes!)) as Map<String, dynamic>;
    expect(document['version'], 1);
    final prefs = document['prefs'] as Map<String, dynamic>;
    expect(prefs['app.themeMode.v1'], 'dark');
    expect(prefs.containsKey(PlaybackSettings.storageKey), isTrue);
    expect(prefs.containsKey('mp.token.v1'), isFalse);
    expect(utf8.decode(picker.savedBytes!).contains('super-secret'), isFalse);
    expect(find.text('备份已导出'), findsOneWidget);
    await flushSnackBar(tester);
  });

  testWidgets('restore applies prefs from the opened backup file', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    final picker = FakeBackupFilePicker(
      openBytes: utf8.encode(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'prefs': <String, dynamic>{
            'app.themeMode.v1': 'dark',
            PlaybackSettings.storageKey: jsonEncode(
              const PlaybackSettings(hwdecEnabled: false).toJson(),
            ),
          },
        }),
      ),
    );
    final service = BackupService(store, picker);
    await pumpSettings(tester, store: store, backupService: service);

    await tester.tap(find.byKey(const Key('settings-backup-restore')));
    await tester.pumpAndSettle();

    expect(picker.openCalls, 1);
    expect(await store.read('app.themeMode.v1'), 'dark');
    expect(
      jsonDecode(
        (await store.read(PlaybackSettings.storageKey))!,
      )['hwdecEnabled'],
      isFalse,
    );
    expect(find.textContaining('备份已导入'), findsOneWidget);
    await flushSnackBar(tester);
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
