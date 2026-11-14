import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
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
  late FakePlaybackService playback;
  late FakePlaybackEngine engine;

  const resumeItem = MediaItem(
    id: 'r1',
    name: 'Resume 1',
    type: 'Movie',
    productionYear: 2024,
    runTimeTicks: 6000000000, // 10 minutes
    userData: UserItemData(positionTicks: 1200000000), // 2 minutes watched
  );

  const ratedItem = MediaItem(
    id: 'm2',
    name: 'Movie 2',
    type: 'Movie',
    productionYear: 2024,
    communityRating: 8.2,
    userData: UserItemData(unplayedItemCount: 12),
  );

  setUp(() {
    library = FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView, fakeShowsView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: <MediaItem>[
          fakeItem('m1', name: 'Movie 1'),
          ratedItem,
        ],
        fakeShowsView.id: <MediaItem>[fakeItem('s1', name: 'Show 1')],
      },
      itemsById: <String, MediaItem>{'r1': resumeItem},
    );
    library.resumableResults = <MediaItem>[resumeItem];
    library.serverNameValue = 'Test Server';
    playback = FakePlaybackService();
    engine = FakePlaybackEngine();
  });

  Future<void> pumpHome(WidgetTester tester) async {
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

  /// The home page is taller than the 800x600 test surface, so anything below
  /// the banner + library strip has to be scrolled into view before asserting.
  Future<void> scrollHome(WidgetTester tester, Finder target) async {
    final Finder scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(target, 300, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

  testWidgets('a resumable episode shows S1E2 and its title (S68)', (
    tester,
  ) async {
    library.resumableResults = <MediaItem>[
      const MediaItem(
        id: 'e1',
        name: '恐龙先生弄丢了',
        type: 'Episode',
        seriesName: '小猪佩奇',
        parentIndexNumber: 1,
        indexNumber: 2,
        runTimeTicks: 6000000000,
        userData: UserItemData(positionTicks: 1200000000),
      ),
    ];
    await pumpHome(tester);

    await scrollHome(tester, find.byKey(const Key('resume-e1')));
    expect(find.text('小猪佩奇'), findsOneWidget);
    expect(find.text('S1E2：恐龙先生弄丢了'), findsOneWidget);
  });

  testWidgets(
    'scrolling down hides the capsule, scrolling up restores it (S63)',
    (tester) async {
      await pumpHome(tester);

      // The capsule starts on screen.
      expect(
        tester
            .widget<AnimatedSlide>(find.byKey(const Key('nav-capsule-slide')))
            .offset,
        Offset.zero,
      );

      final Finder scrollable = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedSlide>(find.byKey(const Key('nav-capsule-slide')))
            .offset,
        isNot(Offset.zero),
      );

      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedSlide>(find.byKey(const Key('nav-capsule-slide')))
            .offset,
        Offset.zero,
      );
    },
  );

  testWidgets(
    'lands on home with the capsule nav and the continue-watching progress',
    (tester) async {
      await pumpHome(tester);

      expect(find.byKey(const Key('home-page')), findsOneWidget);
      expect(find.byKey(const Key('nav-home')), findsOneWidget);
      expect(find.byKey(const Key('nav-search')), findsOneWidget);
      expect(find.byKey(const Key('nav-favorites')), findsOneWidget);
      // S28 header: the server name from System/Info/Public.
      expect(find.byKey(const Key('home-server-name')), findsOneWidget);
      expect(find.text('Test Server'), findsOneWidget);

      await scrollHome(tester, find.text('继续观看'));
      expect(find.text('继续观看'), findsOneWidget);
      await scrollHome(tester, find.text('Resume 1'));
      expect(find.text('Resume 1'), findsOneWidget);

      final LinearProgressIndicator progress = tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('resume-progress-r1')),
          );
      expect(progress.value, closeTo(0.2, 0.0001));
      // 10 min runtime - 2 min watched = 8 min remaining.
      expect(find.text('剩余: 8分 0秒'), findsOneWidget);
    },
  );

  testWidgets('the 媒体库 strip lists every library with its title count', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.byKey(const Key('home-library-view-movies')), findsOneWidget);
    expect(find.byKey(const Key('home-library-view-shows')), findsOneWidget);
    // Two movies, one show: the badges come from TotalRecordCount.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a library cover is drawn at the server\'s 16:9 ratio (S28)', (
    tester,
  ) async {
    // A host makes imageUrl non-null, so the card renders a real Image.
    library.imageHost = '192.168.1.10:8096';
    await pumpHome(tester);

    final Size cover = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('home-library-view-movies')),
        matching: find.byType(Image),
      ),
    );
    // Emby reports library artwork as 1.7778; a card of another shape would
    // crop the cover's sides under BoxFit.cover.
    expect(cover.width / cover.height, closeTo(16 / 9, 0.001));
  });

  testWidgets('posters show the rating and the unwatched count badge', (
    tester,
  ) async {
    await pumpHome(tester);

    await scrollHome(tester, find.text('8.2'));
    expect(find.text('8.2'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('a library card opens the library scoped to that view', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-library-view-shows')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library-tab-all')), findsOneWidget);
    // The library page loaded the view the card pointed at, not its default.
    expect(library.itemsRequests.last.viewId, 'view-shows');
  });

  testWidgets('the banner and a library row render with a 更多 entry', (
    tester,
  ) async {
    await pumpHome(tester);

    await scrollHome(tester, find.byKey(const Key('home-more-view-movies')));
    expect(find.text('Movies'), findsWidgets);
    expect(find.byKey(const Key('home-more-view-movies')), findsOneWidget);
    expect(find.text('Movie 1'), findsWidgets);
  });

  testWidgets('the settings action opens the settings page', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-settings')));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-theme-dark')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('settings-theme-dark')), findsOneWidget);
  });

  testWidgets('the account action opens the server switcher sheet', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-servers-empty')), findsOneWidget);
    expect(find.byKey(const Key('home-server-add')), findsOneWidget);
  });

  testWidgets('tapping a capsule destination navigates to search', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('nav-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-field')), findsOneWidget);
    expect(find.byKey(const Key('home-page')), findsNothing);
  });

  testWidgets('tapping the current capsule destination stays on home', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('nav-home')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-page')), findsOneWidget);
    expect(find.byKey(const Key('search-field')), findsNothing);
  });

  testWidgets('a continue-watching card opens the player at the item', (
    tester,
  ) async {
    await pumpHome(tester);

    await scrollHome(tester, find.byKey(const Key('resume-r1')));
    await tester.tap(find.byKey(const Key('resume-r1')));
    await tester.pumpAndSettle();
    // Past the §10.9 f verdict probe so no timer outlives the test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(playback.resolveItemIds, contains('r1'));
    expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
  });

  testWidgets('an empty continue-watching row shows a hint', (tester) async {
    library.resumableResults = const <MediaItem>[];
    await pumpHome(tester);

    await scrollHome(tester, find.text('没有正在观看的内容'));
    expect(find.text('没有正在观看的内容'), findsOneWidget);
    expect(find.byKey(const Key('resume-progress-r1')), findsNothing);
  });
}
