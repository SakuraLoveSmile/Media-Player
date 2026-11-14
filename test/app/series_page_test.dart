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
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/person.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/features/series/season_page.dart';
import 'package:media_player/features/series/series_page.dart';
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
  overview: '佩奇是一只可爱的粉红色小猪，她有一个名叫乔治的弟弟，乔治不喜欢吃蔬菜，最喜欢的东西是巧克力蛋糕和恐龙。',
  communityRating: 8.8,
  officialRating: 'TV-G',
  productionYear: 2004,
  status: 'Continuing',
  genres: <String>['动画', '儿童'],
  imageTag: 'primary-tag',
  backdropTags: <String>['bd-1', 'bd-2', 'bd-3'],
  people: <Person>[
    Person(name: '约翰·斯帕克斯', role: '旁白', type: 'Actor', id: 'p-1'),
    Person(name: '莫温娜·班克斯', role: '配音', type: 'Actor', id: 'p-2'),
  ],
  studios: <NamedLink>[
    NamedLink(name: 'Astley Baker Davies', target: 'studio-1'),
  ],
  externalUrls: <NamedLink>[
    NamedLink(name: 'IMDb', target: 'https://www.imdb.com/title/tt1/'),
  ],
);

const MediaItem _season1 = MediaItem(
  id: 's1',
  name: '第一季',
  type: 'Season',
  seriesId: 'show',
  indexNumber: 1,
  childCount: 3,
  imageTag: 's1-tag',
);

const MediaItem _season2 = MediaItem(
  id: 's2',
  name: '第二季',
  type: 'Season',
  seriesId: 'show',
  indexNumber: 2,
  childCount: 5,
  imageTag: 's2-tag',
);

const MediaItem _similarMovie = MediaItem(
  id: 'm-1',
  name: '推荐影片',
  type: 'Movie',
  communityRating: 7.1,
  productionYear: 2021,
);

const MediaItem _similarSeries = MediaItem(
  id: 'show-2',
  name: '推荐剧集',
  type: 'Series',
  communityRating: 9.0,
  productionYear: 2023,
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
    overview: '第 $number 集的分集简介文字，用于验证两行截断。',
    userData: UserItemData(
      played: played,
      positionTicks: position.inMicroseconds * 10,
    ),
  );
}

List<MediaItem> _seasonOneEpisodes() => <MediaItem>[
  _episode('e1', 1, name: '泥坑', played: true),
  _episode('e2', 2, name: '恐龙先生弄丢了', position: const Duration(minutes: 2)),
  _episode('e3', 3, name: '最好的朋友', position: const Duration(minutes: 1)),
  _episode('e4', 4, name: '鹦鹉波莉'),
];

FakeLibraryService _library() {
  return FakeLibraryService(
    itemsById: <String, MediaItem>{
      'show': _series,
      _season1.id: _season1,
      _season2.id: _season2,
    },
    seasonsBySeries: <String, List<MediaItem>>{
      'show': <MediaItem>[_season2, _season1],
    },
    episodesBySeason: <String, List<MediaItem>>{
      's1': _seasonOneEpisodes(),
      's2': <MediaItem>[_episode('s2e1', 1, name: '第二季第一集')],
    },
  )..similarResults = const <MediaItem>[_similarMovie, _similarSeries];
}

void main() {
  late _Auth auth;
  late GoRouter router;
  late List<String> openedEpisodes;
  late List<String> openedPersons;
  late List<String> openedLibraries;
  late List<String> openedDetails;
  late List<Uri> openedLinks;

  setUp(() {
    auth = _Auth();
    openedEpisodes = <String>[];
    openedPersons = <String>[];
    openedLibraries = <String>[];
    openedDetails = <String>[];
    openedLinks = <Uri>[];
  });

  tearDown(() async {
    router.dispose();
    await auth.events.close();
  });

  Future<void> pumpSeries(
    WidgetTester tester,
    FakeLibraryService library, {
    Size size = const Size(420, 900),
    bool fromLibrary = false,
    bool settle = true,
    Completer<void>? bootstrapReady,
    TextScaler textScaler = TextScaler.noScaling,
    Future<bool> Function(Uri url)? urlOpener,
  }) async {
    final Future<bool> Function(Uri url) opener =
        urlOpener ??
        (Uri url) async {
          openedLinks.add(url);
          return true;
        };
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: fromLibrary ? '/library' : '/series/show',
      routes: <RouteBase>[
        GoRoute(
          path: '/series/:seriesId',
          builder: (BuildContext context, GoRouterState state) {
            final String seriesId = state.pathParameters['seriesId']!;
            if (seriesId != 'show') {
              return const Scaffold(body: Text('其他剧集页'));
            }
            return SeriesPage(seriesId: seriesId, urlOpener: opener);
          },
        ),
        GoRoute(
          path: '/season/:seasonId',
          builder: (BuildContext context, GoRouterState state) => SeasonPage(
            seriesId: state.uri.queryParameters['series'] ?? '',
            seasonId: state.pathParameters['seasonId']!,
          ),
        ),
        GoRoute(
          path: '/player/:itemId',
          builder: (BuildContext context, GoRouterState state) {
            final String itemId = state.pathParameters['itemId']!;
            openedEpisodes.add(itemId);
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
                    onPressed: () => context.pushReplacement('/player-next/e4'),
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
          path: '/library',
          builder: (BuildContext context, GoRouterState state) {
            openedLibraries.add(state.uri.toString());
            return const Scaffold(body: Text('媒体库入口'));
          },
        ),
        GoRoute(
          path: '/person/:personId',
          builder: (BuildContext context, GoRouterState state) {
            openedPersons.add(state.pathParameters['personId']!);
            return const Scaffold(body: Text('演员页'));
          },
        ),
        GoRoute(
          path: '/detail/:itemId',
          builder: (BuildContext context, GoRouterState state) {
            openedDetails.add(state.pathParameters['itemId']!);
            return const Scaffold(body: Text('电影详情'));
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
          bootstrapProvider.overrideWith((Ref ref) async {
            await bootstrapReady?.future;
            return AppServices(
              auth: auth,
              library: library,
              posters: FakePosterCache(),
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
            );
          }),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
        ),
      ),
    );
    if (fromLibrary) {
      await tester.pump();
      unawaited(router.push<void>('/series/show'));
    }
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  /// Scrolls the page until [finder] is on screen.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final Finder scrollable = find
        .descendant(
          of: find.byKey(const Key('series-scroll')),
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
    // scrollUntilVisible may stop with the target under the floating bar.
    final Offset topLeft = tester.getTopLeft(finder);
    if (topLeft.dy < 80) {
      await tester.drag(scrollable, Offset(0, 80 - topLeft.dy));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'the hero shows rating, official rating, year, seasons and genres',
    (WidgetTester tester) async {
      await pumpSeries(tester, _library());

      expect(find.byKey(const Key('series-hero')), findsOneWidget);
      expect(find.byKey(const Key('series-rating')), findsOneWidget);
      expect(find.text('8.8'), findsOneWidget);
      expect(find.text('TV-G'), findsOneWidget);
      expect(find.text('2004 - 现在'), findsOneWidget);
      expect(find.text('共 2 季'), findsOneWidget);
      expect(find.text('动画'), findsOneWidget);
      expect(find.text('儿童'), findsOneWidget);

      await tester.tap(find.byKey(const Key('series-genre-动画')));
      await tester.pumpAndSettle();
      expect(openedLibraries, hasLength(1));
      expect(Uri.parse(openedLibraries.single).queryParameters['genre'], '动画');
    },
  );

  testWidgets(
    'the play row resumes the in-progress episode with a progress fill',
    (WidgetTester tester) async {
      final FakeLibraryService library = _library();
      await pumpSeries(tester, library);

      final Finder play = find.byKey(const Key('series-play'));
      expect(play, findsOneWidget);
      expect(
        find.descendant(of: play, matching: find.text('继续 (剩余: 3分0秒)')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('series-current-episode')))
            .data,
        'S1E2：恐龙先生弄丢了',
      );
      final FractionallySizedBox fill = tester.widget<FractionallySizedBox>(
        find.descendant(of: play, matching: find.byType(FractionallySizedBox)),
      );
      expect(fill.widthFactor, closeTo(0.4, 0.01));

      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(openedEpisodes, <String>['e2']);
    },
  );

  testWidgets('everything watched shows 已播放 and still starts episode one', (
    WidgetTester tester,
  ) async {
    final MediaItem watchedSeries = MediaItem(
      id: _series.id,
      name: _series.name,
      type: 'Series',
      overview: _series.overview,
      people: _series.people,
      userData: const UserItemData(played: true),
    );
    final FakeLibraryService library = _library()
      ..itemsById['show'] = watchedSeries
      ..episodesBySeason['s1'] = <MediaItem>[
        _episode('e1', 1, name: '泥坑', played: true),
      ];
    await pumpSeries(tester, library);

    final Finder play = find.byKey(const Key('series-play'));
    expect(
      find.descendant(of: play, matching: find.text('已播放')),
      findsOneWidget,
    );
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e1']);
  });

  testWidgets('the chevron opens the episode picker and a pick plays', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());

    await tester.tap(find.byKey(const Key('series-episodes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('episode-picker-title')), findsOneWidget);
    expect(find.text('S1E4：鹦鹉波莉'), findsWidgets);

    await tester.tap(find.byKey(const Key('episode-pick-e4')));
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e4']);
  });

  testWidgets('watched and favorite toggles write through', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeries(tester, library);

    await tester.tap(find.byKey(const Key('series-watched')));
    await tester.pumpAndSettle();
    expect(library.playedWrites.single, (itemId: 'show', played: true));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byKey(const Key('series-favorite')));
    await tester.pumpAndSettle();
    expect(library.favoriteWrites.single, (itemId: 'show', favorite: true));
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('the overflow menu refreshes and marks the series watched', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeries(tester, library);
    final int detailCalls = library.detailRequests.length;

    await tester.tap(find.byKey(const Key('series-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('刷新'), findsOneWidget);
    expect(find.text('标记已看'), findsOneWidget);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(library.detailRequests.length, detailCalls + 1);
    expect(library.similarRequests.length, greaterThan(1));

    await tester.tap(find.byKey(const Key('series-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标记已看'));
    await tester.pumpAndSettle();
    expect(library.playedWrites.single, (itemId: 'show', played: true));
  });

  testWidgets('继续观看 lists in-progress episodes and plays one', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());
    await scrollTo(tester, find.byKey(const Key('series-resume-e2')));

    expect(find.byKey(const Key('series-resumable')), findsOneWidget);
    expect(find.byKey(const Key('series-resume-e2')), findsOneWidget);
    expect(find.text('S1E2：恐龙先生弄丢了'), findsWidgets);
    expect(find.textContaining('剩余: 3分0秒'), findsWidgets);

    await tester.tap(find.byKey(const Key('series-resume-e2')));
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e2']);
  });

  testWidgets('the 继续观看 pager scrolls the row and # opens the season', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());
    await scrollTo(tester, find.byKey(const Key('series-continue-next')));

    final double before = tester
        .getTopLeft(find.byKey(const Key('series-resume-e2')))
        .dx;
    await tester.tap(find.byKey(const Key('series-continue-next')));
    await tester.pumpAndSettle();
    final double after = tester
        .getTopLeft(find.byKey(const Key('series-resume-e2')))
        .dx;
    expect(after, lessThan(before));

    await tester.tap(find.byKey(const Key('series-continue-hash')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('season-page')), findsOneWidget);
  });

  testWidgets('season cards show the episode count badge and open the season', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());
    await scrollTo(tester, find.byKey(const Key('season-s1')));

    expect(find.text('第 2 季'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('season-count-s1')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('season-s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('season-page')), findsOneWidget);
    expect(find.byKey(const Key('season-heading')), findsOneWidget);

    await tester.tap(find.byKey(const Key('season-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('series-page')), findsOneWidget);
  });

  testWidgets('cast cards show name, role and type and open the person', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());
    await scrollTo(tester, find.byKey(const Key('series-person-p-1')));

    expect(find.text('约翰·斯帕克斯'), findsOneWidget);
    expect(find.text('旁白'), findsOneWidget);
    expect(find.text('Actor'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('series-person-p-1')));
    await tester.pumpAndSettle();
    expect(openedPersons, <String>['p-1']);
  });

  testWidgets('artwork, studios, external links and 推荐 render and act', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library()..imageHost = 'host.test';
    await pumpSeries(tester, library);

    await scrollTo(tester, find.byKey(const Key('series-artwork')));
    expect(find.text('艺术图'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('series-artwork')),
        matching: find.byType(Image),
      ),
      findsNWidgets(3),
    );

    await scrollTo(
      tester,
      find.byKey(const Key('series-studio-Astley Baker Davies')),
    );
    expect(find.text('工作室'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('series-studio-Astley Baker Davies')),
    );
    await tester.pumpAndSettle();
    final Uri studioUri = Uri.parse(openedLibraries.single);
    expect(studioUri.queryParameters['studio'], 'studio-1');
    expect(studioUri.queryParameters['studioName'], 'Astley Baker Davies');
    router.pop();
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const Key('series-link-IMDb')));
    expect(find.text('外部链接'), findsOneWidget);
    await tester.tap(find.byKey(const Key('series-link-IMDb')));
    await tester.pumpAndSettle();
    expect(openedLinks.single.toString(), 'https://www.imdb.com/title/tt1/');

    await scrollTo(tester, find.byKey(const Key('series-similar-m-1')));
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('推荐影片'), findsOneWidget);
    expect(find.text('2021'), findsOneWidget);
    await tester.tap(find.byKey(const Key('series-similar-m-1')));
    await tester.pumpAndSettle();
    expect(openedDetails, <String>['m-1']);
    router.pop();
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const Key('series-similar-show-2')));
    await tester.tap(find.byKey(const Key('series-similar-show-2')));
    await tester.pumpAndSettle();
    expect(find.text('其他剧集页'), findsOneWidget);
  });

  testWidgets('the overview is capped at four lines', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());

    final Text overview = tester.widget<Text>(
      find.byKey(const Key('series-overview')),
    );
    expect(overview.maxLines, 4);
    expect(overview.overflow, TextOverflow.ellipsis);
  });

  testWidgets(
    'scrolling past the hero turns the bar black and shows the title',
    (WidgetTester tester) async {
      await pumpSeries(tester, _library());

      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(const Key('series-title')))
            .opacity,
        0,
      );
      await tester.drag(
        find.byKey(const Key('series-scroll')),
        const Offset(0, -520),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(const Key('series-title')))
            .opacity,
        1,
      );
      expect(find.byType(AppBottomNav), findsOneWidget);
    },
  );

  testWidgets('a wide surface constrains the content width', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library(), size: const Size(1280, 900));

    expect(find.byKey(const Key('series-wide-content')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('series-scroll')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing seasons say so without fetching episodes', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService empty = _library()
      ..seasonsBySeries = <String, List<MediaItem>>{'show': <MediaItem>[]};
    await pumpSeries(tester, empty);

    expect(find.text('暂无可观看的季'), findsOneWidget);
    expect(empty.episodeRequests, isEmpty);
    expect(find.byKey(const Key('series-play')), findsNothing);
  });

  testWidgets('an empty season says so and hides the play row', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService noEpisodes = _library()
      ..episodesBySeason = <String, List<MediaItem>>{'s1': <MediaItem>[]};
    await pumpSeries(tester, noEpisodes);

    expect(find.text('这一季暂无分集'), findsOneWidget);
    expect(find.byKey(const Key('series-play')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a load failure offers a retry that recovers', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library()
      ..failure = EmbyException(AppErrorCode.networkUnreachable);
    await pumpSeries(tester, library);

    expect(find.textContaining('无法连接服务器'), findsOneWidget);
    expect(library.detailRequests, hasLength(1));

    library.failure = null;
    await tester.tap(find.byKey(const Key('series-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('series-hero')), findsOneWidget);
    expect(find.byKey(const Key('series-play')), findsOneWidget);
  });

  testWidgets('a failed episode refresh keeps rows and exposes a retry', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeries(tester, library);

    await tester.tap(find.byKey(const Key('series-play')));
    await tester.pumpAndSettle();
    library.failure = EmbyException(AppErrorCode.forbidden);
    await tester.tap(find.text('结束本集'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('series-episodes-error')), findsOneWidget);
    expect(find.textContaining('权限'), findsOneWidget);

    library.failure = null;
    await tester.tap(find.byKey(const Key('series-episodes-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('series-episodes-error')), findsNothing);
    expect(find.byKey(const Key('series-current-episode')), findsOneWidget);
  });

  testWidgets('returning from the player refreshes the current episode', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeries(tester, library);
    await tester.tap(find.byKey(const Key('series-play')));
    await tester.pumpAndSettle();

    library.episodesBySeason['s1'] = <MediaItem>[
      _episode('e1', 1, name: '泥坑', played: true),
      _episode('e2', 2, name: '恐龙先生弄丢了', played: true),
      _episode('e3', 3, name: '最好的朋友', position: const Duration(minutes: 1)),
    ];
    await tester.tap(find.text('结束本集'));
    await tester.pumpAndSettle();

    expect(library.episodeRequests, hasLength(2));
    expect(
      tester.widget<Text>(find.byKey(const Key('series-current-episode'))).data,
      'S1E3：最好的朋友',
    );
    expect(find.text('继续 (剩余: 4分0秒)'), findsOneWidget);
  });

  testWidgets('a session expiry in the player skips the refresh', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeries(tester, library);
    await tester.tap(find.byKey(const Key('series-play')));
    await tester.pumpAndSettle();

    auth.current = null;
    await tester.tap(find.text('结束本集'));
    await tester.pumpAndSettle();
    expect(library.episodeRequests, hasLength(1));
  });

  testWidgets('401 redirects to login without further requests', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library()..unauthorized = true;
    await pumpSeries(tester, library);

    expect(find.text('登录入口'), findsOneWidget);
    expect(library.episodeRequests, isEmpty);
  });

  testWidgets('direct entry back falls back to the library', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());

    await tester.tap(find.byKey(const Key('series-back')));
    await tester.pumpAndSettle();
    expect(find.text('媒体库入口'), findsOneWidget);
  });

  testWidgets('system back from direct entry falls back to the library', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('媒体库入口'), findsOneWidget);
  });

  testWidgets('leaving during bootstrap starts no library requests', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    final Completer<void> bootstrapReady = Completer<void>();
    await pumpSeries(
      tester,
      library,
      bootstrapReady: bootstrapReady,
      settle: false,
      fromLibrary: true,
    );
    expect(find.byKey(const Key('app-loader')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    bootstrapReady.complete();
    await tester.pumpAndSettle();

    expect(find.text('媒体库入口'), findsOneWidget);
    expect(library.detailRequests, isEmpty);
    expect(library.seasonsRequests, isEmpty);
    expect(library.episodeRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a large text scale on a narrow surface does not overflow', (
    WidgetTester tester,
  ) async {
    await pumpSeries(
      tester,
      _library(),
      size: const Size(320, 720),
      textScaler: TextScaler.linear(1.5),
    );

    expect(find.byKey(const Key('series-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await scrollTo(tester, find.byKey(const Key('series-similar-m-1')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the hero is 1.05x wider than the screen with mixed metadata', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());
    final ColorScheme palette = Theme.of(
      tester.element(find.byKey(const Key('series-page'))),
    ).colorScheme;

    expect(
      tester.getSize(find.byKey(const Key('series-hero'))).height,
      closeTo(420 * 1.05, 0.5),
    );

    // The rating is a light-blue star with white digits, not a pill.
    expect(tester.widget(find.byKey(const Key('series-rating'))), isA<Row>());
    final Icon star = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('series-rating')),
        matching: find.byType(Icon),
      ),
    );
    expect(star.color, palette.primary);

    // The year range is plain white text.
    final Text year = tester.widget<Text>(find.byKey(const Key('series-year')));
    expect(year.data, '2004 - 现在');
    expect(year.style!.color, Colors.white);

    // The official rating and the season count are accent-outlined pills.
    for (final String key in <String>[
      'series-official-rating',
      'series-season-count',
    ]) {
      final Container pill = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration decoration = pill.decoration! as BoxDecoration;
      expect((decoration.border! as Border).top.color, palette.primary);
    }

    // Genre chips use the accent tint with accent copy.
    final Finder genre = find.byKey(const Key('series-genre-动画'));
    final Container chip = tester.widget<Container>(
      find.descendant(of: genre, matching: find.byType(Container)).first,
    );
    expect(
      (chip.decoration! as BoxDecoration).color,
      palette.primary.withValues(alpha: 0.18),
    );
    final Text chipText = tester.widget<Text>(
      find.descendant(of: genre, matching: find.byType(Text)),
    );
    expect(chipText.style!.color, palette.primary);
  });

  testWidgets('the play row matches Yamby geometry and colours', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());

    final Finder play = find.byKey(const Key('series-play'));
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
    final Text label = tester.widget<Text>(
      find.descendant(of: play, matching: find.text('继续 (剩余: 3分0秒)')),
    );
    expect(label.style!.color, Colors.white);

    final Finder chevron = find.byKey(const Key('series-episodes'));
    expect(tester.getSize(chevron), const Size(54, 56));
    expect(tester.getTopLeft(chevron).dx - tester.getTopRight(play).dx, 8);
  });

  testWidgets('the top bar uses plain icons and a heart with a plus', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeries(tester, library);

    final Finder favorite = find.byKey(const Key('series-favorite'));
    expect(tester.getSize(favorite), const Size(48, 48));
    expect(
      find.descendant(
        of: favorite,
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: favorite, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    // No circular material background behind the action.
    expect(
      find.descendant(of: favorite, matching: find.byType(Material)),
      findsNothing,
    );

    await tester.tap(favorite);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: favorite, matching: find.byIcon(Icons.favorite)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: favorite, matching: find.byIcon(Icons.add)),
      findsNothing,
    );
  });

  testWidgets('继续观看 also previews the next unstarted episode', (
    WidgetTester tester,
  ) async {
    await pumpSeries(tester, _library());
    await scrollTo(tester, find.byKey(const Key('series-resumable')));

    // e2/e3 are in progress; e4 is the next unstarted episode.
    expect(find.byKey(const Key('series-resume-e2')), findsOneWidget);
    expect(find.byKey(const Key('series-resume-e3')), findsOneWidget);
    expect(find.byKey(const Key('series-resume-e4')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('series-resume-e2'))).width,
      closeTo(420 * 0.46, 0.5),
    );
    // The unstarted card shows the full duration instead of a remaining time.
    expect(find.text('5分0秒'), findsOneWidget);
  });

  testWidgets('the play row unlocks when the player replaces its own route', (
    WidgetTester tester,
  ) async {
    final FakeLibraryService library = _library();
    await pumpSeries(tester, library);

    await tester.tap(find.byKey(const Key('series-play')));
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e2']);
    // The page is covered while the player runs; the return watcher notices.
    await tester.pump(const Duration(seconds: 1));

    // The player's auto-next replaces the player route with another one, so
    // the original push future never completes.
    await tester.tap(find.text('播放下一集'));
    await tester.pumpAndSettle();
    expect(openedEpisodes, <String>['e2', 'next:e4']);

    library.episodesBySeason['s1'] = <MediaItem>[
      _episode('e1', 1, name: '泥坑', played: true),
      _episode('e2', 2, name: '恐龙先生弄丢了', played: true),
      _episode('e3', 3, name: '最好的朋友', position: const Duration(minutes: 1)),
      _episode('e4', 4, name: '鹦鹉波莉'),
    ];
    await tester.tap(find.text('结束本集'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final SeriesPlayButton play = tester.widget<SeriesPlayButton>(
      find.byKey(const Key('series-play')),
    );
    expect(play.onPressed, isNotNull);
    expect(library.episodeRequests.length, greaterThan(1));
    expect(
      tester.widget<Text>(find.byKey(const Key('series-current-episode'))).data,
      'S1E3：最好的朋友',
    );
  });

  testWidgets(
    'a season page pushed from a hidden-nav series page shows the nav',
    (WidgetTester tester) async {
      await pumpSeries(tester, _library());
      final Finder nav = find.byKey(const Key('nav-capsule-slide'));
      await scrollTo(tester, find.byKey(const Key('season-s1')));
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('series-page'))),
      );
      // Simulate the capsule hidden by a downward scroll on the series page.
      container.read(navVisibleProvider.notifier).set(false);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedSlide>(nav).offset, isNot(Offset.zero));

      await tester.tap(find.byKey(const Key('season-s1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('season-page')), findsOneWidget);
      expect(tester.widget<AnimatedSlide>(nav).offset, Offset.zero);
    },
  );
}
