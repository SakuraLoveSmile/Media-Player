import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/features/series/series_page.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';

class _Auth implements AuthService {
  @override
  AuthSession? current = const AuthSession(
    userId: 'user',
    userName: 'Test',
    accessToken: 'fake-token',
    deviceId: 'device',
  );

  final events = StreamController<AuthSession?>.broadcast();

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

const _series = MediaItem(
  id: 'show',
  name: '测试剧集',
  type: 'Series',
  overview: '剧集简介',
);
const _firstSeason = MediaItem(
  id: 's1',
  name: '第一季',
  type: 'Season',
  indexNumber: 1,
);
const _secondSeason = MediaItem(
  id: 's2',
  name: '第二季',
  type: 'Season',
  indexNumber: 2,
);
const _specials = MediaItem(
  id: 's0',
  name: '特别篇',
  type: 'Season',
  indexNumber: 0,
);

MediaItem _episode(String id, String name, {int? number, bool played = false}) {
  return MediaItem(
    id: id,
    name: name,
    type: 'Episode',
    indexNumber: number,
    runTimeTicks: const Duration(minutes: 45).inMicroseconds * 10,
    userData: UserItemData(
      played: played,
      positionTicks: const Duration(minutes: 2).inMicroseconds * 10,
    ),
  );
}

FakeLibraryService _library() => FakeLibraryService(
  itemsById: {'show': _series},
  seasonsBySeries: {
    'show': [_secondSeason, _specials, _firstSeason],
  },
  episodesBySeason: {
    's1': [_episode('e1', '开场', number: 1)],
    's2': [_episode('e2', '重逢', number: 1)],
    's0': [_episode('special', '幕后花絮')],
  },
);

class _DelayedLibrary extends FakeLibraryService {
  _DelayedLibrary()
    : super(
        itemsById: {'show': _series},
        seasonsBySeries: {
          'show': [_firstSeason, _secondSeason],
        },
        episodesBySeason: {
          's1': [_episode('e1', '开场', number: 1)],
        },
      );

  final secondSeason = Completer<List<MediaItem>>();

  @override
  Future<List<MediaItem>> episodes({
    required String seriesId,
    required String seasonId,
  }) {
    if (seasonId == 's2') {
      episodeRequests.add((seriesId: seriesId, seasonId: seasonId));
      return secondSeason.future;
    }
    return super.episodes(seriesId: seriesId, seasonId: seasonId);
  }
}

class _RefreshLibrary extends FakeLibraryService {
  _RefreshLibrary()
    : super(
        itemsById: {'show': _series},
        seasonsBySeries: {
          'show': [_firstSeason],
        },
        episodesBySeason: {
          's1': [_episode('e1', '开场', number: 1)],
        },
      );

  Completer<List<MediaItem>>? nextEpisodes;

  @override
  Future<List<MediaItem>> episodes({
    required String seriesId,
    required String seasonId,
  }) {
    final pending = nextEpisodes;
    if (pending == null) {
      return super.episodes(seriesId: seriesId, seasonId: seasonId);
    }
    episodeRequests.add((seriesId: seriesId, seasonId: seasonId));
    return pending.future;
  }
}

void main() {
  late _Auth auth;
  late GoRouter router;
  late List<String> openedEpisodes;

  setUp(() {
    auth = _Auth();
    openedEpisodes = [];
  });

  tearDown(() async {
    router.dispose();
    await auth.events.close();
  });

  Future<void> pumpSeries(
    WidgetTester tester,
    FakeLibraryService library, {
    Completer<void>? bootstrapReady,
    bool settle = true,
    bool fromLibrary = false,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    router = GoRouter(
      initialLocation: fromLibrary ? '/library' : '/series/show',
      routes: [
        GoRoute(
          path: '/series/:seriesId',
          builder: (_, state) =>
              SeriesPage(seriesId: state.pathParameters['seriesId']!),
        ),
        GoRoute(
          path: '/player/:itemId',
          builder: (context, state) {
            openedEpisodes.add(state.pathParameters['itemId']!);
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
          builder: (_, _) => const Scaffold(body: Text('媒体库入口')),
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
          bootstrapProvider.overrideWith((ref) async {
            await bootstrapReady?.future;
            return AppServices(
              auth: auth,
              library: library,
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
            );
          }),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
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

  testWidgets('shows real season and episode types with viewing metadata', (
    tester,
  ) async {
    final library = _library();
    await pumpSeries(tester, library);

    expect(find.text('测试剧集'), findsOneWidget);
    expect(find.text('剧集简介'), findsOneWidget);
    expect(find.text('第 1 集 · 开场'), findsOneWidget);
    expect(find.text('时长 45:00 · 已观看 02:00'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('season-s1')))
          .selected,
      isTrue,
    );
    expect(library.episodeRequests, [(seriesId: 'show', seasonId: 's1')]);

    await tester.tap(find.byKey(const ValueKey('season-s0')));
    await tester.pumpAndSettle();
    expect(find.text('幕后花絮'), findsOneWidget);
    expect(find.text('第 1 集 · 开场'), findsNothing);
  });

  testWidgets(
    'selects a season, pushes its episode once and refreshes on return',
    (tester) async {
      final library = _library();
      await pumpSeries(tester, library);
      await tester.tap(find.byKey(const ValueKey('season-s2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('episode-e2')));
      await tester.tap(find.byKey(const ValueKey('episode-e2')));
      await tester.pumpAndSettle();
      expect(openedEpisodes, ['e2']);

      library.episodesBySeason['s2'] = [
        _episode('e2', '重逢', number: 1, played: true),
      ];
      await tester.tap(find.text('结束本集'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('season-s2')))
            .selected,
        isTrue,
      );
      expect(find.text('时长 45:00 · 已看 · 已观看 02:00'), findsOneWidget);
      expect(
        library.episodeRequests.where((r) => r.seasonId == 's2').length,
        2,
      );
    },
  );

  testWidgets('clears old episodes while a new season request is pending', (
    tester,
  ) async {
    final library = _DelayedLibrary();
    await pumpSeries(tester, library);
    await tester.tap(find.byKey(const ValueKey('season-s2')));
    await tester.pump();
    expect(find.text('第 1 集 · 开场'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    library.secondSeason.complete([_episode('e2', '重逢', number: 1)]);
    await tester.pumpAndSettle();
    expect(find.text('第 1 集 · 重逢'), findsOneWidget);
  });

  testWidgets('an episode row can be focused and played with the keyboard', (
    tester,
  ) async {
    await pumpSeries(tester, _library());
    const episodeKey = ValueKey('episode-e1');
    ListTile? focusedEpisode() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<ListTile>();

    for (
      var step = 0;
      step < 12 && focusedEpisode()?.key != episodeKey;
      step++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusedEpisode()?.key, episodeKey);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(openedEpisodes, ['e1']);
  });

  testWidgets('shows missing seasons without pretending there are episodes', (
    tester,
  ) async {
    final library = _library()..seasonsBySeries = {'show': []};
    await pumpSeries(tester, library);
    expect(find.text('暂无可观看的季'), findsOneWidget);
    expect(library.episodeRequests, isEmpty);
  });

  testWidgets('shows an empty selected season', (tester) async {
    final library = _library()..episodesBySeason = {};
    await pumpSeries(tester, library);
    expect(find.text('这一季暂无分集'), findsOneWidget);
  });

  testWidgets('shows a load failure and retries only on request', (
    tester,
  ) async {
    final library = _library()
      ..failure = EmbyException(AppErrorCode.networkUnreachable);
    await pumpSeries(tester, library);
    expect(find.textContaining('无法连接服务器'), findsOneWidget);
    expect(find.text('暂无可观看的季'), findsNothing);
    expect(library.detailRequests, hasLength(1));

    library.failure = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('episode-e1')), findsOneWidget);
  });

  testWidgets('episode failures remain errors and can be retried manually', (
    tester,
  ) async {
    final library = _library();
    await pumpSeries(tester, library);
    library.failure = EmbyException(AppErrorCode.forbidden);
    await tester.tap(find.byKey(const ValueKey('season-s2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('权限'), findsOneWidget);
    expect(find.text('这一季暂无分集'), findsNothing);
    final calls = library.episodeRequests.length;
    await tester.pump();
    expect(library.episodeRequests, hasLength(calls));

    library.failure = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('episode-e2')), findsOneWidget);
  });

  testWidgets(
    'narrow long titles remain usable and the last of 75 episodes is reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final longName = List.filled(12, '很长的季名称').join();
      final library = _library()
        ..seasonsBySeries = {
          'show': [
            MediaItem(id: 's1', name: longName, type: 'Season', indexNumber: 1),
          ],
        }
        ..episodesBySeason = {
          's1': List.generate(
            75,
            (index) => _episode(
              'long-$index',
              '${List.filled(10, '很长的分集名称').join()} $index',
              number: index + 1,
            ),
          ),
        };
      await pumpSeries(tester, library);
      expect(find.text(longName), findsOneWidget);
      expect(tester.takeException(), isNull);
      final vertical = find.descendant(
        of: find.byKey(const PageStorageKey('episodes-show-s1')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('episode-long-74')),
        500,
        scrollable: vertical,
        maxScrolls: 30,
      );
      expect(find.byKey(const ValueKey('episode-long-74')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('episode-long-74')));
      await tester.pumpAndSettle();
      expect(openedEpisodes, ['long-74']);
      await tester.tap(find.text('结束本集'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('episode-long-74')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('direct entry back falls back to library', (tester) async {
    await pumpSeries(tester, _library());
    await tester.tap(find.byKey(const Key('series-back')));
    await tester.pumpAndSettle();
    expect(find.text('媒体库入口'), findsOneWidget);
  });

  testWidgets('switching seasons restores each season scroll position', (
    tester,
  ) async {
    final library = _library()
      ..episodesBySeason = {
        for (final seasonId in ['s1', 's2'])
          seasonId: List.generate(
            40,
            (index) => _episode(
              '$seasonId-$index',
              '$seasonId 分集 $index',
              number: index + 1,
            ),
          ),
      };
    await pumpSeries(tester, library);

    Finder episodeList(String seasonId) =>
        find.byKey(PageStorageKey('episodes-show-$seasonId'));
    double scrollOffset(String seasonId) =>
        tester.widget<ListView>(episodeList(seasonId)).controller!.offset;

    await tester.drag(episodeList('s1'), const Offset(0, -600));
    await tester.pumpAndSettle();
    final firstOffset = scrollOffset('s1');
    expect(firstOffset, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('season-s2')));
    await tester.pumpAndSettle();
    expect(scrollOffset('s2'), 0);
    await tester.drag(episodeList('s2'), const Offset(0, -400));
    await tester.pumpAndSettle();
    final secondOffset = scrollOffset('s2');
    expect(secondOffset, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('season-s1')));
    await tester.pumpAndSettle();
    expect(scrollOffset('s1'), closeTo(firstOffset, 0.1));

    await tester.tap(find.byKey(const ValueKey('season-s2')));
    await tester.pumpAndSettle();
    expect(scrollOffset('s2'), closeTo(secondOffset, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back from direct entry falls back to library', (
    tester,
  ) async {
    await pumpSeries(tester, _library());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('媒体库入口'), findsOneWidget);
  });

  testWidgets('leaving during bootstrap does not start library requests', (
    tester,
  ) async {
    final library = _library();
    final bootstrapReady = Completer<void>();
    await pumpSeries(
      tester,
      library,
      bootstrapReady: bootstrapReady,
      settle: false,
      fromLibrary: true,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

  testWidgets('return refresh preserves rows and exposes a retryable failure', (
    tester,
  ) async {
    final library = _RefreshLibrary();
    await pumpSeries(tester, library);
    await tester.tap(find.byKey(const ValueKey('episode-e1')));
    await tester.pumpAndSettle();

    final refresh = Completer<List<MediaItem>>();
    library.nextEpisodes = refresh;
    await tester.tap(find.text('结束本集'));
    await tester.pump();
    expect(library.episodeRequests, hasLength(2));
    expect(find.byKey(const ValueKey('episode-e1')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    refresh.completeError(EmbyException(AppErrorCode.networkUnreachable));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('episode-e1')), findsOneWidget);
    expect(find.textContaining('无法连接服务器'), findsOneWidget);
    expect(find.text('这一季暂无分集'), findsNothing);

    library.nextEpisodes = null;
    library.episodesBySeason['s1'] = [
      _episode('e1', '开场', number: 1, played: true),
    ];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('时长 45:00 · 已看 · 已观看 02:00'), findsOneWidget);
    expect(library.episodeRequests, hasLength(3));
  });

  testWidgets('narrow rows allow wrapped progress at a larger text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = _library()
      ..episodesBySeason['s1'] = [
        _episode('e1', List.filled(12, '很长的分集名称').join(), played: true),
      ];
    await pumpSeries(tester, library, textScaler: TextScaler.linear(1.5));
    expect(find.text('时长 45:00 · 已看 · 已观看 02:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('episode-e1')));
    await tester.pumpAndSettle();
    expect(openedEpisodes, ['e1']);
  });

  testWidgets(
    'does not refresh episodes if the session expires in the player',
    (tester) async {
      final library = _library();
      await pumpSeries(tester, library);
      await tester.tap(find.byKey(const ValueKey('episode-e1')));
      await tester.pumpAndSettle();
      auth.current = null;
      await tester.tap(find.text('结束本集'));
      await tester.pumpAndSettle();
      expect(library.episodeRequests, hasLength(1));
    },
  );

  testWidgets('401 redirects to login without refresh', (tester) async {
    final library = _library()..unauthorized = true;
    await pumpSeries(tester, library);
    expect(find.text('登录入口'), findsOneWidget);
    expect(library.episodeRequests, isEmpty);
  });

  testWidgets(
    'a replaced valid session cannot refresh the previous user data',
    (tester) async {
      final library = _library();
      await pumpSeries(tester, library);
      await tester.tap(find.byKey(const ValueKey('episode-e1')));
      await tester.pumpAndSettle();
      auth.current = const AuthSession(
        userId: 'another-user',
        userName: 'Another test user',
        accessToken: 'another-fake-token',
        deviceId: 'device',
      );
      await tester.tap(find.text('结束本集'));
      await tester.pumpAndSettle();
      expect(library.episodeRequests, hasLength(1));
    },
  );

  testWidgets('session invalidation in the player redirects without refresh', (
    tester,
  ) async {
    final library = _library();
    await pumpSeries(tester, library);
    await tester.tap(find.byKey(const ValueKey('episode-e1')));
    await tester.pumpAndSettle();
    await auth.handleUnauthorized();
    await tester.pumpAndSettle();
    expect(find.text('登录入口'), findsOneWidget);
    expect(library.episodeRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing the episode browser route does not refresh it', (
    tester,
  ) async {
    final library = _library();
    await pumpSeries(tester, library);
    await tester.tap(find.byKey(const ValueKey('episode-e1')));
    await tester.pumpAndSettle();
    router.go('/library');
    await tester.pumpAndSettle();
    expect(find.text('媒体库入口'), findsOneWidget);
    expect(library.episodeRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
