import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/update/update_models.dart';

const String _sha =
    '0123456789abcdef0123456789abcdef'
    '0123456789abcdef0123456789abcdef';

Map<String, dynamic> assetJson({
  String name = 'MediaPlayer-android.apk',
  Object? digest = 'sha256:$_sha',
  Object? size = 1024,
  String? url = 'https://example.test/MediaPlayer-android.apk',
  bool browserDownloadUrl = true,
}) {
  return <String, dynamic>{
    'name': name,
    if (browserDownloadUrl)
      'browser_download_url': url
    else
      ...<String, void>{},
    if (!browserDownloadUrl && url != null) 'download_url': url,
    'size': size,
    'digest': digest,
  };
}

Map<String, dynamic> releaseJson({
  String tagName = 'v0.2.0',
  Object? body = '修复若干问题',
  String? htmlUrl =
      'https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.0',
  String? publishedAt = '2026-10-01T12:00:00Z',
  List<Object?>? assets,
  bool draft = false,
  bool prerelease = false,
}) {
  return <String, dynamic>{
    'tag_name': tagName,
    'name': tagName,
    'body': body,
    'html_url': htmlUrl,
    'published_at': publishedAt,
    'assets': assets ?? <Map<String, dynamic>>[assetJson()],
    'draft': draft,
    'prerelease': prerelease,
  };
}

void main() {
  group('normalizeVersion', () {
    test('accepts v-prefixed and whitespace-padded versions', () {
      expect(normalizeVersion('1.2.3'), '1.2.3');
      expect(normalizeVersion('v1.2.3'), '1.2.3');
      expect(normalizeVersion('V0.0.1'), '0.0.1');
      expect(normalizeVersion('  v10.20.30  '), '10.20.30');
    });

    test('rejects anything that is not major.minor.patch', () {
      for (final String raw in <String>[
        '',
        ' ',
        'v',
        '1',
        '1.2',
        '1.2.3.4',
        '1.2.x',
        'v1.2.3-beta',
        'release-1.2.3',
      ]) {
        expect(
          () => normalizeVersion(raw),
          throwsFormatException,
          reason: 'raw="$raw"',
        );
      }
    });
  });

  group('compareVersions', () {
    test('compares numeric segments, not strings', () {
      expect(compareVersions('1.2.3', '1.2.3'), 0);
      expect(compareVersions('1.2.3', '1.2.4'), -1);
      expect(compareVersions('1.2.4', '1.2.3'), 1);
      expect(compareVersions('1.10.0', '1.9.9'), 1);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
    });

    test('accepts v prefixes and leading zeros', () {
      expect(compareVersions('v1.2.3', '1.2.3'), 0);
      expect(compareVersions('01.002.0003', '1.2.3'), 0);
      expect(compareVersions('v2.0.0', '1.99.99'), 1);
    });

    test('handles build numbers that do not fit in 32 bits', () {
      expect(compareVersions('20260101.1.1', '20260100.999.999'), 1);
      expect(compareVersions('999999999999.1.1', '999999999998.9.9'), 1);
    });

    test('rejects invalid versions on either side', () {
      expect(() => compareVersions('1.2', '1.2.3'), throwsFormatException);
      expect(() => compareVersions('1.2.3', 'latest'), throwsFormatException);
    });
  });

  group('ReleaseAsset.fromJson', () {
    test('parses name, url, size and digest', () {
      final ReleaseAsset asset = ReleaseAsset.fromJson(assetJson());
      expect(asset.name, 'MediaPlayer-android.apk');
      expect(
        asset.downloadUrl,
        Uri.parse('https://example.test/MediaPlayer-android.apk'),
      );
      expect(asset.sizeBytes, 1024);
      expect(asset.sha256, _sha);
    });

    test('tolerates missing digest and size', () {
      final ReleaseAsset asset = ReleaseAsset.fromJson(
        assetJson(digest: null, size: null),
      );
      expect(asset.sha256, isNull);
      expect(asset.sizeBytes, 0);
    });

    test('ignores digests that are not plain sha256', () {
      expect(
        ReleaseAsset.fromJson(assetJson(digest: 'sha512:abc')).sha256,
        isNull,
      );
      expect(
        ReleaseAsset.fromJson(assetJson(digest: 'not-a-digest')).sha256,
        isNull,
      );
    });

    test('accepts a plain sha256 field and normalizes upper case', () {
      final ReleaseAsset asset = ReleaseAsset.fromJson(<String, dynamic>{
        'name': 'MediaPlayer-android.apk',
        'browser_download_url': 'https://example.test/app.apk',
        'sha256': _sha.toUpperCase(),
      });
      expect(asset.sha256, _sha);
    });

    test('falls back to download_url and rejects unusable entries', () {
      final ReleaseAsset asset = ReleaseAsset.fromJson(
        assetJson(browserDownloadUrl: false),
      );
      expect(asset.downloadUrl.host, 'example.test');

      expect(
        () => ReleaseAsset.fromJson(assetJson(name: '')),
        throwsFormatException,
      );
      expect(
        () => ReleaseAsset.fromJson(assetJson(url: null)),
        throwsFormatException,
      );
      expect(
        () => ReleaseAsset.fromJson(assetJson(url: 'not a url')),
        throwsFormatException,
      );
    });
  });

  group('AppRelease.fromGitHubJson', () {
    test('parses the GitHub release payload', () {
      final AppRelease release = AppRelease.fromGitHubJson(releaseJson());
      expect(release.version, '0.2.0');
      expect(release.tagName, 'v0.2.0');
      expect(release.notes, '修复若干问题');
      expect(
        release.pageUrl.toString(),
        'https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.0',
      );
      expect(release.publishedAt, DateTime.utc(2026, 10, 1, 12));
      expect(release.assets, hasLength(1));
      expect(release.assets.single.sha256, _sha);
      expect(release.isPrerelease, isFalse);
    });

    test('tolerates missing optional fields', () {
      final AppRelease release = AppRelease.fromGitHubJson(<String, dynamic>{
        'tag_name': 'v1.0.0',
      });
      expect(release.version, '1.0.0');
      expect(release.notes, '');
      expect(release.publishedAt, isNull);
      expect(release.assets, isEmpty);
      expect(release.isPrerelease, isFalse);
      expect(
        release.pageUrl.toString(),
        'https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v1.0.0',
      );
    });

    test('skips malformed assets instead of failing the release', () {
      final AppRelease release = AppRelease.fromGitHubJson(
        releaseJson(
          assets: <Object?>[
            <String, dynamic>{'name': 'broken.apk'},
            'not-a-map',
            assetJson(),
          ],
        ),
      );
      expect(release.assets, hasLength(1));
      expect(release.assets.single.name, 'MediaPlayer-android.apk');
    });

    test('rejects drafts', () {
      expect(
        () => AppRelease.fromGitHubJson(releaseJson(draft: true)),
        throwsFormatException,
      );
    });

    test('reports prerelease and rejects unusable tags', () {
      expect(
        AppRelease.fromGitHubJson(releaseJson(prerelease: true)).isPrerelease,
        isTrue,
      );
      expect(
        () => AppRelease.fromGitHubJson(releaseJson(tagName: 'latest')),
        throwsFormatException,
      );
      expect(
        () => AppRelease.fromGitHubJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });

  group('pickAsset', () {
    final List<ReleaseAsset> assets = <ReleaseAsset>[
      ReleaseAsset(
        name: 'MediaPlayer-android.apk',
        downloadUrl: Uri(scheme: 'https', host: 'example.test', path: '/a.apk'),
        sizeBytes: 1,
      ),
      ReleaseAsset(
        name: 'MediaPlayer-windows-x64.zip',
        downloadUrl: Uri(scheme: 'https', host: 'example.test', path: '/w.zip'),
        sizeBytes: 2,
      ),
      ReleaseAsset(
        name: 'MediaPlayer-macos.zip',
        downloadUrl: Uri(scheme: 'https', host: 'example.test', path: '/m.zip'),
        sizeBytes: 3,
      ),
    ];

    test('selects the expected artifact per platform', () {
      expect(
        pickAsset(assets, platform: 'android')?.name,
        'MediaPlayer-android.apk',
      );
      expect(
        pickAsset(assets, platform: 'windows')?.name,
        'MediaPlayer-windows-x64.zip',
      );
      expect(
        pickAsset(assets, platform: 'macos')?.name,
        'MediaPlayer-macos.zip',
      );
    });

    test('matches names case-insensitively and ignores padding', () {
      final ReleaseAsset upper = ReleaseAsset(
        name: ' mediaplayer-MACOS.zip ',
        downloadUrl: Uri(scheme: 'https', host: 'example.test', path: '/x'),
        sizeBytes: 1,
      );
      expect(
        pickAsset(<ReleaseAsset>[upper], platform: 'macos')?.name,
        ' mediaplayer-MACOS.zip ',
      );
    });

    test('returns null for a missing artifact or unknown platform', () {
      expect(pickAsset(assets, platform: 'android').runtimeType, ReleaseAsset);
      expect(
        pickAsset(<ReleaseAsset>[
          ReleaseAsset(
            name: 'MediaPlayer-android.apk.sha256',
            downloadUrl: Uri(scheme: 'https', host: 'example.test'),
            sizeBytes: 0,
          ),
        ], platform: 'android'),
        isNull,
      );
      expect(pickAsset(assets, platform: 'linux'), isNull);
      expect(pickAsset(<ReleaseAsset>[], platform: 'macos'), isNull);
    });
  });
}
