/// Public room metadata. It deliberately contains no Emby credentials or account identifiers.
class WatchMedia {
  const WatchMedia({
    required this.itemId,
    required this.mediaSourceId,
    required this.title,
    required this.type,
    required this.runTimeMs,
  });
  factory WatchMedia.fromJson(Map<String, dynamic> json) => WatchMedia(
    itemId: json['itemId'] as String,
    mediaSourceId: json['mediaSourceId'] as String?,
    title: json['title'] as String,
    type: json['type'] as String,
    runTimeMs: (json['runTimeMs'] as num).toInt(),
  );
  final String itemId;
  final String? mediaSourceId;
  final String title;
  final String type;
  final int runTimeMs;
}

class WatchPlayback {
  const WatchPlayback({
    required this.revision,
    required this.state,
    required this.positionMs,
    required this.serverTime,
    required this.waitingMemberIds,
  });
  factory WatchPlayback.fromJson(Map<String, dynamic> json) => WatchPlayback(
    revision: (json['revision'] as num).toInt(),
    state: json['state'] as String,
    positionMs: (json['positionMs'] as num).toInt(),
    serverTime: (json['serverTime'] as num).toInt(),
    waitingMemberIds: (json['waitingMemberIds'] as List<dynamic>? ?? const [])
        .cast<String>(),
  );
  final int revision;
  final String state;
  final int positionMs;
  final int serverTime;
  final List<String> waitingMemberIds;
  int targetAt(int serverNowMs, int runtimeMs) {
    final elapsed = state == 'playing'
        ? (serverNowMs - serverTime).clamp(0, 1 << 52)
        : 0;
    return (positionMs + elapsed).clamp(0, runtimeMs > 0 ? runtimeMs : 1 << 52);
  }
}

class WatchMember {
  const WatchMember({
    required this.memberId,
    required this.name,
    required this.role,
    required this.connected,
    required this.status,
    required this.lagging,
  });
  factory WatchMember.fromJson(Map<String, dynamic> json) => WatchMember(
    memberId: json['memberId'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    connected: json['connected'] as bool,
    status: json['status'] as String,
    lagging: json['lagging'] as bool? ?? false,
  );
  final String memberId, name, role, status;
  final bool connected, lagging;
}

class WatchRoom {
  const WatchRoom({
    required this.roomId,
    required this.code,
    required this.capacity,
    required this.ownerMemberId,
    required this.media,
    required this.playback,
    required this.members,
  });
  factory WatchRoom.fromJson(Map<String, dynamic> json) => WatchRoom(
    roomId: json['roomId'] as String,
    code: json['code'] as String,
    capacity: (json['capacity'] as num).toInt(),
    ownerMemberId: json['ownerMemberId'] as String,
    media: WatchMedia.fromJson(json['media'] as Map<String, dynamic>),
    playback: WatchPlayback.fromJson(json['playback'] as Map<String, dynamic>),
    members: (json['members'] as List<dynamic>)
        .map((e) => WatchMember.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
  );
  final String roomId, code, ownerMemberId;
  final int capacity;
  final WatchMedia media;
  final WatchPlayback playback;
  final List<WatchMember> members;
}

class WatchTogetherException implements Exception {
  const WatchTogetherException(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}
