import 'dart:io';

/// `DeviceName` sent in `X-Emby-Authorization` (contract §10.7).
String defaultDeviceName() => '${Platform.operatingSystem} ${Platform.localHostname}';
