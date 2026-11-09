import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/moviepilot_exception.dart';
import 'package:media_player/data/moviepilot/api/moviepilot_http_client.dart';
import 'package:media_player/data/moviepilot/models/moviepilot_config.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';
import 'package:media_player/data/moviepilot/moviepilot_repository.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/moviepilot_config_store.dart';

import '../../support/fake_moviepilot_server.dart';

void main() {
  late FakeMoviePilotServer server;
  late InMemoryKeyValueStore kv;
  late MoviePilotRepository repository;

  setUp(() async {
    server = FakeMoviePilotServer();
    await server.start();
    kv = InMemoryKeyValueStore();
    repository = MoviePilotRepository(
      MoviePilotConfigStore(kv),
      MoviePilotHttpClient(Dio()),
    );
  });

  tearDown(() async {
    await server.stop();
  });

  Future<void> configure() => MoviePilotConfigStore(
    kv,
  ).write(MoviePilotConfig(baseUrl: server.base, apiToken: server.apiKey));

  group('not configured', () {
    test('every call reports notConfigured before anything is saved', () async {
      await expectLater(
        repository.search('dune'),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.notConfigured,
          ),
        ),
      );
      await expectLater(
        repository.poll(),
        throwsA(isA<MoviePilotException>()),
      );
    });

    test('testConnection still uses the passed config', () async {
      final config = MoviePilotConfig(
        baseUrl: server.base,
        apiToken: server.apiKey,
      );

      await repository.testConnection(config);

      expect(server.lastApiKey, server.apiKey);
    });
  });

  group('search', () {
    test('asks for TMDB media and parses the hits', () async {
      await configure();
      server.searchResults = <Map<String, dynamic>>[
        <String, dynamic>{
          'media_source': 'themoviedb',
          'media_id': '693134',
          'type': '电影',
          'title': '沙丘2',
          'year': '2024',
        },
        <String, dynamic>{'type': '音乐', 'title': 'An album'},
      ];

      final results = await repository.search('沙丘');

      final query = server.lastQuery['/api/v1/media/search']!;
      expect(query['title'], '沙丘');
      expect(query['type'], 'media');
      expect(query['media_source'], 'themoviedb');
      expect(results, hasLength(1));
      expect(results.single.title, '沙丘2');
    });

    test('a bare-list reply parses the same way', () async {
      await configure();
      server.envelope = false;
      server.searchResults = <Map<String, dynamic>>[
        <String, dynamic>{
          'media_source': 'themoviedb',
          'media_id': '1',
          'type': '电视剧',
          'title': 'Show',
        },
      ];

      expect(await repository.search('show'), hasLength(1));
    });

    test('success:false becomes a server error carrying the message', () async {
      await configure();
      server.statusOverrides['/api/v1/media/search'] = 400;

      await expectLater(
        repository.search('x'),
        throwsA(
          isA<MoviePilotException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.serverError,
          ),
        ),
      );
    });
  });

  group('seasons', () {
    test('sends the media identity, not a title', () async {
      await configure();
      server.seasons = <Map<String, dynamic>>[
        <String, dynamic>{'season_number': 1, 'episode_count': 10},
        <String, dynamic>{'season_number': 2, 'episode_count': 8},
      ];
      final media = MpMediaInfo.fromJson(<String, dynamic>{
        'media_source': 'themoviedb',
        'media_id': '1399',
        'type': '电视剧',
        'title': 'Show',
        'year': '2023',
      })!;

      final seasons = await repository.seasons(media);

      final query = server.lastQuery['/api/v1/media/seasons']!;
      expect(query['media_source'], 'themoviedb');
      expect(query['media_id'], '1399');
      expect(query['title'], 'Show');
      expect(seasons, hasLength(2));
      expect(seasons.last.label, '第 2 季（8 集）');
    });
  });

  group('existingItemId', () {
    test('sends mtype (not type) and reads the item id', () async {
      await configure();
      server.existingItem = <String, dynamic>{'id': 'emby-42'};

      final id = await repository.existingItemId(
        ref: const MpMediaRef(
          source: MpMediaSource.tmdb,
          mediaId: '693134',
        ),
        type: MpMediaType.movie,
      );

      final query = server.lastQuery['/api/v1/mediaserver/exists']!;
      expect(query['mtype'], '电影');
      expect(query.containsKey('type'), isFalse);
      expect(query['media_source'], 'themoviedb');
      expect(query['media_id'], '693134');
      expect(query.containsKey('season'), isFalse);
      expect(id, 'emby-42');
    });

    test('passes the season for a series and reports absence as null', () async {
      await configure();

      final id = await repository.existingItemId(
        ref: const MpMediaRef(
          source: MpMediaSource.tmdb,
          mediaId: '1399',
        ),
        type: MpMediaType.series,
        season: 2,
      );

      expect(
        server.lastQuery['/api/v1/mediaserver/exists']!['season'],
        '2',
      );
      expect(id, isNull);
    });
  });

  group('subscriptions', () {
    test('creates with the draft body and returns the id', () async {
      await configure();
      const draft = MpSubscribeDraft(
        ref: MpMediaRef(
          source: MpMediaSource.tmdb,
          mediaId: '693134',
          tmdbId: 693134,
        ),
        type: MpMediaType.movie,
        name: '沙丘2',
        year: '2024',
      );

      final id = await repository.createSubscription(draft);

      expect(id, 100);
      final body = server.lastBody['/api/v1/subscribe/']!;
      expect(body['media_source'], 'themoviedb');
      expect(body['media_id'], '693134');
      expect(body['type'], '电影');
      expect(body['name'], '沙丘2');
    });

    test('a create without an id is a server error', () async {
      await configure();
      server.omitCreatedId = true;
      const draft = MpSubscribeDraft(
        ref: MpMediaRef(source: MpMediaSource.tmdb, mediaId: '1'),
        type: MpMediaType.movie,
        name: 'X',
      );

      await expectLater(
        repository.createSubscription(draft),
        throwsA(
          isA<MoviePilotException>()
              .having((e) => e.code, 'code', AppErrorCode.serverError)
              .having((e) => e.message, 'message', 'subscribe id missing'),
        ),
      );
    });

    test('searchNow posts to the v3 path', () async {
      await configure();

      await repository.searchNow(7);

      expect(server.requestLog, contains('POST /api/v1/subscribe/search/7'));
    });

    test('cancel deletes, and a 404 (already archived) is a no-op', () async {
      await configure();

      await repository.cancelSubscription(7);
      expect(server.requestLog, contains('DELETE /api/v1/subscribe/7'));

      server.statusOverrides['/api/v1/subscribe/8'] = 404;
      await repository.cancelSubscription(8);
    });

    test('cancel still surfaces other failures', () async {
      await configure();
      server.failingPaths.add('/api/v1/subscribe/9');

      await expectLater(
        repository.cancelSubscription(9),
        throwsA(isA<MoviePilotException>()),
      );
    });
  });

  group('poll', () {
    test('an idle round only reads the subscription list', () async {
      await configure();

      final snapshot = await repository.poll(needsTasks: false);

      expect(
        server.requestLog.where((line) => line.startsWith('GET ')),
        <String>['GET /api/v1/subscribe/'],
      );
      expect(snapshot.tasksLoaded, isFalse);
      expect(snapshot.fetchedAt, isNotNull);
    });

    test('reads history only for the media types it was asked for', () async {
      await configure();

      final snapshot = await repository.poll(
        needsTasks: false,
        historyTypes: const <MpMediaType>{MpMediaType.movie},
      );

      // The mtype segment is percent-encoded on the wire.
      final movieHistory = Uri.encodeComponent('电影');
      final seriesHistory = Uri.encodeComponent('电视剧');
      expect(
        server.requestLog,
        contains('GET /api/v1/subscribe/history/$movieHistory'),
      );
      expect(
        server.requestLog,
        isNot(contains('GET /api/v1/subscribe/history/$seriesHistory')),
      );
      expect(snapshot.movieHistory, isEmpty);
    });

    test('loads the task half and parses every endpoint', () async {
      await configure();
      server.subscribes = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'type': '电影',
          'media_source': 'themoviedb',
          'media_id': '1',
          'execution_status': <String, dynamic>{'state': 'R'},
        },
      ];
      server.downloads = <Map<String, dynamic>>[
        <String, dynamic>{'hash': 'h', 'progress': 50},
      ];
      server.transferQueue = <Map<String, dynamic>>[
        <String, dynamic>{
          'season': 1,
          'tasks': <Object?>[
            <String, dynamic>{'download_hash': 'h'},
          ],
        },
      ];
      server.transferHistory = <Map<String, dynamic>>[
        <String, dynamic>{'id': 3, 'status': true, 'seasons': 'S01'},
      ];

      final snapshot = await repository.poll(
        needsTasks: true,
        historyTypes: const <MpMediaType>{MpMediaType.series},
      );

      expect(snapshot.tasksLoaded, isTrue);
      expect(snapshot.subscribes, hasLength(1));
      expect(snapshot.downloads.single.progress, 0.5);
      expect(snapshot.transferQueue.single.hashes, <String>{'h'});
      expect(snapshot.transferHistory.single.succeeded, isTrue);
      expect(server.requestsTo('/api/v1/download/'), 1);
    });

    test('a broken task endpoint fails the round rather than half-filling it',
        () async {
      await configure();
      server.failingPaths.add('/api/v1/transfer/queue');

      await expectLater(
        repository.poll(),
        throwsA(isA<MoviePilotException>()),
      );
    });
  });
}
