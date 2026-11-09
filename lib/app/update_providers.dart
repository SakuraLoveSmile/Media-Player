import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/update/update_installer.dart';
import '../data/update/update_models.dart';
import '../data/update/update_service.dart';
import 'update_channel_settings.dart';

/// Lifecycle of the in-app update flow.
enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  downloaded,
  installing,
  error,
}

/// Immutable snapshot consumed by the settings page and the update dialog.
class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.asset,
    this.file,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.channel = UpdateChannel.stable,
  });

  final UpdateStatus status;
  final AppRelease? release;
  final ReleaseAsset? asset;
  final File? file;

  /// 0..1 download progress, also kept for platforms that report no total.
  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final String? errorMessage;

  /// Channel the last check used, so the UI can label a prerelease offer.
  final UpdateChannel channel;

  static const Object _unset = Object();

  UpdateState copyWith({
    UpdateStatus? status,
    Object? release = _unset,
    Object? asset = _unset,
    Object? file = _unset,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    Object? errorMessage = _unset,
    UpdateChannel? channel,
  }) {
    return UpdateState(
      status: status ?? this.status,
      release: identical(release, _unset)
          ? this.release
          : release as AppRelease?,
      asset: identical(asset, _unset) ? this.asset : asset as ReleaseAsset?,
      file: identical(file, _unset) ? this.file : file as File?,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      channel: channel ?? this.channel,
    );
  }
}

/// Running package metadata; overridden in widget tests.
final FutureProvider<PackageInfo> appVersionProvider =
    FutureProvider<PackageInfo>((Ref ref) => PackageInfo.fromPlatform());

/// Optional GitHub API base override for local end-to-end checks
/// (`--dart-define=UPDATE_API_BASE=http://127.0.0.1:18123`). Production builds
/// leave it empty and talk to api.github.com.
const String _updateApiBaseOverride = String.fromEnvironment('UPDATE_API_BASE');

final Provider<UpdateService> updateServiceProvider = Provider<UpdateService>(
  (Ref ref) => UpdateService(
    packageInfoLoader: () => ref.read(appVersionProvider.future),
    githubApiBase: _updateApiBaseOverride.isEmpty
        ? UpdateService.defaultGitHubApiBase
        : _updateApiBaseOverride,
  ),
);

final Provider<UpdateInstaller> updateInstallerProvider =
    Provider<UpdateInstaller>((Ref ref) => UpdateInstaller());

/// Runtime platform passed to [UpdateService] and [pickAsset].
///
/// A provider (instead of a direct `Platform.operatingSystem` read) keeps the
/// asset-selection tests deterministic on Linux CI runners: widget tests
/// override it with the platform whose release assets they provide.
final Provider<String> updatePlatformProvider = Provider<String>(
  (Ref ref) => Platform.operatingSystem,
);

final NotifierProvider<UpdateController, UpdateState> updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// Drives check / download / install for the settings page and startup check.
///
/// A generation counter invalidates late download callbacks (cancel, dismiss,
/// a newer check) so a stale result can never overwrite newer state.
class UpdateController extends Notifier<UpdateState> {
  CancelToken? _downloadToken;
  int _generation = 0;

  @override
  UpdateState build() {
    ref.onDispose(() {
      _downloadToken?.cancel();
      _downloadToken = null;
    });
    return const UpdateState();
  }

  /// Checks GitHub for a newer release.
  ///
  /// [silent] is used by the startup check: failures reset to [idle] instead
  /// of surfacing an error the user did not ask for.
  Future<void> check({bool silent = false}) async {
    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.installing) {
      return;
    }
    final int generation = ++_generation;
    _downloadToken = null;
    state = const UpdateState(status: UpdateStatus.checking);
    try {
      final String platform = ref.read(updatePlatformProvider);
      final UpdateChannel channel = ref
              .read(updateChannelControllerProvider)
              .value ??
          UpdateChannel.stable;
      final AppRelease? release = await ref
          .read(updateServiceProvider)
          .checkForUpdate(platform: platform, channel: channel);
      if (!_isCurrent(generation)) return;
      if (release == null) {
        state = const UpdateState();
        return;
      }
      state = UpdateState(
        status: UpdateStatus.available,
        release: release,
        asset: pickAsset(release.assets, platform: platform),
        channel: channel,
      );
    } on UpdateException catch (error) {
      if (!_isCurrent(generation)) return;
      state = silent
          ? const UpdateState()
          : UpdateState(
              status: UpdateStatus.error,
              errorMessage: error.message,
            );
    } on CancelException {
      if (!_isCurrent(generation)) return;
      state = const UpdateState();
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = silent
          ? const UpdateState()
          : const UpdateState(
              status: UpdateStatus.error,
              errorMessage: '检查更新失败，请稍后重试',
            );
    }
  }

  /// Downloads the asset selected during [check].
  Future<void> startDownload() async {
    final AppRelease? release = state.release;
    final ReleaseAsset? asset = state.asset;
    if (release != null && asset == null) {
      state = UpdateState(
        status: UpdateStatus.error,
        release: release,
        errorMessage: '当前平台暂无可用安装包，请打开下载页手动下载。',
      );
      return;
    }
    if (release == null || asset == null) return;
    if (state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.installing) {
      return;
    }

    final int generation = ++_generation;
    final CancelToken token = CancelToken();
    _downloadToken = token;
    state = UpdateState(
      status: UpdateStatus.downloading,
      release: release,
      asset: asset,
    );
    try {
      final File file = await ref
          .read(updateServiceProvider)
          .downloadUpdate(
            release,
            asset,
            cancelToken: token,
            onProgress: (int received, int total) {
              if (!_isCurrent(generation)) return;
              if (state.status != UpdateStatus.downloading) return;
              final int totalBytes = total > 0
                  ? total
                  : (asset.sizeBytes > 0 ? asset.sizeBytes : state.totalBytes);
              final double progress = totalBytes > 0
                  ? (received / totalBytes).clamp(0.0, 1.0).toDouble()
                  : 0;
              state = state.copyWith(
                progress: progress,
                receivedBytes: received,
                totalBytes: totalBytes,
              );
            },
          );
      if (!_isCurrent(generation)) return;
      _downloadToken = null;
      final int totalBytes = state.totalBytes > 0
          ? state.totalBytes
          : asset.sizeBytes;
      state = state.copyWith(
        status: UpdateStatus.downloaded,
        file: file,
        progress: 1,
        receivedBytes: totalBytes > 0 ? totalBytes : state.receivedBytes,
        totalBytes: totalBytes,
        errorMessage: null,
      );
    } on CancelException {
      if (!_isCurrent(generation)) return;
      _downloadToken = null;
      state = UpdateState(
        status: UpdateStatus.available,
        release: release,
        asset: asset,
      );
    } on UpdateException catch (error) {
      if (!_isCurrent(generation)) return;
      _downloadToken = null;
      state = UpdateState(
        status: UpdateStatus.error,
        release: release,
        asset: asset,
        errorMessage: error.message,
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _downloadToken = null;
      state = UpdateState(
        status: UpdateStatus.error,
        release: release,
        asset: asset,
        errorMessage: '下载更新失败，请稍后重试',
      );
    }
  }

  /// Cancels an in-flight download and returns to [UpdateStatus.available].
  void cancelDownload() {
    if (state.status != UpdateStatus.downloading) return;
    final CancelToken? token = _downloadToken;
    _downloadToken = null;
    token?.cancel('用户取消下载');
    ++_generation;
    state = UpdateState(
      status: UpdateStatus.available,
      release: state.release,
      asset: state.asset,
    );
  }

  /// Retries a failed download, or checks again when the release is unknown.
  Future<void> retryDownload() async {
    if (state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.installing) {
      return;
    }
    final AppRelease? release = state.release;
    if (release == null) {
      await check();
      return;
    }
    final ReleaseAsset? asset = state.asset;
    if (asset == null) {
      state = UpdateState(
        status: UpdateStatus.error,
        release: release,
        errorMessage: '当前平台暂无可用安装包，请打开下载页手动下载。',
      );
      return;
    }
    await startDownload();
  }

  /// Hands the downloaded package to the platform installer.
  Future<void> install() async {
    final AppRelease? release = state.release;
    final File? file = state.file;
    if (release == null || file == null) return;
    if (state.status == UpdateStatus.installing ||
        state.status == UpdateStatus.downloading) {
      return;
    }
    final int generation = ++_generation;
    state = UpdateState(
      status: UpdateStatus.installing,
      release: release,
      asset: state.asset,
      file: file,
      progress: 1,
      receivedBytes: state.receivedBytes,
      totalBytes: state.totalBytes,
    );
    try {
      await ref.read(updateInstallerProvider).installUpdate(file, release);
      if (!_isCurrent(generation)) return;
      // Android (and the unsupported fallback) return here; the desktop
      // installers exit the process on their own, so this state is only ever
      // observed when the install finished in-place.
      state = const UpdateState();
    } on UpdateException catch (error) {
      if (!_isCurrent(generation)) return;
      state = UpdateState(
        status: UpdateStatus.error,
        release: release,
        asset: state.asset,
        file: file,
        errorMessage: error.message,
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = UpdateState(
        status: UpdateStatus.error,
        release: release,
        asset: state.asset,
        file: file,
        errorMessage: '无法启动安装程序，请前往发布页手动下载安装。',
      );
    }
  }

  /// Opens the current release page in the system browser.
  Future<void> openReleasePage() async {
    AppRelease? release = state.release;
    if (release == null) {
      if (state.status == UpdateStatus.checking) return;
      await check();
      if (!ref.mounted) return;
      release = state.release;
    }
    if (release == null) return;
    try {
      await ref.read(updateInstallerProvider).openReleasePage(release);
    } on UpdateException catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: error.message,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: '无法打开浏览器，请手动访问发布页。',
      );
    }
  }

  /// Clears the pending update and removes temporary download files.
  void dismiss() {
    final File? file = state.file;
    final CancelToken? token = _downloadToken;
    _downloadToken = null;
    token?.cancel('用户关闭更新');
    ++_generation;
    if (file != null) {
      unawaited(_deleteDownloadedFile(file));
    }
    state = const UpdateState();
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  Future<void> _deleteDownloadedFile(File file) async {
    try {
      final Directory parent = file.parent;
      final String name = _basename(parent.path);
      if (name.startsWith('download-')) {
        await parent.delete(recursive: true);
        return;
      }
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      return;
    }
  }

  static String _basename(String path) {
    final int slash = path.lastIndexOf('/');
    final int backslash = path.lastIndexOf(r'\');
    final int index = slash > backslash ? slash : backslash;
    return index >= 0 ? path.substring(index + 1) : path;
  }
}
