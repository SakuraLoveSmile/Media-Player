import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/update_providers.dart';
import 'package:media_player/data/update/update_installer.dart';
import 'package:media_player/data/update/update_models.dart';
import 'package:media_player/data/update/update_service.dart';
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

/// Records the controller's calls and lets a test hold the download open.
class FakeUpdateService extends UpdateService {
  FakeUpdateService(this.tempDir);

  final Directory tempDir;

  AppRelease? release;
  Object? downloadError;
  Completer<void>? downloadGate;
  int downloadCalls = 0;
  final List<String> downloadedAssets = <String>[];

  @override
  Future<AppRelease?> checkForUpdate({
    String? platform,
    UpdateChannel channel = UpdateChannel.stable,
  }) async => release;

  @override
  Future<File> downloadUpdate(
    AppRelease release,
    ReleaseAsset asset, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    downloadCalls++;
    downloadedAssets.add(asset.name);
    onProgress?.call(1024 * 1024, 2 * 1024 * 1024);

    final Object? error = downloadError;
    if (error != null) throw error;

    final Completer<void>? gate = downloadGate;
    if (gate != null) await gate.future;

    // The dialog only renders the asset metadata; no file IO is needed and
    // avoiding it keeps the fake fully synchronous under FakeAsync.
    return File('${tempDir.path}/download-$downloadCalls.bin');
  }
}

class FakeUpdateInstaller extends UpdateInstaller {
  int installCalls = 0;
  int openPageCalls = 0;
  Object? installError;

  @override
  Future<void> installUpdate(File package, AppRelease release) async {
    installCalls++;
    final Object? error = installError;
    if (error != null) throw error;
  }

  @override
  Future<void> openReleasePage(AppRelease release) async {
    openPageCalls++;
  }
}

AppRelease fakeRelease({String notes = '修复若干问题', bool withAssets = true}) {
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
    assets: withAssets
        ? <ReleaseAsset>[
            for (final String name in names)
              ReleaseAsset(
                name: name,
                downloadUrl: Uri.parse('https://example.com/$name'),
                sizeBytes: 3 * 1024 * 1024,
                sha256: 'a' * 64,
              ),
          ]
        : const <ReleaseAsset>[],
    isPrerelease: false,
  );
}

/// Host page that opens the dialog from a button, mirroring how the settings
/// page (or the app shell) starts the flow.
class DialogHost extends StatelessWidget {
  const DialogHost({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => unawaited(showUpdateDialog(context)),
          child: const Text('打开更新弹窗'),
        ),
      ),
    );
  }
}

void main() {
  late Directory tempDir;
  late FakeUpdateService service;
  late FakeUpdateInstaller installer;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mediaplayer-update-ui');
    service = FakeUpdateService(tempDir);
    installer = FakeUpdateInstaller();
    container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWith((ref) async => _packageInfo()),
        updateServiceProvider.overrideWithValue(service),
        updateInstallerProvider.overrideWithValue(installer),
        updatePlatformProvider.overrideWithValue('macos'),
        feedbackServiceConfigProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: _appTheme(), home: const DialogHost()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('打开更新弹窗'));
    await tester.pumpAndSettle();
  }

  Future<void> prepareAvailable(
    WidgetTester tester, {
    bool withAssets = true,
  }) async {
    service.release = fakeRelease(withAssets: withAssets);
    await container.read(updateControllerProvider.notifier).check();
    await pumpHost(tester);
    await openDialog(tester);
  }

  testWidgets('available shows the release details and update actions', (
    tester,
  ) async {
    await prepareAvailable(tester);

    expect(find.text('发现新版本 v1.2.0'), findsOneWidget);
    expect(find.text('修复若干问题'), findsOneWidget);
    expect(find.textContaining('安装包：'), findsOneWidget);
    expect(find.text('大小：3.0 MB'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('取消下载'), findsNothing);
  });

  testWidgets('starting the download calls the service and shows progress', (
    tester,
  ) async {
    service.downloadGate = Completer<void>();
    await prepareAvailable(tester);

    await tester.tap(find.text('立即更新'));
    await tester.pump();
    await tester.pump();

    expect(service.downloadCalls, 1);
    expect(
      container.read(updateControllerProvider).status,
      UpdateStatus.downloading,
    );
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('取消下载'), findsOneWidget);
    expect(find.text('稍后'), findsNothing);

    // A busy download must not be dismissible with the system back gesture.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(UpdateDialog), findsOneWidget);

    // Cancel brings the flow back to `available`.
    await tester.tap(find.text('取消下载'));
    await tester.pump();
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.byType(UpdateDialog), findsOneWidget);

    // Let the abandoned fake download finish so no work is left behind.
    service.downloadGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a finished download offers install', (tester) async {
    await prepareAvailable(tester);

    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 1);
    expect(
      container.read(updateControllerProvider).status,
      UpdateStatus.downloaded,
    );
    expect(find.text('立即安装'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('立即更新'), findsNothing);
  });

  testWidgets('install hands the package over and closes the dialog', (
    tester,
  ) async {
    await prepareAvailable(tester);

    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(
      container.read(updateControllerProvider).status,
      UpdateStatus.downloaded,
    );

    // The fake installer returns normally, so the controller goes back to
    // idle (the Android path) and the dialog closes itself.
    await tester.tap(find.text('立即安装'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(installer.installCalls, 1);
    expect(find.byType(UpdateDialog), findsNothing);
    expect(container.read(updateControllerProvider).status, UpdateStatus.idle);
  });

  testWidgets('a download failure shows the message and retry actions', (
    tester,
  ) async {
    service.downloadError = UpdateException('下载失败，请稍后重试');
    await prepareAvailable(tester);

    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();

    expect(container.read(updateControllerProvider).status, UpdateStatus.error);
    expect(find.text('下载失败，请稍后重试'), findsOneWidget);
    expect(find.text('打开下载页'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('打开下载页'));
    await tester.pump();
    expect(installer.openPageCalls, 1);
  });

  testWidgets('later dismisses the update and closes the dialog', (
    tester,
  ) async {
    await prepareAvailable(tester);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateDialog), findsNothing);
    expect(container.read(updateControllerProvider).status, UpdateStatus.idle);
  });

  testWidgets(
    'a release without a matching asset points at the download page',
    (tester) async {
      await prepareAvailable(tester, withAssets: false);

      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('打开下载页'), findsOneWidget);
      expect(find.text('立即更新'), findsNothing);

      await tester.tap(find.text('打开下载页'));
      await tester.pump();
      expect(installer.openPageCalls, 1);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateDialog), findsNothing);
    },
  );
}
