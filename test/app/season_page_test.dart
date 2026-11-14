import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/core/router/app_routes.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/features/series/season_page.dart';
import 'package:media_player/features/series/series_widgets.dart';
import 'package:media_player/ui/app_bottom_nav.dart';
import 'package:media_player/ui/nav_visibility.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';

class _Auth implements AuthService {
  @override
  AuthSession? current = const AuthSession(
    userId: 'user',
    userName: 'Test',
    accessToken: 'fake-token',
    deviceId: 'device',
  );

  final StreamController<AuthSession?> events =
      StreamController<AuthSession?>.broadcast();

  @override
  Stream<AuthSession?> get session => events.stream;

  @override
  Future<AuthSession?> restore() async => current;

  @override
  Future<ServerProfile?> lastProfile() async => null;

  @override
  Future<void> handleUnauthorized() async {
    current = null;
    events.add(null);
  }

  @override
  Future<void> logout() => handleUnauthorized();

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
}

const MediaItem _series = MediaItem(
  id: 'show',
  name: '测试剧集',
  type: 'Series',
  productionYear: 2004,
  status: 'Continuing',
  imageTag: 'primary-tag',
  backdropTags: <String>['bd-1', 'bd-2'],
);

const MediaItem _season = MediaItem(
  id: 's1',
  name: '第一季',
  type: 'Season',
  seriesId: 'show',
  indexNumber: 1,
  childCount: 3,
  productionYear: 2004,
  imageTag: 's1-tag',
);

MediaItem _episode(
  String id,
  int number, {
  String? name,
  bool played = false,
  Duration position = Duration.zero,
}) {
  return MediaItem(
    id: id,
    name: name ?? '分集的标题',
    type: 'Episode',
    seriesId: 'show',
    seasonId: 's1',
    indexNumber: number,
    parentIndexNumber: 1,
    runTimeTicks: const Duration(minutes: 5).inMicroseconds * 10,
    overview: '第 $number 集的简介文字。',
    userData: UserItemData(
      played: played,
      positionTicks: position.inMicroseconds * 10,
    ),
  );
}

List<MediaItem> _episodes() => <MediaItem>[
  _episode('e1', 1, name: '泥坑', played: true),
  _episode('e2', 2, name: '恐龙先生弄丢了', position: const Duration(minutes: 2)),
  _episode('e3', 3, name: '最好的朋友'),
];

FakeLibraryService _library() {
  return FakeLibraryService(
    itemsById: <String, MediaItem>{'show': _series, 's1': _season},
    seasonsBySeries: <String, List<MediaItem>>{
      'show': <MediaItem>[_season],
    },
    episodesBySeason: <String, List<MediaItem>>{'s1': _episodes()},
  );
}

void main() {
  late _Auth auth;
  GoRouter? router;
  late List<String> openedEpisodes;
  late List<String> openedSeries;

  setUp(() {
    auth = _Auth();
    openedEpisodes = <String>[];
    openedSeries = <String>[];
  });

  tearDown(() async {
    router?.dispose();
    await auth.events.close();
  });

  Future<void> pumpSeason(
    WidgetTester tester,
    FakeLibraryService library, {
    String location = '/season/s1?series=show',
    Size size = const Size(420, 900),
    bool settle = true,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final GoRouter scopedRouter = GoRouter(
      initialLocation: location,
      routes: <RouteBase>[
        GoRoute(
          path: '/season/:seasonId',
          builder: (BuildContext context, GoRouterState state) => SeasonPage(
            seriesId: state.uri.queryParameters['series'] ?? '',
            seasonId: state.pathParameters['seasonId']!,
          ),
        ),
        GoRoute(
          path: '/series/:seriesId',
          builder: (BuildContext context, GoRouterState state) {
            openedSeries.add(state.pathParameters['seriesId']!);
            return const Scaffold(body: Text('剧集页'));
          },
        ),
        GoRoute(
          path: '/player/:itemId',
          builder: (BuildContext context, GoRouterState state) {
            openedEpisodes.add(state.pathParameters['itemId']!);
            return Scaffold(
              body: Column(
                children: <Widget>[
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('结束本集'),
                  ),
                  // Mimics the player's own auto-next: it replaces its route,
                  // so the original push future never completes.
                  TextButton(
                    onPressed: () => context.pushReplacement('/player-next/e3'),
                    child: const Text('播放下一集'),
                  ),
                ],
              ),
            );
          },
        ),
        GoRoute(
          path: '/player-next/:itemId',
          builder: (BuildContext context, GoRouterState state) {
            openedEpisodes.add('next:${state.pathParameters['itemId']!}');
            return Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: const Text('结束本集'),
              ),
            );
          },
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('登录入口')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (Ref ref) async => AppServices(
              auth: auth,
              library: library,
              posters: FakePosterCache(),
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: scopedRouter,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
        ),
      ),
    );
    router = scopedRouter;
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final Finder scrollable = find
        .descendant(
          of: find.byKey(const Key('season-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: scrollable,
      maxScrolls: 40,
    );
    await tester.pumpAndSettle();
    final Offset topLeft = tester.getTopLeft(finder);
    if (topLeft.dy < 80) {
      await tester.drag(scrollable, Offset(0, 80 - topLeft.dy));
      await tester.pumpAndSettle();
    }
  }

  test('the season route carries the series as a query parameter', () {
    expect(
      AppRoutes.seasonFor('s1', seriesId: 'show'),
      '/season/s1?series=show',
    );
  });

  testWidgets('renders the hero, metadata and the episode cards', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeason(tester, library);

    expect(find.byKey(const Key('season-page')), findsOneWidget);
    expect(find.byKey(const Key('season-hero')), findsOneWidget);
    expect(library.detailRequests, <String>['show', 's1']);
    expect(library.episodeRequests, <({String seriesId, String seasonId})>[
      (seriesId: 'show', seasonId: 's1'),
    ]);

    expect(
      tester.widget<Text>(find.byKey(const Key('season-meta'))).data,
      '2004',
    );
    expect(find.textContaining('共 3 集'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('season-hero'))).height,
      closeTo(420 * 1.05, 0.5),
    );
    expect(find.byKey(const Key('season-heading')), findsOneWidget);
    expect(find.text('第 1 季'), findsOneWidget);

    expect(find.text('1.泥坑'), findsOneWidget);
    expect(find.text('2.恐龙先生弄丢了'), findsOneWidget);
    expect(find.text('5分0秒'), findsNWidgets(3));
    expect(find.byKey(const Key('season-episode-played-e1')), findsOneWidget);
    expect(find.byKey(const Key('season-episode-progress-e2')), findsOneWidget);
    expect(find.byKey(const Key('season-episode-progress-e3')), findsNothing);
    expect(find.byType(AppBottomNav), findsOneWidget);
  });

  testWidgets('the play row resumes the in-progress episode', (
    WidgetTester tester,
  ) async {
    await pumpSeason(tester, _library());

    final Finder play = find.byKey(const Key('season-play'));
    expect(play, findsOneWidget);
    expect(
      find.descendant(of: play, matching: find.text('继续 (剩余: 3分0秒)')),
      findsOneWidget,
    );
    final FractionallySizedBox fill = tester.widget<FractionallySizedBox>(
      find.descendant(of: play, matching: find.byType(FractionallySizedBox)),
    );
    expect(fill.widthFactor, closeTo(0.4, 0.01));

    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e2']);
  });

  testWidgets('an episode card starts that episode', (
    WidgetTester tester,
  ) async {
    await pumpSeason(tester, _library());
    await scrollTo(tester, find.byKey(const Key('season-episode-e3')));

    await tester.tap(find.byKey(const Key('season-episode-e3')));
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e3']);
  });

  testWidgets('the chevron opens the episode picker and a pick plays', (
    WidgetTester tester,
  ) async {
    await pumpSeason(tester, _library());

    await tester.tap(find.byKey(const Key('season-episodes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('episode-picker-title')), findsOneWidget);
    expect(find.text('选集 · 第 1 季'), findsOneWidget);

    await tester.tap(find.byKey(const Key('episode-pick-e1')));
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e1']);
  });

  testWidgets('watched and favorite toggles write the season item', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeason(tester, library);

    await tester.tap(find.byKey(const Key('season-watched')));
    await tester.pumpAndSettle();
    expect(library.playedWrites.single, (itemId: 's1', played: true));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byKey(const Key('season-favorite')));
    await tester.pumpAndSettle();
    expect(library.favoriteWrites.single, (itemId: 's1', favorite: true));
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('the overflow menu refreshes and marks the season watched', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeason(tester, library);
    final int detailCalls = library.detailRequests.length;
    final int episodeCalls = library.episodeRequests.length;

    await tester.tap(find.byKey(const Key('season-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('刷新'), findsOneWidget);
    expect(find.text('标记已看'), findsOneWidget);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(library.detailRequests.length, detailCalls + 2);
    expect(library.episodeRequests.length, episodeCalls + 1);

    await tester.tap(find.byKey(const Key('season-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标记已看'));
    await tester.pumpAndSettle();
    expect(library.playedWrites.single, (itemId: 's1', played: true));
  });

  testWidgets('scrolling past the hero shows the title in a black bar', (
    WidgetTester tester,
  ) async {
    // A short phone surface leaves enough scroll range for the hero to pass
    // behind the bar; the taller default surface is not scrollable at all.
    await pumpSeason(tester, _library(), size: const Size(360, 720));

    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('season-title')))
          .opacity,
      0,
    );
    await tester.drag(
      find.byKey(const Key('season-scroll')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('season-title')))
          .opacity,
      1,
    );
  });

  testWidgets('returning from the player refreshes the episode list', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeason(tester, library);
    await tester.tap(find.byKey(const Key('season-play')));
    await tester.pumpAndSettle();

    library.episodesBySeason['s1'] = <MediaItem>[
      _episode('e1', 1, name: '泥坑', played: true),
      _episode('e2', 2, name: '恐龙先生弄丢了', played: true),
      _episode('e3', 3, name: '最好的朋友'),
    ];
    await tester.tap(find.text('结束本集'));
    await tester.pumpAndSettle();

    expect(library.episodeRequests, hasLength(2));
    expect(find.byKey(const Key('season-episode-progress-e2')), findsNothing);
    expect(find.byKey(const Key('season-episode-played-e2')), findsOneWidget);
    final Finder play = find.byKey(const Key('season-play'));
    expect(
      find.descendant(of: play, matching: find.text('播放')),
      findsOneWidget,
    );
  });

  testWidgets('a load failure offers a retry that recovers', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library()
      ..failure = EmbyException(AppErrorCode.networkUnreachable);
    await pumpSeason(tester, library);

    expect(find.textContaining('无法连接服务器'), findsOneWidget);
    library.failure = null;
    await tester.tap(find.byKey(const Key('season-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('season-hero')), findsOneWidget);
    expect(find.byKey(const Key('season-heading')), findsOneWidget);
  });

  testWidgets('401 redirects to login without further requests', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library()..unauthorized = true;
    await pumpSeason(tester, library);

    expect(find.text('登录入口'), findsOneWidget);
    expect(library.episodeRequests, isEmpty);
  });

  testWidgets('back on a direct entry falls back to the series page', (
    WidgetTester tester,
  ) async {
    await pumpSeason(tester, _library());

    await tester.tap(find.byKey(const Key('season-back')));
    await tester.pumpAndSettle();
    expect(find.text('剧集页'), findsOneWidget);
    expect(openedSeries, <String>['show']);
  });

  testWidgets('a missing series query shows the fatal notice', (
    WidgetTester tester,
  ) async {
    await pumpSeason(tester, _library(), location: '/season/s1');

    expect(find.textContaining('季信息缺失'), findsOneWidget);
    expect(find.byKey(const Key('season-retry')), findsOneWidget);
  });

  testWidgets('a wide surface constrains the content width', (
    WidgetTester tester,
  ) async {
    await pumpSeason(tester, _library(), size: const Size(1280, 900));

    expect(find.byKey(const Key('season-wide-content')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a large text scale on a narrow surface does not overflow', (
    WidgetTester tester,
  ) async {
    await pumpSeason(
      tester,
      _library(),
      size: const Size(320, 720),
      textScaler: TextScaler.linear(1.5),
    );

    expect(find.byKey(const Key('season-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the play row matches the Yamby geometry', (
    WidgetTester tester,
  ) async {
    await pumpSeason(tester, _library());

    final Finder play = find.byKey(const Key('season-play'));
    expect(tester.getSize(play).height, 56);
    expect(tester.getSize(play).width, closeTo(420 * 0.58, 0.5));
    final Material button = tester.widget<Material>(
      find.descendant(of: play, matching: find.byType(Material)).first,
    );
    expect(button.color, SeriesPlayButton.surface);
    final ColoredBox fill = tester.widget<ColoredBox>(
      find.descendant(of: play, matching: find.byType(ColoredBox)).first,
    );
    expect(fill.color, SeriesPlayButton.progressFill);

    final Finder chevron = find.byKey(const Key('season-episodes'));
    expect(tester.getSize(chevron), const Size(54, 56));
    expect(tester.getTopLeft(chevron).dx - tester.getTopRight(play).dx, 8);
  });

  testWidgets('the capsule navigation is visible on the season page', (
    WidgetTester tester,
  ) async {
    await pumpSeason(tester, _library());

    final Finder nav = find.byKey(const Key('nav-capsule-slide'));
    expect(tester.widget<AnimatedSlide>(nav).offset, Offset.zero);

    // Auto-hide keeps working after the page mount reset.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('season-page'))),
    );
    container.read(navVisibleProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(nav).offset, isNot(Offset.zero));
  });

  testWidgets('the play row unlocks when the player replaces its own route', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeason(tester, library);

    await tester.tap(find.byKey(const Key('season-play')));
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e2']);
    // The page is covered while the player runs; the return watcher notices.
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('播放下一集'));
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e2', 'next:e3']);

    library.episodesBySeason['s1'] = <MediaItem>[
      _episode('e1', 1, name: '泥坑', played: true),
      _episode('e2', 2, name: '恐龙先生弄丢了', played: true),
      _episode('e3', 3, name: '最好的朋友', position: const Duration(minutes: 1)),
    ];
    await tester.tap(find.text('结束本集'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final SeriesPlayButton play = tester.widget<SeriesPlayButton>(
      find.byKey(const Key('season-play')),
    );
    expect(play.onPressed, isNotNull);
    expect(library.episodeRequests.length, greaterThan(1));
    expect(find.byKey(const Key('season-episode-played-e2')), findsOneWidget);
    expect(find.byKey(const Key('season-episode-progress-e3')), findsOneWidget);
  });
}
