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
import 'package:media_player/data/moviepilot/models/moviepilot_config.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_season.dart';
import 'package:media_player/data/moviepilot/moviepilot_service.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/moviepilot_config_store.dart';
import 'package:media_player/features/request/request_page.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_moviepilot_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';
import '../../support/fake_poster_cache.dart';

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

  /// The router of the page under test, so navigation can be asserted.
  GoRouter? router;

  Future<void> pumpPage(
    WidgetTester tester, {
    bool configured = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    if (configured) {
      await MoviePilotConfigStore(store).write(
        const MoviePilotConfig(
          baseUrl: 'http://nas:3002',
          username: 'admin',
          accessToken: 'token',
        ),
      );
    }

    router = GoRouter(
      initialLocation: '/request',
      routes: <RouteBase>[
        GoRoute(path: '/request', builder: (_, _) => const RequestPage()),
        GoRoute(
          path: '/request/mine',
          builder: (_, _) => const Text('mine page'),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Text('settings page'),
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
              posters: FakePosterCache(),
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
          // An empty heartbeat keeps rounds from firing while the test drives
          // the page; the controller still runs its first round from load().
          requestHeartbeatProvider.overrideWithValue(_silentHeartbeat),
        ],
        child: MaterialApp.router(routerConfig: router),
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
    // A new request opens the progress page, where its card lives now.
    expect(router!.state.matchedLocation, '/request/mine');
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
    expect(router!.state.matchedLocation, '/request/mine');
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

    // No subscription is created; the record comes back playable and the
    // progress page shows it with 去播放.
    expect(service.createRequests, isEmpty);
    expect(router!.state.matchedLocation, '/request/mine');
  });

}
