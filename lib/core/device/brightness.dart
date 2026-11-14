import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// Application-scoped screen brightness for the player gesture layer (S1).
///
/// Application scope (not system) so leaving the player restores the user's
/// own setting; [reset] is called on player teardown.
abstract interface class BrightnessService {
  /// Current application brightness in 0..1.
  Future<double> current();

  /// Sets application brightness, clamped to 0..1.
  Future<void> set(double value);

  /// Restores the system brightness.
  Future<void> reset();
}

/// [BrightnessService] backed by the `screen_brightness` plugin.
///
/// On a platform without a plugin implementation the channel throws; the
/// service then degrades to a no-op instead of breaking playback gestures.
class ScreenBrightnessService implements BrightnessService {
  ScreenBrightnessService([ScreenBrightness? plugin])
    : _plugin = plugin ?? ScreenBrightness.instance;

  final ScreenBrightness _plugin;
  bool _supported = true;
  double _fallback = 0.5;

  @override
  Future<double> current() async {
    if (!_supported) return _fallback;
    try {
      return await _plugin.application;
    } on MissingPluginException {
      return _degrade();
    } on PlatformException {
      return _degrade();
    }
  }

  @override
  Future<void> set(double value) async {
    final double level = value.clamp(0.0, 1.0);
    _fallback = level;
    if (!_supported) return;
    try {
      await _plugin.setApplicationScreenBrightness(level);
    } on MissingPluginException {
      _degrade();
    } on PlatformException {
      _degrade();
    }
  }

  @override
  Future<void> reset() async {
    if (!_supported) return;
    try {
      await _plugin.resetApplicationScreenBrightness();
    } on MissingPluginException {
      _degrade();
    } on PlatformException {
      _degrade();
    }
  }

  double _degrade() {
    _supported = false;
    return _fallback;
  }
}
