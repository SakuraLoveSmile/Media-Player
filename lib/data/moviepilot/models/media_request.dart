import 'mp_media_info.dart';

/// A 求片 the user created, stored on the device (plan S5).
///
/// This is the app's own record: MoviePilot owns the subscription, but the app
/// needs to remember what it asked for before the first poll answers, and to
/// keep showing something after the subscription moves to history (or after the
/// user reinstalls the page). It holds no credentials and no server state that
/// can drift — the progress in it is a cache of the last derivation.
class MediaRequest {
  const MediaRequest({
    required this.id,
    required this.ref,
    required this.type,
    required this.title,
    required this.createdAt,
    this.year = '',
    this.season = 0,
    this.subscribeId,
    this.poster = '',
    this.stage = RequestStage.submitted,
    this.embyItemId,
    this.message = '',
    this.lastUpdatedAt,
    this.progressPercent,
    this.downloadSpeed = '',
    this.eta = '',
    this.completedEpisodes = 0,
    this.totalEpisodes = 0,
    this.activeTaskCount = 0,
    this.archived = false,
  });

  static const int schemaVersion = 1;

  /// Local identifier; stable across restarts and independent of MoviePilot's
  /// subscription id (which is absent until the create call answers).
  final String id;

  /// What was asked for. [MpMediaRef.identityKey] is the join key against
  /// MoviePilot data.
  final MpMediaRef ref;
  final MpMediaType type;
  final String title;
  final String year;

  /// Season asked for; 0 for a movie.
  final int season;

  /// MoviePilot's subscription id, null until `POST /subscribe/` answered.
  final int? subscribeId;

  final String poster;
  final DateTime createdAt;

  /// Last derived stage, so a restored page paints immediately.
  final RequestStage stage;

  /// Emby item id once the title is in the library; it makes the request
  /// playable on the spot.
  final String? embyItemId;

  /// Short user-facing note from the last derivation ("已提交下载，等待下载器").
  final String message;

  /// When [stage] and the progress fields were last refreshed.
  final DateTime? lastUpdatedAt;

  /// Completed download fraction in `0..1`; null while unknown.
  final double? progressPercent;
  final String downloadSpeed;
  final String eta;
  final int completedEpisodes;
  final int totalEpisodes;
  final int activeTaskCount;

  /// True once the subscription is gone from the active list, so the page can
  /// stop polling MoviePilot for it (it still keeps the card).
  final bool archived;

  bool get isMovie => type == MpMediaType.movie;

  bool get isSeries => type == MpMediaType.series;

  /// Whether the stage is a terminal one for polling purposes.
  bool get isFinished => stage == RequestStage.inLibrary;

  bool get isCancelled => stage == RequestStage.cancelled;

  String get seasonLabel => season > 0 ? '第 $season 季' : '';

  int get percentDisplay =>
      progressPercent == null ? 0 : (progressPercent! * 100).round();

  MediaRequest copyWith({
    String? id,
    MpMediaRef? ref,
    MpMediaType? type,
    String? title,
    String? year,
    int? season,
    Object? subscribeId = _unset,
    String? poster,
    DateTime? createdAt,
    RequestStage? stage,
    Object? embyItemId = _unset,
    String? message,
    Object? lastUpdatedAt = _unset,
    Object? progressPercent = _unset,
    String? downloadSpeed,
    String? eta,
    int? completedEpisodes,
    int? totalEpisodes,
    int? activeTaskCount,
    bool? archived,
  }) {
    return MediaRequest(
      id: id ?? this.id,
      ref: ref ?? this.ref,
      type: type ?? this.type,
      title: title ?? this.title,
      year: year ?? this.year,
      season: season ?? this.season,
      subscribeId: identical(subscribeId, _unset)
          ? this.subscribeId
          : subscribeId as int?,
      poster: poster ?? this.poster,
      createdAt: createdAt ?? this.createdAt,
      stage: stage ?? this.stage,
      embyItemId: identical(embyItemId, _unset)
          ? this.embyItemId
          : embyItemId as String?,
      message: message ?? this.message,
      lastUpdatedAt: identical(lastUpdatedAt, _unset)
          ? this.lastUpdatedAt
          : lastUpdatedAt as DateTime?,
      progressPercent: identical(progressPercent, _unset)
          ? this.progressPercent
          : progressPercent as double?,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      eta: eta ?? this.eta,
      completedEpisodes: completedEpisodes ?? this.completedEpisodes,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      activeTaskCount: activeTaskCount ?? this.activeTaskCount,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'id': id,
    ...ref.toJson(),
    'type': type.wire,
    'title': title,
    'year': year,
    'season': season,
    if (subscribeId != null) 'subscribeId': subscribeId,
    'poster': poster,
    'createdAt': createdAt.toIso8601String(),
    'stage': stage.name,
    if (embyItemId != null) 'embyItemId': embyItemId,
    'message': message,
    if (lastUpdatedAt != null)
      'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
    if (progressPercent != null) 'progressPercent': progressPercent,
    'downloadSpeed': downloadSpeed,
    'eta': eta,
    'completedEpisodes': completedEpisodes,
    'totalEpisodes': totalEpisodes,
    'activeTaskCount': activeTaskCount,
    'archived': archived,
  };

  /// Tolerant parse: an unreadable record is dropped rather than crashing the
  /// page, and an unknown stage falls back to "submitted" so the next poll can
  /// correct it.
  static MediaRequest? fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final type = MpMediaType.parse(json['type']);
    if (id == null || type == null) return null;

    final ref = MpMediaRef.fromJson(json);
    final title = _string(json['title']) ?? ref.title;
    if (title.isEmpty) return null;

    return MediaRequest(
      id: id,
      ref: ref,
      type: type,
      title: title,
      year: _string(json['year']) ?? ref.year,
      season: _int(json['season']) ?? 0,
      subscribeId: _int(json['subscribeId']),
      poster: _string(json['poster']) ?? '',
      createdAt:
          DateTime.tryParse(_string(json['createdAt']) ?? '') ?? DateTime.now(),
      stage: RequestStage.parse(json['stage']),
      embyItemId: _string(json['embyItemId']),
      message: _string(json['message']) ?? '',
      lastUpdatedAt: DateTime.tryParse(_string(json['lastUpdatedAt']) ?? ''),
      progressPercent: _double(json['progressPercent']),
      downloadSpeed: _string(json['downloadSpeed']) ?? '',
      eta: _string(json['eta']) ?? '',
      completedEpisodes: _int(json['completedEpisodes']) ?? 0,
      totalEpisodes: _int(json['totalEpisodes']) ?? 0,
      activeTaskCount: _int(json['activeTaskCount']) ?? 0,
      archived: json['archived'] == true,
    );
  }

  /// The key two records collide on: the same media, same season, same type.
  String get identityKey {
    final media = ref.identityKey;
    if (media == null) return 'title:${title.toLowerCase()}|$year|s$season';
    return '$media|${type.wire}|s$season';
  }

  static String? _string(Object? value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value is num) return value.toString();
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static const Object _unset = Object();
}

/// Where a request is in the MoviePilot -> Emby pipeline (plan S5/S6).
///
/// The order matters: the engine walks forwards and never jumps back, so a
/// later signal always wins over an earlier one in the same round.
enum RequestStage {
  /// The create call succeeded; MoviePilot has not reported a round yet.
  submitted,

  /// MoviePilot is searching (or waiting for the next scheduled search).
  searching,

  /// A download was handed to the downloader.
  downloading,

  /// Files are being moved or renamed (transfer queue).
  organizing,

  /// The transfer history shows a success; Emby may not have scanned it yet.
  organizedPendingLibrary,

  /// Emby reports the item, so it is playable now.
  inLibrary,

  /// MoviePilot says there is no resource; it keeps searching.
  noResource,

  /// The user paused the subscription inside MoviePilot.
  paused,

  /// The user removed the request here.
  cancelled;

  bool get isTerminal =>
      this == RequestStage.inLibrary || this == RequestStage.cancelled;

  /// Whether the card should show a determined progress bar.
  bool get hasDeterminateProgress => this == RequestStage.downloading;

  /// Whether the card should show an indeterminate progress bar.
  bool get isBusy =>
      this == RequestStage.submitted ||
      this == RequestStage.searching ||
      this == RequestStage.organizing;

  static RequestStage parse(Object? value) {
    final name = value is String ? value : '';
    for (final stage in RequestStage.values) {
      if (stage.name == name) return stage;
    }
    return RequestStage.submitted;
  }

  /// The stage chain shown on the card, without the side branches.
  static const List<RequestStage> chain = <RequestStage>[
    RequestStage.submitted,
    RequestStage.searching,
    RequestStage.downloading,
    RequestStage.organizing,
    RequestStage.organizedPendingLibrary,
    RequestStage.inLibrary,
  ];

  /// Position in [chain], or -1 for a side branch.
  int get chainIndex {
    final index = chain.indexOf(this);
    if (index >= 0) return index;
    return switch (this) {
      RequestStage.noResource => chain.indexOf(RequestStage.searching),
      RequestStage.paused => chain.indexOf(RequestStage.searching),
      _ => 0,
    };
  }
}
