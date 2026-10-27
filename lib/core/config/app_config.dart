/// App-wide constants that do not depend on the runtime environment.
abstract final class AppConfig {
  static const String appName = 'Media Player';

  /// Client name sent in `X-Emby-Authorization` (contract §1.4).
  static const String clientName = 'MediaPlayer';

  /// Keep in sync with `version` in pubspec.yaml (major.minor.patch).
  static const String appVersion = '0.1.0';
}
