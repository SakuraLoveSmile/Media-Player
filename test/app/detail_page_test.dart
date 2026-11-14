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
import 'package:media_player/data/cast/dlna_cast_service.dart';
import 'package:media_player/data/cast/dlna_device.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/models/media_source.dart';
import 'package:media_player/data/models/media_stream.dart';
import 'package:media_player/data/models/person.dart';
import 'package:media_player/data/models/server_profile.dart';

import '../support/fake_dlna_cast_service.dart';
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

MediaItem movieDetail({
  List<MediaSource> mediaSources = const <MediaSource>[],
  String? remoteTrailer,
  List<NamedLink> studios = const <NamedLink>[],
}) {
  return MediaItem(
    id: 'm-0',
    name: '库内影片',
    type: 'Movie',
    productionYear: 2024,
    runTimeTicks: const Duration(minutes: 128).inMicroseconds * 10,
    overview: '一段简介',
    tagline: '一句标语',
    communityRating: 8.5,
    officialRating: 'PG-13',
    genres: const <String>['科幻', '冒险'],
    people: const <Person>[
      Person(name: '演员甲', role: '角色甲', type: 'Actor', id: 'p-1'),
      Person(name: '导演乙', type: 'Director', id: 'p-2'),
    ],
    remoteTrailer: remoteTrailer,
    mediaSources: mediaSources,
    studios: studios,
  );
}

const List<MediaSource> twoSources = <MediaSource>[
  MediaSource(
    id: 'src-1',
    name: '1080p',
    container: 'mkv',
    bitrate: 12000000,
    supportsDirectPlay: true,
    supportsDirectStream: true,
  ),
  MediaSource(
    id: 'src-2',
    name: '4K 重制',
    container: 'mp4',
    bitrate: 40000000,
    supportsDirectPlay: true,
    supportsDirectStream: true,
  ),
];

void main() {
  late FakeLibraryService library;
  late FakePlaybackService playback;
  late FakePlaybackEngine engine;

  setUp(() {
    library = FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: <MediaItem>[fakeItem('m-0', name: '库内影片')],
      },
      itemsById: <String, MediaItem>{'m-0': movieDetail()},
    );
    playback = FakePlaybackService();
    engine = FakePlaybackEngine();
  });

  Future<void> pumpApp(WidgetTester tester, {DlnaCastService? cast}) async {
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
              cast: cast,
            ),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpDetail(WidgetTester tester, {DlnaCastService? cast}) async {
    await pumpApp(tester, cast: cast);
    // P1: the post-login landing is home; open the library so the movie poster
    // is tapped in its grid (unique there, unlike the home banner + rows).
    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.library);
    await tester.pumpAndSettle();
    await tester.tap(find.text('库内影片'));
    await tester.pumpAndSettle();
  }

  /// The 800x600 test surface is landscape, so the player's top bar auto-hides
  /// after 3 s; a tap on the video brings it back before tapping 返回.
  Future<void> leavePlayer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player-gesture-area')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-back')));
    await tester.pumpAndSettle();
  }

  testWidgets('a movie poster opens the detail page with its fields', (
    tester,
  ) async {
    await pumpDetail(tester);

    expect(library.detailRequests, contains('m-0'));
    expect(find.byKey(const Key('detail-title')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('detail-title'))).data,
      '库内影片',
    );
    expect(find.byKey(const Key('detail-tagline')), findsOneWidget);
    expect(find.byKey(const Key('detail-rating')), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
    expect(find.text('PG-13'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('2小时8分'), findsOneWidget);
    expect(find.text('科幻'), findsOneWidget);
    expect(find.text('冒险'), findsOneWidget);
    expect(find.text('一段简介'), findsOneWidget);

    // The cast row sits below the fold; scroll the page until it is built.
    await tester.scrollUntilVisible(
      find.text('演员甲'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-cast')), findsOneWidget);
    expect(find.text('演员甲'), findsOneWidget);
    expect(find.text('角色甲'), findsOneWidget);
  });

  testWidgets('renders track rows, media info, links and 推荐 (S28)', (
    tester,
  ) async {
    library.itemsById['m-0'] = MediaItem(
      id: 'm-0',
      name: '库内影片',
      type: 'Movie',
      productionYear: 2024,
      runTimeTicks: const Duration(minutes: 128).inMicroseconds * 10,
      overview: '一段简介',
      communityRating: 8.5,
      officialRating: 'PG-13',
      genres: const <String>['科幻'],
      dateCreated: '2026-04-13T14:10:00.0000000Z',
      studios: const <NamedLink>[NamedLink(name: 'Universal Pictures')],
      externalUrls: const <NamedLink>[
        NamedLink(name: 'IMDb', target: 'https://imdb.test/x'),
      ],
      backdropTags: const <String>['b-1', 'b-2'],
      mediaSources: const <MediaSource>[
        MediaSource(
          id: 'src-1',
          name: '1080p',
          container: 'mkv',
          bitrate: 12000000,
          supportsDirectPlay: true,
          supportsDirectStream: true,
          size: 6592614400,
          streams: <MediaStream>[
            MediaStream(
              type: MediaStreamType.video,
              index: 0,
              codec: 'hevc',
              displayTitle: '1080p HEVC',
              width: 1920,
              height: 1080,
              frameRate: 23.976,
              bitRate: 9070000,
              bitDepth: 10,
              colorSpace: 'bt709',
              pixelFormat: 'yuv420p10le',
              profile: 'Main 10',
              videoRange: 'SDR',
            ),
            MediaStream(
              type: MediaStreamType.audio,
              index: 1,
              codec: 'ac3',
              displayTitle: 'English AC3 5.1 (默认)',
              language: 'eng',
              displayLanguage: 'English',
              channels: 6,
              bitRate: 437000,
              isDefault: true,
            ),
            MediaStream(
              type: MediaStreamType.subtitle,
              index: 9,
              codec: 'ass',
              displayTitle: 'Chinese (默认 ASS)',
              title: '中上英下',
              language: 'chi',
              displayLanguage: 'Chinese',
              isDefault: true,
              isExternal: true,
            ),
          ],
        ),
      ],
    );
    library.similarResults = <MediaItem>[
      const MediaItem(
        id: 's-1',
        name: '相似影片',
        type: 'Movie',
        productionYear: 2022,
        communityRating: 7.8,
      ),
    ];

    await pumpDetail(tester);

    // Pre-playback track rows (video / audio / subtitle).
    expect(find.text('当前轨道'), findsOneWidget);
    expect(find.text('1080p HEVC'), findsWidgets);
    expect(find.text('English AC3 5.1 (默认)'), findsWidgets);
    expect(find.text('Chinese (默认 ASS)'), findsWidgets);
    expect(library.similarRequests.single.itemId, 'm-0');

    final Finder scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Universal Pictures'),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Universal Pictures'), findsOneWidget);
    expect(find.byKey(const Key('detail-link-IMDb')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('detail-media-info')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-media-info')), findsOneWidget);
    expect(find.text('6.14 GB'), findsOneWidget);
    expect(find.textContaining('添加于:'), findsOneWidget);
  });

  testWidgets('the recommendation row opens another detail page', (
    tester,
  ) async {
    library.similarResults = <MediaItem>[
      const MediaItem(
        id: 's-1',
        name: '相似影片',
        type: 'Movie',
        productionYear: 2022,
      ),
    ];
    library.itemsById['s-1'] = const MediaItem(
      id: 's-1',
      name: '相似影片',
      type: 'Movie',
    );
    await pumpDetail(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('detail-similar')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('相似影片'));
    await tester.pumpAndSettle();
    expect(library.detailRequests, contains('s-1'));
  });

  testWidgets('a resumable item offers continue with the remaining time', (
    tester,
  ) async {
    library.itemsById['m-0'] = MediaItem(
      id: 'm-0',
      name: '库内影片',
      type: 'Movie',
      productionYear: 2024,
      runTimeTicks: const Duration(minutes: 100).inMicroseconds * 10,
      userData: const UserItemData(positionTicks: 25 * 60 * 10000000),
    );
    await pumpDetail(tester);

    expect(find.text('继续 (剩余: 1时15分 0秒)'), findsOneWidget);
  });
  testWidgets('track picks on the detail page ride into the player (S37)', (
    tester,
  ) async {
    library.itemsById['m-0'] = MediaItem(
      id: 'm-0',
      name: '库内影片',
      type: 'Movie',
      runTimeTicks: const Duration(minutes: 90).inMicroseconds * 10,
      mediaSources: const <MediaSource>[
        MediaSource(
          id: 'src-1',
          container: 'mkv',
          bitrate: 12000000,
          supportsDirectPlay: true,
          supportsDirectStream: true,
          streams: <MediaStream>[
            MediaStream(
              type: MediaStreamType.video,
              index: 0,
              codec: 'hevc',
              displayTitle: '1080p HEVC',
            ),
            MediaStream(
              type: MediaStreamType.audio,
              index: 1,
              codec: 'aac',
              displayTitle: '国语 AAC',
              language: 'chi',
              isDefault: true,
            ),
            MediaStream(
              type: MediaStreamType.audio,
              index: 2,
              codec: 'ac3',
              displayTitle: '英语 AC3',
              language: 'eng',
            ),
            MediaStream(
              type: MediaStreamType.subtitle,
              index: 9,
              codec: 'ass',
              displayTitle: '简体中文',
              language: 'chi',
              isDefault: true,
            ),
          ],
        ),
      ],
    );
    playback.plan = fakePlan(
      audios: const <MediaStream>[
        MediaStream(
          type: MediaStreamType.audio,
          index: 1,
          displayTitle: '国语 AAC',
          language: 'chi',
        ),
        MediaStream(
          type: MediaStreamType.audio,
          index: 2,
          displayTitle: '英语 AC3',
          language: 'eng',
        ),
      ],
      subtitles: const <MediaStream>[
        MediaStream(
          type: MediaStreamType.subtitle,
          index: 9,
          displayTitle: '简体中文',
          language: 'chi',
        ),
      ],
    );

    await pumpDetail(tester);

    await tester.tap(find.byKey(const Key('detail-audio-row')));
    await tester.pumpAndSettle();
    expect(find.text('选择音轨'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detail-audio-option-2')));
    await tester.pumpAndSettle();
    expect(find.text('英语 AC3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-subtitle-row')));
    await tester.pumpAndSettle();
    expect(find.text('选择字幕'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detail-subtitle-off')));
    await tester.pumpAndSettle();
    expect(find.text('字幕：关闭'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-play')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Server stream index 2 is position 1 in the negotiated audio list.
    expect(engine.audioTracks, contains(1));
    expect(engine.subtitleTracks, isNotEmpty);
    expect(engine.subtitleTracks.last, isNull);
  });
  testWidgets('the hero cast action negotiates and hands the URL (S38)', (
    tester,
  ) async {
    // A token-bearing plan, so the cast URL has to append `api_key`.
    playback.plan = PlaybackPlan(
      itemId: 'm-0',
      mode: PlaybackMode.direct,
      endpointKind: EndpointKind.lan,
      url: 'http://lan.example/videos/m-0/stream',
      headers: const <String, String>{'X-Emby-Token': 'tok-1'},
      mediaSourceId: 'src-1',
      playSessionId: 'ps-1',
    );
    final cast = FakeDlnaCastService()
      ..devices = <DlnaDevice>[
        const DlnaDevice(
          id: 'uuid:tv',
          name: '客厅电视',
          controlUrl: 'http://192.168.1.20/control',
          address: '192.168.1.20:8895',
        ),
      ];
    await pumpDetail(tester, cast: cast);

    await tester.tap(find.byKey(const Key('detail-cast-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-cast-sheet')), findsOneWidget);
    expect(find.text('客厅电视'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-cast-device-uuid:tv')));
    await tester.pumpAndSettle();

    expect(cast.casts, hasLength(1));
    expect(cast.casts.single.url, contains('api_key='));
    expect(find.byKey(const Key('detail-cast-status')), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-cast-stop')));
    await tester.pumpAndSettle();
    expect(cast.stops, hasLength(1));
  });

  testWidgets('a genre chip opens the library filtered to it (S46)', (
    tester,
  ) async {
    await pumpDetail(tester);

    final Finder chip = find.byKey(const Key('detail-genre-科幻'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    // The library opens with the genre already applied, shown as a chip.
    final Finder active = find.byKey(const Key('library-filter-genre-active'));
    expect(active, findsOneWidget);
    expect(
      find.descendant(of: active, matching: find.text('科幻')),
      findsOneWidget,
    );
  });

  testWidgets('a studio opens the library filtered to it (S60)', (
    tester,
  ) async {
    library.itemsById['m-0'] = movieDetail(
      studios: const <NamedLink>[
        NamedLink(name: 'Studio Colorido', target: 'studio-1'),
      ],
    );
    await pumpDetail(tester);

    final Finder link = find.byKey(const Key('detail-studio-Studio Colorido'));
    await tester.scrollUntilVisible(
      link,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.text('工作室: Studio Colorido'), findsOneWidget);
    expect(library.itemsStudioIds, contains('studio-1'));
    expect(library.itemsStudios, contains('Studio Colorido'));
  });
  testWidgets('a director name opens the person page (S54)', (tester) async {
    await pumpDetail(tester);

    final Finder link = find.byKey(const Key('detail-director-p-2'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.text('导演乙'), findsWidgets);
  });
  testWidgets('a cast card opens the person page (S46)', (tester) async {
    await pumpDetail(tester);

    final Finder card = find.byKey(const Key('detail-person-p-1'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('演员甲'), findsWidgets);
  });
  testWidgets('the favorite toggle calls setFavorite and flips the icon', (
    tester,
  ) async {
    await pumpDetail(tester);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-favorite')));
    await tester.pumpAndSettle();

    expect(library.favoriteWrites, <({String itemId, bool favorite})>[
      (itemId: 'm-0', favorite: true),
    ]);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-favorite')));
    await tester.pumpAndSettle();
    expect(library.favoriteWrites.last, (itemId: 'm-0', favorite: false));
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('the watched toggle calls setPlayed', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byKey(const Key('detail-watched')));
    await tester.pumpAndSettle();

    expect(library.playedWrites, <({String itemId, bool played})>[
      (itemId: 'm-0', played: true),
    ]);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('play opens the player and returning refreshes the item', (
    tester,
  ) async {
    await pumpDetail(tester);

    await tester.tap(find.byKey(const Key('detail-play')));
    await tester.pumpAndSettle();
    // Past the §10.9 f verdict probe so no timer outlives the test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
    expect(engine.openedPlans.single.itemId, 'm-0');
    expect(playback.resolveSourceIds, <String?>[null]);

    await leavePlayer(tester);

    expect(find.byKey(const Key('detail-play')), findsOneWidget);
    // Detail load, the player's own detail fetch, then the quiet refresh.
    expect(library.detailRequests, <String>['m-0', 'm-0', 'm-0']);
  });

  testWidgets('a picked version reaches negotiation as the source query', (
    tester,
  ) async {
    library.itemsById['m-0'] = movieDetail(mediaSources: twoSources);
    await pumpDetail(tester);

    await tester.tap(find.byKey(const Key('detail-version')));
    await tester.pumpAndSettle();
    expect(find.text('选择版本'), findsOneWidget);
    expect(find.text('4K 重制'), findsOneWidget);
    expect(find.text('MP4 · 40.0 Mbps'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-source-src-2')));
    await tester.pumpAndSettle();
    expect(find.text('4K 重制'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-play')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(playback.resolveSourceIds, <String?>['src-2']);
    expect(engine.openedPlans.single.mediaSourceId, 'src-2');
  });

  testWidgets('the trailer button only appears with a remote trailer', (
    tester,
  ) async {
    await pumpDetail(tester);
    expect(find.byKey(const Key('detail-trailer')), findsNothing);
    expect(find.text('预告片'), findsNothing);
  });

  testWidgets('a trailer link is offered when the server provides one', (
    tester,
  ) async {
    library.itemsById['m-0'] = movieDetail(
      remoteTrailer: 'https://example.com/trailer',
    );
    await pumpDetail(tester);

    expect(find.byKey(const Key('detail-trailer')), findsOneWidget);
    expect(find.text('预告片'), findsOneWidget);
  });

  testWidgets('a detail load failure shows copy with a retry', (tester) async {
    await pumpApp(tester);
    // P1: open the library so the poster is tapped in its grid, not the home
    // banner/rows where the same title appears twice.
    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.library);
    await tester.pumpAndSettle();
    // Fail only the detail fetch; the grid itself must stay usable.
    library.itemsById.clear();
    library.failure = EmbyException(AppErrorCode.networkUnreachable);
    await tester.tap(find.text('库内影片'));
    await tester.pumpAndSettle();

    expect(find.text('无法连接服务器，请检查网络'), findsOneWidget);

    library.failure = null;
    library.itemsById['m-0'] = movieDetail();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-title')), findsOneWidget);
  });
}
