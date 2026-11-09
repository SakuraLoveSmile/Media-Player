import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken, ProgressCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/update_providers.dart';
import 'package:media_player/data/update/update_installer.dart';
import 'package:media_player/data/update/update_models.dart';
import 'package:media_player/data/update/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String _sha =
    '0123456789abcdef0123456789abcdef'
    '0123456789abcdef0123456789abcdef';

typedef _DownloadHandler = Future<File> Function(
  AppRelease release,
  ReleaseAsset asset,
  ProgressCallback? onProgress,
  CancelToken? cancelToken,
);

class _FakeUpdateService extends UpdateService {
  Future<AppRelease?> Function()? onCheck;
  _DownloadHandler? onDownload;

  int checkCalls = 0;
  int downloadCalls = 0;
  final List<String?> platforms = <String?>[];

  @override
  Future<AppRelease?> checkForUpdate({
    String? platform,
    UpdateChannel channel = UpdateChannel.stable,
  }) {
    checkCalls++;
    platforms.add(platform);
    return onCheck?.call() ?? Future<AppRelease?>.value();
  }

  @override
  Future<File> downloadUpdate(
    AppRelease release,
    ReleaseAsset asset, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) {
    downloadCalls++;
    final _DownloadHandler? handler = onDownload;
    if (handler == null) {
      return Future<File>.error(StateError('no download handler'));
    }
    return handler(release, asset, onProgress, cancelToken);
  }
}

class _FakeUpdateInstaller extends UpdateInstaller {
  Future<void> Function(File package, AppRelease release)? onInstall;
  Future<void> Function(AppRelease release)? onOpenPage;

  final List<File> installed = <File>[];
  final List<AppRelease> opened = <AppRelease>[];

  @override
  Future<void> installUpdate(File package, AppRelease release) {
    installed.add(package);
    return onInstall?.call(package, release) ?? Future<void>.value();
  }

  @override
  Future<void> openReleasePage(AppRelease release) {
    opened.add(release);
    return onOpenPage?.call(release) ?? Future<void>.value();
  }
}

ReleaseAsset _asset(String name) {
  return ReleaseAsset(
    name: name,
    downloadUrl: Uri.parse('https://example.test/$name'),
    sizeBytes: 4096,
    sha256: _sha,
  );
}

AppRelease _release({List<ReleaseAsset>? assets, bool prerelease = false}) {
  return AppRelease(
    version: '0.2.0',
    tagName: 'v0.2.0',
    notes: '修复若干问题',
    pageUrl: Uri.parse(
      'https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.0',
    ),
    publishedAt: DateTime.utc(2026, 10, 1, 12),
    isPrerelease: prerelease,
    assets:
        assets ??
        <ReleaseAsset>[
          _asset('MediaPlayer-macos.zip'),
          _asset('MediaPlayer-windows-x64.zip'),
          _asset('MediaPlayer-android.apk'),
        ],
  );
}

void main() {
  // The controller's platform is overridden below so the selected asset is the
  // same on every CI runner (Linux runners have no release asset otherwise).
  const String platform = 'macos';
  final ReleaseAsset? platformAsset = pickAsset(
    _release().assets,
    platform: platform,
  );

  late Directory tempDir;
  late _FakeUpdateService service;
  late _FakeUpdateInstaller installer;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('update_controller_test_');
    service = _FakeUpdateService();
    installer = _FakeUpdateInstaller();
    container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWith(
          (Ref ref) async => PackageInfo(
            appName: 'Media Player',
            packageName: 'media_player',
            version: '0.1.0',
            buildNumber: '1',
          ),
        ),
        updateServiceProvider.overrideWithValue(service),
        updateInstallerProvider.overrideWithValue(installer),
        updatePlatformProvider.overrideWithValue('macos'),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  UpdateController controller() =>
      container.read(updateControllerProvider.notifier);

  UpdateState state() => container.read(updateControllerProvider);

  Future<File> createDownloadedFile() async {
    final Directory dir = await Directory(
      '${tempDir.path}${Platform.pathSeparator}download-'
      '${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    final File file = File(
      '${dir.path}${Platform.pathSeparator}${platformAsset?.name ?? 'package.zip'}',
    );
    await file.writeAsString('package-bytes');
    return file;
  }

  /// Runs check + download so tests start from the `downloaded` state.
  Future<File> prepareDownloadedFile() async {
    final AppRelease release = _release();
    service.onCheck = () async => release;
    await controller().check();
    final File file = await createDownloadedFile();
    service.onDownload =
        (
          AppRelease release,
          ReleaseAsset asset,
          ProgressCallback? onProgress,
          CancelToken? cancelToken,
        ) async {
          onProgress?.call(asset.sizeBytes, asset.sizeBytes);
          return file;
        };
    await controller().startDownload();
    expect(state().status, UpdateStatus.downloaded, reason: 'fixture setup');
    return file;
  }

  group('check', () {
    test('reports an available update with the platform asset', () async {
      final AppRelease release = _release();
      service.onCheck = () async => release;

      await controller().check();

      expect(state().status, UpdateStatus.available);
      expect(state().release?.version, '0.2.0');
      expect(state().asset?.name, platformAsset?.name);
      expect(service.platforms.single, platform);
      expect(state().errorMessage, isNull);
    });

    test('returns to idle when no update is available', () async {
      service.onCheck = () async => null;

      await controller().check();

      expect(state().status, UpdateStatus.idle);
      expect(state().release, isNull);
    });

    test('silent checks swallow failures', () async {
      service.onCheck = () async => throw const UpdateException('服务器错误');

      await controller().check(silent: true);

      expect(state().status, UpdateStatus.idle);
      expect(state().errorMessage, isNull);
    });

    test('non-silent checks surface the Chinese error message', () async {
      service.onCheck = () async => throw const UpdateException('服务器错误');

      await controller().check();

      expect(state().status, UpdateStatus.error);
      expect(state().errorMessage, '服务器错误');
    });

    test('unexpected failures fall back to a generic message', () async {
      service.onCheck = () async => throw StateError('boom');

      await controller().check();

      expect(state().status, UpdateStatus.error);
      expect(state().errorMessage, '检查更新失败，请稍后重试');
    });

    test('ignores concurrent checks', () async {
      final Completer<AppRelease?> pending = Completer<AppRelease?>();
      service.onCheck = () => pending.future;

      final Future<void> first = controller().check();
      await controller().check();

      expect(service.checkCalls, 1);
      expect(state().status, UpdateStatus.checking);

      pending.complete(null);
      await first;
      expect(state().status, UpdateStatus.idle);
    });

    test('is ignored while downloading', () async {
      await prepareDownloadedFile();
      final int checksBefore = service.checkCalls;

      final Completer<File> pending = Completer<File>();
      service.onDownload = (
        AppRelease release,
        ReleaseAsset asset,
        ProgressCallback? onProgress,
        CancelToken? cancelToken,
      ) => pending.future;
      unawaited(controller().startDownload());
      await pumpEventQueue();

      await controller().check();

      expect(service.checkCalls, checksBefore);
      pending.completeError(const CancelException());
      await pumpEventQueue();
    });
  });

  group('download', () {
    test('streams progress and keeps the downloaded file', () async {
      final AppRelease release = _release();
      service.onCheck = () async => release;
      await controller().check();

      final File file = await createDownloadedFile();
      final List<UpdateState> snapshots = <UpdateState>[];
      final ProviderSubscription<UpdateState> subscription = container.listen(
        updateControllerProvider,
        (UpdateState? previous, UpdateState next) {
          snapshots.add(next);
        },
      );
      addTearDown(subscription.close);

      service.onDownload =
          (
            AppRelease release,
            ReleaseAsset asset,
            ProgressCallback? onProgress,
            CancelToken? cancelToken,
          ) async {
            onProgress?.call(asset.sizeBytes ~/ 4, asset.sizeBytes);
            onProgress?.call(asset.sizeBytes, asset.sizeBytes);
            return file;
          };

      await controller().startDownload();

      expect(state().status, UpdateStatus.downloaded);
      expect(state().file?.path, file.path);
      expect(state().progress, 1);
      expect(state().receivedBytes, state().totalBytes);
      expect(
        snapshots.any(
          (UpdateState snapshot) =>
              snapshot.status == UpdateStatus.downloading &&
              snapshot.progress > 0 &&
              snapshot.progress < 1,
        ),
        isTrue,
      );
    }, skip: platformAsset == null ? '当前平台没有匹配的安装包' : false);

    test('reports a missing platform asset instead of downloading', () async {
      service.onCheck = () async =>
          _release(assets: <ReleaseAsset>[_asset('MediaPlayer-unknown.zip')]);
      await controller().check();
      expect(state().status, UpdateStatus.available);
      expect(state().asset, isNull);

      await controller().startDownload();

      expect(state().status, UpdateStatus.error);
      expect(state().errorMessage, contains('暂无可用安装包'));
      expect(service.downloadCalls, 0);
    });

    test('keeps the release on download failure', () async {
      final AppRelease release = _release();
      service.onCheck = () async => release;
      await controller().check();
      service.onDownload = (
        AppRelease release,
        ReleaseAsset asset,
        ProgressCallback? onProgress,
        CancelToken? cancelToken,
      ) async => throw const UpdateException('磁盘空间不足');

      await controller().startDownload();

      expect(state().status, UpdateStatus.error);
      expect(state().errorMessage, '磁盘空间不足');
      expect(state().release?.version, '0.2.0');
      expect(state().file, isNull);
    }, skip: platformAsset == null ? '当前平台没有匹配的安装包' : false);

    test('cancel returns to available and ignores the late result', () async {
      final AppRelease release = _release();
      service.onCheck = () async => release;
      await controller().check();

      final Completer<File> pending = Completer<File>();
      CancelToken? token;
      service.onDownload =
          (
            AppRelease release,
            ReleaseAsset asset,
            ProgressCallback? onProgress,
            CancelToken? cancelToken,
          ) {
            token = cancelToken;
            onProgress?.call(1, 100);
            return pending.future;
          };

      final Future<void> started = controller().startDownload();
      await pumpEventQueue();
      expect(state().status, UpdateStatus.downloading);

      controller().cancelDownload();

      expect(state().status, UpdateStatus.available);
      expect(token?.isCancelled, isTrue);
      expect(state().release?.version, '0.2.0');

      // A late completion must not overwrite the cancelled state.
      pending.complete(await createDownloadedFile());
      await started;
      expect(state().status, UpdateStatus.available);
    }, skip: platformAsset == null ? '当前平台没有匹配的安装包' : false);

    test('retryDownload restarts a failed download', () async {
      final AppRelease release = _release();
      service.onCheck = () async => release;
      await controller().check();
      var attempts = 0;
      final File file = await createDownloadedFile();
      service.onDownload =
          (
            AppRelease release,
            ReleaseAsset asset,
            ProgressCallback? onProgress,
            CancelToken? cancelToken,
          ) async {
            attempts++;
            if (attempts == 1) {
              throw const UpdateException('网络中断');
            }
            return file;
          };

      await controller().startDownload();
      expect(state().status, UpdateStatus.error);

      await controller().retryDownload();

      expect(attempts, 2);
      expect(state().status, UpdateStatus.downloaded);
      expect(state().file?.path, file.path);
    }, skip: platformAsset == null ? '当前平台没有匹配的安装包' : false);
  });

  group('install', () {
    test('returns to idle after an in-place install', () async {
      final File file = await prepareDownloadedFile();

      await controller().install();

      expect(installer.installed.single.path, file.path);
      expect(state().status, UpdateStatus.idle);
      expect(state().file, isNull);
    }, skip: platformAsset == null ? '当前平台没有匹配的安装包' : false);

    test('keeps the downloaded file when installing fails', () async {
      final File file = await prepareDownloadedFile();
      installer.onInstall = (File package, AppRelease release) async =>
          throw const UpdateException('无法启动安装程序');

      await controller().install();

      expect(state().status, UpdateStatus.error);
      expect(state().errorMessage, '无法启动安装程序');
      expect(state().file?.path, file.path);
    }, skip: platformAsset == null ? '当前平台没有匹配的安装包' : false);
  });

  group('dismiss', () {
    test('removes the temporary download and resets the state', () async {
      final File file = await prepareDownloadedFile();
      final Directory downloadDir = file.parent;
      expect(await downloadDir.exists(), isTrue);

      controller().dismiss();
      await pumpEventQueue();

      expect(state().status, UpdateStatus.idle);
      expect(state().release, isNull);
      expect(await downloadDir.exists(), isFalse);
    }, skip: platformAsset == null ? '当前平台没有匹配的安装包' : false);
  });

  group('openReleasePage', () {
    test('opens the current release page', () async {
      final AppRelease release = _release();
      service.onCheck = () async => release;
      await controller().check();

      await controller().openReleasePage();

      expect(installer.opened.single.version, '0.2.0');
      expect(state().status, UpdateStatus.available);
    });

    test('reports an error when the browser cannot be opened', () async {
      final AppRelease release = _release();
      service.onCheck = () async => release;
      await controller().check();
      installer.onOpenPage = (AppRelease release) async =>
          throw const UpdateException('浏览器不可用');

      await controller().openReleasePage();

      expect(state().status, UpdateStatus.error);
      expect(state().errorMessage, '浏览器不可用');
      expect(state().release?.version, '0.2.0');
    });
  });
}
