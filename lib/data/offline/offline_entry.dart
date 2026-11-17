/// Local metadata only: never stores an endpoint, URL, or access token.
enum OfflineStatus { downloading, paused, failed, complete }

class OfflineEntry {
  OfflineEntry({
    required this.id,
    required this.serverId,
    required this.userId,
    required this.itemId,
    required this.sourceId,
    required this.title,
    required this.serverName,
    this.container = 'mkv',
    this.status = OfflineStatus.paused,
    this.received = 0,
    this.total = 0,
    this.validator,
    this.error,
  });

  final String id;
  final String serverId;
  final String userId;
  final String itemId;
  final String sourceId;
  final String title;
  final String serverName;
  final String container;
  OfflineStatus status;
  int received;
  int total;
  String? validator;
  String? error;

  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;
  String get fileName => '$id.$container';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'serverId': serverId,
    'userId': userId,
    'itemId': itemId,
    'sourceId': sourceId,
    'title': title,
    'serverName': serverName,
    'container': container,
    'status': status.name,
    'received': received,
    'total': total,
    'validator': validator,
    'error': error,
  };

  factory OfflineEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final container = json['container'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        !RegExp(r'^[a-z0-9]{1,8}$').hasMatch(container)) {
      throw const FormatException('Invalid local media name');
    }
    return OfflineEntry(
      id: id,
      serverId: json['serverId'] as String,
      userId: json['userId'] as String,
      itemId: json['itemId'] as String,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String,
      serverName: json['serverName'] as String,
      container: container,
      status: OfflineStatus.values.byName(json['status'] as String),
      received: (json['received'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      validator: json['validator'] as String?,
      error: json['error'] as String?,
    );
  }
}
