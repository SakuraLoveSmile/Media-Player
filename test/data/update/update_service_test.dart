import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/update/update_models.dart';
import 'package:media_player/data/update/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String _sha =
    '0123456789abcdef0123456789abcdef'
    '0123456789abcdef0123456789abcdef';

/// Minimal GitHub Releases surface served from a real loopback HttpServer.
class _FakeGitHub {
  late HttpServer _server;

  /// What `/releases/latest` answers; see [_handleLatest].
  String mode = 'update';

  /// What `/releases` answers for the preview channel; empty by default.
  List<Map<String, dynamic>> releases = <Map<String, dynamic>>[];

  List<int> downloadBytes = List<int>.generate(
    4096,
    (int index) => index % 251,
  );

  final List<String> requestPaths = <String>[];
  final List<HttpHeaders> requestHeaders = <HttpHeaders>[];

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((HttpRequest request) {
      unawaited(_handle(request));
    });
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requestPaths.add(request.uri.path);
    requestHeaders.add(request.headers);
    final HttpResponse response = request.response;
    try {
      final String path = request.uri.path;
      if (path.endsWith('/releases/latest')) {
        await _handleLatest(response);
        return;
      }
      if (path.endsWith('/releases')) {
        await _json(response, HttpStatus.ok, releases);
        return;
      }
      if (path.startsWith('/download/')) {
        await _handleDownload(path, response);
        return;
      }
      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (_) {
      // The updater may cancel and close the socket mid-response.
      try {
        await response.close();
      } catch (_) {
        return;
      }
    }
  }

  Future<void> _handleLatest(HttpResponse response) async {
    switch (mode) {
      case 'update':
        await _json(response, HttpStatus.ok, _releaseJson(version: '0.2.0'));
      case 'same-version':
        await _json(response, HttpStatus.ok, _releaseJson(version: '0.1.0'));
      case 'older':
        await _json(response, HttpStatus.ok, _releaseJson(version: '0.0.9'));
      case 'draft':
        await _json(
          response,
          HttpStatus.ok,
          _releaseJson(version: '0.2.0', draft: true),
        );
      case 'prerelease':
        await _json(
          response,
          HttpStatus.ok,
          _releaseJson(version: '0.2.0', prerelease: true),
        );
      case 'bad-tag':
        await _json(
          response,
          HttpStatus.ok,
          _releaseJson(version: '0.2.0', tagName: 'latest'),
        );
      case 'not-object':
        await _json(response, HttpStatus.ok, <Object>[]);
      case 'bad-payload':
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.json;
        response.write('not json');
        await response.close();
      case 'not-found':
        await _json(response, HttpStatus.notFound, <String, String>{});
      case 'forbidden':
        await _json(response, HttpStatus.forbidden, <String, String>{});
      case 'rate-limited':
        await _json(response, 429, <String, String>{});
      case 'server-error':
        await _json(
          response,
          HttpStatus.internalServerError,
          <String, String>{},
        );
      default:
        await _json(response, 418, <String, String>{});
    }
  }

  Future<void> _handleDownload(String path, HttpResponse response) async {
    if (path == '/download/forbidden') {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }
    final List<int> bytes = downloadBytes;
    response.contentLength = bytes.length;
    if (path == '/download/slow.bin') {
      final int half = bytes.length ~/ 2;
      response.add(bytes.sublist(0, half));
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      response.add(bytes.sublist(half));
      await response.close();
      return;
    }
    response.add(bytes);
    await response.close();
  }

  Future<void> _json(HttpResponse response, int status, Object body) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}

Map<String, dynamic> _releaseJson({
  required String version,
  String? tagName,
  bool draft = false,
  bool prerelease = false,
}) {
  return <String, dynamic>{
    'tag_name': tagName ?? 'v$version',
    'name': tagName ?? 'v$version',
    'body': '修复若干问题',
    'html_url':
        'https://github.com/SakuraLoveSmile/Media-Player/releases/tag/'
        'v$version',
    'published_at': '2026-10-01T12:00:00Z',
    'draft': draft,
    'prerelease': prerelease,
    'assets': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'MediaPlayer-macos.zip',
        'browser_download_url': 'https://example.test/MediaPlayer-macos.zip',
        'size': 4096,
        'digest': 'sha256:$_sha',
      },
    ],
  };
}

AppRelease _release() {
  return AppRelease(
    version: '0.2.0',
    tagName: 'v0.2.0',
    notes: '修复若干问题',
    pageUrl: Uri.parse(
      'https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.0',
    ),
    publishedAt: DateTime.utc(2026, 10, 1, 12),
  );
}

Future<void> _expectNoDownloadDirectories(Directory tempDir) async {
  final Directory updates = Directory(
    '${tempDir.path}${Platform.pathSeparator}updates',
  );
  if (!await updates.exists()) return;
  expect(await updates.list().toList(), isEmpty);
}

void main() {
  late Directory tempDir;
  late _FakeGitHub github;
  late PackageInfo packageInfo;

  UpdateService buildService({Dio? dio, String? githubApiBase}) {
    return UpdateService(
      dio: dio ?? Dio(),
      packageInfoLoader: () async => packageInfo,
      temporaryDirectoryLoader: () async => tempDir,
      githubApiBase: githubApiBase ?? github.base,
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('update_service_test_');
    packageInfo = PackageInfo(
      appName: 'Media Player',
      packageName: 'media_player',
      version: '0.1.0',
      buildNumber: '1',
    );
    github = _FakeGitHub();
    await github.start();
  });

  tearDown(() async {
    await github.stop();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('checkForUpdate preview channel', () {
    test(
      'offers the newest prerelease build above the installed one',
      () async {
        github.releases = <Map<String, dynamic>>[
          _releaseJson(version: '0.2.0', tagName: 'v0.2.0'),
          _releaseJson(
            version: '0.2.2',
            tagName: 'v0.2.2-pilot.200',
            prerelease: true,
          ),
          _releaseJson(
            version: '0.2.1',
            tagName: 'v0.2.1-pilot.100',
            prerelease: true,
          ),
        ];
        final AppRelease? release = await buildService().checkForUpdate(
          platform: 'macos',
          channel: UpdateChannel.preview,
        );
        expect(release, isNotNull);
        expect(release!.tagName, 'v0.2.2-pilot.200');
        expect(release.isPrerelease, isTrue);
        expect(release.buildNumber, 200);
        expect(github.requestPaths.last, contains('/releases'));
      },
    );

    test(
      'ignores a preview build that is not newer than the installed build',
      () async {
        packageInfo = PackageInfo(
          appName: 'Media Player',
          packageName: 'media_player',
          version: '0.2.2',
          buildNumber: '300',
        );
        github.releases = <Map<String, dynamic>>[
          _releaseJson(
            version: '0.2.2',
            tagName: 'v0.2.2-pilot.200',
            prerelease: true,
          ),
        ];
        expect(
          await buildService().checkForUpdate(channel: UpdateChannel.preview),
          isNull,
        );
      },
    );

    test('prefers a newer stable release over an older preview', () async {
      github.releases = <Map<String, dynamic>>[
        _releaseJson(
          version: '0.2.3',
          tagName: 'v0.2.3-pilot.900',
          prerelease: true,
        ),
        _releaseJson(version: '0.2.4', tagName: 'v0.2.4'),
      ];
      final AppRelease? release = await buildService().checkForUpdate(
        channel: UpdateChannel.preview,
      );
      expect(release?.tagName, 'v0.2.4');
      expect(release?.isPrerelease, isFalse);
    });

    test('never downgrades when the channel has only older builds', () async {
      packageInfo = PackageInfo(
        appName: 'Media Player',
        packageName: 'media_player',
        version: '0.2.4',
        buildNumber: '1794215665',
      );
      github.releases = <Map<String, dynamic>>[
        _releaseJson(
          version: '0.2.4',
          tagName: 'v0.2.4-pilot.100',
          prerelease: true,
        ),
        _releaseJson(version: '0.2.3', tagName: 'v0.2.3'),
      ];
      expect(
        await buildService().checkForUpdate(channel: UpdateChannel.preview),
        isNull,
      );
    });

    test(
      'stable channel still ignores prereleases on the same endpoint',
      () async {
        github.mode = 'prerelease';
        expect(await buildService().checkForUpdate(), isNull);
      },
    );
  });

  group('checkForUpdate', () {
    test('returns a newer release and sends the GitHub headers', () async {
      final AppRelease? release = await buildService().checkForUpdate(
        platform: 'macos',
      );

      expect(release, isNotNull);
      expect(release!.version, '0.2.0');
      expect(release.tagName, 'v0.2.0');
      expect(release.isPrerelease, isFalse);
      expect(release.assets, hasLength(1));
      expect(
        github.requestPaths.single,
        '/repos/SakuraLoveSmile/Media-Player/releases/latest',
      );
      final HttpHeaders headers = github.requestHeaders.single;
      expect(headers.value('accept'), 'application/vnd.github+json');
      expect(headers.value('user-agent'), 'MediaPlayer/0.1.0');
    });

    test(
      'returns null when the installed version is current or newer',
      () async {
        for (final String mode in <String>['same-version', 'older']) {
          github.mode = mode;
          expect(await buildService().checkForUpdate(), isNull, reason: mode);
        }
      },
    );

    test('returns null when no release has been published yet (404)', () async {
      github.mode = 'not-found';
      expect(await buildService().checkForUpdate(), isNull);
    });

    test('returns null for drafts and prereleases', () async {
      for (final String mode in <String>['draft', 'prerelease']) {
        github.mode = mode;
        expect(await buildService().checkForUpdate(), isNull, reason: mode);
      }
    });

    test('maps 403 and 429 to a rate limit message', () async {
      for (final String mode in <String>['forbidden', 'rate-limited']) {
        github.mode = mode;
        await expectLater(
          buildService().checkForUpdate(),
          throwsA(
            isA<UpdateException>().having(
              (UpdateException error) => error.message,
              'message',
              contains('受限'),
            ),
          ),
          reason: mode,
        );
      }
    });

    test('maps other HTTP failures to an UpdateException', () async {
      github.mode = 'server-error';
      await expectLater(
        buildService().checkForUpdate(),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('HTTP 500'),
          ),
        ),
      );
    });

    test('maps network failures to an UpdateException', () async {
      final HttpServer closed = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int port = closed.port;
      await closed.close(force: true);

      await expectLater(
        buildService(githubApiBase: 'http://127.0.0.1:$port').checkForUpdate(),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('无法连接'),
          ),
        ),
      );
    });

    test('maps malformed payloads to an UpdateException', () async {
      for (final String mode in <String>[
        'bad-payload',
        'not-object',
        'bad-tag',
      ]) {
        github.mode = mode;
        await expectLater(
          buildService().checkForUpdate(),
          throwsA(isA<UpdateException>()),
          reason: mode,
        );
      }
    });

    test('rejects an unparseable installed version', () async {
      packageInfo = PackageInfo(
        appName: 'Media Player',
        packageName: 'media_player',
        version: 'dev',
        buildNumber: '1',
      );
      await expectLater(
        buildService().checkForUpdate(),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('无法识别当前应用版本'),
          ),
        ),
      );
    });

    test('maps package info failures to an UpdateException', () async {
      final UpdateService service = UpdateService(
        dio: Dio(),
        packageInfoLoader: () async => throw StateError('no plugin'),
        temporaryDirectoryLoader: () async => tempDir,
        githubApiBase: github.base,
      );
      await expectLater(
        service.checkForUpdate(),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('无法读取当前应用版本'),
          ),
        ),
      );
    });

    test('keeps default timeouts on an injected bare Dio', () {
      final Dio dio = Dio();
      buildService(dio: dio);
      expect(dio.options.connectTimeout, const Duration(seconds: 8));
      expect(dio.options.sendTimeout, const Duration(seconds: 8));
      expect(dio.options.receiveTimeout, const Duration(seconds: 15));
    });
  });

  group('downloadUpdate', () {
    ReleaseAsset assetFor({
      String name = 'MediaPlayer-macos.zip',
      String path = '/download/package.bin',
      String? sha256,
    }) {
      return ReleaseAsset(
        name: name,
        downloadUrl: Uri.parse('${github.base}$path'),
        sizeBytes: github.downloadBytes.length,
        sha256: sha256,
      );
    }

    test('downloads, reports progress and verifies sha256', () async {
      final List<int> bytes = github.downloadBytes;
      final String digest = sha256.convert(bytes).toString();
      final List<({int received, int total})> progress =
          <({int received, int total})>[];

      final File file = await buildService().downloadUpdate(
        _release(),
        assetFor(sha256: digest),
        onProgress: (int received, int total) {
          progress.add((received: received, total: total));
        },
      );

      expect(await file.readAsBytes(), bytes);
      expect(
        file.path,
        startsWith(
          '${tempDir.path}${Platform.pathSeparator}updates'
          '${Platform.pathSeparator}download-',
        ),
      );
      expect(file.path, endsWith('MediaPlayer-macos.zip'));
      expect(progress, isNotEmpty);
      expect(progress.last.received, bytes.length);
      expect(progress.last.total, bytes.length);
    });

    test('refuses assets without a checksum', () async {
      await expectLater(
        buildService().downloadUpdate(_release(), assetFor()),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('校验信息'),
          ),
        ),
      );
      await _expectNoDownloadDirectories(tempDir);
    });

    test('rejects path separators in the file name', () async {
      await expectLater(
        buildService().downloadUpdate(
          _release(),
          assetFor(name: '../evil.zip', sha256: _sha),
        ),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('文件名非法'),
          ),
        ),
      );
      expect(
        await Directory('${tempDir.path}${Platform.pathSeparator}updates')
            .exists(),
        isFalse,
      );
    });

    test('deletes the download when sha256 does not match', () async {
      final String wrongDigest = sha256.convert(<int>[1, 2, 3, 4]).toString();

      await expectLater(
        buildService().downloadUpdate(
          _release(),
          assetFor(sha256: wrongDigest),
        ),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('完整性校验失败'),
          ),
        ),
      );
      await _expectNoDownloadDirectories(tempDir);
    });

    test('maps download HTTP errors to an UpdateException', () async {
      await expectLater(
        buildService().downloadUpdate(
          _release(),
          assetFor(path: '/download/forbidden', sha256: _sha),
        ),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('受限'),
          ),
        ),
      );
      await _expectNoDownloadDirectories(tempDir);
    });

    test('cancel throws CancelException and removes partial files', () async {
      github.downloadBytes = List<int>.filled(64 * 1024, 7);
      final CancelToken token = CancelToken();
      final UpdateService service = buildService();

      final Future<File> future = service.downloadUpdate(
        _release(),
        assetFor(path: '/download/slow.bin', sha256: _sha),
        cancelToken: token,
        onProgress: (int received, int total) {
          if (!token.isCancelled) token.cancel('test cancel');
        },
      );

      await expectLater(future, throwsA(isA<CancelException>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _expectNoDownloadDirectories(tempDir);
    });

    test('maps a missing temporary directory to an UpdateException', () async {
      final UpdateService service = UpdateService(
        dio: Dio(),
        packageInfoLoader: () async => packageInfo,
        temporaryDirectoryLoader: () async => throw StateError('no temp'),
        githubApiBase: github.base,
      );
      await expectLater(
        service.downloadUpdate(_release(), assetFor(sha256: _sha)),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('临时目录'),
          ),
        ),
      );
    });
  });
}
