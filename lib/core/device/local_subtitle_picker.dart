import 'package:file_picker/file_picker.dart';

/// Picks a local subtitle file for the player (subtitle extras slice).
///
/// Injected into the player controller so tests never touch the plugin's
/// platform channels, the same trade-off as [BrightnessService].
abstract interface class LocalSubtitlePicker {
  /// Absolute path of the chosen subtitle file, or null when the user
  /// cancels. Throws when the picker itself fails.
  Future<String?> pick();
}

/// [LocalSubtitlePicker] backed by the `file_picker` plugin, restricted to
/// the text-subtitle containers mpv can mount.
class FilePickerLocalSubtitlePicker implements LocalSubtitlePicker {
  const FilePickerLocalSubtitlePicker();

  /// Extensions offered by the native dialog (Yamby parity).
  static const List<String> extensions = <String>[
    'srt',
    'ass',
    'ssa',
    'sub',
    'vtt',
  ];

  @override
  Future<String?> pick() async {
    // The macOS build ships with the sandbox off (M0 decision), so the
    // plugin's entitlement pre-check would block the dialog; skipping it is
    // a no-op on every other platform.
    await FilePicker.skipEntitlementsChecks();
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: '选择字幕文件',
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    return file?.path;
  }
}
