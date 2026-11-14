import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

/// S15 tablet / wide-screen adaptive layout: browse grids change their column
/// count with the surface width, the library gains a master-detail preview
/// pane at >=900 and the detail page switches to a capped two-column layout.
void main() {
  const Size narrow = Size(400, 800);
  const Size wide = Size(1200, 800);

  late FakeLibraryService library;
  late FakePlaybackService playback;
  late FakePlaybackEngine engine;

  setUp(() {
    library = FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: List<MediaItem>.generate(
          70,
          (index) => fakeItem('${index + 1}'),
        ),
      },
    );
    playback = FakePlaybackService();
    engine = FakePlaybackEngine();
  });

  void setSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: StaticAuth(),
              library: library,
              posters: FakePosterCache(),
              playback: playback,
              createEngine: () => engine,
              createReporter: FakePlaybackReporter.new,
            ),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  GoRouter routerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
          .read(appRouterProvider);

  Future<void> pumpLibrary(WidgetTester tester, Size size) async {
    setSurface(tester, size);
    await pumpApp(tester);
    routerOf(tester).go(AppRoutes.library);
    await tester.pumpAndSettle();
  }

  int gridColumns(WidgetTester tester) {
    final GridView grid = tester.widget<GridView>(find.byType(GridView));
    return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;
  }

  group('library grid + master-detail', () {
    testWidgets('narrow surface: 3 columns, no pane, tap navigates', (
      tester,
    ) async {
      await pumpLibrary(tester, narrow);

      expect(gridColumns(tester), 3);
      expect(find.byKey(const Key('library-preview-pane')), findsNothing);

      await tester.tap(find.text('Item 1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-title')), findsOneWidget);
    });

    testWidgets('wide surface: pane appears and the grid adapts to its width', (
      tester,
    ) async {
      await pumpLibrary(tester, wide);

      // 1200 - 360 preview pane = 840 for the grid → 4 columns.
      expect(gridColumns(tester), 4);
      expect(find.byKey(const Key('library-preview-pane')), findsOneWidget);
      expect(find.text('选择海报查看详情'), findsOneWidget);
    });

    testWidgets('wide tap selects for the pane instead of navigating', (
      tester,
    ) async {
      await pumpLibrary(tester, wide);

      await tester.tap(find.text('Item 2'));
      await tester.pumpAndSettle();

      // Still on the library; the pane fetched and shows the selection.
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Movies')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('detail-title')), findsNothing);
      expect(library.detailRequests, contains('2'));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('library-preview-title')))
            .data,
        'Item 2',
      );

      // Selecting another item swaps the pane without a route change.
      await tester.tap(find.text('Item 3'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('library-preview-title')))
            .data,
        'Item 3',
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Movies')),
        findsOneWidget,
      );
    });

    testWidgets('the pane 详情 button opens the detail page', (tester) async {
      await pumpLibrary(tester, wide);

      await tester.tap(find.text('Item 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-preview-details')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detail-title')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('detail-title'))).data,
        'Item 2',
      );
    });

    testWidgets('the pane 播放 button opens the player', (tester) async {
      await pumpLibrary(tester, wide);

      await tester.tap(find.text('Item 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-preview-play')));
      await tester.pumpAndSettle();

      expect(playback.resolveItemIds, contains('1'));
      expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
      // Let the direct-play probe timers finish without a live session.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('wide library keeps infinite-scroll paging', (tester) async {
      await pumpLibrary(tester, wide);
      final int before = library.itemCalls;

      await tester.drag(find.byType(GridView), const Offset(0, -8000));
      await tester.pumpAndSettle();

      expect(library.itemCalls, greaterThan(before));
      expect(find.byKey(const Key('library-preview-pane')), findsOneWidget);
    });

    testWidgets('the pane follows tab switches and clears stale selections', (
      tester,
    ) async {
      library.resumableResults = <MediaItem>[fakeItem('r-1', name: '继续影片')];
      library.itemsById['r-1'] = fakeItem('r-1', name: '继续影片');
      await pumpLibrary(tester, wide);

      await tester.tap(find.text('Item 2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-preview-title')), findsOneWidget);

      // The selection is gone with the 全部 grid; the pane resets.
      await tester.tap(find.byKey(const Key('library-tab-resume')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-preview-empty')), findsOneWidget);

      // Selecting on another tab fills the pane again.
      await tester.tap(find.text('继续影片'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('library-preview-title')))
            .data,
        '继续影片',
      );
    });
  });

  group('search grid', () {
    Future<void> pumpSearchResults(WidgetTester tester, Size size) async {
      library.searchResults = List<MediaItem>.generate(
        12,
        (index) => fakeItem('s-${index + 1}', name: '结果 ${index + 1}'),
      );
      setSurface(tester, size);
      await pumpApp(tester);
      routerOf(tester).go(AppRoutes.library);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('search-field')), '结果');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    testWidgets('3 columns on a narrow surface', (tester) async {
      await pumpSearchResults(tester, narrow);
      expect(find.text('结果 1'), findsOneWidget);
      expect(gridColumns(tester), 3);
    });

    testWidgets('6 columns on a wide surface', (tester) async {
      await pumpSearchResults(tester, wide);
      expect(find.text('结果 1'), findsOneWidget);
      expect(gridColumns(tester), 6);
    });
  });

  group('favorites grid', () {
    Future<void> pumpFavorites(WidgetTester tester, Size size) async {
      library.favoriteResults = List<MediaItem>.generate(
        12,
        (index) => fakeItem('f-${index + 1}', name: '收藏 ${index + 1}'),
      );
      setSurface(tester, size);
      await pumpApp(tester);
      routerOf(tester).go(AppRoutes.library);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-favorites')));
      await tester.pumpAndSettle();
    }

    testWidgets('3 columns on a narrow surface', (tester) async {
      await pumpFavorites(tester, narrow);
      expect(find.text('收藏 1'), findsOneWidget);
      expect(gridColumns(tester), 3);
    });

    testWidgets('6 columns on a wide surface', (tester) async {
      await pumpFavorites(tester, wide);
      expect(find.text('收藏 1'), findsOneWidget);
      expect(gridColumns(tester), 6);
    });
  });

  group('home rows', () {
    Future<void> pumpHome(WidgetTester tester, Size size) async {
      library.resumableResults = <MediaItem>[
        const MediaItem(
          id: 'r1',
          name: 'Resume 1',
          type: 'Movie',
          runTimeTicks: 6000000000,
          userData: UserItemData(positionTicks: 1200000000),
        ),
      ];
      setSurface(tester, size);
      await pumpApp(tester);
    }

    testWidgets('keep their compact metrics on a narrow surface', (
      tester,
    ) async {
      await pumpHome(tester, narrow);

      expect(tester.getSize(find.byKey(const Key('resume-r1'))).width, 178);
      expect(
        tester.getSize(find.byType(PageView)).height,
        closeTo(368 / 2.15, 0.01),
      );
    });

    testWidgets('scale their cards and banner on a wide surface', (
      tester,
    ) async {
      await pumpHome(tester, wide);

      expect(tester.getSize(find.byKey(const Key('resume-r1'))).width, 280);
      expect(tester.getSize(find.byType(PageView)).height, 260);
    });
  });

  group('detail page', () {
    Future<void> pumpDetail(WidgetTester tester, Size size) async {
      library.itemsById['m-0'] = const MediaItem(
        id: 'm-0',
        name: '宽屏影片',
        type: 'Movie',
        productionYear: 2024,
        overview: '一段简介',
        genres: <String>['科幻'],
      );
      setSurface(tester, size);
      await pumpApp(tester);
      routerOf(tester).go(AppRoutes.detailFor('m-0'));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps the single-column stack on a narrow surface', (
      tester,
    ) async {
      await pumpDetail(tester, narrow);

      expect(find.byKey(const Key('detail-title')), findsOneWidget);
      expect(find.byKey(const Key('detail-two-column')), findsNothing);
      expect(find.byKey(const Key('detail-play')), findsOneWidget);
    });

    testWidgets('caps the content width and uses two columns on wide', (
      tester,
    ) async {
      await pumpDetail(tester, wide);

      expect(find.byKey(const Key('detail-title')), findsOneWidget);
      expect(find.byKey(const Key('detail-two-column')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('detail-wide-content'))).width,
        1000,
      );
      expect(find.byKey(const Key('detail-play')), findsOneWidget);
      expect(find.text('一段简介'), findsOneWidget);
    });
  });
}
