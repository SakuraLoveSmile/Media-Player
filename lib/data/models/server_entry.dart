import 'json_read.dart';
import 'server_profile.dart';

/// Stable local id of the legacy single-server configuration (S20).
///
/// The credential stores reuse their original keys for this id, so migrating an
/// existing install to the multi-server directory never moves a token: the
/// legacy session simply becomes the `default` server's session.
const String defaultServerId = 'default';

/// Icon ids offered by 自定义图标 (S80). Kept as plain strings so the data layer
/// stays free of Flutter; the UI maps each id onto a Material icon.
const List<String> serverIconIds = <String>[
  'diamond',
  'tv',
  'movie',
  'router',
  'cloud',
  'home',
  'star',
  'game',
  'music',
  'storage',
];

/// One saved server in the [ServerDirectory] (S20).
///
/// Holds only non-secret identity and addresses; the access token and session
/// metadata stay in the secure per-server stores keyed by [id].
///
/// S80 adds the Yamby server-card preferences: a custom icon id, whether the
/// second line shows the user name and/or the last time something was played
/// from this server. None of it is secret, so it lives in the same directory.
class ServerEntry {
  const ServerEntry({
    required this.id,
    required this.name,
    this.lanUrl,
    this.wanUrl,
    this.customIcon = '',
    this.showUserName = true,
    this.showLastPlayed = false,
    this.lastPlayedAt,
  });

  factory ServerEntry.fromJson(Map<String, dynamic> json) {
    return ServerEntry(
      id: asStringOr(json['id'], ''),
      name: asStringOr(json['name'], ''),
      lanUrl: asString(json['lanUrl']),
      wanUrl: asString(json['wanUrl']),
      customIcon: asStringOr(json['customIcon'], ''),
      showUserName: asBool(json['showUserName'], fallback: true),
      showLastPlayed: asBool(json['showLastPlayed']),
      lastPlayedAt: _dateOrNull(json['lastPlayedAt']),
    );
  }

  /// Local directory id; also the key suffix for this server's secure session.
  final String id;
  final String name;
  final String? lanUrl;
  final String? wanUrl;

  /// Id from [serverIconIds]; empty keeps the default server glyph.
  final String customIcon;

  /// S80: show the signed-in user on the server card.
  final bool showUserName;

  /// S80: show when this server last played something.
  final bool showLastPlayed;

  /// S80: last playback start on this server (null until something played).
  final DateTime? lastPlayedAt;

  bool get hasAnyAddress => lanUrl != null || wanUrl != null;

  /// A short address label for the settings list (prefers LAN).
  String get addressLabel => lanUrl ?? wanUrl ?? '';

  /// 添加备选地址 fills the first empty address slot: LAN when it is still
  /// blank, otherwise WAN (so the row becomes an edit of the WAN address).
  bool get hasLan => (lanUrl ?? '').isNotEmpty;
  bool get hasWan => (wanUrl ?? '').isNotEmpty;
  bool get alternateSlotIsLan => !hasLan;

  /// Null arguments keep the current value; pass an explicit empty string to
  /// clear an address. [clearLastPlayed] resets the timestamp.
  ServerEntry copyWith({
    String? id,
    String? name,
    String? lanUrl,
    String? wanUrl,
    String? customIcon,
    bool? showUserName,
    bool? showLastPlayed,
    DateTime? lastPlayedAt,
    bool clearLastPlayed = false,
  }) {
    return ServerEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      lanUrl: lanUrl == '' ? null : (lanUrl ?? this.lanUrl),
      wanUrl: wanUrl == '' ? null : (wanUrl ?? this.wanUrl),
      customIcon: customIcon ?? this.customIcon,
      showUserName: showUserName ?? this.showUserName,
      showLastPlayed: showLastPlayed ?? this.showLastPlayed,
      lastPlayedAt: clearLastPlayed
          ? null
          : (lastPlayedAt ?? this.lastPlayedAt),
    );
  }

  /// Builds the login/resolve profile for this entry. [serverId] is the Emby
  /// identity (empty until the first successful login), distinct from [id].
  ServerProfile toProfile({String serverId = ''}) => ServerProfile(
    serverId: serverId,
    name: name,
    lanUrl: lanUrl,
    wanUrl: wanUrl,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'lanUrl': lanUrl,
    'wanUrl': wanUrl,
    'customIcon': customIcon,
    'showUserName': showUserName,
    'showLastPlayed': showLastPlayed,
    'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
  };

  /// Accepts epoch milliseconds (what [toJson] writes) or an ISO string.
  static DateTime? _dateOrNull(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
