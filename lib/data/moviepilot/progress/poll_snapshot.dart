import '../models/mp_downloader_torrent.dart';
import '../models/mp_subscribe.dart';
import '../models/mp_transfer_history.dart';
import '../models/mp_transfer_job.dart';

/// Everything one poll round observed, with no interpretation (plan S5).
///
/// The engine derives stages from this snapshot; keeping it a plain value means
/// it can be persisted and re-derived after a restart without another round.
class PollSnapshot {
  const PollSnapshot({
    this.subscribes = const <MpSubscribe>[],
    this.movieHistory = const <MpSubscribe>[],
    this.seriesHistory = const <MpSubscribe>[],
    this.downloads = const <MpDownloaderTorrent>[],
    this.transferQueue = const <MpTransferJob>[],
    this.transferHistory = const <MpTransferHistory>[],
    this.tasksLoaded = false,
    this.fetchedAt,
  });

  static const PollSnapshot empty = PollSnapshot();

  /// `GET /subscribe/` — the active subscriptions.
  final List<MpSubscribe> subscribes;

  /// `GET /subscribe/history/电影`.
  final List<MpSubscribe> movieHistory;

  /// `GET /subscribe/history/电视剧`.
  final List<MpSubscribe> seriesHistory;

  /// `GET /download/` — running downloader tasks.
  final List<MpDownloaderTorrent> downloads;

  /// `GET /transfer/queue` — jobs MoviePilot is moving/renaming right now.
  final List<MpTransferJob> transferQueue;

  /// `GET /history/transfer` — finished transfers, `status == true` means the
  /// files reached the media library.
  final List<MpTransferHistory> transferHistory;

  /// False when this round skipped the download/transfer half, so the engine
  /// knows an empty [downloads] means "not asked" rather than "nothing there".
  final bool tasksLoaded;

  /// When the round ran; used for the grace window on a just-created request.
  final DateTime? fetchedAt;

  /// Every archived subscription, whichever media type it belongs to.
  List<MpSubscribe> get history => <MpSubscribe>[
    ...movieHistory,
    ...seriesHistory,
  ];

  bool get isEmpty =>
      subscribes.isEmpty &&
      movieHistory.isEmpty &&
      seriesHistory.isEmpty &&
      downloads.isEmpty &&
      transferQueue.isEmpty &&
      transferHistory.isEmpty;

  PollSnapshot copyWith({
    List<MpSubscribe>? subscribes,
    List<MpSubscribe>? movieHistory,
    List<MpSubscribe>? seriesHistory,
    List<MpDownloaderTorrent>? downloads,
    List<MpTransferJob>? transferQueue,
    List<MpTransferHistory>? transferHistory,
    bool? tasksLoaded,
    DateTime? fetchedAt,
  }) {
    return PollSnapshot(
      subscribes: subscribes ?? this.subscribes,
      movieHistory: movieHistory ?? this.movieHistory,
      seriesHistory: seriesHistory ?? this.seriesHistory,
      downloads: downloads ?? this.downloads,
      transferQueue: transferQueue ?? this.transferQueue,
      transferHistory: transferHistory ?? this.transferHistory,
      tasksLoaded: tasksLoaded ?? this.tasksLoaded,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  /// Replaces the task half while keeping the subscription half.
  PollSnapshot withTasks({
    required List<MpDownloaderTorrent> downloads,
    required List<MpTransferJob> transferQueue,
    required List<MpTransferHistory> transferHistory,
  }) {
    return copyWith(
      downloads: downloads,
      transferQueue: transferQueue,
      transferHistory: transferHistory,
      tasksLoaded: true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'subscribes': <Map<String, dynamic>>[
      for (final subscribe in subscribes) subscribe.toJson(),
    ],
    'movieHistory': <Map<String, dynamic>>[
      for (final subscribe in movieHistory) subscribe.toJson(),
    ],
    'seriesHistory': <Map<String, dynamic>>[
      for (final subscribe in seriesHistory) subscribe.toJson(),
    ],
    'downloads': <Map<String, dynamic>>[
      for (final torrent in downloads) _torrentJson(torrent),
    ],
    'transferQueue': <Map<String, dynamic>>[
      for (final job in transferQueue) _jobJson(job),
    ],
    'transferHistory': <Map<String, dynamic>>[
      for (final row in transferHistory) _historyJson(row),
    ],
    'tasksLoaded': tasksLoaded,
    if (fetchedAt != null) 'fetchedAt': fetchedAt!.toIso8601String(),
  };

  static PollSnapshot fromJson(Map<String, dynamic> json) {
    return PollSnapshot(
      subscribes: _subscribes(json['subscribes']),
      movieHistory: _subscribes(json['movieHistory']),
      seriesHistory: _subscribes(json['seriesHistory']),
      downloads: <MpDownloaderTorrent>[
        for (final raw in _maps(json['downloads']))
          ?MpDownloaderTorrent.fromJson(raw),
      ],
      transferQueue: <MpTransferJob>[
        for (final raw in _maps(json['transferQueue']))
          MpTransferJob.fromJson(raw),
      ],
      transferHistory: <MpTransferHistory>[
        for (final raw in _maps(json['transferHistory']))
          ?MpTransferHistory.fromJson(raw),
      ],
      tasksLoaded: json['tasksLoaded'] == true,
      fetchedAt: DateTime.tryParse('${json['fetchedAt'] ?? ''}'),
    );
  }

  static List<MpSubscribe> _subscribes(Object? value) => <MpSubscribe>[
    for (final raw in _maps(value)) ?MpSubscribe.fromJson(raw),
  ];

  static List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// Snapshots keep the fields the UI renders, not every field the API returns,
  /// so a restored page shows real values without a second request.
  static Map<String, dynamic> _torrentJson(MpDownloaderTorrent torrent) {
    return <String, dynamic>{
      'hash': torrent.hash,
      'name': torrent.name,
      'title': torrent.title,
      'year': torrent.year,
      'season_episode': torrent.seasonEpisode,
      'state': torrent.state,
      'progress': torrent.progress,
      'size': torrent.size,
      'dlspeed': torrent.downloadSpeed,
      'left_time': torrent.leftTime,
      if (torrent.media != null)
        'media': <String, dynamic>{
          ...torrent.media!.ref.toJson(),
          if (torrent.media!.type != null) 'type': torrent.media!.type!.wire,
          'season': torrent.media!.season,
          'episode': torrent.media!.episode,
        },
    };
  }

  static Map<String, dynamic> _jobJson(MpTransferJob job) {
    return <String, dynamic>{
      'season': job.season,
      if (job.media != null)
        'media': <String, dynamic>{
          ...job.media!.ref.toJson(),
          if (job.media!.type != null) 'type': job.media!.type!.wire,
          'season': job.media!.season,
          'episode': job.media!.episode,
        },
      'tasks': <Map<String, dynamic>>[
        for (final task in job.tasks)
          <String, dynamic>{
            'state': task.state,
            'download_hash': task.downloadHash,
          },
      ],
    };
  }

  static Map<String, dynamic> _historyJson(MpTransferHistory row) {
    return <String, dynamic>{
      'id': row.id,
      'title': row.title,
      'year': row.year,
      if (row.type != null) 'type': row.type!.wire,
      'seasons': row.seasons,
      'episodes': row.episodes,
      'download_hash': row.downloadHash,
      'status': row.status,
      'origin': row.origin,
      'date': row.date,
      ...row.ref.toJson(),
    };
  }
}
