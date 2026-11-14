import 'package:media_player/core/device/local_subtitle_picker.dart';

/// Local subtitle picker double for controller/page tests; no platform
/// channels. [path] null simulates a cancelled dialog.
class FakeLocalSubtitlePicker implements LocalSubtitlePicker {
  FakeLocalSubtitlePicker({this.path = '/local/测试字幕.ass', this.failure});

  String? path;
  Object? failure;
  int calls = 0;

  @override
  Future<String?> pick() async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return path;
  }
}
