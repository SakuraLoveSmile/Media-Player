import 'dart:convert';
import 'dart:typed_data';

import '../../core/device/backup_file_picker.dart';
import 'key_value_store.dart';

/// Raised when a backup document is malformed, an unsupported version, or
/// carries a key outside the preference whitelist.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Exports and restores the app's non-sensitive preferences (S22).
///
/// Only the keys in [preferenceKeys] are ever read or written: credentials
/// (access token, session, password, MoviePilot bearer) live under other keys
/// and must never leave the device in a backup file. The document shape is
/// `{version: 1, exportedAt, prefs: {key: value, ...}}`; [restore] rejects any
/// other version or an unknown key with a [BackupException] before writing.
///
/// File save/open is delegated to an injected [BackupFilePicker] so tests fake
/// the dialog instead of touching the plugin (same pattern as the local
/// subtitle picker).
class BackupService {
  BackupService(this._store, this._filePicker);

  /// Document schema version. Bump only with a migration; older/newer files
  /// are rejected rather than silently mis-read.
  static const int schemaVersion = 1;

  /// The exhaustive whitelist of preference keys included in a backup.
  ///
  /// Mirrors the constants owned by each feature (PlayerController.styleKey /
  /// trackPrefsKey, PlaybackSettings.storageKey, themeModeStorageKey,
  /// LibrarySearchController.historyKey). Kept as literals here so the data
  /// layer never imports a feature (tool/check_layering.sh).
  static const List<String> preferenceKeys = <String>[
    'player.subtitleStyle.v1',
    'player.trackPrefs.v1',
    'player.playbackSettings.v1',
    'app.themeMode.v1',
    'search.history.v1',
  ];

  final KeyValueStore _store;
  final BackupFilePicker _filePicker;

  /// Reads the whitelisted keys and builds the backup document. Keys with no
  /// stored value are omitted; nothing outside the whitelist is ever read.
  Future<Map<String, dynamic>> export() async {
    final Map<String, dynamic> prefs = <String, dynamic>{};
    for (final String key in preferenceKeys) {
      final String? value = await _store.read(key);
      if (value != null) prefs[key] = value;
    }
    return <String, dynamic>{
      'version': schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'prefs': prefs,
    };
  }

  /// Validates [document] and writes only whitelisted keys back to the store.
  ///
  /// Throws [BackupException] on a bad version, a non-map shape, a non-string
  /// value, or any unknown key. Validation completes before the first write so
  /// a rejected document never partially applies.
  Future<void> restore(Map<String, dynamic> document) async {
    if (document['version'] != schemaVersion) {
      throw const BackupException('备份版本不支持');
    }
    final Object? rawPrefs = document['prefs'];
    if (rawPrefs is! Map) {
      throw const BackupException('备份格式无效');
    }
    final Map<String, dynamic> prefs = Map<String, dynamic>.from(rawPrefs);
    for (final MapEntry<String, dynamic> entry in prefs.entries) {
      if (!preferenceKeys.contains(entry.key)) {
        throw const BackupException('备份包含未知设置项');
      }
      if (entry.value is! String) {
        throw const BackupException('备份格式无效');
      }
    }
    for (final MapEntry<String, dynamic> entry in prefs.entries) {
      await _store.write(entry.key, entry.value as String);
    }
  }

  /// Exports the document and saves it through the picker.
  ///
  /// Returns `true` when a file was written, `false` when the user cancels.
  /// Picker/IO errors propagate so the UI can warn.
  Future<bool> exportToFile() async {
    final Map<String, dynamic> document = await export();
    final Uint8List bytes = utf8.encode(jsonEncode(document));
    return _filePicker.saveFile(_fileName(document), bytes);
  }

  /// Opens a backup file and restores it.
  ///
  /// Returns `true` when preferences were applied, `false` when the user
  /// cancels. A malformed file or invalid document throws [BackupException].
  Future<bool> importFromFile() async {
    final Uint8List? bytes = await _filePicker.openFile();
    if (bytes == null) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const BackupException('备份文件无法解析');
    }
    if (decoded is! Map) {
      throw const BackupException('备份格式无效');
    }
    await restore(Map<String, dynamic>.from(decoded));
    return true;
  }

  /// A dated, collision-resistant default name for the saved document.
  String _fileName(Map<String, dynamic> document) {
    final String digits = (document['exportedAt'] as String? ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final String stamp = digits.length >= 8
        ? digits.substring(0, 8)
        : DateTime.now()
              .toUtc()
              .toIso8601String()
              .substring(0, 10)
              .replaceAll('-', '');
    return 'media_player_backup_$stamp.json';
  }
}
