import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_season.dart';
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';

void main() {
  group('MpMediaInfo', () {
    test('parses a v3 search hit', () {
      final info = MpMediaInfo.fromJson(<String, dynamic>{
        'media_source': 'themoviedb',
        'media_id': '693134',
        'tmdb_id': 693134,
        'type': '电影',
        'title': '沙丘2',
        'year': '2024',
        'poster_path': '/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg',
        'vote_average': 8.2,
        'overview': '保罗·厄崔迪与弗雷曼人…',
      });

      expect(info, isNotNull);
      expect(info!.title, '沙丘2');
      expect(info.year, '2024');
      expect(info.ref.source, MpMediaSource.tmdb);
      expect(info.ref.mediaId, '693134');
      expect(info.ref.tmdbId, 693134);
      expect(info.ref.identityKey, 'themoviedb:693134');
      expect(info.type, MpMediaType.movie);
      expect(info.isMovie, isTrue);
      expect(info.vote, 8.2);
      expect(info.posterUri.toString(),
          'https://image.tmdb.org/t/p/w342/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg');
    });

    test('keeps an absolute poster URL as given', () {
      final info = MpMediaInfo.fromJson(<String, dynamic>{
        'media_source': 'themoviedb',
        'media_id': '1',
        'type': '电影',
        'title': 'T',
        'poster': 'https://cdn.example.com/p.jpg',
      });

      expect(info!.posterUri.toString(), 'https://cdn.example.com/p.jpg');
    });

    test('coerces numeric strings and a missing tmdb id', () {
      final info = MpMediaInfo.fromJson(<String, dynamic>{
        'media_source': 'themoviedb',
        'media_id': 550,
        'type': '电视剧',
        'title': 'Show',
        'vote_average': '7.5',
        'number_of_seasons': '3',
        'number_of_episodes': '24',
        'season': '2',
      });

      expect(info!.ref.mediaId, '550');
      expect(info.ref.tmdbId, isNull);
      expect(info.vote, 7.5);
      expect(info.numberOfSeasons, 3);
      expect(info.numberOfEpisodes, 24);
      expect(info.season, 2);
      expect(info.isSeries, isTrue);
    });

    test('drops music, collections and unidentified entries', () {
      expect(
        MpMediaInfo.fromJson(<String, dynamic>{'type': '音乐', 'title': 'Album'}),
        isNull,
      );
      expect(
        MpMediaInfo.fromJson(<String, dynamic>{'type': '电影'}),
        isNull,
      );
    });

    test('accepts an entry that only has a title', () {
      final info = MpMediaInfo.fromJson(<String, dynamic>{
        'type': '电影',
        'title': 'Only a title',
        'media_source': '',
      });

      expect(info, isNotNull);
      expect(info!.ref.isIdentified, isFalse);
      expect(info.ref.identityKey, isNull);
    });
  });

  group('MpSeason', () {
    test('parses season_number and the episode count', () {
      final season = MpSeason.fromJson(<String, dynamic>{
        'season_number': 2,
        'name': '第 2 季',
        'episode_count': 8,
        'air_date': '2024-03-01',
      });

      expect(season!.seasonNumber, 2);
      expect(season.label, '第 2 季（8 集）');
    });

    test('counts episodes when only the list is present', () {
      final season = MpSeason.fromJson(<String, dynamic>{
        'season_number': 1,
        'episodes': <Object?>[
          <String, dynamic>{'episode_number': 1},
          <String, dynamic>{'episode_number': 2},
        ],
      });

      expect(season!.episodeCount, 2);
    });

    test('drops a season without a number', () {
      expect(MpSeason.fromJson(<String, dynamic>{'name': 'Specials'}), isNull);
    });
  });

  group('MpExecutionStatus', () {
    test('reads the v3 fields', () {
      final status = MpExecutionStatus.fromJson(<String, dynamic>{
        'state': 'R',
        'phase': 'searching',
        'error': '',
        'submitted_count': 2,
        'can_cancel': true,
        'next_run_at': '2026-01-01T00:00:00',
      });

      expect(status.isRunning, isTrue);
      expect(status.isSearching, isFalse);
      expect(status.submittedCount, 2);
      expect(status.canCancel, isTrue);
      expect(status.hasError, isFalse);
    });

    test('an empty or missing status is inert', () {
      final status = MpExecutionStatus.fromJson(const <String, dynamic>{});

      expect(status.isRunning, isFalse);
      expect(status.isSearching, isTrue);
      expect(status.submittedCount, 0);
    });

    test('coerces string flags', () {
      final status = MpExecutionStatus.fromJson(<String, dynamic>{
        'submitted_count': '3',
        'can_cancel': 'true',
      });

      expect(status.submittedCount, 3);
      expect(status.canCancel, isTrue);
    });
  });

  group('MpSubscribe', () {
    test('parses an active series subscription with execution status', () {
      final subscribe = MpSubscribe.fromJson(<String, dynamic>{
        'id': 12,
        'name': 'Show',
        'year': '2023',
        'type': '电视剧',
        'season': 2,
        'media_source': 'themoviedb',
        'media_id': '1399',
        'total_episode': 10,
        'lack_episode': 4,
        'completed_episode': 6,
        'state': 'R',
        'execution_status': <String, dynamic>{
          'state': 'R',
          'phase': 'searching',
          'submitted_count': 0,
        },
      });

      expect(subscribe, isNotNull);
      expect(subscribe!.id, 12);
      expect(subscribe.isSeries, isTrue);
      expect(subscribe.season, 2);
      expect(subscribe.effectiveCompletedEpisode, 6);
      expect(subscribe.matchKey, 'themoviedb:1399#s2');
      expect(subscribe.executionStatus.isSearching, isTrue);
    });

    test('falls back to total - lack when completed_episode is absent', () {
      final subscribe = MpSubscribe.fromJson(<String, dynamic>{
        'id': 1,
        'type': '电视剧',
        'media_source': 'themoviedb',
        'media_id': '2',
        'total_episode': 12,
        'lack_episode': 5,
      });

      expect(subscribe!.effectiveCompletedEpisode, 7);
    });

    test('a movie subscription has no episode counters', () {
      final subscribe = MpSubscribe.fromJson(<String, dynamic>{
        'id': 2,
        'type': '电影',
        'media_source': 'themoviedb',
        'media_id': '3',
      });

      expect(subscribe!.isSeries, isFalse);
      expect(subscribe.effectiveCompletedEpisode, 0);
      expect(subscribe.matchKey, 'themoviedb:3#s0');
    });

    test('drops a record without an id', () {
      expect(MpSubscribe.fromJson(<String, dynamic>{'name': 'x'}), isNull);
    });

    test('round-trips through toJson', () {
      final subscribe = MpSubscribe.fromJson(<String, dynamic>{
        'id': 9,
        'type': '电视剧',
        'season': 1,
        'media_source': 'themoviedb',
        'media_id': '42',
        'state': 'S',
        'total_episode': 8,
        'lack_episode': 8,
        'execution_status': <String, dynamic>{'state': 'S'},
      })!;

      final again = MpSubscribe.fromJson(subscribe.toJson())!;
      expect(again.id, 9);
      expect(again.season, 1);
      expect(again.isPaused, isTrue);
      expect(again.executionStatus.isPaused, isTrue);
      expect(again.matchKey, 'themoviedb:42#s1');
    });
  });

  group('MpSubscribeDraft', () {
    test('a movie draft leaves the season out', () {
      final media = MpMediaInfo.fromJson(<String, dynamic>{
        'media_source': 'themoviedb',
        'media_id': '693134',
        'type': '电影',
        'title': '沙丘2',
        'year': '2024',
      });

      final json = MpSubscribeDraft.fromMedia(media!).toJson();
      expect(json, <String, dynamic>{
        'name': '沙丘2',
        'year': '2024',
        'type': '电影',
        'media_source': 'themoviedb',
        'media_id': '693134',
      });
    });

    test('a series draft carries the season', () {
      final media = MpMediaInfo.fromJson(<String, dynamic>{
        'media_source': 'themoviedb',
        'media_id': '1399',
        'type': '电视剧',
        'title': 'Show',
      });

      final json = MpSubscribeDraft.fromMedia(media!, season: 2).toJson();
      expect(json['season'], 2);
      expect(json['type'], '电视剧');
    });
  });
}
