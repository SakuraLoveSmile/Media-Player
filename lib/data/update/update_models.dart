/// Release metadata parsed from the public GitHub Releases API.
///
/// Parsing is deliberately tolerant: optional fields (notes, publish date,
/// size, checksum) may be missing, while a release without a usable tag or
/// download URL is rejected with a [FormatException].
library;

/// Repository that publishes MediaPlayer releases.
///
/// Kept here so the models can derive a release page when GitHub omits
/// `html_url`; [UpdateService] reuses these defaults.
const String defaultReleaseOwner = 'SakuraLoveSmile';
const String defaultReleaseRepo = 'Media-Player';

final RegExp _versionPattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');
final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');

/// One downloadable artifact attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    this.sha256,
  });

  final String name;
  final Uri downloadUrl;
  final int sizeBytes;

  /// Lower-case hex SHA-256 from GitHub's `digest` field, or null when the
  /// asset carries no checksum (the updater refuses to install such assets).
  final String? sha256;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    final name = _string(json['name']);
    if (name == null) {
      throw const FormatException('安装包缺少文件名');
    }
    final rawUrl =
        _string(json['browser_download_url']) ?? _string(json['download_url']);
    final downloadUrl = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (downloadUrl == null ||
        !downloadUrl.hasScheme ||
        downloadUrl.host.isEmpty) {
      throw FormatException('安装包 $name 缺少下载地址');
    }
    return ReleaseAsset(
      name: name,
      downloadUrl: downloadUrl,
      sizeBytes: _integer(json['size']),
      sha256: _sha256Digest(_string(json['digest']) ?? _string(json['sha256'])),
    );
  }
}

/// A GitHub release normalized for the in-app updater.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tagName,
    required this.notes,
    required this.pageUrl,
    this.publishedAt,
    this.assets = const <ReleaseAsset>[],
    this.isPrerelease = false,
  });

  /// Normalized `major.minor.patch` version used for comparisons.
  final String version;
  final String tagName;
  final String notes;
  final Uri pageUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;
  final bool isPrerelease;

  factory AppRelease.fromGitHubJson(Map<String, dynamic> json) {
    // Draft releases are never announced; only the owner can see them, so a
    // draft must never be treated as an update.
    if (json['draft'] == true) {
      throw const FormatException('草稿发布不参与更新');
    }
    final tagName = _string(json['tag_name']);
    if (tagName == null) {
      throw const FormatException('发布缺少版本标签');
    }

    final assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final rawAsset in rawAssets) {
        if (rawAsset is! Map) continue;
        try {
          assets.add(
            ReleaseAsset.fromJson(Map<String, dynamic>.from(rawAsset)),
          );
        } on FormatException {
          // One malformed asset must not hide the rest of the release.
          continue;
        }
      }
    }

    return AppRelease(
      version: normalizeVersion(tagName),
      tagName: tagName,
      notes: _string(json['body']) ?? '',
      pageUrl: _releasePageUrl(json, tagName),
      publishedAt: _dateTime(_string(json['published_at'])),
      assets: List<ReleaseAsset>.unmodifiable(assets),
      isPrerelease: json['prerelease'] == true,
    );
  }
}

/// Strips a leading `v`/`V` and validates a strict `major.minor.patch` tag.
///
/// Throws [FormatException] for anything that is not three numeric segments.
String normalizeVersion(String raw) {
  var value = raw.trim();
  if (value.isEmpty) {
    throw const FormatException('版本号为空');
  }
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  if (!_versionPattern.hasMatch(value)) {
    throw FormatException('非法版本号：$raw');
  }
  return value;
}

/// Compares two `major.minor.patch` versions numerically.
///
/// Returns -1, 0 or 1; throws [FormatException] when either side is not a
/// valid version. Segments are compared as arbitrary-length integers so very
/// large build numbers cannot overflow.
int compareVersions(String a, String b) {
  final left = normalizeVersion(a).split('.');
  final right = normalizeVersion(b).split('.');
  for (var index = 0; index < 3; index++) {
    final result = _compareNumber(left[index], right[index]);
    if (result != 0) return result;
  }
  return 0;
}

/// Picks the install package for [platform], matching the asset name
/// case-insensitively.
///
/// Returns null when the platform is unknown or the release does not contain
/// the expected artifact.
ReleaseAsset? pickAsset(List<ReleaseAsset> assets, {required String platform}) {
  final expected = _assetNamesByPlatform[platform.trim().toLowerCase()];
  if (expected == null) return null;
  final target = expected.toLowerCase();
  for (final asset in assets) {
    if (asset.name.trim().toLowerCase() == target) return asset;
  }
  return null;
}

const Map<String, String> _assetNamesByPlatform = <String, String>{
  'android': 'MediaPlayer-android.apk',
  'windows': 'MediaPlayer-windows-x64.zip',
  'macos': 'MediaPlayer-macos.zip',
};

int _compareNumber(String a, String b) {
  final left = a.replaceFirst(_leadingZeros, '');
  final right = b.replaceFirst(_leadingZeros, '');
  if (left.length != right.length) return left.length < right.length ? -1 : 1;
  final comparison = left.compareTo(right);
  if (comparison == 0) return 0;
  return comparison < 0 ? -1 : 1;
}

String? _string(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

String? _sha256Digest(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  final separator = value.indexOf(':');
  if (separator >= 0) {
    final algorithm = value.substring(0, separator).toLowerCase();
    if (algorithm != 'sha256') return null;
    value = value.substring(separator + 1);
  }
  if (!_sha256Pattern.hasMatch(value)) return null;
  return value.toLowerCase();
}

Uri _releasePageUrl(Map<String, dynamic> json, String tagName) {
  final raw = _string(json['html_url']);
  final parsed = raw == null ? null : Uri.tryParse(raw);
  if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
    return parsed;
  }
  return Uri.https(
    'github.com',
    '/$defaultReleaseOwner/$defaultReleaseRepo/releases/tag/$tagName',
  );
}

DateTime? _dateTime(String? raw) => raw == null ? null : DateTime.tryParse(raw);
