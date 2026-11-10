import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Fetches the bytes for a poster URL. Injected so the cache owns no transport.
typedef PosterFetcher = Future<Uint8List> Function(Uri url);

/// Disk cache for library posters.
///
/// [url] carries `api_key`, so it is handed to the fetcher and never persisted:
/// entries are named by a hash of the item identity plus the server host. That
/// also keeps the cache valid across a token rotation, which changes every URL.
abstract interface class PosterCache {
  Future<Uint8List> load(String itemId, Uri url, {String? tag, int? maxWidth});
}

/// Poster bytes under a dedicated directory, evicted oldest-first past a budget.
class FilePosterCache implements PosterCache {
  FilePosterCache({
    required this.directory,
    required this.fetch,
    this.maxBytes = 256 * 1024 * 1024,
  });

  final Directory directory;
  final PosterFetcher fetch;
  final int maxBytes;

  /// Measured once, then kept incrementally. Rescanning the directory on every
  /// write would cost more IO than the cache saves on a library of thousands.
  int? _total;

  @override
  Future<Uint8List> load(
    String itemId,
    Uri url, {
    String? tag,
    int? maxWidth,
  }) async {
    final file = File('${directory.path}/${_key(itemId, url, tag, maxWidth)}');
    final cached = await _read(file);
    if (cached != null) return cached;

    final bytes = await fetch(url);
    if (bytes.isEmpty) return bytes;
    await _write(file, bytes);
    return bytes;
  }

  /// A truncated or unreadable entry is a miss, not a failure: the poster must
  /// never be the reason the library stops rendering.
  Future<Uint8List?> _read(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _write(File file, Uint8List bytes) async {
    try {
      await directory.create(recursive: true);
      // Rename into place so a crash mid-write cannot leave a half poster that
      // reads back as a hit and then fails to decode on every later launch.
      final partial = File('${file.path}.partial');
      await partial.writeAsBytes(bytes);
      await partial.rename(file.path);
      await _evict(bytes.length);
    } on FileSystemException {
      // A read-only or full disk degrades to no caching.
    }
  }

  Future<void> _evict(int addedBytes) async {
    final known = _total;
    if (known != null && known + addedBytes <= maxBytes) {
      _total = known + addedBytes;
      return;
    }

    final entries = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      entries.add((entity, stat));
      total += stat.size;
    }

    if (total > maxBytes) {
      entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in entries) {
        if (total <= maxBytes) break;
        try {
          await file.delete();
          total -= stat.size;
        } on FileSystemException {
          // Already gone; the budget accounting still moves on.
        }
      }
    }
    // Re-measured from disk, so a new instance over an existing directory does
    // not start from zero and let the budget drift.
    _total = total;
  }

  static String _key(String itemId, Uri url, String? tag, int? maxWidth) {
    final identity =
        '$itemId|${tag ?? ''}|${maxWidth ?? ''}|${url.host}:${url.port}';
    return sha256.convert(utf8.encode(identity)).toString();
  }
}
