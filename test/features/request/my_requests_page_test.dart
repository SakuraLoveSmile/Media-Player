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
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';
import 'package:media_player/data/moviepilot/moviepilot_service.dart';
import 'package:media_player/data/moviepilot/progress/poll_snapshot.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/moviepilot_config_store.dart';
import 'package:media_player/data/storage/request_store.dart';
import 'package:media_player/features/request/my_requests_page.dart';

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
  GoRouter? router;

  setUp(() {
    store = InMemoryKeyValueStore();
    service = FakeMoviePilotService();
    library = FakeLibraryService();
    router = null;
  });

  Future<void> settle(WidgetTester tester) async {
    // The controller loads the stored records and runs one round; a bounded
    // pump avoids waiting on a never-settling indeterminate bar.
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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

  Future<void> pumpPage(
    WidgetTester tester, {
    List<MediaRequest> requests = const <MediaRequest>[],
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await MoviePilotConfigStore(store).write(
      const MoviePilotConfig(baseUrl: 'http://nas:3002', apiToken: 'token'),
    );
    await RequestStore(store).write(requests);

    router = GoRouter(
      initialLocation: '/request/mine',
      routes: <RouteBase>[
        GoRoute(
          path: '/request/mine',
          builder: (_, _) => const MyRequestsPage(),
        ),
        GoRoute(
          path: '/request',
          builder: (_, _) => const Text('search page'),
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
    addTearDown(router!.dispose);

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
          requestHeartbeatProvider.overrideWithValue(_silentHeartbeat),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
  }

  testWidgets('an empty list explains how to start', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('my-requests-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-requests-to-search')));
    await settle(tester);

    expect(router!.state.matchedLocation, '/request');
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
    await pumpPage(
      tester,
      requests: <MediaRequest>[
        seeded(type: MpMediaType.series, season: 2, total: 10),
      ],
    );

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
    await pumpPage(tester, requests: <MediaRequest>[seeded()]);

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
    await pumpPage(tester, requests: <MediaRequest>[seeded()]);

    expect(find.text('暂无资源'), findsOneWidget);
    await tester.tap(find.byKey(const Key('request-search-now-req-1')));
    await settle(tester);

    expect(service.searchNowRequests, contains(100));
  });

  testWidgets('a paused subscription says so', (tester) async {
    service.snapshot = PollSnapshot(
      subscribes: <MpSubscribe>[fakeSubscribe(state: 'S')],
    );
    await pumpPage(tester, requests: <MediaRequest>[seeded()]);

    expect(find.text('已暂停'), findsOneWidget);
  });

  testWidgets('cancelling removes the card and the subscription', (
    tester,
  ) async {
    service.snapshot = PollSnapshot(
      subscribes: <MpSubscribe>[fakeSubscribe()],
    );
    await pumpPage(tester, requests: <MediaRequest>[seeded()]);

    await tester.tap(find.byKey(const Key('request-cancel-req-1')));
    await settle(tester);

    expect(service.cancelRequests, <int>[100]);
    expect(find.byKey(const Key('request-cancel-req-1')), findsNothing);
    expect(find.byKey(const Key('my-requests-empty')), findsOneWidget);
  });

  testWidgets('a movie in the library opens the player', (tester) async {
    await pumpPage(
      tester,
      requests: <MediaRequest>[
        seeded(stage: RequestStage.inLibrary, embyItemId: 'emby-9'),
      ],
    );

    expect(find.text('已入库'), findsOneWidget);
    await tester.tap(find.byKey(const Key('request-play-req-1')));
    await settle(tester);

    expect(router!.state.matchedLocation, '/player/emby-9');
  });

  testWidgets('a series in the library opens the episode picker', (
    tester,
  ) async {
    await pumpPage(
      tester,
      requests: <MediaRequest>[
        seeded(
          type: MpMediaType.series,
          season: 1,
          stage: RequestStage.inLibrary,
          embyItemId: 'emby-series',
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('request-play-req-1')));
    await settle(tester);

    // The episode picker, not the player: a series id has no playable source.
    expect(router!.state.matchedLocation, '/series/emby-series');
  });

  testWidgets('a poll failure keeps the cards and shows the reason', (
    tester,
  ) async {
    service.pollFailure = mpFailure(AppErrorCode.networkUnreachable);
    await pumpPage(tester, requests: <MediaRequest>[seeded()]);

    expect(find.byKey(const Key('my-requests-error')), findsOneWidget);
    expect(find.textContaining('无法连接'), findsOneWidget);
    // Losing the network must never empty the list.
    expect(find.byKey(const Key('request-cancel-req-1')), findsOneWidget);
  });
}
