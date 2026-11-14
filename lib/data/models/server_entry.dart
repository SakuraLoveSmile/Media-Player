import 'json_read.dart';
import 'server_profile.dart';

/// Stable local id of the legacy single-server configuration (S20).
///
/// The credential stores reuse their original keys for this id, so migrating an
/// existing install to the multi-server directory never moves a token: the
/// legacy session simply becomes the `default` server's session.
const String defaultServerId = 'default';

/// One saved server in the [ServerDirectory] (S20).
///
/// Holds only non-secret identity and addresses; the access token and session
/// metadata stay in the secure per-server stores keyed by [id].
class ServerEntry {
  const ServerEntry({
    required this.id,
    required this.name,
    this.lanUrl,
    this.wanUrl,
  });

  factory ServerEntry.fromJson(Map<String, dynamic> json) {
    return ServerEntry(
      id: asStringOr(json['id'], ''),
      name: asStringOr(json['name'], ''),
      lanUrl: asString(json['lanUrl']),
      wanUrl: asString(json['wanUrl']),
    );
  }

  /// Local directory id; also the key suffix for this server's secure session.
  final String id;
  final String name;
  final String? lanUrl;
  final String? wanUrl;

  bool get hasAnyAddress => lanUrl != null || wanUrl != null;

  /// A short address label for the settings list (prefers LAN).
  String get addressLabel => lanUrl ?? wanUrl ?? '';

  ServerEntry copyWith({
    String? id,
    String? name,
    String? lanUrl,
    String? wanUrl,
  }) {
    return ServerEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      lanUrl: lanUrl == '' ? null : (lanUrl ?? this.lanUrl),
      wanUrl: wanUrl == '' ? null : (wanUrl ?? this.wanUrl),
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
  };
}
