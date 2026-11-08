import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/library_view.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/playback_engine.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';

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
    FakePlaybackEngine Function()? createEngine,
    FakePlaybackReporter Function()? createReporter,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: StaticAuth(),
              library: library,
              playback: playback ?? FakePlaybackService(),
              createEngine: createEngine ?? FakePlaybackEngine.new,
              createReporter: createReporter ?? FakePlaybackReporter.new,
            ),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
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

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Movies'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Shows'), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
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
      final library = buildService(movies: 1, shows: 30);
      const seriesId = 's16';
      library.seasonsBySeries[seriesId] = const [
        MediaItem(id: 'season-2', name: '第二季', type: 'Season', indexNumber: 2),
        MediaItem(id: 'specials', name: '特别篇', type: 'Season', indexNumber: 0),
        MediaItem(id: 'season-1', name: '第一季', type: 'Season', indexNumber: 1),
      ];
      library.episodesBySeason['season-1'] = const [
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
      await tester.tap(find.byKey(const ValueKey('season-season-2')));
      await tester.pumpAndSettle();
      final episodeScrollable = find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('episode-e75')),
        500,
        scrollable: episodeScrollable,
      );
      await tester.pumpAndSettle();
      final episodeOffset = tester
          .state<ScrollableState>(episodeScrollable)
          .position
          .pixels;
      await tester.tap(find.byKey(const ValueKey('episode-e75')));
      await tester.tap(find.byKey(const ValueKey('episode-e75')));
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
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('season-season-2')))
            .selected,
        isTrue,
      );
      expect(
        tester.state<ScrollableState>(episodeScrollable).position.pixels,
        episodeOffset,
      );
      expect(find.textContaining('已观看 02:30'), findsOneWidget);
      expect(engines.first.disposeCalls, 1);

      await tester.ensureVisible(find.byKey(const ValueKey('episode-e76')));
      await tester.tap(find.byKey(const ValueKey('episode-e76')));
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
      await tester.tap(find.byKey(const Key('series-back')));
      await tester.pumpAndSettle();
      expect(find.text('媒体库'), findsOneWidget);
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
    expect(library.itemCalls, 1);

    await tester.drag(find.byType(GridView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(library.itemCalls, greaterThanOrEqualTo(2));
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
}
