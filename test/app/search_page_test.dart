import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/router.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/core/router/app_routes.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/library_view.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/server_profile.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';

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
  late FakeLibraryService library;
  late FakePlaybackEngine engine;

  setUp(() {
    library = FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: <MediaItem>[fakeItem('m-0', name: '库内影片')],
      },
    );
    engine = FakePlaybackEngine();
  });

  Future<void> pumpSearch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: StaticAuth(),
              library: library,
              posters: FakePosterCache(),
              playback: FakePlaybackService(),
              createEngine: () => engine,
              createReporter: FakePlaybackReporter.new,
            ),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
    // P1: land on home, then open the library to reach its search action.
    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.library);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-search')));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String term) async {
    await tester.enterText(find.byKey(const Key('search-field')), term);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets('the library action opens the search page', (tester) async {
    await pumpSearch(tester);

    expect(find.byKey(const Key('search-field')), findsOneWidget);
    expect(find.text('输入名称搜索电影 / 剧集'), findsOneWidget);
  });

  testWidgets('a settled query shows matching posters', (tester) async {
    library.searchResults = <MediaItem>[
      fakeItem('s-1', name: '冰海战记'),
      fakeItem('m-1', name: '冰海战记 剧场版'),
    ];
    await pumpSearch(tester);

    await type(tester, '冰海');

    expect(library.searchRequests.single.term, '冰海');
    expect(find.text('冰海战记'), findsOneWidget);
    expect(find.text('冰海战记 剧场版'), findsOneWidget);
  });

  testWidgets('the type chips cover 合集 and 演员 and narrow the request', (
    tester,
  ) async {
    library.searchResults = <MediaItem>[
      fakeItem('s-1', name: '冰海战记'),
      const MediaItem(id: 'box-1', name: '合集一', type: 'BoxSet'),
      const MediaItem(id: 'per-1', name: '演员一', type: 'Person'),
    ];
    await pumpSearch(tester);
    await type(tester, '冰海');

    expect(find.byKey(const Key('search-filter-collections')), findsOneWidget);
    expect(find.byKey(const Key('search-filter-persons')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-filter-collections')));
    await tester.pumpAndSettle();
    expect(library.searchRequests.last.types, 'BoxSet');

    await tester.tap(find.byKey(const Key('search-filter-persons')));
    await tester.pumpAndSettle();
    // S50: the types stack instead of replacing each other.
    expect(library.searchRequests.last.types, 'BoxSet,Person');
  });

  testWidgets('a person result opens their filmography', (tester) async {
    library.searchResults = <MediaItem>[
      const MediaItem(id: 'per-1', name: '演员一', type: 'Person'),
    ];
    library.personItemsById['per-1'] = <MediaItem>[
      fakeItem('m-1', name: '演员作品一'),
    ];
    await pumpSearch(tester);
    await type(tester, '演员');
    await tester.tap(find.byKey(const Key('search-filter-persons')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('演员一'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-page')), findsOneWidget);
    expect(library.personItemRequests, contains('per-1'));
    expect(find.text('演员作品一'), findsOneWidget);
  });

  testWidgets('a collection result opens its children', (tester) async {
    library.searchResults = <MediaItem>[
      const MediaItem(id: 'box-1', name: '合集一', type: 'BoxSet'),
    ];
    library.collectionItemsById['box-1'] = <MediaItem>[
      fakeItem('m-2', name: '合集影片一'),
    ];
    await pumpSearch(tester);
    await type(tester, '合集');
    await tester.tap(find.byKey(const Key('search-filter-collections')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('合集一'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('collection-page')), findsOneWidget);
    expect(library.collectionItemRequests, contains('box-1'));
    expect(find.text('合集影片一'), findsOneWidget);
  });
  testWidgets('the type chip narrows the request', (tester) async {
    library.searchResults = <MediaItem>[
      const MediaItem(id: 's-1', name: '冰海战记', type: 'Series'),
      fakeItem('m-1', name: '冰海战记 剧场版'),
    ];
    await pumpSearch(tester);
    await type(tester, '冰海');

    await tester.tap(find.byKey(const Key('search-filter-series')));
    await tester.pumpAndSettle();

    expect(library.searchRequests.last.types, 'Series');
    expect(find.text('冰海战记'), findsOneWidget);
    expect(find.text('冰海战记 剧场版'), findsNothing);
  });

  testWidgets('a series result opens the series page', (tester) async {
    library.searchResults = <MediaItem>[
      const MediaItem(id: 's-1', name: '冰海战记', type: 'Series'),
    ];
    await pumpSearch(tester);
    await type(tester, '冰海');

    await tester.tap(find.text('冰海战记'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('series-back')), findsOneWidget);
  });

  testWidgets('a movie result opens the detail page, then play starts it', (
    tester,
  ) async {
    library.searchResults = <MediaItem>[fakeItem('m-1', name: '冰海战记 剧场版')];
    library.itemsById = <String, MediaItem>{
      'm-1': fakeItem('m-1', name: '冰海战记 剧场版'),
    };
    await pumpSearch(tester);
    await type(tester, '冰海');

    await tester.tap(find.text('冰海战记 剧场版'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-title')), findsOneWidget);
    expect(find.byKey(const Key('detail-play')), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-play')));
    await tester.pumpAndSettle();
    // Past the §10.9 f verdict probe so no timer outlives the test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
    expect(engine.openedPlans.single.itemId, 'm-1');
  });

  testWidgets('no match states the query', (tester) async {
    await pumpSearch(tester);

    await type(tester, '不存在的片子');

    expect(find.text('没有找到「不存在的片子」'), findsOneWidget);
  });

  testWidgets('clearing the field offers recent terms', (tester) async {
    library.searchResults = <MediaItem>[fakeItem('m-1', name: '冰海战记 剧场版')];
    await pumpSearch(tester);
    await type(tester, '冰海');

    await type(tester, '');

    final chip = find.byKey(const Key('search-history-冰海'));
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(library.searchRequests.last.term, '冰海');
    expect(find.text('冰海战记 剧场版'), findsOneWidget);
  });

  testWidgets('history entries can be removed and cleared (S52)', (
    tester,
  ) async {
    library.searchResults = <MediaItem>[fakeItem('m-1', name: '冰海战记 剧场版')];
    await pumpSearch(tester);
    await type(tester, '冰海');
    await type(tester, '冰之');
    await type(tester, '');

    expect(find.byKey(const Key('search-history-冰海')), findsOneWidget);
    expect(find.byKey(const Key('search-history-冰之')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-history-remove-冰海')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-history-冰海')), findsNothing);
    expect(find.byKey(const Key('search-history-冰之')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-history-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-history-冰之')), findsNothing);
    expect(find.text('输入名称搜索电影 / 剧集'), findsOneWidget);
  });

  testWidgets('results are grouped by type (S61)', (tester) async {
    // A tall surface keeps all three sections inside the lazy list's cache.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    library.searchResults = <MediaItem>[
      fakeItem('m-1', name: '冰海战记 剧场版'),
      const MediaItem(id: 's-1', name: '冰海战记', type: 'Series'),
      const MediaItem(id: 'per-1', name: '演员一', type: 'Person'),
    ];
    await pumpSearch(tester);
    await type(tester, '冰海');

    expect(find.byKey(const Key('search-group-Movie')), findsOneWidget);
    expect(find.byKey(const Key('search-group-Series')), findsOneWidget);
    expect(find.byKey(const Key('search-group-Person')), findsOneWidget);

    // Sections stay in Yamby's order: 电影 then 剧集 then 演员.
    final double movies = tester
        .getTopLeft(find.byKey(const Key('search-group-Movie')))
        .dy;
    final double series = tester
        .getTopLeft(find.byKey(const Key('search-group-Series')))
        .dy;
    final double people = tester
        .getTopLeft(find.byKey(const Key('search-group-Person')))
        .dy;
    expect(movies, lessThan(series));
    expect(series, lessThan(people));
  });

  testWidgets('a search failure shows copy with a retry', (tester) async {
    library.searchFailure = Exception('socket closed');
    await pumpSearch(tester);

    await type(tester, '冰海');

    expect(find.text('搜索失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);

    library.searchFailure = null;
    library.searchResults = <MediaItem>[fakeItem('m-1', name: '冰海战记 剧场版')];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('冰海战记 剧场版'), findsOneWidget);
  });
}
