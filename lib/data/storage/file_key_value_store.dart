import 'dart:convert';
import 'dart:io';

import 'key_value_store.dart';

/// Flat JSON key/value file with `0600` permissions (contract §10.1).
///
/// Used when `flutter_secure_storage` is unavailable — notably macOS builds
/// signed ad-hoc without a Developer ID.
class FileKeyValueStore implements KeyValueStore {
  FileKeyValueStore(this.file);

  final File file;
  Map<String, String>? _cache;

  @override
  Future<String?> read(String key) async {
    final values = await _load();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    final values = await _load();
    values[key] = value;
    await _persist(values);
  }

  @override
  Future<void> delete(String key) async {
    final values = await _load();
    if (values.remove(key) == null) return;
    await _persist(values);
  }

  Future<Map<String, String>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final values = <String, String>{};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          decoded.forEach((dynamic key, dynamic value) {
            if (value is String) values[key.toString()] = value;
          });
        }
      }
    } on FormatException {
      // A corrupt file is treated as empty; the user simply logs in again.
    } on FileSystemException {
      // Unreadable file: same as empty, and the next write recreates it.
    }
    return _cache = values;
  }

  Future<void> _persist(Map<String, String> values) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(values), flush: true);
    await temp.rename(file.path);
    await _restrictPermissions(file.path);
  }

  static Future<void> _restrictPermissions(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', <String>['600', path]);
    } on ProcessException {
      // Best effort: a shared CI sandbox may not expose chmod.
    }
  }
}
