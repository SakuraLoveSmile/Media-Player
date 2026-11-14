import 'package:flutter/services.dart';

/// Screen orientations the player offers (S77).
///
/// The player opens in [landscape]; the control in both layouts switches to
/// the other mode and pins the device to it.
enum PlaybackOrientation { landscape, portrait }

/// Locks the screen to a playback orientation and releases the lock again.
///
/// Abstract so widget tests can record the calls without touching the
/// `flutter/platform` channel, the same trade-off as `PipController` and
/// `BrightnessService`.
abstract interface class ScreenOrientationService {
  /// Pins the screen to [orientation].
  Future<void> lock(PlaybackOrientation orientation);

  /// Releases the pin so the rest of the app follows the device again.
  Future<void> restore();
}

/// [ScreenOrientationService] backed by [SystemChrome].
///
/// Desktop platforms have no screen rotation, where the platform request is
/// rejected or missing; the service swallows that instead of failing playback,
/// and the layout mode still works on its own.
class SystemScreenOrientationService implements ScreenOrientationService {
  const SystemScreenOrientationService();

  static const List<DeviceOrientation> _landscapeOrientations =
      <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ];

  static const List<DeviceOrientation> _portraitOrientations =
      <DeviceOrientation>[DeviceOrientation.portraitUp];

  @override
  Future<void> lock(PlaybackOrientation orientation) => _set(
    orientation == PlaybackOrientation.landscape
        ? _landscapeOrientations
        : _portraitOrientations,
  );

  /// An empty list is `SystemChrome`'s "follow the platform default" value,
  /// which is what every page outside the player used before S77.
  @override
  Future<void> restore() => _set(const <DeviceOrientation>[]);

  Future<void> _set(List<DeviceOrientation> orientations) async {
    try {
      await SystemChrome.setPreferredOrientations(orientations);
    } on MissingPluginException {
      // No rotation on this platform (desktop, tests).
    } on PlatformException {
      // A refused request must not break playback.
    }
  }
}
