import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Saves and opens the preference backup document (S22).
///
/// Injected into [BackupService] so tests never touch the plugin's platform
/// channels, the same trade-off as [LocalSubtitlePicker] and [BrightnessService].
abstract interface class BackupFilePicker {
  /// Writes [bytes] to a user-chosen location suggested as [name].
  ///
  /// Returns `true` when the file was saved, `false` when the user cancels the
  /// dialog. Throws when the picker itself fails.
  Future<bool> saveFile(String name, Uint8List bytes);

  /// Bytes of the chosen backup file, or `null` when the user cancels.
  /// Throws when the picker itself fails.
  Future<Uint8List?> openFile();
}

/// [BackupFilePicker] backed by the `file_picker` plugin, restricted to the
/// JSON container the backup document uses.
class FilePickerBackupFilePicker implements BackupFilePicker {
  const FilePickerBackupFilePicker();

  /// Extension offered by the native open dialog.
  static const List<String> extensions = <String>['json'];

  @override
  Future<bool> saveFile(String name, Uint8List bytes) async {
    // The macOS build ships with the sandbox off (M0 decision), so the
    // plugin's entitlement pre-check would block the dialog; skipping it is a
    // no-op on every other platform.
    await FilePicker.skipEntitlementsChecks();
    final Uri? saved = await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: '导出备份',
    );
    return saved != null;
  }

  @override
  Future<Uint8List?> openFile() async {
    await FilePicker.skipEntitlementsChecks();
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: '导入备份',
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }
}
