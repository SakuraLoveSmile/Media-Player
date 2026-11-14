import 'package:flutter/services.dart';

/// Android picture-in-picture entry for the player (S18).
///
/// Injected into the player controller so tests never touch the platform
/// channel, the same trade-off as `BrightnessService` and
/// `LocalSubtitlePicker`.
abstract interface class PipController {
  /// Asks the host activity to enter picture-in-picture. Returns whether the
  /// platform accepted the request; implementations must not throw. Playback
  /// keeps running either way — entering PIP never pauses the engine.
  Future<bool> enterPip();
}

/// [PipController] backed by the `media_player/pip` MethodChannel implemented
/// in MainActivity (API 26+). A missing or failing channel degrades to false
/// instead of breaking the player, the same trade-off as
/// `ScreenBrightnessService`.
class MethodChannelPipController implements PipController {
  const MethodChannelPipController();

  /// Shared with MainActivity.kt; exposed so the channel unit test can mock
  /// the exact contract.
  static const MethodChannel channel = MethodChannel('media_player/pip');

  @override
  Future<bool> enterPip() async {
    try {
      return await channel.invokeMethod<bool>('enterPip') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// A [PipController] that does nothing, for tests and for platforms without
/// picture-in-picture (iOS / macOS / Windows / web).
class NoopPipController implements PipController {
  const NoopPipController();

  @override
  Future<bool> enterPip() async => false;
}
