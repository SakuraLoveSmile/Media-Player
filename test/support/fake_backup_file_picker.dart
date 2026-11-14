import 'dart:typed_data';

import 'package:media_player/core/device/backup_file_picker.dart';

/// Backup file picker double for service/section tests; no platform channels.
/// [openBytes] null simulates a cancelled open dialog; [saveResult] false
/// simulates a cancelled save dialog. [failure] throws from either call.
class FakeBackupFilePicker implements BackupFilePicker {
  FakeBackupFilePicker({this.openBytes, this.saveResult = true, this.failure});

  Uint8List? openBytes;
  bool saveResult;
  Object? failure;

  int saveCalls = 0;
  int openCalls = 0;
  String? savedName;
  Uint8List? savedBytes;

  @override
  Future<bool> saveFile(String name, Uint8List bytes) async {
    saveCalls++;
    savedName = name;
    savedBytes = bytes;
    final Object? error = failure;
    if (error != null) throw error;
    return saveResult;
  }

  @override
  Future<Uint8List?> openFile() async {
    openCalls++;
    final Object? error = failure;
    if (error != null) throw error;
    return openBytes;
  }
}
