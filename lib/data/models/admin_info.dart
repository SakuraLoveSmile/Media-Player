import 'json_read.dart';

/// Read-only Emby admin snapshots (S24).
///
/// Kept deliberately small: the admin page shows status, it never mutates
/// users, libraries or the server itself.

/// `GET /System/Info` (S24 服务器信息).
class AdminSystemInfo {
  const AdminSystemInfo({
    this.serverName = '',
    this.version = '',
    this.operatingSystem = '',
    this.hasPendingRestart = false,
  });

  factory AdminSystemInfo.fromJson(Map<String, dynamic> json) {
    return AdminSystemInfo(
      serverName: asStringOr(json['ServerName'], ''),
      version: asStringOr(json['Version'], ''),
      operatingSystem: asStringOr(json['OperatingSystem'], ''),
      hasPendingRestart: asBool(json['HasPendingRestart']),
    );
  }

  final String serverName;
  final String version;
  final String operatingSystem;

  /// True when an update/config change is waiting for a server restart. The
  /// page only reports it; restarting is out of scope (S24 is read-only).
  final bool hasPendingRestart;
}

/// One entry of `GET /Users` (S24 用户).
class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    this.isAdministrator = false,
    this.lastLoginDate,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: asStringOr(json['Id'], ''),
      name: asStringOr(json['Name'], ''),
      isAdministrator: asBool(asMap(json['Policy'])['IsAdministrator']),
      lastLoginDate: DateTime.tryParse(asStringOr(json['LastLoginDate'], '')),
    );
  }

  final String id;
  final String name;
  final bool isAdministrator;

  /// Null when the user never logged in (Emby omits `LastLoginDate`).
  final DateTime? lastLoginDate;
}

/// One entry of `GET /Sessions` (S24 活跃会话).
class AdminSessionInfo {
  const AdminSessionInfo({
    this.userName = '',
    this.client = '',
    this.deviceName = '',
    this.nowPlayingName,
    this.positionTicks = 0,
  });

  factory AdminSessionInfo.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> nowPlaying = asMap(json['NowPlayingItem']);
    final Map<String, dynamic> playState = asMap(json['PlayState']);
    final String? name = asString(nowPlaying['Name']);
    final String? seriesName = asString(nowPlaying['SeriesName']);
    return AdminSessionInfo(
      userName: asStringOr(json['UserName'], ''),
      client: asStringOr(json['Client'], ''),
      deviceName: asStringOr(json['DeviceName'], ''),
      // Episodes carry the episode title in `Name`; prefix the series so the
      // row reads "Series · Episode" instead of a bare "Episode 3".
      nowPlayingName: name == null
          ? null
          : seriesName == null
          ? name
          : '$seriesName · $name',
      positionTicks: asInt(playState['PositionTicks']),
    );
  }

  final String userName;
  final String client;
  final String deviceName;

  /// Null when the session is idle (no `NowPlayingItem`).
  final String? nowPlayingName;

  /// `PlayState.PositionTicks`; 0 when idle or absent.
  final int positionTicks;

  bool get isPlaying => nowPlayingName != null;
}
