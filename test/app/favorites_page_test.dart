import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/ui/app_controls.dart';
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

  Future<void> pumpFavorites(WidgetTester tester) async {
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
    // P1: land on home, then open the library to reach its favorites action.
    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.library);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-favorites')));
    await tester.pumpAndSettle();
  }

  testWidgets('the shuffle action opens a random favorite (S71)', (
    tester,
  ) async {
    await pumpFavorites(tester);

    final Finder shuffle = find.byKey(const Key('favorites-random'));
    expect(shuffle, findsOneWidget);
    // Empty list disables the action.
    final AppIconButton button = tester.widget<AppIconButton>(shuffle);
    expect(button.onPressed, isNull);
  });

  testWidgets('the library action opens the favorites page', (tester) async {
    library.favoriteResults = <MediaItem>[fakeItem('m-1', name: '收藏影片')];
    await pumpFavorites(tester);

    expect(find.byKey(const Key('favorites-filter-all')), findsOneWidget);
    expect(find.text('收藏影片'), findsOneWidget);
    expect(
      library.favoritesRequests.single.types,
      'Movie,Series,BoxSet,Person',
    );
  });

  testWidgets('the type tab narrows the request and the grid', (tester) async {
    library.favoriteResults = <MediaItem>[
      fakeItem('m-1', name: '收藏电影'),
      const MediaItem(id: 's-1', name: '收藏剧集', type: 'Series'),
    ];
    await pumpFavorites(tester);
    expect(find.text('收藏电影'), findsOneWidget);
    expect(find.text('收藏剧集'), findsOneWidget);

    await tester.tap(find.byKey(const Key('favorites-filter-series')));
    await tester.pumpAndSettle();

    expect(library.favoritesRequests.last.types, 'Series');
    expect(find.text('收藏剧集'), findsOneWidget);
    expect(find.text('收藏电影'), findsNothing);
  });

  testWidgets('the toolbar shows the count, view switch and sort label', (
    tester,
  ) async {
    library.favoriteResults = <MediaItem>[fakeItem('m-1', name: '收藏影片')];
    await pumpFavorites(tester);

    expect(find.byKey(const Key('favorites-count')), findsOneWidget);
    expect(find.text('1 项'), findsOneWidget);
    expect(find.byKey(const Key('favorites-view-toggle')), findsOneWidget);
    expect(find.byKey(const Key('favorites-sort')), findsOneWidget);
    expect(find.text('创建日期 ↓'), findsOneWidget);
  });

  testWidgets('the 合集 and 演员 tabs request BoxSet and Person', (tester) async {
    library.favoriteResults = <MediaItem>[
      fakeItem('m-1', name: '收藏影片'),
      const MediaItem(id: 'box-1', name: '收藏合集', type: 'BoxSet'),
      const MediaItem(id: 'per-1', name: '收藏演员', type: 'Person'),
    ];
    await pumpFavorites(tester);

    await tester.tap(find.byKey(const Key('favorites-filter-collections')));
    await tester.pumpAndSettle();
    expect(library.favoritesRequests.last.types, 'BoxSet');
    expect(find.text('收藏合集'), findsOneWidget);

    await tester.tap(find.byKey(const Key('favorites-filter-persons')));
    await tester.pumpAndSettle();
    expect(library.favoritesRequests.last.types, 'Person');
    expect(find.text('收藏演员'), findsOneWidget);
  });

  testWidgets('the list view renders compact rows', (tester) async {
    library.favoriteResults = <MediaItem>[fakeItem('m-1', name: '收藏影片')];
    await pumpFavorites(tester);

    await tester.tap(find.byKey(const Key('favorites-view-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('favorite-row-m-1')), findsOneWidget);
    expect(find.text('收藏影片'), findsOneWidget);
  });

  testWidgets('the filter dialog narrows the query and shows an active tag', (
    tester,
  ) async {
    library.favoriteResults = <MediaItem>[fakeItem('m-1', name: '收藏影片')];
    library.genreNames = const <String>['动作', '喜剧'];
    await pumpFavorites(tester);

    await tester.tap(find.byKey(const Key('favorites-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorites-genre-动作')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorites-filter-apply')));
    await tester.pumpAndSettle();

    expect(library.favoritesRequests.last.genre, '动作');
    expect(
      find.byKey(const Key('favorites-filter-genre-active')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('favorites-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorites-filter-clear')));
    await tester.pumpAndSettle();
    expect(library.favoritesRequests.last.genre, isNull);
    expect(
      find.byKey(const Key('favorites-filter-genre-active')),
      findsNothing,
    );
  });

  testWidgets('fullscreen hides the app bar and the exit restores it', (
    tester,
  ) async {
    library.favoriteResults = <MediaItem>[fakeItem('m-1', name: '收藏影片')];
    await pumpFavorites(tester);

    await tester.tap(find.byKey(const Key('favorites-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('favorites-fullscreen-exit')), findsOneWidget);

    await tester.tap(find.byKey(const Key('favorites-fullscreen-exit')));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('favorites-fullscreen-exit')), findsNothing);
  });
  testWidgets('the sort picker changes the query', (tester) async {
    library.favoriteResults = <MediaItem>[fakeItem('m-1', name: '收藏影片')];
    await pumpFavorites(tester);
    expect(library.favoritesRequests.last.sortBy, 'DateCreated');

    await tester.tap(find.byKey(const Key('favorites-sort')));
    await tester.pumpAndSettle();
    // S70: the field list scrolls now, so bring the target into view.
    await tester.scrollUntilVisible(
      find.byKey(const Key('favorites-sort-dateAdded')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorites-sort-dateAdded')));
    await tester.pumpAndSettle();

    expect(library.favoritesRequests.last.sortBy, 'DateCreated');
    expect(library.favoritesRequests.last.sortOrder, 'Descending');
  });

  testWidgets('a series favorite opens the series page', (tester) async {
    library.favoriteResults = <MediaItem>[
      const MediaItem(id: 's-1', name: '收藏剧集', type: 'Series'),
    ];
    await pumpFavorites(tester);

    await tester.tap(find.text('收藏剧集'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('series-back')), findsOneWidget);
  });

  testWidgets('a movie favorite opens the detail page, then play starts it', (
    tester,
  ) async {
    library.favoriteResults = <MediaItem>[fakeItem('m-1', name: '收藏电影')];
    library.itemsById = <String, MediaItem>{
      'm-1': fakeItem('m-1', name: '收藏电影'),
    };
    await pumpFavorites(tester);

    await tester.tap(find.text('收藏电影'));
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

  testWidgets('an empty favorites list shows the empty state', (tester) async {
    library.favoriteResults = const <MediaItem>[];
    await pumpFavorites(tester);

    expect(find.text('还没有收藏任何影片'), findsOneWidget);
  });
}
