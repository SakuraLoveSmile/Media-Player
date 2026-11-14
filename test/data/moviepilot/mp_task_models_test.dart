import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/moviepilot/models/mp_downloader_torrent.dart';
import 'package:media_player/data/moviepilot/models/mp_transfer_history.dart';
import 'package:media_player/data/moviepilot/models/mp_transfer_job.dart';

void main() {
  group('MpDownloaderTorrent', () {
    test('parses a v3 download task', () {
      final torrent = MpDownloaderTorrent.fromJson(<String, dynamic>{
        'hash': 'abc123',
        'name': 'Dune.Part.Two.2024.1080p',
        'title': '沙丘2',
        'year': '2024',
        'season_episode': 'S01E02',
        'state': 'downloading',
        'progress': 42.5,
        'size': 8000000000.0,
        'dlspeed': '5.2 MB/s',
        'left_time': '12m',
        'media': <String, dynamic>{
          'media_source': 'themoviedb',
          'media_id': '693134',
          'type': '电影',
          'season': 'S01',
        },
      });

      expect(torrent, isNotNull);
      expect(torrent!.hash, 'abc123');
      expect(torrent.progress, closeTo(0.425, 1e-9));
      expect(torrent.percent, 43);
      expect(torrent.season, 1);
      expect(torrent.episodes, <int>[2]);
      expect(torrent.downloadSpeed, '5.2 MB/s');
      expect(torrent.leftTime, '12m');
      expect(torrent.media!.ref.identityKey, 'themoviedb:693134');
      expect(torrent.media!.season, 1);
      expect(torrent.isDownloading, isTrue);
      expect(torrent.isComplete, isFalse);
    });

    test('reads a 0-1 progress unchanged', () {
      final torrent = MpDownloaderTorrent.fromJson(<String, dynamic>{
        'hash': 'h',
        'progress': 0.125,
      });

      expect(torrent!.progress, closeTo(0.125, 1e-9));
      expect(torrent.percent, 13);
    });

    test('treats exactly 1 as complete under both conventions', () {
      expect(
        MpDownloaderTorrent.fromJson(<String, dynamic>{
          'hash': 'h',
          'progress': 1,
        })!.isComplete,
        isTrue,
      );
      expect(
        MpDownloaderTorrent.fromJson(<String, dynamic>{
          'hash': 'h',
          'progress': 100,
        })!.isComplete,
        isTrue,
      );
    });

    test('clamps a nonsense progress instead of throwing', () {
      expect(
        MpDownloaderTorrent.fromJson(<String, dynamic>{
          'hash': 'h',
          'progress': -5,
        })!.progress,
        0,
      );
      expect(
        MpDownloaderTorrent.fromJson(<String, dynamic>{
          'hash': 'h',
          'progress': '150',
        })!.progress,
        1,
      );
      expect(
        MpDownloaderTorrent.fromJson(<String, dynamic>{
          'hash': 'h',
          'progress': 'not a number',
        })!.progress,
        0,
      );
    });

    test('survives a missing media dict', () {
      final torrent = MpDownloaderTorrent.fromJson(<String, dynamic>{
        'hash': 'h',
        'name': 'Some.Release.2024',
      });

      expect(torrent!.media, isNull);
      expect(torrent.progress, 0);
      expect(torrent.season, 0);
      expect(torrent.episodes, isEmpty);
    });

    test('parses a multi-episode range', () {
      final torrent = MpDownloaderTorrent.fromJson(<String, dynamic>{
        'hash': 'h',
        'season_episode': 'S02E01-E03',
      });

      expect(torrent!.season, 2);
      expect(torrent.episodes, <int>[1, 3]);
    });

    test('falls back to the media season when the text has none', () {
      final torrent = MpDownloaderTorrent.fromJson(<String, dynamic>{
        'hash': 'h',
        'media': <String, dynamic>{'season': 4},
      });

      expect(torrent!.season, 4);
    });

    test('drops a task with neither hash nor name', () {
      expect(MpDownloaderTorrent.fromJson(const <String, dynamic>{}), isNull);
    });
  });

  group('MpTransferJob', () {
    test('collects hashes and the season', () {
      final job = MpTransferJob.fromJson(<String, dynamic>{
        'season': 2,
        'media': <String, dynamic>{
          'media_source': 'themoviedb',
          'media_id': '1399',
          'type': '电视剧',
        },
        'tasks': <Object?>[
          <String, dynamic>{'state': 'running', 'download_hash': 'h1'},
          <String, dynamic>{'state': 'running', 'download_hash': 'h2'},
        ],
      });

      expect(job.season, 2);
      expect(job.effectiveSeason, 2);
      expect(job.hashes, <String>{'h1', 'h2'});
      expect(job.media!.ref.identityKey, 'themoviedb:1399');
      expect(job.failed, isFalse);
    });

    test('takes the season from the media summary when absent', () {
      final job = MpTransferJob.fromJson(<String, dynamic>{
        'media': <String, dynamic>{'season': 3},
        'tasks': <Object?>[],
      });

      expect(job.effectiveSeason, 3);
    });

    test('reports a failed task', () {
      final job = MpTransferJob.fromJson(<String, dynamic>{
        'tasks': <Object?>[
          <String, dynamic>{'state': 'failed'},
        ],
      });

      expect(job.failed, isTrue);
    });

    test('an empty job degrades quietly', () {
      final job = MpTransferJob.fromJson(const <String, dynamic>{});

      expect(job.effectiveSeason, 0);
      expect(job.hashes, isEmpty);
      expect(job.media, isNull);
    });
  });

  group('MpTransferHistory', () {
    test('parses a successful transfer row', () {
      final history = MpTransferHistory.fromJson(<String, dynamic>{
        'id': 5,
        'title': 'Show',
        'year': '2023',
        'type': '电视剧',
        'media_source': 'themoviedb',
        'media_id': '1399',
        'seasons': 'S02',
        'episodes': 'E01-E10',
        'download_hash': 'h1',
        'status': true,
        'date': '2026-01-01',
      });

      expect(history, isNotNull);
      expect(history!.succeeded, isTrue);
      expect(history.season, 2);
      expect(history.ref.identityKey, 'themoviedb:1399');
      expect(history.downloadHash, 'h1');
    });

    test('a failure row is not a success signal', () {
      final history = MpTransferHistory.fromJson(<String, dynamic>{
        'id': 6,
        'status': false,
      });

      expect(history!.succeeded, isFalse);
    });

    test('coerces the string status older payloads use', () {
      expect(
        MpTransferHistory.fromJson(<String, dynamic>{'id': 7, 'status': 1})!
            .succeeded,
        isTrue,
      );
      expect(
        MpTransferHistory.fromJson(<String, dynamic>{
          'id': 8,
          'status': 'true',
        })!.succeeded,
        isTrue,
      );
      expect(
        MpTransferHistory.fromJson(<String, dynamic>{'id': 9, 'status': '0'})!
            .succeeded,
        isFalse,
      );
    });

    test('drops a row without an id', () {
      expect(MpTransferHistory.fromJson(const <String, dynamic>{}), isNull);
    });
  });

  group('normalizeProgress', () {
    test('passes a fraction through', () {
      expect(normalizeProgress(0.5), 0.5);
      expect(normalizeProgress(0), 0);
    });

    test('divides a percentage', () {
      expect(normalizeProgress(50), 0.5);
      expect(normalizeProgress(100), 1);
    });

    test('null, NaN and infinity become zero', () {
      expect(normalizeProgress(null), 0);
      expect(normalizeProgress(double.nan), 0);
      expect(normalizeProgress(double.infinity), 0);
    });
  });
}
