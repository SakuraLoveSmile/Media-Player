import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/moviepilot/models/media_request.dart';
import 'package:media_player/data/moviepilot/models/mp_downloader_torrent.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';
import 'package:media_player/data/moviepilot/models/mp_transfer_history.dart';
import 'package:media_player/data/moviepilot/models/mp_transfer_job.dart';
import 'package:media_player/data/moviepilot/progress/poll_snapshot.dart';
import 'package:media_player/data/moviepilot/progress/request_matcher.dart';

/// Builds an active subscription; `title`/`year` are carried on the ref.
MpSubscribe active({
  int id = 7,
  String mediaId = '693134',
  MpMediaType type = MpMediaType.movie,
  int season = 0,
  String title = '沙丘2',
  String year = '2024',
  String state = 'R',
  int submittedCount = 0,
  String phase = 'searching',
  String error = '',
  int totalEpisode = 0,
  int completedEpisode = 0,
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
      phase: phase,
      error: error,
      submittedCount: submittedCount,
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
  bool withMedia = true,
}) {
  final json = <String, dynamic>{
    'hash': hash,
    'title': title,
    'year': year,
    'season_episode': seasonEpisode,
    'progress': progress,
    'size': size,
    'dlspeed': '5 MB/s',
    'left_time': '10m',
    if (withMedia)
      'media': <String, dynamic>{
        'media_source': 'themoviedb',
        'media_id': mediaId,
        'type': type.wire,
        'season': mediaSeason,
      },
  };
  return MpDownloaderTorrent.fromJson(json)!;
}

MpTransferJob job({
  int season = 0,
  String mediaId = '693134',
  MpMediaType type = MpMediaType.movie,
  List<String> hashes = const <String>['h1'],
  String taskState = 'running',
  bool withMedia = true,
}) {
  return MpTransferJob.fromJson(<String, dynamic>{
    'season': season,
    if (withMedia)
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
  String seasons = 'S01',
  String hash = 'h1',
  bool status = true,
  MpMediaType? type = MpMediaType.movie,
}) {
  return MpTransferHistory.fromJson(<String, dynamic>{
    'id': id,
    'media_source': 'themoviedb',
    'media_id': mediaId,
    if (type != null) 'type': type.wire,
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
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    stage: stage,
    embyItemId: embyItemId,
  );
}

void main() {
  group('RequestMatcher.subscription', () {
    test('matches on the recorded subscription id first', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          subscribes: <MpSubscribe>[
            active(id: 1, mediaId: '999', title: 'Other'),
            active(id: 7, mediaId: '693134'),
          ],
        ),
      );

      expect(matcher.subscription(request())!.id, 7);
    });

    test('falls back to the identity pair when the id is unknown', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          subscribes: <MpSubscribe>[
            active(id: 1, mediaId: '999'),
            active(id: 8, mediaId: '693134'),
          ],
        ),
      );

      expect(matcher.subscription(request(subscribeId: null))!.id, 8);
    });

    test('distinguishes seasons of the same show', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          subscribes: <MpSubscribe>[
            active(id: 1, type: MpMediaType.series, season: 1, mediaId: '1399'),
            active(id: 2, type: MpMediaType.series, season: 2, mediaId: '1399'),
          ],
        ),
      );

      expect(
        matcher
            .subscription(
              request(
                subscribeId: null,
                type: MpMediaType.series,
                season: 2,
                mediaId: '1399',
              ),
            )!
            .id,
        2,
      );
    });

    test('never matches a different year on the title fallback', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          subscribes: <MpSubscribe>[
            active(id: 1, mediaId: '111', title: 'Dune', year: '1984'),
          ],
        ),
      );

      final unidentified = MediaRequest(
        id: 'r',
        ref: const MpMediaRef(source: MpMediaSource.unknown, mediaId: ''),
        type: MpMediaType.movie,
        title: 'Dune',
        year: '2021',
        subscribeId: null,
        createdAt: DateTime.utc(2026),
      );

      expect(matcher.subscription(unidentified), isNull);
    });

    test('matches an unidentified request on the normalized title', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          subscribes: <MpSubscribe>[
            active(id: 3, mediaId: '111', title: 'The Dune: Part Two!'),
          ],
        ),
      );

      final unidentified = MediaRequest(
        id: 'r',
        ref: const MpMediaRef(source: MpMediaSource.unknown, mediaId: ''),
        type: MpMediaType.movie,
        title: 'dune part two',
        year: '',
        subscribeId: null,
        createdAt: DateTime.utc(2026),
      );

      expect(matcher.subscription(unidentified)!.id, 3);
    });

    test('a movie never matches a series subscription', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          subscribes: <MpSubscribe>[
            active(id: 1, mediaId: '693134', type: MpMediaType.series),
          ],
        ),
      );

      expect(matcher.subscription(request(subscribeId: null)), isNull);
    });

    test('an empty snapshot matches nothing', () {
      expect(
        const RequestMatcher(PollSnapshot.empty).subscription(request()),
        isNull,
      );
    });
  });

  group('RequestMatcher.downloads', () {
    test('matches a task by media identity and season', () {
      final matcher = RequestMatcher(
        PollSnapshot(downloads: <MpDownloaderTorrent>[torrent()]),
      );

      expect(matcher.downloads(request()), hasLength(1));
    });

    test('a series aggregates only its own season', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          downloads: <MpDownloaderTorrent>[
            torrent(
              hash: 's1',
              type: MpMediaType.series,
              mediaId: '1399',
              mediaSeason: 1,
              seasonEpisode: 'S01E01',
            ),
            torrent(
              hash: 's2',
              type: MpMediaType.series,
              mediaId: '1399',
              mediaSeason: 2,
              seasonEpisode: 'S02E01',
            ),
          ],
        ),
      );

      final seasonTwo = matcher.downloads(
        request(type: MpMediaType.series, season: 2, mediaId: '1399'),
      );

      expect(seasonTwo.map((t) => t.hash), <String>['s2']);
    });

    test(
      'a task without media matches a series only when the season agrees',
      () {
        final matcher = RequestMatcher(
          PollSnapshot(
            downloads: <MpDownloaderTorrent>[
              torrent(
                withMedia: false,
                seasonEpisode: 'S02E03',
                title: 'Some.Show',
              ),
            ],
          ),
        );

        expect(
          matcher.downloads(
            request(
              type: MpMediaType.series,
              season: 2,
              title: 'Some Show',
              year: '',
            ),
          ),
          hasLength(1),
        );
        expect(
          matcher.downloads(
            request(
              type: MpMediaType.series,
              season: 1,
              title: 'Some Show',
              year: '',
            ),
          ),
          isEmpty,
        );
      },
    );

    test('a task with another identity never matches, even by title', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          downloads: <MpDownloaderTorrent>[
            torrent(mediaId: '999', title: '沙丘2'),
          ],
        ),
      );

      expect(matcher.downloads(request()), isEmpty);
    });
  });

  group('RequestMatcher.transfers and jobs', () {
    test('a job matches on download_hash when media is missing', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          subscribes: <MpSubscribe>[active()],
          downloads: <MpDownloaderTorrent>[torrent(hash: 'h1')],
          transferQueue: <MpTransferJob>[
            job(withMedia: false, hashes: <String>['h1']),
          ],
        ),
      );

      expect(matcher.transferJobs(request()), hasLength(1));
    });

    test('a job for another title does not match', () {
      final matcher = RequestMatcher(
        PollSnapshot(transferQueue: <MpTransferJob>[job(mediaId: '999')]),
      );

      expect(matcher.transferJobs(request()), isEmpty);
    });

    test('only successful transfers count', () {
      final failed = RequestMatcher(
        PollSnapshot(
          transferHistory: <MpTransferHistory>[transfer(status: false)],
        ),
      );
      final succeeded = RequestMatcher(
        PollSnapshot(transferHistory: <MpTransferHistory>[transfer()]),
      );

      expect(failed.transfers(request()), isEmpty);
      expect(succeeded.transfers(request()), hasLength(1));
    });

    test('a transfer for another season does not match', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          transferHistory: <MpTransferHistory>[
            transfer(mediaId: '1399', seasons: 'S01'),
          ],
        ),
      );

      expect(
        matcher.transfers(
          request(type: MpMediaType.series, season: 2, mediaId: '1399'),
        ),
        isEmpty,
      );
    });
  });

  group('RequestMatcher.archived', () {
    test('reads only the request media type history', () {
      final matcher = RequestMatcher(
        PollSnapshot(
          movieHistory: <MpSubscribe>[active(id: 1)],
          seriesHistory: <MpSubscribe>[active(id: 2, type: MpMediaType.series)],
        ),
      );

      expect(matcher.archived(request())!.id, 1);
    });
  });
}
