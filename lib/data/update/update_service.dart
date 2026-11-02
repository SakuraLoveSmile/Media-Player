import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_models.dart';

/// Loads the running app's package metadata.
///
/// Injectable so tests never touch the platform channels used by
/// [PackageInfo.fromPlatform].
typedef PackageInfoLoader = Future<PackageInfo> Function();

/// Resolves the directory downloads are written to.
///
/// Injectable so tests can download into a throwaway temp directory.
typedef TemporaryDirectoryLoader = Future<Directory> Function();

/// Raised for every expected updater failure; [message] is user facing.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Raised when the caller cancels an in-flight download.
///
/// Callers should return to a neutral state instead of showing an error.
class CancelException implements Exception {
  const CancelException();

  @override
  String toString() => '下载已取消';
}

/// Checks GitHub Releases and downloads the matching install package.
///
/// Only GitHub's public API is used; no authentication is involved.
class UpdateService {
  UpdateService({
    Dio? dio,
    PackageInfoLoader? packageInfoLoader,
    TemporaryDirectoryLoader? temporaryDirectoryLoader,
    String githubApiBase = defaultGitHubApiBase,
    this.owner = defaultOwner,
    this.repo = defaultRepo,
  }) : _dio = dio ?? Dio(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _temporaryDirectoryLoader =
           temporaryDirectoryLoader ?? getTemporaryDirectory,
       _githubApiBase = _trimTrailingSlash(githubApiBase) {
    _applyDefaultTimeouts(_dio);
  }

  static const String defaultGitHubApiBase = 'https://api.github.com';
  static const String defaultOwner = defaultReleaseOwner;
  static const String defaultRepo = defaultReleaseRepo;

  /// GitHub rejects requests without a User-Agent and asks API clients to pin
  /// the version they speak.
  static const String _acceptHeader = 'application/vnd.github+json';
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _sendTimeout = Duration(seconds: 8);
  static const Duration _receiveTimeout = Duration(seconds: 15);

  /// Repository owner used for the Releases API (constant by default,
  /// injectable for tests that talk to a local server).
  final String owner;

  /// Repository name used for the Releases API.
  final String repo;

  final Dio _dio;
  final PackageInfoLoader _packageInfoLoader;
  final TemporaryDirectoryLoader _temporaryDirectoryLoader;
  final String _githubApiBase;
  final Random _random = Random();

  /// Returns the newest release when it is newer than the running app.
  ///
  /// A `null` result means "nothing to do": no published release (404), a
  /// draft/prerelease, or a release that is not newer than the installed
  /// version. [platform] is accepted for call-site symmetry; asset selection
  /// is the caller's job via [pickAsset].
  Future<AppRelease?> checkForUpdate({String? platform}) async {
    final PackageInfo info = await _loadPackageInfo();
    final String currentVersion;
    try {
      currentVersion = normalizeVersion(info.version);
    } on FormatException {
      throw const UpdateException('无法识别当前应用版本，请稍后重试');
    }

    final String url = '$_githubApiBase/repos/$owner/$repo/releases/latest';
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: <String, String>{
            'Accept': _acceptHeader,
            'User-Agent': 'MediaPlayer/${info.version}',
          },
        ),
      );
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      if (status == HttpStatus.notFound) return null;
      if (status == HttpStatus.forbidden || status == 429) {
        throw const UpdateException('GitHub 请求受限，请稍后重试');
      }
      throw UpdateException(_checkFailureMessage(error));
    }

    final int status = response.statusCode ?? HttpStatus.ok;
    if (status == HttpStatus.notFound) return null;
    if (status == HttpStatus.forbidden || status == 429) {
      throw const UpdateException('GitHub 请求受限，请稍后重试');
    }
    if (status < HttpStatus.ok || status >= HttpStatus.multipleChoices) {
      throw UpdateException('检查更新失败（HTTP $status），请稍后重试');
    }

    final dynamic data = response.data;
    if (data is! Map) {
      throw const UpdateException('更新信息格式异常，请稍后重试');
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(data);
    // Drafts are internal to the repository owner and must never surface.
    if (json['draft'] == true) return null;

    final AppRelease release;
    try {
      release = AppRelease.fromGitHubJson(json);
    } on FormatException {
      throw const UpdateException('更新信息格式异常，请稍后重试');
    }
    if (release.isPrerelease) return null;
    if (compareVersions(release.version, currentVersion) <= 0) return null;
    return release;
  }

  /// Downloads [asset] into a fresh temp directory and verifies its SHA-256.
  ///
  /// Throws [CancelException] when [cancelToken] is cancelled and
  /// [UpdateException] for every other failure (including checksum mismatch,
  /// after which the partial files are removed).
  Future<File> downloadUpdate(
    AppRelease release,
    ReleaseAsset asset, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final String? expectedDigest = _normalizeDigest(asset.sha256);
    if (expectedDigest == null) {
      throw const UpdateException('安装包缺少 SHA-256 校验信息，已取消下载');
    }
    final String? fileName = _safeFileName(asset.name);
    if (fileName == null) {
      throw const UpdateException('安装包文件名非法，已取消下载');
    }

    final Directory tempRoot = await _loadTemporaryDirectory();
    final Directory downloadDir;
    try {
      downloadDir = await Directory(
        '${tempRoot.path}${Platform.pathSeparator}updates'
        '${Platform.pathSeparator}download-'
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}',
      ).create(recursive: true);
    } on FileSystemException {
      throw const UpdateException('无法创建下载目录，请检查存储空间后重试');
    }
    final File target = File(
      '${downloadDir.path}${Platform.pathSeparator}$fileName',
    );

    try {
      await _dio.download(
        asset.downloadUrl.toString(),
        target.path,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        deleteOnError: true,
        options: Options(
          receiveTimeout: _receiveTimeout,
          headers: <String, String>{
            'Accept': 'application/octet-stream',
            'User-Agent': 'MediaPlayer-updater',
          },
        ),
      );
    } on DioException catch (error) {
      await _deleteQuietly(downloadDir);
      if (CancelToken.isCancel(error)) {
        throw const CancelException();
      }
      final int? status = error.response?.statusCode;
      if (status == HttpStatus.forbidden || status == 429) {
        throw const UpdateException('GitHub 请求受限，请稍后重试');
      }
      throw UpdateException(_downloadFailureMessage(error));
    } catch (_) {
      await _deleteQuietly(downloadDir);
      rethrow;
    }

    final String? actualDigest = await _sha256OfFile(target);
    if (actualDigest == null || actualDigest != expectedDigest) {
      await _deleteQuietly(downloadDir);
      throw const UpdateException('安装包完整性校验失败，文件已删除');
    }
    return target;
  }

  Future<PackageInfo> _loadPackageInfo() async {
    try {
      return await _packageInfoLoader();
    } catch (_) {
      throw const UpdateException('无法读取当前应用版本，请稍后重试');
    }
  }

  Future<Directory> _loadTemporaryDirectory() async {
    try {
      return await _temporaryDirectoryLoader();
    } catch (_) {
      throw const UpdateException('无法访问临时目录，请检查存储空间后重试');
    }
  }

  static String _trimTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static void _applyDefaultTimeouts(Dio dio) {
    dio.options.connectTimeout ??= _connectTimeout;
    dio.options.sendTimeout ??= _sendTimeout;
    dio.options.receiveTimeout ??= _receiveTimeout;
  }

  static String? _safeFileName(String rawName) {
    final String name = rawName.trim();
    if (name.isEmpty || name == '.' || name == '..') return null;
    if (name.contains('/') || name.contains(r'\')) return null;
    if (name.contains('\u0000')) return null;
    return name;
  }

  static String? _normalizeDigest(String? raw) {
    if (raw == null) return null;
    var value = raw.trim().toLowerCase();
    if (value.startsWith('sha256:')) value = value.substring(7);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) return null;
    return value;
  }

  static Future<String?> _sha256OfFile(File file) async {
    try {
      final Digest digest = await sha256.bind(file.openRead()).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) {
        await entity.delete(recursive: true);
      }
    } catch (_) {
      return;
    }
  }

  static String _checkFailureMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '连接更新服务器超时，请稍后重试';
      case DioExceptionType.connectionError:
        return '无法连接更新服务器，请检查网络后重试';
      case DioExceptionType.badCertificate:
        return '更新服务器证书校验失败，请稍后重试';
      case DioExceptionType.badResponse:
        return '检查更新失败（HTTP ${error.response?.statusCode ?? '未知'}），请稍后重试';
      case DioExceptionType.cancel:
        return '检查更新已取消';
      case DioExceptionType.unknown:
        return '检查更新失败，请检查网络后重试';
    }
  }

  static String _downloadFailureMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '下载安装包超时，请稍后重试';
      case DioExceptionType.connectionError:
        return '无法连接下载服务器，请检查网络后重试';
      case DioExceptionType.badCertificate:
        return '下载服务器证书校验失败，请稍后重试';
      case DioExceptionType.badResponse:
        return '下载安装包失败（HTTP ${error.response?.statusCode ?? '未知'}），请稍后重试';
      case DioExceptionType.cancel:
        return '下载已取消';
      case DioExceptionType.unknown:
        return '下载安装包失败，请检查网络后重试';
    }
  }
}
