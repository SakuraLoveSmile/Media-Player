import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/router.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/core/router/app_routes.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/library_view.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/app/hidden_libraries.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/ui/app_controls.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';

class _PendingEpisodeStop extends FakePlaybackReporter {
  final completion = Completer<void>();

  @override
  Future<void> stopped(PlaybackPlan plan, Duration position) {
    unawaited(super.stopped(plan, position));
    return completion.future;
  }
}

class StaticAuth implements AuthService {
  @override
  AuthSession? get current => const AuthSession(
    userId: 'u1',
    userName: 'test',
    accessToken: 'token',
    deviceId: 'd1',
  );

  @override
  Stream<AuthSession?> get session => const Stream<AuthSession?>.empty();

  @override
  Future<AuthSession?> restore() async => current;

  @override
  Future<ServerProfile?> lastProfile() async => null;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required ServerProfile profile,
  }) => throw UnimplementedError();

  @override
  Future<ServerProfile> adoptAddress({
    required ServerProfile profile,
    required EndpointKind kind,
    required String rawUrl,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> handleUnauthorized() async {}
}

void main() {
  Future<void> pumpLibrary(
    WidgetTester tester,
    FakeLibraryService library, {
    FakePlaybackService? playback,
    FakePosterCache? posters,
    FakePlaybackEngine Function()? createEngine,
    FakePlaybackReporter Function()? createReporter,
    KeyValueStore? store,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: StaticAuth(),
              library: library,
              posters: posters ?? FakePosterCache(),
              playback: playback ?? FakePlaybackService(),
              createEngine: createEngine ?? FakePlaybackEngine.new,
              createReporter: createReporter ?? FakePlaybackReporter.new,
            ),
          ),
          // S32: the library page filters its view chips through this list.
          hiddenLibrariesStoreProvider.overrideWith(
            (ref) async => store ?? InMemoryKeyValueStore(),
          ),
          hiddenLibrariesControllerProvider.overrideWith(
            () => _TestHiddenLibrariesController(store),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
    // P1: the post-login landing is the home dashboard; open the library
    // explicitly so these tests keep exercising the library page.
    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.library);
    await tester.pumpAndSettle();
  }

  FakeLibraryService buildService({int movies = 70, int shows = 3}) {
    return FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView, fakeShowsView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: List<MediaItem>.generate(
          movies,
          (index) => fakeItem('${index + 1}'),
        ),
        fakeShowsView.id: List<MediaItem>.generate(
          shows,
          (index) => MediaItem(
            id: 's${index + 1}',
            name: 'Show ${index + 1}',
            type: 'Series',
          ),
        ),
      },
    );
  }

  testWidgets('renders the view chips and the first page', (tester) async {
    await pumpLibrary(tester, buildService());

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Movies')),
      findsOneWidget,
    );
    expect(find.widgetWithText(ChoiceChip, 'Movies'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Shows'), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('hidden libraries never become the selected view (S32)', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await store.write(hiddenLibrariesStorageKey, '["view-shows"]');
    // A single visible library drops the chip row, so assert on the app-bar
    // title and the loaded page instead: the first visible view wins and the
    // hidden one is never requested.
    final library = buildService();
    await pumpLibrary(tester, library, store: store);

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Movies')),
      findsOneWidget,
    );
    expect(
      library.itemsRequests.map((request) => request.viewId),
      isNot(contains('view-shows')),
    );
  });

  testWidgets('the upcoming tab lists future premieres only (S45)', (
    tester,
  ) async {
    final library = buildService(movies: 3);
    library.itemsByView[fakeMoviesView.id] = <MediaItem>[
      const MediaItem(
        id: 'past',
        name: '过去',
        type: 'Movie',
        premiereDate: '2020-01-01T00:00:00Z',
      ),
      const MediaItem(
        id: 'future',
        name: '未来',
        type: 'Movie',
        premiereDate: '2999-01-01T00:00:00Z',
      ),
    ];
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-tab-upcoming')));
    await tester.pumpAndSettle();

    expect(find.text('未来'), findsOneWidget);
    expect(find.text('过去'), findsNothing);
  });
  testWidgets('the toolbar shows the count, fullscreen and sort label', (
    tester,
  ) async {
    await pumpLibrary(tester, buildService(movies: 70));

    expect(find.byKey(const Key('library-count')), findsOneWidget);
    expect(find.text('70 项'), findsOneWidget);
    expect(find.byKey(const Key('library-fullscreen')), findsOneWidget);
    expect(find.byKey(const Key('library-view-toggle')), findsOneWidget);
    expect(find.byKey(const Key('library-filter')), findsOneWidget);
    expect(find.byKey(const Key('library-random')), findsOneWidget);
    expect(find.text('创建日期 ↓'), findsOneWidget);
  });

  testWidgets('fullscreen hides the app bar and the exit restores it', (
    tester,
  ) async {
    await pumpLibrary(tester, buildService());

    await tester.tap(find.byKey(const Key('library-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('library-fullscreen-exit')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-fullscreen-exit')));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('library-fullscreen-exit')), findsNothing);
  });

  testWidgets('posters show the rating, count and year range', (tester) async {
    final library = FakeLibraryService(
      viewList: <LibraryView>[fakeShowsView],
      itemsByView: <String, List<MediaItem>>{
        fakeShowsView.id: <MediaItem>[
          const MediaItem(
            id: 'sh1',
            name: 'Show One',
            type: 'Series',
            productionYear: 2004,
            status: 'Continuing',
            communityRating: 8.4,
            userData: UserItemData(unplayedItemCount: 12),
          ),
        ],
      },
    );
    await pumpLibrary(tester, library);

    expect(find.text('8.4'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('2004 - 现在'), findsOneWidget);
  });

  testWidgets('switching views replaces the grid', (tester) async {
    final library = buildService();
    await pumpLibrary(tester, library);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Shows'));
    await tester.pumpAndSettle();

    expect(find.text('Show 1'), findsOneWidget);
    expect(find.text('Item 1'), findsNothing);
  });

  testWidgets(
    'series selection keeps episode identity, sessions and return positions',
    (tester) async {
      // A phone surface keeps the series hero, the 季 row and the season
      // page's long episode list reachable in a few scrolls.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final library = buildService(movies: 1, shows: 30);
      const seriesId = 's16';
      const MediaItem seasonOne = MediaItem(
        id: 'season-1',
        name: '第一季',
        type: 'Season',
        seriesId: seriesId,
        indexNumber: 1,
      );
      const MediaItem seasonTwo = MediaItem(
        id: 'season-2',
        name: '第二季',
        type: 'Season',
        seriesId: seriesId,
        indexNumber: 2,
      );
      library.seasonsBySeries[seriesId] = const <MediaItem>[
        seasonTwo,
        seasonOne,
      ];
      library.itemsById[seasonOne.id] = seasonOne;
      library.itemsById[seasonTwo.id] = seasonTwo;
      library.episodesBySeason['season-1'] = const <MediaItem>[
        MediaItem(id: 'first', name: '第一季单集', type: 'Episode', indexNumber: 1),
      ];
      library.episodesBySeason['season-2'] = List.generate(
        80,
        (index) => MediaItem(
          id: 'e${index + 1}',
          name: '第二季第${index + 1}集',
          type: 'Episode',
          seriesId: seriesId,
          seasonId: 'season-2',
          indexNumber: index + 1,
          runTimeTicks: const Duration(minutes: 45).inMicroseconds * 10,
        ),
      );
      library.itemsById['e75'] = MediaItem(
        id: 'e75',
        name: '第二季第75集',
        type: 'Episode',
        runTimeTicks: const Duration(minutes: 45).inMicroseconds * 10,
        userData: UserItemData(
          positionTicks: const Duration(seconds: 125).inMicroseconds * 10,
        ),
      );
      library.itemsById['e76'] = library.episodesBySeason['season-2']![75];
      final playback = FakePlaybackService();
      final engines = <FakePlaybackEngine>[];
      final reporters = <FakePlaybackReporter>[];
      final firstReporter = _PendingEpisodeStop();
      await pumpLibrary(
        tester,
        library,
        playback: playback,
        createEngine: () {
          final engine = FakePlaybackEngine();
          engines.add(engine);
          return engine;
        },
        createReporter: () {
          final reporter = reporters.isEmpty
              ? firstReporter
              : FakePlaybackReporter();
          reporters.add(reporter);
          return reporter;
        },
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Shows'));
      await tester.pumpAndSettle();
      final gridScrollable = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Show 16'),
        300,
        scrollable: gridScrollable,
      );
      await tester.pumpAndSettle();
      final gridOffset = tester
          .state<ScrollableState>(gridScrollable)
          .position
          .pixels;
      await tester.tap(find.text('Show 16'));
      await tester.pumpAndSettle();

      expect(playback.resolveItemIds, isEmpty);
      expect(engines, isEmpty);
      expect(library.seasonsRequests, [seriesId]);
      expect(library.episodeRequests.last, (
        seriesId: seriesId,
        seasonId: 'season-1',
      ));

      // The 季 row opens the season page; the series page only loads the
      // selected season's episodes for its resume row.
      final seriesScrollable = find
          .descendant(
            of: find.byKey(const Key('series-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('season-season-2')),
        400,
        scrollable: seriesScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('season-season-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('season-page')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('season-heading'))).data,
        '第 2 季',
      );
      expect(library.episodeRequests.last, (
        seriesId: seriesId,
        seasonId: 'season-2',
      ));

      final episodeScrollable = find
          .descendant(
            of: find.byKey(const Key('season-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('season-episode-e75')),
        500,
        scrollable: episodeScrollable,
      );
      await tester.pumpAndSettle();
      final episodeOffset = tester
          .state<ScrollableState>(episodeScrollable)
          .position
          .pixels;
      await tester.tap(find.byKey(const ValueKey('season-episode-e75')));
      await tester.tap(find.byKey(const ValueKey('season-episode-e75')));
      await tester.pumpAndSettle();
      expect(playback.resolveItemIds, ['e75']);
      expect(engines, hasLength(1));
      expect(engines.single.openedPlans.single.itemId, 'e75');
      expect(playback.resolveStartAts, [const Duration(seconds: 125)]);
      expect(reporters.single.startedItemIds, ['e75']);
      expect(find.text('已从 02:05 继续播放'), findsOneWidget);

      engines.single.emit(
        const PlaybackSnapshot(position: Duration(seconds: 145), playing: true),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('player-play-toggle')));
      await tester.pump();
      final slider = tester.widget<Slider>(
        find.byKey(const Key('player-progress')),
      );
      slider.onChangeEnd!(150000);
      await tester.pump();
      expect(reporters.single.progressItemIds, ['e75', 'e75']);
      final requestsBeforeExit = library.episodeRequests.length;
      await tester.tap(find.byKey(const Key('player-back')));
      await tester.pump();
      expect(reporters.single.stoppedItemIds, ['e75']);
      expect(reporters.single.stoppedAt, const Duration(seconds: 150));
      expect(library.episodeRequests, hasLength(requestsBeforeExit));
      expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);

      // Simulate the server's response after the awaited Stopped report.
      library.episodesBySeason['season-2']![74] = MediaItem(
        id: 'e75',
        name: '第二季第75集',
        type: 'Episode',
        indexNumber: 75,
        runTimeTicks: const Duration(minutes: 45).inMicroseconds * 10,
        userData: UserItemData(
          positionTicks: const Duration(seconds: 150).inMicroseconds * 10,
        ),
      );
      firstReporter.completion.complete();
      await tester.pumpAndSettle();
      expect(library.episodeRequests, hasLength(requestsBeforeExit + 1));
      expect(library.episodeRequests.last, (
        seriesId: seriesId,
        seasonId: 'season-2',
      ));
      // The season page kept its place and shows the refreshed progress.
      expect(find.byKey(const Key('season-page')), findsOneWidget);
      expect(
        tester.state<ScrollableState>(episodeScrollable).position.pixels,
        closeTo(episodeOffset, 0.1),
      );
      expect(
        find.byKey(const ValueKey('season-episode-progress-e75')),
        findsOneWidget,
      );
      expect(engines.first.disposeCalls, 1);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('season-episode-e76')),
        500,
        scrollable: episodeScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('season-episode-e76')));
      await tester.pumpAndSettle();
      expect(playback.resolveItemIds, ['e75', 'e76']);
      expect(engines, hasLength(2));
      expect(reporters, hasLength(2));
      expect(engines.last.openedPlans.single.itemId, 'e76');
      expect(reporters.last.startedItemIds, ['e76']);
      expect(playback.resolveStartAts.last, Duration.zero);
      await tester.tap(find.byKey(const Key('player-back')));
      await tester.pumpAndSettle();
      expect(reporters.last.stoppedItemIds, ['e76']);
      expect(reporters.first.stoppedCalls, 1);

      // Back through the season page to the series page and the library.
      await tester.tap(find.byKey(const Key('season-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-back')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Shows')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Shows'))
            .selected,
        isTrue,
      );
      expect(
        tester.state<ScrollableState>(gridScrollable).position.pixels,
        gridOffset,
      );
      // Let the existing direct-play probe timers finish without a live session.
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('scrolling to the end loads the next page', (tester) async {
    final library = buildService();
    await pumpLibrary(tester, library);
    // The home dashboard already issued items() calls before the library
    // opened, so measure the paging delta rather than an absolute count.
    final int before = library.itemCalls;

    // S15: the 800px surface now lays out 4 wider columns, so the first page
    // is taller; drag past its end to trigger the next-page load.
    await tester.drag(find.byType(GridView), const Offset(0, -8000));
    await tester.pumpAndSettle();

    expect(library.itemCalls, greaterThan(before));
  });

  testWidgets('a failure shows a retry that recovers', (tester) async {
    final library = buildService();
    library.failure = EmbyException(AppErrorCode.networkUnreachable);
    await pumpLibrary(tester, library);

    expect(find.text('无法连接服务器，请检查网络'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    library.failure = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('an expired session returns to the login screen', (tester) async {
    final library = buildService();
    library.unauthorized = true;
    await pumpLibrary(tester, library);

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('an empty view shows the empty message', (tester) async {
    final library = FakeLibraryService(viewList: <LibraryView>[fakeMoviesView]);
    await pumpLibrary(tester, library);

    expect(find.text('这个库还没有内容'), findsOneWidget);
  });

  testWidgets('a server without views shows the empty message', (tester) async {
    await pumpLibrary(tester, FakeLibraryService());

    expect(find.text('服务器没有可浏览的媒体库'), findsOneWidget);
  });

  testWidgets('posters resolve once and survive a grid rebuild', (
    tester,
  ) async {
    final library = buildService()..imageHost = '192.168.1.10:8096';
    final posters = FakePosterCache();
    await pumpLibrary(tester, library, posters: posters);

    expect(posters.loadCalls, greaterThan(0));
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    final int resolved = posters.loadCalls;

    // Refresh rebuilds every card with a freshly constructed provider. Value
    // equality is what keeps Flutter's image cache from re-resolving them.
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();

    expect(posters.loadCalls, resolved);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });

  testWidgets('a re-login does not re-resolve the posters', (tester) async {
    final library = buildService()..imageHost = '192.168.1.10:8096';
    final posters = FakePosterCache();
    await pumpLibrary(tester, library, posters: posters);
    final int resolved = posters.loadCalls;
    expect(resolved, greaterThan(0));

    library.imageToken = 'token-2';
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();

    expect(posters.loadCalls, resolved);
  });

  testWidgets('without an image url the card keeps its placeholder', (
    tester,
  ) async {
    final posters = FakePosterCache();
    await pumpLibrary(tester, buildService(), posters: posters);

    expect(posters.loadCalls, 0);
    expect(find.byIcon(Icons.movie_outlined), findsWidgets);
  });

  testWidgets('sub-tabs switch between all, resume and favorites', (
    tester,
  ) async {
    final library = buildService();
    library.resumableResults = <MediaItem>[fakeItem('r-1', name: '继续影片')];
    library.favoriteResults = <MediaItem>[fakeItem('f-1', name: '收藏影片')];
    await pumpLibrary(tester, library);

    expect(find.byKey(const Key('library-tab-all')), findsOneWidget);
    expect(find.byKey(const Key('library-tab-resume')), findsOneWidget);
    expect(find.byKey(const Key('library-tab-favorites')), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('library-tab-all')))
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('library-tab-resume')));
    await tester.pumpAndSettle();
    expect(find.text('继续影片'), findsOneWidget);
    expect(find.text('Item 1'), findsNothing);
    // View chips only scope the 全部 tab.
    expect(find.widgetWithText(ChoiceChip, 'Movies'), findsNothing);

    await tester.tap(find.byKey(const Key('library-tab-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('收藏影片'), findsOneWidget);
    expect(find.text('继续影片'), findsNothing);

    await tester.tap(find.byKey(const Key('library-tab-all')));
    await tester.pumpAndSettle();
    expect(find.text('Item 1'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Movies'), findsOneWidget);
  });

  testWidgets('the sort picker changes the items query', (tester) async {
    final library = buildService();
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    // S70: the list scrolls; bring the target field into view first.
    await tester.scrollUntilVisible(
      find.byKey(const Key('library-sort-year')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-sort-year')));
    await tester.pumpAndSettle();

    expect(library.itemsSorts.last, (
      sortBy: 'ProductionYear',
      sortOrder: 'Descending',
    ));

    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-sort-asc')));
    await tester.pumpAndSettle();

    expect(library.itemsSorts.last, (
      sortBy: 'ProductionYear',
      sortOrder: 'Ascending',
    ));
  });

  testWidgets('the sort dialog offers 上映日期 (S56)', (tester) async {
    final library = buildService();
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    final Finder premiere = find.byKey(const Key('library-sort-premiereDate'));
    await tester.scrollUntilVisible(
      premiere,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(premiere, findsOneWidget);

    await tester.tap(premiere);
    await tester.pumpAndSettle();

    expect(library.itemsSorts.last, (
      sortBy: 'PremiereDate',
      sortOrder: 'Descending',
    ));
    expect(find.text('首映日期 ↓'), findsOneWidget);
  });
  testWidgets('the view toggle switches between grid and list', (tester) async {
    final library = FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: <MediaItem>[
          const MediaItem(
            id: '1',
            name: 'Item 1',
            type: 'Movie',
            productionYear: 2024,
            userData: UserItemData(played: true),
          ),
        ],
      },
    );
    await pumpLibrary(tester, library);
    expect(find.byType(GridView), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-view-toggle')));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsNothing);
    expect(find.byKey(const Key('library-row-1')), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('已看'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-view-toggle')));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byKey(const Key('library-row-1')), findsNothing);
  });

  testWidgets('random play opens a movie detail', (tester) async {
    final library = buildService(movies: 1);
    library.itemsById['1'] = fakeItem('1');
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-random')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-title')), findsOneWidget);
  });

  testWidgets('random play opens the series page for a series', (tester) async {
    final library = FakeLibraryService(
      viewList: <LibraryView>[fakeShowsView],
      itemsByView: <String, List<MediaItem>>{
        fakeShowsView.id: <MediaItem>[
          const MediaItem(id: 's-1', name: 'Solo Show', type: 'Series'),
        ],
      },
    );
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-random')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('series-back')), findsOneWidget);
  });

  testWidgets('random play is disabled without loaded items', (tester) async {
    final library = FakeLibraryService(viewList: <LibraryView>[fakeMoviesView]);
    await pumpLibrary(tester, library);

    expect(
      tester
          .widget<AppIconButton>(find.byKey(const Key('library-random')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('the collections tab renders BoxSet posters', (tester) async {
    final library = buildService();
    library.collectionResults = <MediaItem>[
      const MediaItem(id: 'box-1', name: '漫威合集', type: 'BoxSet'),
    ];
    await pumpLibrary(tester, library);

    expect(find.byKey(const Key('library-tab-collections')), findsOneWidget);
    expect(find.byKey(const Key('library-tab-type')), findsOneWidget);
    expect(find.byKey(const Key('library-tab-tag')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-tab-collections')));
    await tester.pumpAndSettle();

    expect(find.text('漫威合集'), findsOneWidget);
    expect(find.text('Item 1'), findsNothing);
    // Collections is a global row: the view chips stay hidden.
    expect(find.widgetWithText(ChoiceChip, 'Movies'), findsNothing);
    expect(library.collectionsRequests, isNotEmpty);
  });

  testWidgets('the type tab chooser filters by IncludeItemTypes', (
    tester,
  ) async {
    final library = FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: <MediaItem>[
          fakeItem('m-1', name: '电影一'),
          const MediaItem(id: 't-1', name: '剧集一', type: 'Series'),
        ],
      },
    );
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-tab-type')));
    await tester.pumpAndSettle();
    expect(find.text('电影一'), findsOneWidget);
    expect(find.text('剧集一'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-type-movies')));
    await tester.pumpAndSettle();
    expect(library.itemsRequests.last.includeItemTypes, 'Movie');
    expect(find.text('电影一'), findsOneWidget);
    expect(find.text('剧集一'), findsNothing);

    await tester.tap(find.byKey(const Key('library-type-series')));
    await tester.pumpAndSettle();
    expect(library.itemsRequests.last.includeItemTypes, 'Series');
    expect(find.text('剧集一'), findsOneWidget);
    expect(find.text('电影一'), findsNothing);
  });

  testWidgets('the tag tab lists tags and filters by selection', (
    tester,
  ) async {
    final library = FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: <MediaItem>[
          const MediaItem(
            id: 'm-1',
            name: '4K 影片',
            type: 'Movie',
            tags: <String>['4K'],
          ),
          fakeItem('m-2', name: '普通影片'),
        ],
      },
    );
    library.tagNames = <String>['4K', '完结'];
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-tab-tag')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '4K'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '完结'), findsOneWidget);
    expect(find.text('4K 影片'), findsOneWidget);
    expect(find.text('普通影片'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-tag-4K')));
    await tester.pumpAndSettle();
    expect(library.itemsRequests.last.tag, '4K');
    expect(find.text('4K 影片'), findsOneWidget);
    expect(find.text('普通影片'), findsNothing);

    await tester.tap(find.byKey(const Key('library-tag-all')));
    await tester.pumpAndSettle();
    expect(library.itemsRequests.last.tag, isNull);
    expect(find.text('普通影片'), findsOneWidget);
  });

  testWidgets('a tag load failure offers a retry', (tester) async {
    final library = buildService();
    library.tagsFailure = EmbyException(AppErrorCode.networkUnreachable);
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-tab-tag')));
    await tester.pumpAndSettle();
    expect(find.text('无法连接服务器，请检查网络'), findsOneWidget);

    library.tagsFailure = null;
    library.tagNames = <String>['4K'];
    await tester.tap(find.byKey(const Key('library-tags-retry')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '4K'), findsOneWidget);
  });

  testWidgets('the filter dialog applies genre and year', (tester) async {
    final library = buildService();
    library.genreNames = <String>['动作', '科幻'];
    await pumpLibrary(tester, library);

    await tester.tap(find.byKey(const Key('library-filter')));
    await tester.pumpAndSettle();
    expect(find.text('筛选'), findsOneWidget);
    expect(find.byKey(const Key('library-filter-genre-动作')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-filter-genre-动作')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('library-filter-year')),
      '2024',
    );
    await tester.tap(find.byKey(const Key('library-filter-apply')));
    await tester.pumpAndSettle();

    expect(library.itemsRequests.last.genre, '动作');
    expect(library.itemsRequests.last.year, 2024);
    expect(
      find.byKey(const Key('library-filter-genre-active')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('library-filter-year-active')), findsOneWidget);

    // Clearing through the dialog removes both facets in one reload.
    await tester.tap(find.byKey(const Key('library-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-filter-clear')));
    await tester.pumpAndSettle();

    expect(library.itemsRequests.last.genre, isNull);
    expect(library.itemsRequests.last.year, isNull);
    expect(find.byKey(const Key('library-filter-genre-active')), findsNothing);
    expect(find.byKey(const Key('library-filter-year-active')), findsNothing);
  });

  testWidgets('the filter affordance only shows on the all tab', (
    tester,
  ) async {
    final library = buildService();
    library.resumableResults = <MediaItem>[fakeItem('r-1')];
    await pumpLibrary(tester, library);
    expect(find.byKey(const Key('library-filter')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-tab-resume')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-filter')), findsNothing);

    await tester.tap(find.byKey(const Key('library-tab-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-filter')), findsOneWidget);
  });
}

/// Hidden-library double (S32): seeds the state synchronously so the library
/// page's first page already hides the requested ids.
class _TestHiddenLibrariesController extends HiddenLibrariesController {
  _TestHiddenLibrariesController(this._seed);

  final KeyValueStore? _seed;

  @override
  Future<Set<String>> build() async {
    if (_seed == null) return <String>{};
    try {
      return decodeHiddenLibraries(await _seed.read(hiddenLibrariesStorageKey));
    } catch (_) {
      return <String>{};
    }
  }
}
