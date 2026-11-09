import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/moviepilot/models/media_request.dart';
import 'package:media_player/data/moviepilot/models/mp_downloader_torrent.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';
import 'package:media_player/data/moviepilot/models/mp_transfer_history.dart';
import 'package:media_player/data/moviepilot/models/mp_transfer_job.dart';
import 'package:media_player/data/moviepilot/progress/poll_snapshot.dart';
import 'package:media_player/data/moviepilot/progress/request_progress_engine.dart';

const RequestProgressEngine engine = RequestProgressEngine();

final DateTime now = DateTime.utc(2026, 1, 10, 12);
final DateTime longAgo = now.subtract(const Duration(days: 1));

MpSubscribe active({
  int id = 7,
  String mediaId = '693134',
  MpMediaType type = MpMediaType.movie,
  int season = 0,
  String title = '沙丘2',
  String year = '2024',
  String state = 'R',
  int submittedCount = 0,
  String error = '',
  int totalEpisode = 0,
  int completedEpisode = 0,
  String nextRunAt = '',
}) {
  return MpSubscribe(
    id: id,
    ref: MpMediaRef(
      source: MpMediaSource.tmdb,
      mediaId: mediaId,
      title: title,
      year: year,
    ),
    type: type,
    name: title,
    year: year,
    season: season,
    state: state,
    totalEpisode: totalEpisode,
    completedEpisode: completedEpisode,
    executionStatus: MpExecutionStatus(
      state: state,
      phase: 'searching',
      error: error,
      submittedCount: submittedCount,
      nextRunAt: nextRunAt,
    ),
  );
}

MpDownloaderTorrent torrent({
  String hash = 'h1',
  String mediaId = '693134',
  MpMediaType type = MpMediaType.movie,
  int mediaSeason = 0,
  String seasonEpisode = '',
  double progress = 0.5,
  double size = 100,
  String title = '沙丘2',
  String year = '2024',
  String speed = '5 MB/s',
  String eta = '10m',
}) {
  return MpDownloaderTorrent.fromJson(<String, dynamic>{
    'hash': hash,
    'title': title,
    'year': year,
    'season_episode': seasonEpisode,
    'progress': progress,
    'size': size,
    'dlspeed': speed,
    'left_time': eta,
    'media': <String, dynamic>{
      'media_source': 'themoviedb',
      'media_id': mediaId,
      'type': type.wire,
      'season': mediaSeason,
    },
  })!;
}

MpTransferJob job({
  int season = 0,
  String mediaId = '693134',
  MpMediaType type = MpMediaType.movie,
  List<String> hashes = const <String>['h1'],
  String taskState = 'running',
}) {
  return MpTransferJob.fromJson(<String, dynamic>{
    'season': season,
    'media': <String, dynamic>{
      'media_source': 'themoviedb',
      'media_id': mediaId,
      'type': type.wire,
      'season': season,
    },
    'tasks': <Map<String, dynamic>>[
      for (final hash in hashes)
        <String, dynamic>{'state': taskState, 'download_hash': hash},
    ],
  });
}

MpTransferHistory transfer({
  int id = 1,
  String mediaId = '693134',
  String seasons = '',
  String hash = 'h1',
  bool status = true,
}) {
  return MpTransferHistory.fromJson(<String, dynamic>{
    'id': id,
    'media_source': 'themoviedb',
    'media_id': mediaId,
    'seasons': seasons,
    'download_hash': hash,
    'status': status,
  })!;
}

MediaRequest request({
  String mediaId = '693134',
  MpMediaType type = MpMediaType.movie,
  int season = 0,
  String title = '沙丘2',
  String year = '2024',
  int? subscribeId = 7,
  DateTime? createdAt,
  RequestStage stage = RequestStage.submitted,
  String? embyItemId,
}) {
  return MediaRequest(
    id: 'req-1',
    ref: MpMediaRef(
      source: MpMediaSource.tmdb,
      mediaId: mediaId,
      title: title,
      year: year,
    ),
    type: type,
    title: title,
    year: year,
    season: season,
    subscribeId: subscribeId,
    createdAt: createdAt ?? longAgo,
    stage: stage,
    embyItemId: embyItemId,
  );
}

RequestProgress derive(
  MediaRequest record,
  PollSnapshot snapshot, {
  String? embyItemId,
}) {
  return engine.derive(
    record,
    snapshot,
    now: now,
    embyItemId: embyItemId,
  );
}

void main() {
  group('stage derivation', () {
    test('a verified Emby hit is inLibrary and playable', () {
      final progress = derive(
        request(),
        PollSnapshot(subscribes: <MpSubscribe>[active()]),
        embyItemId: 'emby-9',
      );

      expect(progress.stage, RequestStage.inLibrary);
      expect(progress.embyItemId, 'emby-9');
      expect(progress.message, '已入库，可以播放');
    });

    test('a stored Emby id survives without a fresh lookup', () {
      final progress = derive(
        request(embyItemId: 'emby-1'),
        PollSnapshot.empty,
      );

      expect(progress.stage, RequestStage.inLibrary);
      expect(progress.embyItemId, 'emby-1');
    });

    test('a cancelled request stays cancelled whatever the poll says', () {
      final progress = derive(
        request(stage: RequestStage.cancelled),
        PollSnapshot(subscribes: <MpSubscribe>[active(submittedCount: 5)]),
      );

      expect(progress.stage, RequestStage.cancelled);
    });

    test('a new (N) subscription with no round yet is submitted', () {
      final progress = derive(
        request(),
        PollSnapshot(subscribes: <MpSubscribe>[active(state: 'N')]),
      );

      expect(progress.stage, RequestStage.submitted);
      expect(progress.canSearchNow, isTrue);
    });

    test('a running round with nothing submitted is searching', () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active(nextRunAt: '2026-01-10T13:00:00')],
        ),
      );

      expect(progress.stage, RequestStage.searching);
      expect(progress.message, '正在搜索资源');
      expect(progress.canSearchNow, isTrue);
      expect(progress.nextRunAt, '2026-01-10T13:00:00');
    });

    test('an explicitly running status with no submission is searching', () {
      final progress = derive(
        request(),
        PollSnapshot(subscribes: <MpSubscribe>[active()]),
      );

      expect(progress.stage, isNot(RequestStage.downloading));
      expect(progress.stage, isNot(RequestStage.submitted));
    });

    test('downloads in flight are downloading with weighted progress', () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active()],
          downloads: <MpDownloaderTorrent>[
            torrent(hash: 'a', progress: 0.2, size: 100),
            torrent(hash: 'b', progress: 0.8, size: 300),
          ],
        ),
      );

      expect(progress.stage, RequestStage.downloading);
      // (100*0.2 + 300*0.8) / 400 = 0.65
      expect(progress.progress, closeTo(0.65, 1e-9));
      expect(progress.activeTaskCount, 2);
      expect(progress.downloadSpeed, '5 MB/s');
      expect(progress.eta, '10m');
    });

    test('a completed download still reports downloading until it organizes',
        () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active()],
          downloads: <MpDownloaderTorrent>[torrent(progress: 1)],
        ),
      );

      expect(progress.stage, RequestStage.downloading);
      expect(progress.progress, 1);
      expect(progress.message, '下载完成，等待整理');
    });

    test('submitted downloads that are not listed yet are downloading',
        () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active(submittedCount: 2)],
        ),
      );

      expect(progress.stage, RequestStage.downloading);
      expect(progress.progress, isNull);
      expect(progress.message, '已添加下载，等待下载器');
    });

    test('a transfer job with no active download is organizing', () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active()],
          downloads: <MpDownloaderTorrent>[torrent(progress: 1)],
          transferQueue: <MpTransferJob>[job()],
        ),
      );

      expect(progress.stage, RequestStage.organizing);
      expect(progress.message, '正在整理文件到媒体库');
    });

    test('an active download outranks the queue entry', () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active()],
          downloads: <MpDownloaderTorrent>[torrent(progress: 0.4)],
          transferQueue: <MpTransferJob>[job()],
        ),
      );

      expect(progress.stage, RequestStage.downloading);
    });

    test('a failed transfer job says so', () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active()],
          transferQueue: <MpTransferJob>[job(taskState: 'failed')],
        ),
      );

      expect(progress.stage, RequestStage.organizing);
      expect(progress.message, contains('重试'));
    });

    test('a successful transfer waits for Emby', () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active()],
          transferHistory: <MpTransferHistory>[transfer()],
        ),
      );

      expect(progress.stage, RequestStage.organizedPendingLibrary);
      expect(progress.message, '整理完成，等待 Emby 入库');
      expect(progress.transferHash, 'h1');
    });

    test('a subscription that moved to history is pending library', () {
      final progress = derive(
        request(subscribeId: null),
        PollSnapshot(movieHistory: <MpSubscribe>[active(id: 7)]),
      );

      expect(progress.stage, RequestStage.organizedPendingLibrary);
      expect(progress.archived, isTrue);
    });

    test('a paused subscription is paused', () {
      final progress = derive(
        request(),
        PollSnapshot(subscribes: <MpSubscribe>[active(state: 'S')]),
      );

      expect(progress.stage, RequestStage.paused);
    });

    test('a round that errored is noResource with a retry hint', () {
      final progress = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active(error: '没有可用的站点')],
        ),
      );

      expect(progress.stage, RequestStage.noResource);
      expect(progress.canSearchNow, isTrue);
    });

    test('a just-created request stays submitted inside the grace window', () {
      final progress = derive(
        request(createdAt: now.subtract(const Duration(seconds: 5))),
        PollSnapshot.empty,
      );

      expect(progress.stage, RequestStage.submitted);
      expect(progress.stale, isFalse);
    });

    test('a request missing from MoviePilot past the window is stale', () {
      final progress = derive(request(), PollSnapshot.empty);

      expect(progress.stage, RequestStage.searching);
      expect(progress.stale, isTrue);
      expect(progress.message, contains('尚未'));
    });
  });

  group('series aggregation', () {
    test('completed episodes count only finished tasks of the season', () {
      final progress = derive(
        request(type: MpMediaType.series, season: 2, mediaId: '1399'),
        PollSnapshot(
          subscribes: <MpSubscribe>[
            active(type: MpMediaType.series, season: 2, mediaId: '1399'),
          ],
          downloads: <MpDownloaderTorrent>[
            torrent(hash: 'a', type: MpMediaType.series, mediaId: '1399',
                mediaSeason: 2, seasonEpisode: 'S02E01', progress: 1),
            torrent(hash: 'b', type: MpMediaType.series, mediaId: '1399',
                mediaSeason: 2, seasonEpisode: 'S02E02', progress: 1),
            torrent(hash: 'c', type: MpMediaType.series, mediaId: '1399',
                mediaSeason: 2, seasonEpisode: 'S02E03', progress: 0.1),
          ],
        ),
      );

      expect(progress.stage, RequestStage.downloading);
      expect(progress.completedEpisodes, 2);
      expect(progress.activeTaskCount, 3);
    });

    test('a whole-series subscription accepts any season', () {
      final progress = derive(
        request(type: MpMediaType.series, season: 0, mediaId: '1399'),
        PollSnapshot(
          downloads: <MpDownloaderTorrent>[
            torrent(type: MpMediaType.series, mediaId: '1399', mediaSeason: 3),
          ],
        ),
      );

      expect(progress.stage, RequestStage.downloading);
    });

    test('episode counters come from the subscription while searching', () {
      final progress = derive(
        request(type: MpMediaType.series, season: 1, mediaId: '1399'),
        PollSnapshot(
          subscribes: <MpSubscribe>[
            active(
              type: MpMediaType.series,
              season: 1,
              mediaId: '1399',
              totalEpisode: 10,
              completedEpisode: 4,
              submittedCount: 1,
            ),
          ],
        ),
      );

      expect(progress.totalEpisodes, 10);
      expect(progress.completedEpisodes, 4);
    });
  });

  group('mutation checks', () {
    // Each block flips exactly one decisive input and asserts the stage moves.
    // Without these, a derive() that always returned one stage would pass the
    // table above.

    test('submitted_count 0 -> 1 moves searching to downloading', () {
      final record = request();
      final before = derive(
        record,
        PollSnapshot(subscribes: <MpSubscribe>[active(submittedCount: 0)]),
      );
      final after = derive(
        record,
        PollSnapshot(subscribes: <MpSubscribe>[active(submittedCount: 1)]),
      );

      expect(before.stage, isNot(RequestStage.downloading));
      expect(after.stage, RequestStage.downloading);
    });

    test('adding a matching download moves organizing back to downloading', () {
      final record = request();
      final queue = <MpTransferJob>[job()];
      final organizing = derive(
        record,
        PollSnapshot(transferQueue: queue),
      );
      final downloading = derive(
        record,
        PollSnapshot(
          downloads: <MpDownloaderTorrent>[torrent(progress: 0.3)],
          transferQueue: queue,
        ),
      );

      expect(organizing.stage, RequestStage.organizing);
      expect(downloading.stage, RequestStage.downloading);
    });

    test('removing the download keeps the transfer stage', () {
      final record = request();
      final withDownload = derive(
        record,
        PollSnapshot(
          downloads: <MpDownloaderTorrent>[torrent(progress: 0.5)],
          transferQueue: <MpTransferJob>[job()],
        ),
      );
      final without = derive(
        record,
        PollSnapshot(transferQueue: <MpTransferJob>[job()]),
      );

      expect(withDownload.stage, RequestStage.downloading);
      expect(without.stage, RequestStage.organizing);
    });

    test('transfer history false -> true moves pending to nothing', () {
      final record = request();
      final failed = derive(
        record,
        PollSnapshot(
          subscribes: <MpSubscribe>[active(submittedCount: 1)],
          transferHistory: <MpTransferHistory>[transfer(status: false)],
        ),
      );
      final succeeded = derive(
        record,
        PollSnapshot(
          subscribes: <MpSubscribe>[active(submittedCount: 1)],
          transferHistory: <MpTransferHistory>[transfer(status: true)],
        ),
      );

      expect(failed.stage, RequestStage.downloading);
      expect(succeeded.stage, RequestStage.organizedPendingLibrary);
    });

    test('moving the subscription to history changes the stage', () {
      final record = request(subscribeId: null);
      final activeRound = derive(
        record,
        PollSnapshot(subscribes: <MpSubscribe>[active(submittedCount: 1)]),
      );
      final archivedRound = derive(
        record,
        PollSnapshot(movieHistory: <MpSubscribe>[active()]),
      );

      expect(activeRound.stage, RequestStage.downloading);
      expect(archivedRound.stage, RequestStage.organizedPendingLibrary);
    });

    test('an error appearing turns searching into noResource', () {
      final clean = derive(
        request(),
        PollSnapshot(subscribes: <MpSubscribe>[active()]),
      );
      final broken = derive(
        request(),
        PollSnapshot(subscribes: <MpSubscribe>[active(error: 'boom')]),
      );

      expect(clean.stage, isNot(RequestStage.noResource));
      expect(broken.stage, RequestStage.noResource);
    });

    test('state R -> S turns searching into paused', () {
      final running = derive(
        request(),
        PollSnapshot(subscribes: <MpSubscribe>[active(state: 'R')]),
      );
      final paused = derive(
        request(),
        PollSnapshot(subscribes: <MpSubscribe>[active(state: 'S')]),
      );

      expect(running.stage, isNot(RequestStage.paused));
      expect(paused.stage, RequestStage.paused);
    });

    test('progress reaching 100% changes the message, not the stage', () {
      final halfway = derive(
        request(),
        PollSnapshot(
          downloads: <MpDownloaderTorrent>[torrent(progress: 0.5)],
        ),
      );
      final complete = derive(
        request(),
        PollSnapshot(
          downloads: <MpDownloaderTorrent>[torrent(progress: 1)],
        ),
      );

      expect(halfway.message, '正在下载');
      expect(complete.message, '下载完成，等待整理');
      expect(complete.progress, 1);
    });

    test('an Emby id appearing moves anything to inLibrary', () {
      final before = derive(
        request(),
        PollSnapshot(
          subscribes: <MpSubscribe>[active(submittedCount: 1)],
        ),
      );
      final after = derive(
        request(),
        PollSnapshot(movieHistory: <MpSubscribe>[active()]),
        embyItemId: 'emby-1',
      );

      expect(before.stage, RequestStage.downloading);
      expect(after.stage, RequestStage.inLibrary);
    });
  });
}
