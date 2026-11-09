import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/app/moviepilot_providers.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/moviepilot/models/media_request.dart';
import 'package:media_player/data/moviepilot/models/moviepilot_config.dart';
import 'package:media_player/data/moviepilot/models/mp_downloader_torrent.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_season.dart';
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';
import 'package:media_player/data/moviepilot/moviepilot_service.dart';
import 'package:media_player/data/moviepilot/progress/poll_snapshot.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/moviepilot_config_store.dart';
import 'package:media_player/data/storage/request_store.dart';
import 'package:media_player/features/request/request_page.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_moviepilot_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';

class _NoAuth implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A heartbeat that never ticks, so a widget test fully controls the rounds.
final Stream<void> _silentHeartbeat = const Stream<void>.empty();

void main() {
  late InMemoryKeyValueStore store;
  late FakeMoviePilotService service;
  late FakeLibraryService library;

  setUp(() {
    store = InMemoryKeyValueStore();
    service = FakeMoviePilotService();
    library = FakeLibraryService();
  });

  /// Pumps a bounded number of frames instead of settling: an indeterminate
  /// progress bar never stops animating, so `pumpAndSettle` cannot be used on a
  /// page that shows one.
  Future<void> settle(WidgetTester tester) async {
    // The subscribe path awaits /mediaserver/exists, the create call, a short
    // delay and then a poll round, so a couple of frames is not enough. Fake
    // time makes these pumps cheap, and bounded pumping avoids the
    // never-settling indeterminate bar.
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    bool configured = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    if (configured) {
      await MoviePilotConfigStore(store).write(
        const MoviePilotConfig(baseUrl: 'http://nas:3002', apiToken: 'token'),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: _NoAuth(),
              library: library,
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
              store: store,
              moviePilotConfigStore: MoviePilotConfigStore(store),
            ),
          ),
          moviePilotServiceProvider.overrideWith(
            (ref) async => service as MoviePilotService,
          ),
          requestLibraryProvider.overrideWith((ref) async => library),
        ],
        // An empty heartbeat keeps rounds from firing while the test drives
        // the page; the controller still runs its first round from load().
        child: MaterialApp(home: RequestPage(heartbeat: _silentHeartbeat)),
      ),
    );
    await settle(tester);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const Key('request-search-field')),
      query,
    );
    await tester.tap(find.byKey(const Key('request-search-button')));
    await settle(tester);
  }

  Future<void> seedRequest(
    MediaRequest request, {
    PollSnapshot? snapshot,
  }) async {
    await RequestStore(store).write(<MediaRequest>[request], snapshot: snapshot);
  }

  /// Pumps the request page inside a router so navigation can be asserted.
  Future<GoRouter> pumpWithRouter(
    WidgetTester tester,
    MediaRequest request,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedRequest(request);
    await MoviePilotConfigStore(store).write(
      const MoviePilotConfig(baseUrl: 'http://nas:3002', apiToken: 'token'),
    );

    final router = GoRouter(
      initialLocation: '/request',
      routes: <RouteBase>[
        GoRoute(
          path: '/request',
          builder: (_, _) => RequestPage(heartbeat: _silentHeartbeat),
        ),
        GoRoute(
          path: '/player/:itemId',
          builder: (_, GoRouterState state) =>
              Text('player ${state.pathParameters['itemId']}'),
        ),
        GoRoute(
          path: '/series/:seriesId',
          builder: (_, GoRouterState state) =>
              Text('series ${state.pathParameters['seriesId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: _NoAuth(),
              library: library,
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
              store: store,
              moviePilotConfigStore: MoviePilotConfigStore(store),
            ),
          ),
          moviePilotServiceProvider.overrideWith(
            (ref) async => service as MoviePilotService,
          ),
          requestLibraryProvider.overrideWith((ref) async => library),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    return router;
  }

  MediaRequest seeded({
    RequestStage stage = RequestStage.searching,
    String id = 'req-1',
    MpMediaType type = MpMediaType.movie,
    int season = 0,
    int? subscribeId = 100,
    String? embyItemId,
    double? progress,
    int completed = 0,
    int total = 0,
    String speed = '',
    String eta = '',
  }) {
    return MediaRequest(
      id: id,
      ref: const MpMediaRef(source: MpMediaSource.tmdb, mediaId: '693134'),
      type: type,
      title: '沙丘2',
      year: '2024',
      season: season,
      subscribeId: subscribeId,
      createdAt: DateTime.utc(2026, 1, 1),
      stage: stage,
      embyItemId: embyItemId,
      progressPercent: progress,
      completedEpisodes: completed,
      totalEpisodes: total,
      downloadSpeed: speed,
      eta: eta,
    );
  }

  testWidgets('a search renders the results', (tester) async {
    service.searchResults = <String, List<MpMediaInfo>>{
      '沙丘': <MpMediaInfo>[fakeMedia()],
    };
    await pumpPage(tester);

    await search(tester, '沙丘');

    expect(find.text('沙丘2'), findsWidgets);
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.byKey(const Key('search-request-693134')), findsOneWidget);
  });

  testWidgets('without a connection the page points at the settings', (
    tester,
  ) async {
    await pumpPage(tester, configured: false);

    expect(find.text('还没有连接 MoviePilot'), findsOneWidget);
    expect(find.byKey(const Key('request-go-settings')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('request-search-field')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('a search failure is shown as copy', (tester) async {
    service.searchFailure = mpFailure(AppErrorCode.networkUnreachable);
    await pumpPage(tester);

    await search(tester, '沙丘');

    expect(
      find.byKey(const Key('request-search-error')),
      findsOneWidget,
    );
    expect(find.textContaining('无法连接'), findsOneWidget);
  });

  testWidgets('an empty request list shows the empty hint', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('requests-empty')), findsOneWidget);
  });

  testWidgets('a movie is subscribed straight from the result', (tester) async {
    service.searchResults = <String, List<MpMediaInfo>>{
      '沙丘': <MpMediaInfo>[fakeMedia()],
    };
    await pumpPage(tester);
    await search(tester, '沙丘');

    await tester.tap(find.byKey(const Key('search-request-693134')));
    await settle(tester);

    expect(service.createRequests, hasLength(1));
    expect(service.createRequests.single.type, MpMediaType.movie);
    // The record id is generated, so assert on the card affordance rather than
    // on an id this test cannot know.
    expect(find.text('取消求片'), findsOneWidget);
  });

  testWidgets('a series asks for a season first', (tester) async {
    service.searchResults = <String, List<MpMediaInfo>>{
      'show': <MpMediaInfo>[
        fakeMedia(
          mediaId: '1399',
          type: MpMediaType.series,
          title: 'Show',
        ),
      ],
    };
    service.seasonsByMediaId = <String, List<MpSeason>>{
      '1399': <MpSeason>[
        const MpSeason(seasonNumber: 1, episodeCount: 10),
        const MpSeason(seasonNumber: 2, episodeCount: 8),
      ],
    };
    await pumpPage(tester);
    await search(tester, 'show');

    await tester.tap(find.byKey(const Key('search-request-1399')));
    await settle(tester);

    expect(find.text('选择要订阅的季'), findsOneWidget);
    await tester.tap(find.byKey(const Key('season-2')));
    await settle(tester);

    expect(service.createRequests.single.season, 2);
  });

  testWidgets('a title already in the library is offered as playable', (
    tester,
  ) async {
    service.searchResults = <String, List<MpMediaInfo>>{
      '沙丘': <MpMediaInfo>[fakeMedia()],
    };
    service.existingItems = <String, String>{
      'themoviedb:693134#s0': 'emby-42',
    };
    await pumpPage(tester);
    await search(tester, '沙丘');

    await tester.tap(find.byKey(const Key('search-request-693134')));
    await settle(tester);

    expect(service.createRequests, isEmpty);
    expect(find.text('已入库'), findsOneWidget);
    expect(find.text('去播放'), findsOneWidget);
  });

  testWidgets('a download renders percent, speed, ETA and episode progress', (
    tester,
  ) async {
    service.snapshot = PollSnapshot(
      subscribes: <MpSubscribe>[
        fakeSubscribe(
          type: MpMediaType.series,
          season: 2,
          mediaId: '693134',
          title: '沙丘2',
          totalEpisode: 10,
        ),
      ],
      downloads: <MpDownloaderTorrent>[
        MpDownloaderTorrent.fromJson(<String, dynamic>{
          'hash': 'h1',
          'progress': 42,
          'size': 100,
          'dlspeed': '5 MB/s',
          'left_time': '10m',
          'media': <String, dynamic>{
            'media_source': 'themoviedb',
            'media_id': '693134',
            'type': '电视剧',
            'season': 2,
          },
        })!,
        MpDownloaderTorrent.fromJson(<String, dynamic>{
          'hash': 'h2',
          'progress': 42,
          'size': 100,
          'season_episode': 'S02E01',
          'media': <String, dynamic>{
            'media_source': 'themoviedb',
            'media_id': '693134',
            'type': '电视剧',
            'season': 2,
          },
        })!,
      ],
      tasksLoaded: true,
    );
    await seedRequest(
      seeded(
        type: MpMediaType.series,
        season: 2,
        stage: RequestStage.downloading,
        total: 10,
      ),
    );
    await pumpPage(tester);

    expect(find.byKey(const Key('request-bar-req-1')), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('5 MB/s'), findsOneWidget);
    expect(find.text('剩余 10m'), findsOneWidget);
    expect(find.text('已完成 0/10 集'), findsOneWidget);
    expect(find.text('2 个任务并行下载'), findsOneWidget);
  });

  testWidgets('a searching request shows an indeterminate bar', (tester) async {
    service.snapshot = PollSnapshot(
      subscribes: <MpSubscribe>[fakeSubscribe(submittedCount: 0)],
    );
    await seedRequest(seeded());
    await pumpPage(tester);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('request-bar-req-1')),
    );
    expect(bar.value, isNull);
  });

  testWidgets('a request with no resource offers an immediate search', (
    tester,
  ) async {
    service.snapshot = PollSnapshot(
      subscribes: <MpSubscribe>[fakeSubscribe(error: '站点全部失败')],
    );
    await seedRequest(seeded());
    await pumpPage(tester);

    expect(find.text('暂无资源'), findsOneWidget);
    expect(
      find.byKey(const Key('request-search-now-req-1')),
      findsOneWidget,
    );
  });

  testWidgets('a paused subscription says so', (tester) async {
    service.snapshot = PollSnapshot(
      subscribes: <MpSubscribe>[fakeSubscribe(state: 'S')],
    );
    await seedRequest(seeded());
    await pumpPage(tester);

    expect(find.text('已暂停'), findsOneWidget);
  });

  testWidgets('a request in the library offers playback', (tester) async {
    await seedRequest(
      seeded(stage: RequestStage.inLibrary, embyItemId: 'emby-9'),
    );
    await pumpPage(tester);

    expect(find.text('已入库'), findsOneWidget);
    expect(find.byKey(const Key('request-play-req-1')), findsOneWidget);
  });

  testWidgets('a movie in the library opens the player', (tester) async {
    final router = await pumpWithRouter(
      tester,
      seeded(stage: RequestStage.inLibrary, embyItemId: 'emby-9'),
    );

    await tester.tap(find.byKey(const Key('request-play-req-1')));
    await settle(tester);

    expect(router.state.matchedLocation, '/player/emby-9');
  });

  testWidgets('a series in the library opens the episode picker', (
    tester,
  ) async {
    final router = await pumpWithRouter(
      tester,
      seeded(
        type: MpMediaType.series,
        season: 1,
        stage: RequestStage.inLibrary,
        embyItemId: 'emby-series',
      ),
    );

    await tester.tap(find.byKey(const Key('request-play-req-1')));
    await settle(tester);

    // The episode picker, not the player: a series id has no playable source.
    expect(router.state.matchedLocation, '/series/emby-series');
  });

  testWidgets('cancelling removes the card and the subscription', (
    tester,
  ) async {
    service.snapshot = PollSnapshot(
      subscribes: <MpSubscribe>[fakeSubscribe()],
    );
    await seedRequest(seeded());
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('request-cancel-req-1')));
    await settle(tester);

    expect(service.cancelRequests, <int>[100]);
    expect(find.byKey(const Key('request-cancel-req-1')), findsNothing);
    expect(find.byKey(const Key('requests-empty')), findsOneWidget);
  });

  testWidgets('search now posts for the subscription', (tester) async {
    service.snapshot = PollSnapshot(
      subscribes: <MpSubscribe>[fakeSubscribe(error: '还没有资源')],
    );
    await seedRequest(seeded());
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('request-search-now-req-1')));
    await settle(tester);

    expect(service.searchNowRequests, contains(100));
  });
}
