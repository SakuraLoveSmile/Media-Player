/// Emby header names and value builders (contract §1.4).
abstract final class EmbyHeaders {
  static const String token = 'X-Emby-Token';
  static const String deviceId = 'X-Emby-Device-Id';
  static const String authorization = 'X-Emby-Authorization';

  /// `MediaBrowser Client="...", Device="...", DeviceId="...", Version="..."`
  static String authorizationValue({
    required String client,
    required String device,
    required String deviceId,
    required String version,
  }) {
    // Device names come from the hostname and must not break the quoted list.
    final safeDevice = device.replaceAll('"', "'");
    return 'MediaBrowser Client="$client", Device="$safeDevice", '
        'DeviceId="$deviceId", Version="$version"';
  }
}
