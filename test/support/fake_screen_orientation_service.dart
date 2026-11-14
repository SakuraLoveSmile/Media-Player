import 'package:media_player/core/device/screen_orientation.dart';

/// Records the player's orientation lock (S77) instead of reaching the
/// `flutter/platform` channel.
class FakeScreenOrientationService implements ScreenOrientationService {
  /// Every lock the player asked for, in order.
  final List<PlaybackOrientation> locks = <PlaybackOrientation>[];

  /// Number of times the screen was handed back to the device.
  int restores = 0;

  @override
  Future<void> lock(PlaybackOrientation orientation) async {
    locks.add(orientation);
  }

  @override
  Future<void> restore() async {
    restores += 1;
  }
}
