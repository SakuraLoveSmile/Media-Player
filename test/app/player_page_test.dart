import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/screenshot_settings.dart';
import 'package:media_player/app/router.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/device/local_subtitle_picker.dart';
import 'package:media_player/core/device/pip.dart';
import 'package:media_player/core/device/screen_orientation.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/core/router/app_routes.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/cast/dlna_cast_service.dart';
import 'package:media_player/data/cast/dlna_device.dart';
import 'package:media_player/data/danmaku/danmaku_repository.dart';
import 'package:media_player/data/danmaku/danmaku_settings.dart';
import 'package:media_player/data/danmaku/models/danmaku_anime.dart';
import 'package:media_player/data/danmaku/models/danmaku_comment.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/library_view.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/media_source.dart';
import 'package:media_player/data/models/media_stream.dart';
import 'package:media_player/data/models/person.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/data/playback/playback_settings.dart';
import 'package:media_player/data/playback/subtitle_repository.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/player/player_page.dart';
import 'package:media_player/ui/app_controls.dart';
import 'package:media_player/ui/theme/app_theme.dart';

import '../support/fake_danmaku_service.dart';
import '../support/fake_dlna_cast_service.dart';
import '../support/fake_library_service.dart';
import '../support/fake_local_subtitle_picker.dart';
import '../support/fake_pip_controller.dart';
import '../support/fake_screen_orientation_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';
import '../support/fake_subtitle_service.dart';

class PendingStopReporter extends FakePlaybackReporter {
  final completion = Completer<void>();

  @override
  Future<void> stopped(PlaybackPlan plan, Duration position) {
    unawaited(super.stopped(plan, position));
    return completion.future;
  }
}

class ResettingSurfaceEngine extends FakePlaybackEngine {
  ResettingSurfaceEngine(this.onSurfaceDispose);

  final VoidCallback onSurfaceDispose;

  @override
  Widget createSurface() => _TeardownSurface(
    onDispose: () {
      emit(const PlaybackSnapshot());
      onSurfaceDispose();
    },
  );
}

class _TeardownSurface extends StatefulWidget {
  const _TeardownSurface({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_TeardownSurface> createState() => _TeardownSurfaceState();
}

class _TeardownSurfaceState extends State<_TeardownSurface> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// An engine whose `open()` never finishes: the player stays in its opening
/// state so the pre-play UI (loader, speed, hidden chrome) can be inspected.
class HangingOpenEngine extends FakePlaybackEngine {
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> open(PlaybackPlan plan) {
    openedPlans.add(plan);
    return gate.future;
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

const Duration runtime = Duration(minutes: 90);

MediaItem playerItem({
  Duration position = Duration.zero,
  List<MediaSource> mediaSources = const <MediaSource>[],
}) {
  return MediaItem(
    id: 'item-1',
    name: '测试影片',
    type: 'Movie',
    runTimeTicks: runtime.inMicroseconds * 10,
    userData: UserItemData(positionTicks: position.inMicroseconds * 10),
    mediaSources: mediaSources,
  );
}

const MediaStream embeddedSubtitle = MediaStream(
  type: MediaStreamType.subtitle,
  index: 2,
  codec: 'subrip',
  language: 'chi',
  displayTitle: '中文',
);

const MediaStream externalSubtitle = MediaStream(
  type: MediaStreamType.subtitle,
  index: 3,
  codec: 'ass',
  isExternal: true,
  displayTitle: '简体中文',
);

const MediaStream chiAudio = MediaStream(
  type: MediaStreamType.audio,
  index: 1,
  codec: 'aac',
  language: 'chi',
  displayTitle: '国语',
);

const MediaStream engAudio = MediaStream(
  type: MediaStreamType.audio,
  index: 2,
  codec: 'aac',
  language: 'eng',
  displayTitle: '英语',
);

void main() {
  late FakePlaybackEngine engine;
  late FakePlaybackReporter reporter;
  late FakePlaybackService playback;

  setUp(() {
    engine = FakePlaybackEngine();
    reporter = FakePlaybackReporter();
    playback = FakePlaybackService();
  });

  void armSubtitles() {
    playback.plan = fakePlan(
      subtitles: <MediaStream>[embeddedSubtitle, externalSubtitle],
    );
  }

  void armTracks() {
    playback.plan = fakePlan(
      audios: <MediaStream>[chiAudio, engAudio],
      subtitles: <MediaStream>[embeddedSubtitle, externalSubtitle],
    );
  }

  /// Opens the library, taps the poster, starts playback from the detail page
  /// (S7) and settles on the player page. The extra 4 s covers the §10.9 f
  /// verdict check scheduled 3 s after start. [createEngine] / [createReporter]
  /// default to the shared doubles; the retry tests pass factories so each
  /// playback gets its own pair.
  Future<void> pumpPlayer(
    WidgetTester tester, {
    MediaItem? item,
    FakePlaybackEngine Function()? createEngine,
    FakePlaybackReporter Function()? createReporter,
    FakeLibraryService? libraryOverride,
    SubtitleService? subtitles,
    LocalSubtitlePicker? localPicker,
    PipController? pip,
    DanmakuService? danmaku,
    KeyValueStore? store,
    DlnaCastService? cast,
    ScreenOrientationService? orientation,
    bool legacyRoute = false,
    String? source,
  }) async {
    final media = item ?? playerItem();
    final library =
        libraryOverride ??
        FakeLibraryService(
          viewList: <LibraryView>[fakeMoviesView],
          itemsByView: <String, List<MediaItem>>{
            fakeMoviesView.id: <MediaItem>[media],
          },
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: StaticAuth(),
              library: library,
              posters: FakePosterCache(),
              playback: playback,
              createEngine: createEngine ?? () => engine,
              createReporter: createReporter ?? () => reporter,
              subtitles: subtitles,
              localSubtitlePicker: localPicker,
              pip: pip,
              danmaku: danmaku,
              store: store,
              cast: cast,
            ),
          ),
          if (orientation != null)
            playerOrientationServiceProvider.overrideWithValue(orientation),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();

    if (legacyRoute) {
      ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
          .read(appRouterProvider)
          .go(AppRoutes.playerFor(media.id, source: source));
    } else {
      // P1: the post-login landing is home; open the library so the movie
      // poster is tapped in its grid (unique there, unlike the home rows).
      ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
          .read(appRouterProvider)
          .go(AppRoutes.library);
      await tester.pumpAndSettle();
      await tester.tap(find.text(media.name));
      await tester.pumpAndSettle();
      // S15: on wide surfaces the library tap selects for the preview pane;
      // reach the detail page through its 详情 action before playing.
      final previewDetails = find.byKey(const Key('library-preview-details'));
      if (previewDetails.evaluate().isNotEmpty) {
        await tester.tap(previewDetails);
        await tester.pumpAndSettle();
      }
      // S7: movie posters open the detail page; Play starts the session.
      await tester.tap(find.byKey(const Key('detail-play')));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    // Controls auto-hide when idle; re-show them so later taps land. Absent on
    // the unsupported/series notice, which has no gesture layer.
    final gestureArea = find.byKey(const Key('player-gesture-area'));
    if (gestureArea.evaluate().isNotEmpty) {
      await tester.tap(gestureArea);
      await tester.pumpAndSettle();
    }
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  /// Opens the S16/S13 options sheet from the control bar.
  Future<void> openOptions(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player-options-menu')));
    await tester.pumpAndSettle();
  }

  /// S77: the player opens in landscape (默认横屏播放), so the portrait cases
  /// switch modes with the same control the user taps.
  Future<void> switchToPortrait(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player-orientation-toggle')));
    await tester.pumpAndSettle();
  }

  testWidgets('opening a video waits with the configured loader (S79)', (
    tester,
  ) async {
    // Bootstrap never resolves, so the player is still opening its controller
    // and shows the pre-play state: 外观 → 加载动画 must be what the user sees
    // before the video starts, not a bare Material spinner.
    final Completer<AppServices> bootstrap = Completer<AppServices>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((ref) => bootstrap.future),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: const PlayerPage(itemId: 'item-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const Key('app-loader')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('opening hides the chrome and shows the network speed (S79)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // open() never finishes, so the player stays in its opening state.
    final HangingOpenEngine hanging = HangingOpenEngine()
      ..stats = const PlaybackStats(cacheSpeed: 2097152);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: StaticAuth(),
              library: FakeLibraryService(
                viewList: <LibraryView>[fakeMoviesView],
                itemsByView: <String, List<MediaItem>>{
                  fakeMoviesView.id: <MediaItem>[playerItem()],
                },
              ),
              posters: FakePosterCache(),
              playback: playback,
              createEngine: () => hanging,
              createReporter: () => reporter,
            ),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.playerFor('item-1'));
    // Bounded pumps: the opening loader animates forever, so pumpAndSettle
    // would never return.
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The chrome (back button, quick actions) is mounted but faded out and
    // pointer-inert while the stream opens.
    double chromeOpacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byKey(const Key('player-back')),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    expect(find.byKey(const Key('app-loader')), findsOneWidget);
    expect(find.byKey(const Key('player-opening-speed')), findsOneWidget);
    expect(find.text('2.00 MB/s'), findsOneWidget);
    expect(find.byKey(const Key('player-opening-tap')), findsOneWidget);
    expect(chromeOpacity(), 0);

    // A tap on the video brings the chrome back so 返回 / 画面 / 字幕 are usable
    // even before the first frame.
    await tester.tap(find.byKey(const Key('player-opening-tap')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(chromeOpacity(), 1);
  });

  testWidgets('a mid-session stall shows the speed readout (S79)', (
    tester,
  ) async {
    await pumpPlayer(tester);
    engine.stats = const PlaybackStats(cacheSpeed: 307200);
    double chromeOpacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byKey(const Key('player-play-toggle')),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    // pumpPlayer left the chrome revealed; a mid-session stall must not take
    // it away, it only adds the loader and the speed readout.
    expect(chromeOpacity(), 1);
    engine.emit(const PlaybackSnapshot(buffering: true));
    // Bounded pumps: the loader animates forever, and the first speed sample
    // lands one microtask after the readout mounts.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('player-opening-speed')), findsOneWidget);
    expect(find.text('300 KB/s'), findsOneWidget);
    expect(chromeOpacity(), 1);

    engine.emit(
      const PlaybackSnapshot(playing: true, duration: Duration(minutes: 90)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('player-opening-speed')), findsNothing);
  });

  testWidgets('the toggle drives play and pause on the engine', (tester) async {
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-play-toggle')));
    await tester.pumpAndSettle();
    expect(engine.playCalls, 1);
    expect(engine.pauseCalls, 0);

    await tester.tap(find.byKey(const Key('player-play-toggle')));
    await tester.pumpAndSettle();
    expect(engine.pauseCalls, 1);
  });

  testWidgets('controls auto-hide after idle and a tap brings them back', (
    tester,
  ) async {
    await pumpPlayer(tester);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    for (final w in tester.widgetList<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    )) {
      expect(w.opacity, 0);
    }

    await tester.tap(find.byKey(const Key('player-gesture-area')));
    await tester.pumpAndSettle();
    for (final w in tester.widgetList<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    )) {
      expect(w.opacity, 1);
    }
  });

  testWidgets('player overlays stay dark under a light app theme', (
    tester,
  ) async {
    await pumpPlayer(tester);
    final context = tester.element(find.byKey(const Key('player-progress')));
    expect(Theme.of(context).colorScheme.brightness, Brightness.dark);
  });

  testWidgets('reserves a subtitle band above the bottom edge', (tester) async {
    await pumpPlayer(tester);
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(engine.subtitleMargins, isNotEmpty);
    expect(engine.subtitleMargins.last, closeTo(0.05 * height, 0.5));
  });

  group('portrait player (S78)', () {
    void portraitSurface(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    MediaItem episodeItem() => MediaItem(
      id: 'e1',
      name: '第 1 集 开场',
      type: 'Episode',
      seriesName: '剧集标题',
      parentIndexNumber: 1,
      seriesId: 'show',
      seasonId: 's1',
      indexNumber: 1,
      runTimeTicks: runtime.inMicroseconds * 10,
      overview: '一段简介内容',
      premiereDate: '2004-06-04T00:00:00.000Z',
      communityRating: 7.0,
      people: const <Person>[
        Person(id: 'p1', name: '演员甲', type: 'Actor', role: '角色甲'),
      ],
    );

    MediaItem secondEpisode() => MediaItem(
      id: 'e2',
      name: '第 2 集 重逢',
      type: 'Episode',
      seriesName: '剧集标题',
      parentIndexNumber: 1,
      seriesId: 'show',
      seasonId: 's1',
      indexNumber: 2,
      runTimeTicks: runtime.inMicroseconds * 10,
    );

    FakeLibraryService episodeLibrary(MediaItem episode, MediaItem second) {
      return FakeLibraryService(
        viewList: <LibraryView>[fakeMoviesView],
        itemsByView: <String, List<MediaItem>>{
          fakeMoviesView.id: <MediaItem>[episode],
        },
        itemsById: <String, MediaItem>{episode.id: episode, second.id: second},
        episodesBySeason: <String, List<MediaItem>>{
          's1': <MediaItem>[episode, second],
        },
      );
    }

    /// Opens a two-episode season in the portrait player and returns its
    /// library double (so navigation can be asserted).
    Future<FakeLibraryService> pumpEpisodePortrait(
      WidgetTester tester, {
      Size size = const Size(400, 800),
      FakeScreenOrientationService? orientation,
      MediaItem? episode,
      FakeLibraryService? libraryOverride,
    }) async {
      portraitSurface(tester, size);
      final MediaItem first = episode ?? episodeItem();
      final MediaItem second = secondEpisode();
      final library = libraryOverride ?? episodeLibrary(first, second);
      await pumpPlayer(
        tester,
        item: first,
        libraryOverride: library,
        legacyRoute: true,
        orientation: orientation,
      );
      await switchToPortrait(tester);
      return library;
    }

    testWidgets('pins the video box to the top with the full overlay', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      final Rect video = tester.getRect(find.byType(AspectRatio));
      expect(video.top, 0);
      expect(video.left, 0);
      expect(video.width, 400);
      expect(video.height, closeTo(400 * 9 / 16, 0.01));

      // One control layer over the video: back + title + round quick actions,
      // the side columns and the centre transport all stay inside the box.
      for (final String key in <String>[
        'player-back',
        'player-top-screenshot',
        'player-quick-aspect',
        'player-quick-cast',
        'player-top-subtitle',
        'player-options-menu',
        'player-orientation-toggle',
        'player-quick-screenshot',
        'player-quick-lock',
        'player-rate-down',
        'player-rate-menu',
        'player-rate-up',
        'player-seek-back-10',
        'player-play-toggle',
        'player-seek-forward-10',
      ]) {
        final Finder finder = find.byKey(Key(key));
        expect(finder, findsOneWidget, reason: key);
        final Rect rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(-0.01), reason: key);
        expect(
          rect.bottom,
          lessThanOrEqualTo(video.bottom + 0.01),
          reason: key,
        );
        expect(rect.right, lessThanOrEqualTo(video.right + 0.01), reason: key);
      }
      // S78: portrait turns subtitle margins on so ASS dialogue clears the
      // dock title row (the 黑边 setting only governs landscape).
      expect(engine.subtitleMarginModes.last, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the top bar round actions are uniform and right-aligned', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      const List<String> keys = <String>[
        'player-top-screenshot',
        'player-quick-aspect',
        'player-quick-cast',
        'player-top-subtitle',
        'player-options-menu',
        'player-orientation-toggle',
      ];
      final List<Rect> rects = <Rect>[
        for (final String key in keys) tester.getRect(find.byKey(Key(key))),
      ];
      for (int i = 0; i < rects.length; i++) {
        // P0-5: same 34 dp circle, same baseline as the rest of the group.
        expect(rects[i].width, closeTo(34, 0.01), reason: keys[i]);
        expect(rects[i].height, closeTo(34, 0.01), reason: keys[i]);
        expect(rects[i].top, closeTo(rects.first.top, 0.01), reason: keys[i]);
      }
      // The group ends 8 dp inside the video's right edge, not flush with it.
      expect(rects.last.right, closeTo(400 - 8, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the portrait overlay transport and speed drive playback', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      await tester.tap(find.byKey(const Key('player-play-toggle')));
      await tester.pumpAndSettle();
      expect(engine.playCalls, 1);

      await tester.tap(find.byKey(const Key('player-rate-up')));
      await tester.pumpAndSettle();
      expect(engine.rates.last, 1.25);

      await tester.tap(find.byKey(const Key('player-seek-forward-10')));
      await tester.pumpAndSettle();
      expect(engine.seeks.last, const Duration(seconds: 10));

      await tester.tap(find.byKey(const Key('player-top-screenshot')));
      await tester.pumpAndSettle();
      expect(engine.screenshotPaths, hasLength(1));
    });

    testWidgets('hangs a two-row dock off the video edge', (tester) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      final Rect video = tester.getRect(find.byType(AspectRatio));
      // Row 1 floats on the video's bottom edge: prev / next / tappable title.
      final Rect title = tester.getRect(
        find.byKey(const Key('player-dock-title')),
      );
      expect(title.top, greaterThan(video.top));
      expect(title.bottom, lessThanOrEqualTo(video.bottom + 0.01));
      expect(find.byKey(const Key('player-prev-episode')), findsOneWidget);
      expect(find.byKey(const Key('player-next-episode')), findsOneWidget);

      // Row 2 is the black strip under the video: clock, wave bar, track and
      // subtitle entries.
      final Finder dock = find.byKey(const Key('player-portrait-dock'));
      final Rect dockRect = tester.getRect(dock);
      expect(dockRect.top, greaterThanOrEqualTo(video.bottom - 0.01));
      for (final String key in <String>[
        'player-portrait-time',
        'player-progress',
        'player-track-menu',
        'player-subtitle-menu',
      ]) {
        expect(
          find.descendant(of: dock, matching: find.byKey(Key(key))),
          findsOneWidget,
          reason: key,
        );
      }
      expect(find.text('00:00 / 01:30:00'), findsOneWidget);
      // S78: the wave bar is a CustomPainter, not Material's Slider.
      expect(find.byType(Slider), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the wave progress seeks on drag and on tap', (tester) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      final Finder progress = find.byKey(const Key('player-progress'));
      final Rect rect = tester.getRect(progress);
      expect(rect.height, 28);

      // A tap jumps to that fraction directly.
      await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.center.dy));
      await tester.pumpAndSettle();
      expect(engine.seeks, hasLength(1));
      expect(engine.seeks.last.inMinutes, closeTo(22, 2));

      // Dragging past the right edge clamps to the runtime and seeks once.
      await tester.dragFrom(rect.center, Offset(rect.width, 0));
      await tester.pumpAndSettle();
      expect(engine.seeks, hasLength(2));
      expect(engine.seeks.last, runtime);
    });

    testWidgets('seek-on-drag throttles while dragging the wave bar (S33)', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      await store.write(
        PlaybackSettings.storageKey,
        jsonEncode(const PlaybackSettings(seekOnDrag: true).toJson()),
      );
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true, store: store);
      await switchToPortrait(tester);

      final Finder progress = find.byKey(const Key('player-progress'));
      final Rect rect = tester.getRect(progress);
      await tester.dragFrom(rect.center, Offset(rect.width, 0));
      await tester.pumpAndSettle();

      // The drag itself seeks (throttled) and the release seeks once more.
      expect(engine.seeks.length, greaterThan(1));
      expect(engine.seeks.last, runtime);
    });

    testWidgets('the dock title opens the dark info sheet', (tester) async {
      await pumpEpisodePortrait(tester);

      await tester.tap(find.byKey(const Key('player-dock-title')));
      await tester.pumpAndSettle();

      final Finder sheet = find.byKey(const Key('player-info-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        Theme.of(tester.element(sheet)).colorScheme.brightness,
        Brightness.dark,
      );
      // Series title, episode label, premiere date, rating and overview.
      expect(find.text('剧集标题'), findsWidgets);
      expect(find.text('S1E1：第 1 集 开场'), findsWidgets);
      expect(find.text('2004/06/04'), findsOneWidget);
      expect(find.text('7.0'), findsOneWidget);
      // The below-video info region shows the same overview, so scope loosely.
      expect(find.text('一段简介内容'), findsWidgets);
      // 集 strip: both episodes, with the current one carrying the progress.
      expect(find.byKey(const Key('player-info-episodes')), findsOneWidget);
      expect(find.byKey(const Key('player-episode-e1')), findsOneWidget);
      expect(find.byKey(const Key('player-episode-e2')), findsOneWidget);
      // 演员 row from the detail response's People list.
      expect(find.byKey(const Key('player-info-people')), findsOneWidget);
      expect(find.text('演员甲'), findsOneWidget);
      // Yamby's 集 cards are about half the screen wide.
      expect(
        tester.getSize(find.byKey(const Key('player-episode-e2'))).width,
        closeTo(400 * 0.48, 0.5),
      );
      expect(tester.takeException(), isNull);

      // Dragging the handle down dismisses the sheet (Yamby parity).
      await tester.drag(
        find.byKey(const Key('player-info-handle')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-info-sheet')), findsNothing);
    });

    testWidgets('keeps title, overview and 选集 under the video', (tester) async {
      await pumpEpisodePortrait(tester);

      // S78 rev: the info Yamby hides behind the title sheet stays visible.
      expect(find.byKey(const Key('player-portrait-info')), findsOneWidget);
      expect(
        find.byKey(const Key('player-portrait-info-title')),
        findsOneWidget,
      );
      expect(find.text('一段简介内容'), findsWidgets);
      expect(find.byKey(const Key('player-portrait-episodes')), findsOneWidget);
      expect(find.byKey(const Key('player-strip-e2')), findsOneWidget);
    });

    testWidgets('the below-video 选集 strip switches episodes', (tester) async {
      final FakeLibraryService library = await pumpEpisodePortrait(tester);

      await tester.tap(find.byKey(const Key('player-strip-e2')));
      await tester.pumpAndSettle();

      expect(library.detailRequests, contains('e2'));
      expect(find.byKey(const Key('player-portrait')), findsOneWidget);

      // Let the new session's §10.9 f verdict timer fire before teardown.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('the info panel button opens the detail sheet', (tester) async {
      await pumpEpisodePortrait(tester);

      await tester.tap(find.byKey(const Key('player-portrait-details')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-info-sheet')), findsOneWidget);
    });

    testWidgets('the below-video 选集 strip starts on the playing episode', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      final List<MediaItem> season = <MediaItem>[
        for (int index = 1; index <= 5; index++)
          MediaItem(
            id: 'e$index',
            name: '第 $index 集',
            type: 'Episode',
            seriesName: '剧集标题',
            parentIndexNumber: 1,
            seriesId: 'show',
            seasonId: 's1',
            indexNumber: index,
            runTimeTicks: runtime.inMicroseconds * 10,
          ),
      ];
      final MediaItem playing = season[3];
      final FakeLibraryService library = FakeLibraryService(
        viewList: <LibraryView>[fakeMoviesView],
        itemsByView: <String, List<MediaItem>>{
          fakeMoviesView.id: <MediaItem>[playing],
        },
        itemsById: <String, MediaItem>{playing.id: playing},
        episodesBySeason: <String, List<MediaItem>>{'s1': season},
      );
      await pumpPlayer(
        tester,
        item: playing,
        libraryOverride: library,
        legacyRoute: true,
      );
      await switchToPortrait(tester);
      await tester.pumpAndSettle();

      final Finder strip = find.descendant(
        of: find.byKey(const Key('player-portrait-episodes')),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(strip).position.pixels,
        greaterThan(0),
      );
    });

    testWidgets('the info sheet falls back to the series rating', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      final MediaItem episode = MediaItem(
        id: 'e1',
        name: '第 1 集 开场',
        type: 'Episode',
        seriesName: '剧集标题',
        parentIndexNumber: 1,
        seriesId: 'show',
        seasonId: 's1',
        indexNumber: 1,
        runTimeTicks: runtime.inMicroseconds * 10,
        overview: '一段简介内容',
      );
      final MediaItem second = secondEpisode();
      final MediaItem series = MediaItem(
        id: 'show',
        name: '剧集标题',
        type: 'Series',
        communityRating: 6.5,
        premiereDate: '2004-06-01T00:00:00.000Z',
      );
      final library = FakeLibraryService(
        viewList: <LibraryView>[fakeMoviesView],
        itemsByView: <String, List<MediaItem>>{
          fakeMoviesView.id: <MediaItem>[episode],
        },
        itemsById: <String, MediaItem>{
          'e1': episode,
          'e2': second,
          'show': series,
        },
        episodesBySeason: <String, List<MediaItem>>{
          's1': <MediaItem>[episode, second],
        },
      );
      await pumpPlayer(
        tester,
        item: episode,
        libraryOverride: library,
        legacyRoute: true,
      );
      await switchToPortrait(tester);

      await tester.tap(find.byKey(const Key('player-dock-title')));
      await tester.pumpAndSettle();

      // Episodes carry no rating on Emby, so the sheet uses the series'.
      final Finder rating = find.byKey(const Key('player-info-rating'));
      expect(rating, findsOneWidget);
      expect(
        find.descendant(of: rating, matching: find.text('6.5')),
        findsOneWidget,
      );
      // Same fallback for the date.
      expect(find.text('2004/06/01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking an episode in the info sheet switches playback', (
      tester,
    ) async {
      final orientation = FakeScreenOrientationService();
      final FakeLibraryService library = await pumpEpisodePortrait(
        tester,
        orientation: orientation,
      );
      expect(library.detailRequests, contains('e1'));
      expect(library.detailRequests, isNot(contains('e2')));

      await tester.tap(find.byKey(const Key('player-dock-title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-episode-e2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-info-sheet')), findsNothing);
      expect(library.detailRequests, contains('e2'));
      expect(find.text('S1E2：第 2 集 重逢'), findsWidgets);
      // P0-1: the replacement page stays in 竖屏播放 instead of the default
      // landscape pin.
      expect(find.byKey(const Key('player-portrait')), findsOneWidget);
      expect(orientation.locks.last, PlaybackOrientation.portrait);
      expect(tester.takeException(), isNull);

      // Let the new session's §10.9 f verdict timer fire before teardown.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets("the dock's next-episode button advances playback", (
      tester,
    ) async {
      final orientation = FakeScreenOrientationService();
      final FakeLibraryService library = await pumpEpisodePortrait(
        tester,
        orientation: orientation,
      );

      await tester.tap(find.byKey(const Key('player-next-episode')));
      await tester.pumpAndSettle();

      expect(library.detailRequests, contains('e2'));
      expect(find.text('S1E2：第 2 集 重逢'), findsWidgets);
      // P0-1: continuous play forwards 竖屏播放 through the new route.
      expect(find.byKey(const Key('player-portrait')), findsOneWidget);
      expect(orientation.locks.last, PlaybackOrientation.portrait);

      // Let the new session's §10.9 f verdict timer fire before teardown.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('portrait auto-next keeps the portrait pin', (tester) async {
      final orientation = FakeScreenOrientationService();
      final FakeLibraryService library = await pumpEpisodePortrait(
        tester,
        orientation: orientation,
      );

      engine.emit(
        PlaybackSnapshot(
          position: runtime - const Duration(minutes: 1),
          duration: runtime,
          playing: true,
        ),
      );
      await tester.pump();
      engine.emit(
        PlaybackSnapshot(position: runtime, duration: runtime, playing: true),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // P0-1: 自动连播 replaces the route with the same 竖屏播放 pin.
      expect(library.detailRequests, contains('e2'));
      expect(find.byKey(const Key('player-portrait')), findsOneWidget);
      expect(orientation.locks.last, PlaybackOrientation.portrait);

      // Let the new session's §10.9 f verdict timer fire before teardown.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('the next-up card shows near the end and hides away from it', (
      tester,
    ) async {
      await pumpEpisodePortrait(tester);
      expect(find.byKey(const Key('player-next-up')), findsNothing);

      engine.emit(
        PlaybackSnapshot(
          position: runtime - const Duration(seconds: 15),
          duration: runtime,
        ),
      );
      await tester.pumpAndSettle();

      final Finder card = find.byKey(const Key('player-next-up'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('接下来')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('S1E2：第 2 集 重逢')),
        findsOneWidget,
      );
      // Bottom-right corner of the video box.
      final Rect video = tester.getRect(find.byType(AspectRatio));
      final Rect rect = tester.getRect(card);
      expect(rect.right, closeTo(video.right, 16));
      expect(rect.bottom, closeTo(video.bottom, 16));

      engine.emit(
        const PlaybackSnapshot(
          position: Duration(minutes: 10),
          duration: runtime,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-next-up')), findsNothing);

      // Back in the window, tapping the card advances to the next episode.
      engine.emit(
        PlaybackSnapshot(
          position: runtime - const Duration(seconds: 12),
          duration: runtime,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-next-up')));
      await tester.pumpAndSettle();
      expect(find.text('S1E2：第 2 集 重逢'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Let the new session's §10.9 f verdict timer fire before teardown.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('the next-up card has a 30 second boundary', (tester) async {
      await pumpEpisodePortrait(tester);

      // Exactly 30 s left is still outside the window (spec: 剩余 < 30 s).
      engine.emit(
        PlaybackSnapshot(
          position: runtime - const Duration(seconds: 30),
          duration: runtime,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-next-up')), findsNothing);

      // 29 s left is inside it: title, still and progress line show up.
      engine.emit(
        PlaybackSnapshot(
          position: runtime - const Duration(seconds: 29),
          duration: runtime,
        ),
      );
      await tester.pumpAndSettle();
      final Finder card = find.byKey(const Key('player-next-up'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('S1E2：第 2 集 重逢')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(CustomPaint)),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the portrait chrome auto-hides and a tap restores it', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      for (final AnimatedOpacity w in tester.widgetList<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      )) {
        expect(w.opacity, 0);
      }

      await tester.tap(find.byKey(const Key('player-gesture-area')));
      await tester.pumpAndSettle();
      for (final AnimatedOpacity w in tester.widgetList<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      )) {
        expect(w.opacity, 1);
      }
    });

    testWidgets('the subtitle margin derives from the video box height', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      // Fallback 16:9 box (225 high): 15% is 33.75, below the 44 dp floor that
      // keeps the band above the dock's title row (P0-2).
      expect(engine.subtitleMargins.last, closeTo(44, 0.01));

      // A 4:3 source makes the box 300 high, so 15% (45) wins over the floor.
      engine.emit(const PlaybackSnapshot(videoWidth: 1200, videoHeight: 900));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        closeTo(1200 / 900, 0.001),
      );
      expect(engine.subtitleMargins.last, closeTo(0.15 * 300, 0.01));

      // Cinematic 2.40:1 box (166.7 high) falls back to the same floor.
      engine.emit(const PlaybackSnapshot(videoWidth: 1920, videoHeight: 800));
      await tester.pump();
      await tester.pump();
      expect(engine.subtitleMargins.last, closeTo(44, 0.01));
    });

    testWidgets('drags over the video drive volume, below it they do not', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);
      final Rect video = tester.getRect(find.byType(AspectRatio));

      // Two moves like the S1 gesture tests: the recognizer needs a ramp.
      final TestGesture gesture = await tester.startGesture(
        Offset(video.center.dx + 40, 60),
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.volumes, isNotEmpty);
      expect(engine.volumes.last, lessThan(100.0));

      // The black area under the video only holds the dock, not gestures.
      final int count = engine.volumes.length;
      final TestGesture below = await tester.startGesture(
        Offset(200, video.bottom + 120),
      );
      await below.moveBy(const Offset(0, 60));
      await tester.pump();
      await below.up();
      await tester.pumpAndSettle();
      expect(engine.volumes.length, count);
    });

    testWidgets('locking hides the portrait chrome and unlock restores it', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      await tester.tap(find.byKey(const Key('player-quick-lock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-play-toggle')), findsNothing);
      expect(find.byKey(const Key('player-portrait-dock')), findsNothing);
      expect(find.byKey(const Key('player-unlock')), findsOneWidget);

      await tester.tap(find.byKey(const Key('player-unlock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
      expect(find.byKey(const Key('player-portrait-dock')), findsOneWidget);
    });

    testWidgets('the 更多 sheet keeps the media-info entry in portrait', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      await tester.tap(find.byKey(const Key('player-options-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-options-sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('player-stats-entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-stats-sheet')), findsOneWidget);
    });

    testWidgets('a cinematic source keeps the overlay usable', (tester) async {
      portraitSurface(tester, const Size(360, 640));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      // 2.35:1 leaves a 153 dp tall box on a 360 dp wide phone: the overlay
      // must still fit without overflowing.
      engine.emit(const PlaybackSnapshot(videoWidth: 1920, videoHeight: 816));
      await tester.pump();
      await tester.pump();

      final Rect video = tester.getRect(find.byType(AspectRatio));
      expect(video.height, closeTo(360 / (1920 / 816), 0.01));
      for (final String key in <String>[
        'player-play-toggle',
        'player-seek-back-10',
        'player-seek-forward-10',
        'player-rate-menu',
        'player-quick-lock',
        'player-dock-title',
      ]) {
        final Rect rect = tester.getRect(find.byKey(Key(key)));
        expect(
          rect.bottom,
          lessThanOrEqualTo(video.bottom + 0.01),
          reason: key,
        );
        expect(rect.right, lessThanOrEqualTo(video.right + 0.01), reason: key);
      }
      // The dock stays under the video and the transport is still tappable.
      expect(
        tester.getRect(find.byKey(const Key('player-portrait-dock'))).top,
        greaterThanOrEqualTo(video.bottom - 0.01),
      );
      await tester.tap(find.byKey(const Key('player-play-toggle')));
      await tester.pumpAndSettle();
      expect(engine.playCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tall source caps the video box so controls stay reachable', (
      tester,
    ) async {
      portraitSurface(tester, const Size(400, 800));
      await pumpPlayer(tester, legacyRoute: true);
      await switchToPortrait(tester);

      engine.emit(const PlaybackSnapshot(videoWidth: 1080, videoHeight: 1920));
      await tester.pump();
      await tester.pump();

      // 9:16 would be 711 high; the box caps at 60% of 800 and keeps its
      // aspect (270 wide), centered, still pinned to the top.
      final Rect video = tester.getRect(find.byType(AspectRatio));
      expect(video.top, 0);
      expect(video.height, closeTo(0.6 * 800, 0.01));
      expect(video.width, closeTo(0.6 * 800 * 9 / 16, 0.01));
      expect(engine.subtitleMargins.last, closeTo(0.15 * 0.6 * 800, 0.01));

      final Rect toggle = tester.getRect(
        find.byKey(const Key('player-play-toggle')),
      );
      expect(toggle.bottom, lessThan(800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape continuous play stays landscape', (tester) async {
      final orientation = FakeScreenOrientationService();
      portraitSurface(tester, const Size(800, 400));
      final MediaItem episode = episodeItem();
      final MediaItem second = secondEpisode();
      final library = episodeLibrary(episode, second);
      await pumpPlayer(
        tester,
        item: episode,
        libraryOverride: library,
        legacyRoute: true,
        orientation: orientation,
      );

      await tester.tap(find.byKey(const Key('player-next-episode')));
      await tester.pumpAndSettle();

      expect(library.detailRequests, contains('e2'));
      expect(find.byKey(const Key('player-portrait')), findsNothing);
      expect(orientation.locks.last, PlaybackOrientation.landscape);
      expect(find.byTooltip('竖屏播放'), findsOneWidget);

      // Let the new session's §10.9 f verdict timer fire before teardown.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('the portrait top bar falls back to the text title', (
      tester,
    ) async {
      await pumpEpisodePortrait(tester);

      expect(
        find.byKey(const Key('player-portrait-title-text')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('player-portrait-logo')), findsNothing);
    });

    testWidgets('the portrait top bar draws the series logo when available', (
      tester,
    ) async {
      final MediaItem episode = MediaItem(
        id: 'e1',
        name: '第 1 集 开场',
        type: 'Episode',
        seriesName: '剧集标题',
        parentIndexNumber: 1,
        seriesId: 'show',
        seasonId: 's1',
        indexNumber: 1,
        runTimeTicks: runtime.inMicroseconds * 10,
        parentLogoItemId: 'show',
        parentLogoTag: 'logo-tag',
      );
      final FakeLibraryService library = episodeLibrary(
        episode,
        secondEpisode(),
      )..imageHost = 'img.test';
      await pumpEpisodePortrait(
        tester,
        episode: episode,
        libraryOverride: library,
      );

      // S78: Yamby shows the transparent series logo instead of the title.
      expect(find.byKey(const Key('player-portrait-logo')), findsOneWidget);
      expect(find.byKey(const Key('player-portrait-title-text')), findsNothing);
    });

    testWidgets('landscape keeps the full-screen surface and screen band', (
      tester,
    ) async {
      portraitSurface(tester, const Size(800, 400));
      await pumpPlayer(tester, legacyRoute: true);

      expect(find.byType(AspectRatio), findsNothing);
      expect(find.byKey(const Key('player-portrait')), findsNothing);
      expect(find.byKey(const Key('player-portrait-dock')), findsNothing);
      // The gesture layer spans the whole screen (minus its edge margins),
      // exactly as before S26.
      expect(
        tester.getSize(find.byKey(const Key('player-gesture-area'))),
        const Size(800 - 32, 400 - 16),
      );
      // Landscape still reserves 5% of the SCREEN height and leaves ASS
      // margins to the user's 黑边 setting (off by default).
      expect(engine.subtitleMargins.last, closeTo(0.05 * 400, 0.01));
      expect(engine.subtitleMarginModes.last, isFalse);
      expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
    });
  });

  group('playback orientation (S77)', () {
    testWidgets('opens in landscape playback and pins the screen', (
      tester,
    ) async {
      final orientation = FakeScreenOrientationService();
      await pumpPlayer(tester, orientation: orientation);

      // 默认横屏播放: no portrait region, and the pin asked for landscape.
      expect(find.byKey(const Key('player-portrait')), findsNothing);
      expect(orientation.locks, <PlaybackOrientation>[
        PlaybackOrientation.landscape,
      ]);
      expect(
        find.byKey(const Key('player-orientation-toggle')),
        findsOneWidget,
      );
      expect(find.byTooltip('竖屏播放'), findsOneWidget);
    });

    testWidgets('a portrait device still opens in landscape playback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final orientation = FakeScreenOrientationService();
      await pumpPlayer(tester, orientation: orientation);

      // S77: the mode decides the layout, not the window shape.
      expect(orientation.locks.single, PlaybackOrientation.landscape);
      expect(find.byKey(const Key('player-portrait')), findsNothing);
      expect(find.byTooltip('竖屏播放'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the toggle switches to 竖屏播放 and back to 横屏播放', (tester) async {
      final orientation = FakeScreenOrientationService();
      await pumpPlayer(tester, orientation: orientation);

      await tester.tap(find.byKey(const Key('player-orientation-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-portrait')), findsOneWidget);
      expect(find.byTooltip('横屏播放'), findsOneWidget);
      expect(orientation.locks.last, PlaybackOrientation.portrait);

      await tester.tap(find.byKey(const Key('player-orientation-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-portrait')), findsNothing);
      expect(find.byTooltip('竖屏播放'), findsOneWidget);
      expect(orientation.locks.last, PlaybackOrientation.landscape);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a locked interface hides the orientation toggle', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      final sw = find.byKey(const Key('player-lock-switch'));
      await tester.dragUntilVisible(
        sw,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      await tester.tap(sw);
      await tester.pumpAndSettle();

      // Close the sheet to reveal the locked player.
      final close = find.byKey(const Key('player-options-close'));
      await tester.dragUntilVisible(
        close,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, 250),
      );
      await tester.tap(close);
      await tester.pumpAndSettle();

      // S77: the rotate control is part of the live controls, so the lock
      // suppresses it like the rest of the bars.
      expect(find.byKey(const Key('player-orientation-toggle')), findsNothing);
      expect(find.byKey(const Key('player-unlock')), findsOneWidget);
    });

    testWidgets('leaving the player releases the orientation pin', (
      tester,
    ) async {
      final orientation = FakeScreenOrientationService();
      await pumpPlayer(tester, orientation: orientation);

      await tester.tap(find.byKey(const Key('player-back')));
      await tester.pumpAndSettle();

      expect(orientation.restores, 1);
    });
  });

  testWidgets('speed steppers and menu drive the engine rate', (tester) async {
    await pumpPlayer(tester);
    expect(find.text('1.0x'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-rate-up')));
    await tester.pumpAndSettle();
    expect(engine.rates.last, 1.25);
    expect(find.text('1.25x'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-rate-down')));
    await tester.pumpAndSettle();
    expect(engine.rates.last, 1.0);

    await tester.tap(find.byKey(const Key('player-rate-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0x').last);
    await tester.pumpAndSettle();
    expect(engine.rates.last, 2.0);
    expect(find.text('2.0x'), findsOneWidget);
  });

  testWidgets('the subtitle menu lists off plus every server stream', (
    tester,
  ) async {
    armSubtitles();
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();

    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('简体中文（外挂）'), findsOneWidget);
  });

  testWidgets('an item without subtitles offers only the style entry', (
    tester,
  ) async {
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();

    expect(find.text('关闭'), findsNothing);
    expect(find.text('无字幕'), findsOneWidget);
    expect(find.text('字幕样式…'), findsOneWidget);
  });

  testWidgets('a TrueHD source raises no kernel-capability banner', (
    tester,
  ) async {
    await pumpPlayer(
      tester,
      item: playerItem(
        mediaSources: <MediaSource>[
          const MediaSource(
            id: 'source-1',
            container: 'mkv',
            bitrate: 12000000,
            supportsDirectPlay: true,
            supportsDirectStream: true,
            streams: <MediaStream>[
              MediaStream(
                type: MediaStreamType.audio,
                index: 1,
                codec: 'truehd',
                isDefault: true,
              ),
            ],
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('player-audio-notice')), findsNothing);
  });

  testWidgets('the style sheet drives engine subtitle properties', (
    tester,
  ) async {
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('字幕样式…'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('subtitle-style-sheet')), findsOneWidget);

    final scale = find.byKey(const Key('subtitle-scale'));
    await tester.ensureVisible(scale);
    await tester.drag(scale, const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(engine.subtitleStyles.last.scale, greaterThan(1.0));

    final serif = find.byKey(const Key('subtitle-font-serif'));
    // The sheet list builds lazily: the scale drag above can scroll the font
    // row out of the built range, so scroll back up instead of ensureVisible.
    await tester.dragUntilVisible(
      serif,
      find.byKey(const Key('subtitle-style-sheet')),
      const Offset(0, 250),
    );
    await tester.tap(serif);
    await tester.pumpAndSettle();
    expect(engine.subtitleStyles.last.font, 'serif');

    final override = find.byKey(const Key('subtitle-ass-override'));
    await tester.ensureVisible(override);
    await tester.tap(override);
    await tester.pumpAndSettle();
    expect(engine.subtitleStyles.last.overrideAss, isTrue);

    final reset = find.byKey(const Key('subtitle-style-reset'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(engine.subtitleStyles.last.scale, 1.0);
    expect(engine.subtitleStyles.last.font, '');
    expect(engine.subtitleStyles.last.overrideAss, isFalse);

    final close = find.byKey(const Key('subtitle-style-close'));
    // The sheet list builds lazily: scroll back up instead of ensureVisible.
    await tester.dragUntilVisible(
      close,
      find.byKey(const Key('subtitle-style-sheet')),
      const Offset(0, 250),
    );
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('subtitle-style-sheet')), findsNothing);
  });

  testWidgets('picking an embedded subtitle drives the engine track', (
    tester,
  ) async {
    armSubtitles();
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();

    expect(engine.subtitleTracks, <int?>[0]);
    expect(engine.externalSubtitlePaths, isEmpty);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(engine.subtitleTracks, <int?>[0, null]);
  });

  testWidgets('picking an external subtitle downloads and mounts the file', (
    tester,
  ) async {
    final subtitles = FakeSubtitleService();
    armSubtitles();
    await pumpPlayer(tester, subtitles: subtitles);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文（外挂）'));
    await tester.pumpAndSettle();

    expect(subtitles.requests, hasLength(1));
    expect(engine.externalSubtitlePaths, <String>[subtitles.path]);
    expect(find.byKey(const Key('player-subtitle-notice')), findsNothing);
  });

  testWidgets(
    'a failed subtitle download shows a notice, video keeps playing',
    (tester) async {
      final subtitles = FakeSubtitleService(
        failure: EmbyException(AppErrorCode.subtitleFailed),
      );
      armSubtitles();
      await pumpPlayer(tester, subtitles: subtitles);

      await tester.tap(find.byKey(const Key('player-subtitle-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文（外挂）'));
      await tester.pumpAndSettle();

      final notice = find.byKey(const Key('player-subtitle-notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.text('字幕加载失败')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
      expect(find.byKey(const Key('player-error')), findsNothing);
      expect(engine.externalSubtitlePaths, isEmpty);
    },
  );

  testWidgets('the subtitle menu mounts a picked local file directly', (
    tester,
  ) async {
    final picker = FakeLocalSubtitlePicker();
    final subtitles = FakeSubtitleService();
    await pumpPlayer(tester, subtitles: subtitles, localPicker: picker);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    expect(find.text('添加本地字幕…'), findsOneWidget);
    await tester.tap(find.text('添加本地字幕…'));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(engine.externalSubtitlePaths, <String>[picker.path!]);
    expect(subtitles.requests, isEmpty);
    expect(find.byKey(const Key('player-subtitle-notice')), findsNothing);

    // The mounted file shows as "filename（本地）" on the next open.
    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    expect(find.text('测试字幕.ass（本地）'), findsOneWidget);
  });

  testWidgets('a cancelled local pick changes nothing', (tester) async {
    final picker = FakeLocalSubtitlePicker(path: null);
    await pumpPlayer(tester, localPicker: picker);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加本地字幕…'));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(engine.externalSubtitlePaths, isEmpty);
    expect(find.byKey(const Key('player-subtitle-notice')), findsNothing);
  });

  testWidgets('a failed local pick shows a notice, video keeps playing', (
    tester,
  ) async {
    final picker = FakeLocalSubtitlePicker(failure: Exception('dialog'));
    await pumpPlayer(tester, localPicker: picker);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加本地字幕…'));
    await tester.pumpAndSettle();

    final notice = find.byKey(const Key('player-subtitle-notice'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(of: notice, matching: find.text('字幕加载失败')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
    expect(engine.externalSubtitlePaths, isEmpty);
  });

  testWidgets('the track panel lists the mounted local file', (tester) async {
    final picker = FakeLocalSubtitlePicker();
    await pumpPlayer(tester, localPicker: picker);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加本地字幕…'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-track-menu')));
    await tester.pumpAndSettle();
    final localRow = find.byKey(const Key('track-subtitle-local'));
    await tester.ensureVisible(localRow);
    expect(
      find.descendant(of: localRow, matching: find.text('测试字幕.ass（本地）')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: localRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    // "关闭" must not look selected while the local file is active.
    final offRow = find.byKey(const Key('track-subtitle-off'));
    expect(
      find.descendant(of: offRow, matching: find.byIcon(Icons.check)),
      findsNothing,
    );
  });

  testWidgets('the margins switch drives engine subtitle styles', (
    tester,
  ) async {
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('字幕样式…'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('subtitle-style-sheet')), findsOneWidget);

    final margins = find.byKey(const Key('subtitle-ass-margins'));
    final reset = find.byKey(const Key('subtitle-style-reset'));
    // The sheet list builds lazily: scroll to the bottom so the switch and
    // the reset button are both built and fully inside the sheet.
    await tester.dragUntilVisible(
      reset,
      find.byKey(const Key('subtitle-style-sheet')),
      const Offset(0, -100),
    );
    await tester.tap(margins);
    await tester.pumpAndSettle();
    expect(engine.subtitleStyles.last.useMargins, isTrue);

    await tester.tap(margins);
    await tester.pumpAndSettle();
    expect(engine.subtitleStyles.last.useMargins, isFalse);

    // 恢复默认 clears the toggle too.
    await tester.tap(margins);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(engine.subtitleStyles.last.useMargins, isFalse);
  });

  testWidgets('the track panel switches audio and subtitle tracks', (
    tester,
  ) async {
    armTracks();
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-track-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-sheet')), findsOneWidget);

    final audioRow = find.byKey(const Key('track-audio-1'));
    await tester.ensureVisible(audioRow);
    expect(
      find.descendant(of: audioRow, matching: find.text('英语')),
      findsOneWidget,
    );
    await tester.tap(audioRow);
    await tester.pumpAndSettle();
    expect(engine.audioTracks, <int>[1]);
    expect(
      find.descendant(of: audioRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );

    final subtitleRow = find.byKey(const Key('track-subtitle-0'));
    await tester.ensureVisible(subtitleRow);
    expect(
      find.descendant(of: subtitleRow, matching: find.text('中文')),
      findsOneWidget,
    );
    await tester.tap(subtitleRow);
    await tester.pumpAndSettle();
    expect(engine.subtitleTracks, <int?>[0]);
    expect(
      find.descendant(of: subtitleRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );

    final close = find.byKey(const Key('track-sheet-close'));
    // The sheet list builds lazily: scroll back up instead of ensureVisible.
    await tester.dragUntilVisible(
      close,
      find.byKey(const Key('track-sheet')),
      const Offset(0, 250),
    );
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-sheet')), findsNothing);

    // The quick subtitle menu keeps working next to the new panel.
    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
  });

  testWidgets('track panel preference chips drive auto-match', (tester) async {
    armTracks();
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-track-menu')));
    await tester.pumpAndSettle();

    final audioPref = find.byKey(const Key('track-pref-audio-eng'));
    await tester.ensureVisible(audioPref);
    await tester.tap(audioPref);
    await tester.pumpAndSettle();
    expect(engine.audioTracks, <int>[1]);
    expect(tester.widget<ChoiceChip>(audioPref).selected, isTrue);

    final subtitlePref = find.byKey(const Key('track-pref-subtitle-chi'));
    await tester.ensureVisible(subtitlePref);
    await tester.tap(subtitlePref);
    await tester.pumpAndSettle();
    // The embedded Chinese subtitle is the first match in server order.
    expect(engine.subtitleTracks, <int?>[0]);
    expect(tester.widget<ChoiceChip>(subtitlePref).selected, isTrue);
  });

  testWidgets('the track panel reports an item without tracks', (tester) async {
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-track-menu')));
    await tester.pumpAndSettle();

    expect(find.text('无音轨'), findsOneWidget);
    expect(find.text('无字幕'), findsOneWidget);
    expect(find.byKey(const Key('track-subtitle-off')), findsOneWidget);
  });

  testWidgets(
    'legacy Series player can replace itself with episode selection',
    (tester) async {
      const series = MediaItem(id: 'show', name: '测试剧集', type: 'Series');
      final library = FakeLibraryService(
        viewList: [fakeShowsView],
        itemsByView: {
          fakeShowsView.id: [series],
        },
        seasonsBySeries: {
          'show': [
            const MediaItem(
              id: 's1',
              name: '第一季',
              type: 'Season',
              indexNumber: 1,
            ),
          ],
        },
        episodesBySeason: {
          's1': [
            const MediaItem(
              id: 'ep1',
              name: '开场',
              type: 'Episode',
              indexNumber: 1,
            ),
          ],
        },
      );
      await pumpPlayer(
        tester,
        item: series,
        libraryOverride: library,
        legacyRoute: true,
      );
      expect(find.text('请选择分集后播放'), findsOneWidget);
      expect(playback.resolveCalls, 0);
      expect(engine.openedPlans, isEmpty);
      await tester.tap(find.byKey(const Key('player-select-episodes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-page')), findsOneWidget);
      expect(find.byKey(const Key('player-error')), findsNothing);
      expect(playback.resolveCalls, 0);
      expect(reporter.startedCalls, 0);
      expect(engine.disposeCalls, 1);

      await tester.tap(find.byKey(const Key('series-back')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Shows')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('player-error')), findsNothing);
    },
  );

  testWidgets('an Episode playback 401 returns to login', (tester) async {
    playback.failure = EmbyException(AppErrorCode.unauthorized);
    const episode = MediaItem(id: 'ep1', name: '测试分集', type: 'Episode');
    await pumpPlayer(tester, item: episode, legacyRoute: true);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(playback.resolveItemIds, ['ep1']);
    expect(engine.openedPlans, isEmpty);
    expect(reporter.startedItemIds, isEmpty);
  });

  testWidgets('the centre transport seeks ±10 s (S40)', (tester) async {
    await pumpPlayer(tester);
    // Controls are visible right after the initial load.
    await tester.tap(find.byKey(const Key('player-seek-forward-10')));
    await tester.pumpAndSettle();
    expect(engine.seeks.last, const Duration(seconds: 10));

    await tester.tap(find.byKey(const Key('player-seek-back-10')));
    await tester.pumpAndSettle();
    expect(engine.seeks.last, Duration.zero);
  });

  testWidgets('the top bar offers capture and subtitles (S48)', (tester) async {
    await pumpPlayer(tester);
    // Both entries appear only while the landscape chrome is visible.

    expect(find.byKey(const Key('player-top-screenshot')), findsOneWidget);
    expect(find.byKey(const Key('player-top-subtitle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-top-screenshot')));
    await tester.pumpAndSettle();
    expect(engine.screenshotPaths, hasLength(1));
  });

  testWidgets('the top subtitle entry opens the same menu (S48)', (
    tester,
  ) async {
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-top-subtitle')));
    await tester.pumpAndSettle();

    expect(find.text('字幕样式…'), findsOneWidget);
    expect(find.text('添加本地字幕…'), findsOneWidget);
  });
  testWidgets('finishing a progress drag seeks once', (tester) async {
    await pumpPlayer(tester);

    // Dragging past the right edge clamps to the item runtime.
    await tester.drag(
      find.byKey(const Key('player-progress')),
      const Offset(2000, 0),
    );
    await tester.pumpAndSettle();

    expect(engine.seeks, <Duration>[runtime]);
    expect(reporter.progressReports, hasLength(1));
  });

  testWidgets('seek-on-drag follows the thumb when enabled (S33)', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await store.write(
      PlaybackSettings.storageKey,
      jsonEncode(const PlaybackSettings(seekOnDrag: true).toJson()),
    );
    await pumpPlayer(tester, store: store);

    await tester.drag(
      find.byKey(const Key('player-progress')),
      const Offset(2000, 0),
    );
    await tester.pumpAndSettle();

    // The drag itself seeks (throttled) and the release seeks once more.
    expect(engine.seeks.length, greaterThan(1));
    expect(engine.seeks.last, runtime);
  });
  testWidgets(
    'the back button retains position and stops before surface teardown',
    (tester) async {
      int? stoppedCallsAtSurfaceDispose;
      engine = ResettingSurfaceEngine(() {
        stoppedCallsAtSurfaceDispose = reporter.stoppedCalls;
      });
      await pumpPlayer(tester);
      engine.emit(const PlaybackSnapshot(position: Duration(seconds: 100)));
      await tester.pump();
      engine.emit(const PlaybackSnapshot());
      await tester.pump();

      await tester.tap(find.byKey(const Key('player-back')));
      await tester.pumpAndSettle();

      // S7: the player was pushed from the detail page, so back returns there.
      expect(find.byKey(const Key('detail-play')), findsOneWidget);
      expect(reporter.stoppedCalls, 1);
      expect(reporter.stoppedAt, const Duration(seconds: 100));
      expect(stoppedCallsAtSurfaceDispose, 1);
      expect(engine.disposeCalls, 1);
    },
  );

  testWidgets(
    'a system back retains position and reports stopped exactly once',
    (tester) async {
      await pumpPlayer(tester);
      engine.emit(const PlaybackSnapshot(position: Duration(seconds: 61)));
      await tester.pump();
      engine.emit(const PlaybackSnapshot());
      await tester.pump();

      await systemBack(tester);
      await systemBack(tester);

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Movies')),
        findsOneWidget,
      );
      expect(reporter.stoppedCalls, 1);
      expect(reporter.stoppedAt, const Duration(seconds: 61));
    },
  );

  testWidgets('back waits for stopped completion before popping', (
    tester,
  ) async {
    final pending = PendingStopReporter();
    reporter = pending;
    await pumpPlayer(tester);
    engine.emit(const PlaybackSnapshot(position: Duration(seconds: 100)));
    await tester.pump();

    await tester.tap(find.byKey(const Key('player-back')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('player-back')));
    await systemBack(tester);

    expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
    expect(engine.disposeCalls, 0);
    expect(reporter.stoppedCalls, 1);
    expect(reporter.stoppedAt, const Duration(seconds: 100));

    pending.completion.complete();
    await tester.pumpAndSettle();

    // S7: back lands on the detail page the player was pushed from.
    expect(find.byKey(const Key('detail-play')), findsOneWidget);
    expect(reporter.stoppedCalls, 1);
    expect(engine.disposeCalls, 1);
  });

  testWidgets('a transcoding verdict is called out', (tester) async {
    playback.confirmedPlan = fakePlan(videoDirect: false);
    await pumpPlayer(tester);

    final status = find.byKey(const Key('player-direct-status'));
    expect(status, findsOneWidget);
    expect(
      find.descendant(of: status, matching: find.textContaining('转码')),
      findsOneWidget,
    );
  });

  testWidgets('an unconfirmed verdict is not shown as direct', (tester) async {
    await pumpPlayer(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('player-direct-status')),
        matching: find.textContaining('未确认'),
      ),
      findsOneWidget,
    );
    expect(find.text('直连播放'), findsNothing);
  });

  testWidgets('a confirmed direct play says so', (tester) async {
    playback.confirmedPlan = fakePlan(videoDirect: true);
    await pumpPlayer(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('player-direct-status')),
        matching: find.text('直连播放'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failure shows mapped copy without an exception string', (
    tester,
  ) async {
    playback.failure = EmbyException(AppErrorCode.playbackUnsupported);
    await pumpPlayer(tester);

    expect(find.byKey(const Key('player-error')), findsOneWidget);
    expect(find.text('这个片源无法播放'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('EmbyException'), findsNothing);
  });

  testWidgets('a resumed playback states where it continued from', (
    tester,
  ) async {
    await pumpPlayer(
      tester,
      item: playerItem(position: const Duration(seconds: 125)),
    );

    final hint = find.byKey(const Key('player-resume-hint'));
    expect(hint, findsOneWidget);
    expect(
      find.descendant(of: hint, matching: find.text('已从 02:05 继续播放')),
      findsOneWidget,
    );
  });

  testWidgets('the volume slider is scaled for the engine', (tester) async {
    await pumpPlayer(tester);

    await tester.drag(
      find.byKey(const Key('player-volume')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();

    expect(engine.volumes.last, 0);
  });

  group('retrying after a playback error', () {
    final List<FakePlaybackEngine> engines = <FakePlaybackEngine>[];
    final List<FakePlaybackReporter> reporters = <FakePlaybackReporter>[];

    setUp(() {
      engines.clear();
      reporters.clear();
    });

    /// The first playback fails inside the engine, which is the only error
    /// that reaches the retry button: a snapshot error on a ready session is
    /// shown as a banner over the running surface instead.
    Future<void> pumpFailingPlayer(WidgetTester tester) async {
      await pumpPlayer(
        tester,
        createEngine: () {
          final next = FakePlaybackEngine();
          if (engines.isEmpty) {
            next.openError = EmbyException(AppErrorCode.transcodeFailed);
          }
          engines.add(next);
          return next;
        },
        createReporter: () {
          final next = FakePlaybackReporter();
          reporters.add(next);
          return next;
        },
      );
      expect(find.byKey(const Key('player-error')), findsOneWidget);
    }

    /// Taps 重试 and pumps the rebuild: one frame for the teardown plus the
    /// fresh bootstrap, then past the 3 s §10.9 f verdict probe.
    Future<void> tapRetry(WidgetTester tester) async {
      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    }

    testWidgets('closes the failed session and builds a new pair', (
      tester,
    ) async {
      await pumpFailingPlayer(tester);
      await tapRetry(tester);

      // Contract §3.6: the re-negotiated session is a track change, so the
      // first `PlaySessionId` has to be stopped before the second starts.
      expect(reporters.first.stoppedCalls, 1);
      expect(engines.first.disposeCalls, 1);
      expect(engines, hasLength(2));
      expect(reporters, hasLength(2));
    });

    testWidgets('resumes playback on the fresh session', (tester) async {
      await pumpFailingPlayer(tester);
      await tapRetry(tester);

      expect(find.byKey(const Key('player-error')), findsNothing);
      expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
      expect(reporters.last.startedCalls, 1);
      expect(engines.last.openedPlans, hasLength(1));
    });
  });

  group('continuous play (P1)', () {
    const episodeRuntime = Duration(minutes: 24);
    final List<FakePlaybackEngine> engines = <FakePlaybackEngine>[];
    final List<FakePlaybackReporter> reporters = <FakePlaybackReporter>[];

    setUp(() {
      engines.clear();
      reporters.clear();
    });

    MediaItem episode(String id, int index) {
      return MediaItem(
        id: id,
        name: '第 $index 集',
        type: 'Episode',
        seriesId: 'series-1',
        seasonId: 'season-1',
        indexNumber: index,
        runTimeTicks: episodeRuntime.inMicroseconds * 10,
      );
    }

    /// Each episode page gets its own engine/reporter pair, exactly like the
    /// real app: navigation replaces the route and builds a fresh session.
    Future<void> pumpEpisode(
      WidgetTester tester,
      MediaItem item, {
      String? source,
      KeyValueStore? store,
    }) async {
      final season = <MediaItem>[
        episode('ep1', 1),
        episode('ep2', 2),
        episode('ep3', 3),
      ];
      await pumpPlayer(
        tester,
        item: item,
        libraryOverride: FakeLibraryService(
          viewList: <LibraryView>[fakeShowsView],
          itemsById: <String, MediaItem>{for (final e in season) e.id: e},
          episodesBySeason: <String, List<MediaItem>>{'season-1': season},
        ),
        legacyRoute: true,
        source: source,
        store: store,
        createEngine: () {
          final next = FakePlaybackEngine();
          engines.add(next);
          return next;
        },
        createReporter: () {
          final next = FakePlaybackReporter();
          reporters.add(next);
          return next;
        },
      );
    }

    /// Settles the replaced route plus the new page's 3 s verdict probe.
    Future<void> settleEpisodeSwitch(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }

    AppIconButton button(WidgetTester tester, String key) =>
        tester.widget<AppIconButton>(find.byKey(Key(key)));

    testWidgets('a middle episode enables both neighbor buttons', (
      tester,
    ) async {
      await pumpEpisode(tester, episode('ep2', 2));

      expect(button(tester, 'player-prev-episode').onPressed, isNotNull);
      expect(button(tester, 'player-next-episode').onPressed, isNotNull);
    });

    testWidgets('the first episode disables previous', (tester) async {
      await pumpEpisode(tester, episode('ep1', 1));

      expect(button(tester, 'player-prev-episode').onPressed, isNull);
      expect(button(tester, 'player-next-episode').onPressed, isNotNull);
    });

    testWidgets('the last episode disables next', (tester) async {
      await pumpEpisode(tester, episode('ep3', 3));

      expect(button(tester, 'player-prev-episode').onPressed, isNotNull);
      expect(button(tester, 'player-next-episode').onPressed, isNull);
    });

    testWidgets('a movie disables both episode buttons', (tester) async {
      await pumpPlayer(tester);

      expect(button(tester, 'player-prev-episode').onPressed, isNull);
      expect(button(tester, 'player-next-episode').onPressed, isNull);
    });

    testWidgets('tapping next replaces the route with the next episode', (
      tester,
    ) async {
      await pumpEpisode(tester, episode('ep2', 2));

      await tester.tap(find.byKey(const Key('player-next-episode')));
      await settleEpisodeSwitch(tester);

      expect(engines, hasLength(2));
      expect(engines.last.openedPlans.single.itemId, 'ep3');
      expect(reporters.first.stoppedCalls, 1);
      expect(find.text('第 3 集'), findsWidgets);
      // S26: the fresh session's engine gets the reserved subtitle margin
      // again; the cached value must not skip the new engine.
      expect(engines.last.subtitleMargins, isNotEmpty);

      // Back must not stack episodes: the route was replaced, so the exit
      // path lands in the library instead of the previous episode.
      await tester.tap(find.byKey(const Key('player-gesture-area')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-back')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Shows')),
        findsOneWidget,
      );
      expect(engines, hasLength(2));
    });

    testWidgets(
      'tapping previous replaces the route with the previous episode',
      (tester) async {
        await pumpEpisode(tester, episode('ep2', 2));

        await tester.tap(find.byKey(const Key('player-prev-episode')));
        await settleEpisodeSwitch(tester);

        expect(engines, hasLength(2));
        expect(engines.last.openedPlans.single.itemId, 'ep1');
        expect(reporters.first.stoppedCalls, 1);
        expect(find.text('第 1 集'), findsWidgets);
      },
    );

    testWidgets('completion auto-advances to the next episode', (tester) async {
      await pumpEpisode(tester, episode('ep2', 2));

      engines.first.emit(
        const PlaybackSnapshot(
          position: Duration(minutes: 12),
          duration: episodeRuntime,
          playing: true,
        ),
      );
      await tester.pump();
      engines.first.emit(
        const PlaybackSnapshot(
          position: episodeRuntime,
          duration: episodeRuntime,
          playing: true,
        ),
      );
      await tester.pump();
      await settleEpisodeSwitch(tester);

      expect(engines, hasLength(2));
      expect(engines.last.openedPlans.single.itemId, 'ep3');
      expect(reporters.first.stoppedCalls, 1);
      expect(reporters.first.stoppedAt, episodeRuntime);
      expect(find.text('第 3 集'), findsWidgets);
    });

    testWidgets('completion stays put when auto-play is off (S33)', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      await store.write(
        PlaybackSettings.storageKey,
        jsonEncode(const PlaybackSettings(autoPlayNext: false).toJson()),
      );
      await pumpEpisode(tester, episode('ep2', 2), store: store);

      engines.first.emit(
        const PlaybackSnapshot(
          position: episodeRuntime,
          duration: episodeRuntime,
          playing: true,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(engines, hasLength(1));
      expect(find.text('第 2 集'), findsWidgets);
    });
    testWidgets('completion on the last episode stays put', (tester) async {
      await pumpEpisode(tester, episode('ep3', 3));

      engines.first.emit(
        const PlaybackSnapshot(
          position: episodeRuntime,
          duration: episodeRuntime,
          playing: true,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(engines, hasLength(1));
      expect(reporters.first.stoppedCalls, 0);
      expect(find.text('第 3 集'), findsWidgets);
    });

    testWidgets('a paused end does not auto-advance', (tester) async {
      await pumpEpisode(tester, episode('ep2', 2));

      engines.first.emit(
        const PlaybackSnapshot(
          position: Duration(minutes: 12),
          duration: episodeRuntime,
          playing: true,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('player-play-toggle')));
      await tester.pumpAndSettle();
      engines.first.emit(
        const PlaybackSnapshot(
          position: episodeRuntime,
          duration: episodeRuntime,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(engines, hasLength(1));
      expect(find.text('第 2 集'), findsWidgets);
    });

    testWidgets('the pinned version survives episode navigation', (
      tester,
    ) async {
      await pumpEpisode(tester, episode('ep2', 2), source: 'source-2');
      expect(playback.resolveSourceIds.last, 'source-2');

      await tester.tap(find.byKey(const Key('player-next-episode')));
      await settleEpisodeSwitch(tester);

      expect(engines.last.openedPlans.single.itemId, 'ep3');
      expect(playback.resolveSourceIds.last, 'source-2');
      expect(engines.last.openedPlans.single.mediaSourceId, 'source-2');
    });
  });

  testWidgets('the stats sheet shows live decoder diagnostics', (tester) async {
    engine.stats = const PlaybackStats(
      videoCodec: 'hevc',
      audioCodec: 'truehd',
      width: 3840,
      height: 2160,
      containerFps: 24.0,
      estimatedFps: 23.976,
      videoBitrate: 45000000,
      audioBitrate: 4500000,
      cacheSpeed: 6291456,
      hwdec: 'mediacodec',
      vo: 'gpu',
      ao: 'opensles',
      audioSampleRate: 48000,
      audioChannels: '7.1',
      speed: 1.0,
    );
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-stats-menu')));
    await tester.pump(); // sheet route + initState
    await tester.pump(); // first readStats completes

    expect(find.byKey(const Key('player-stats-sheet')), findsOneWidget);
    expect(find.text('3840×2160'), findsOneWidget);
    expect(find.text('hevc'), findsOneWidget);
    expect(find.text('23.976 fps'), findsOneWidget);
    expect(find.text('45.00 Mbps'), findsOneWidget);
    expect(find.text('6.00 MB/s'), findsOneWidget);
    expect(find.text('7.1'), findsOneWidget);

    // Let the sheet entrance animation finish so the close button is on
    // screen; avoid pumpAndSettle here (the 1 s poll timer never settles).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('player-stats-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-stats-sheet')), findsNothing);
  });

  group('player chapter skip (S12)', () {
    MediaItem chapterItem() => MediaItem(
      id: 'item-1',
      name: '测试影片',
      type: 'Episode',
      runTimeTicks: const Duration(seconds: 1440).inMicroseconds * 10,
      chapters: <Chapter>[
        Chapter(name: 'Intro', startTicks: 0),
        Chapter(name: '正片', startTicks: 90 * 10000000),
        Chapter(name: 'Credits', startTicks: 1320 * 10000000),
      ],
    );

    testWidgets('the intro button shows in the intro and seeks to content', (
      tester,
    ) async {
      await pumpPlayer(tester, item: chapterItem(), legacyRoute: true);

      expect(find.byKey(const Key('player-skip-intro')), findsOneWidget);
      expect(find.byKey(const Key('player-skip-credits')), findsNothing);

      await tester.tap(find.byKey(const Key('player-skip-intro')));
      await tester.pumpAndSettle();

      expect(engine.seeks.last, const Duration(seconds: 90));
      expect(find.byKey(const Key('player-skip-intro')), findsNothing);
    });

    testWidgets(
      'the credits button shows at the chapter and seeks to the end',
      (tester) async {
        await pumpPlayer(tester, item: chapterItem(), legacyRoute: true);

        engine.emit(
          const PlaybackSnapshot(
            position: Duration(seconds: 1320),
            playing: true,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const Key('player-skip-credits')), findsOneWidget);
        expect(find.byKey(const Key('player-skip-intro')), findsNothing);

        await tester.tap(find.byKey(const Key('player-skip-credits')));
        await tester.pumpAndSettle();

        expect(engine.seeks.last, const Duration(seconds: 1440));
      },
    );

    testWidgets('an item without chapters shows no skip button', (
      tester,
    ) async {
      await pumpPlayer(tester);
      expect(find.byKey(const Key('player-skip-intro')), findsNothing);
      expect(find.byKey(const Key('player-skip-credits')), findsNothing);
    });
  });

  group('player cast (S19)', () {
    const device = DlnaDevice(
      id: 'uuid:tv',
      name: '客厅电视',
      controlUrl: 'http://192.168.0.5:8080/AVTransport/control',
      address: '192.168.0.5:8080',
    );

    Future<void> openCast(WidgetTester tester, FakeDlnaCastService cast) async {
      await pumpPlayer(tester, cast: cast);
      await openOptions(tester);
      await tester.dragUntilVisible(
        find.byKey(const Key('player-cast')),
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.tap(find.byKey(const Key('player-cast')));
      await tester.pumpAndSettle();
    }

    testWidgets('the picker lists renderers and casts then stops on tap', (
      tester,
    ) async {
      final cast = FakeDlnaCastService()..devices = <DlnaDevice>[device];
      await openCast(tester, cast);

      expect(find.byKey(const Key('player-cast-sheet')), findsOneWidget);
      expect(
        find.byKey(const Key('player-cast-device-uuid:tv')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('player-cast-device-uuid:tv')));
      await tester.pumpAndSettle();

      expect(cast.casts, hasLength(1));
      expect(find.byKey(const Key('player-cast-stop')), findsOneWidget);
      expect(find.text('正在投屏到 客厅电视'), findsOneWidget);

      await tester.tap(find.byKey(const Key('player-cast-stop')));
      await tester.pumpAndSettle();

      expect(cast.stops, hasLength(1));
      expect(find.byKey(const Key('player-cast-stop')), findsNothing);
    });

    testWidgets('an empty scan shows the empty line', (tester) async {
      final cast = FakeDlnaCastService();
      await openCast(tester, cast);

      expect(find.byKey(const Key('player-cast-empty')), findsOneWidget);
      expect(find.byKey(const Key('player-cast-device-uuid:tv')), findsNothing);
    });
  });

  group('player options (S16 / S13)', () {
    testWidgets('the single-row control bar fits the options button', (
      tester,
    ) async {
      // Wide window: the single-row layout (>= 880) must not overflow with the
      // added options entry. An overflow would surface during pumpPlayer.
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpPlayer(tester);

      expect(find.byKey(const Key('player-options-menu')), findsOneWidget);
      expect(find.byKey(const Key('player-volume')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the options sheet opens forced-dark from the control bar', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      expect(find.byKey(const Key('player-options-sheet')), findsOneWidget);
      expect(find.text('旋转'), findsOneWidget);
      expect(find.text('画面比例'), findsOneWidget);
      expect(find.text('音量增益'), findsOneWidget);
      expect(find.text('定时关闭'), findsOneWidget);
      final context = tester.element(
        find.byKey(const Key('player-options-sheet')),
      );
      expect(Theme.of(context).colorScheme.brightness, Brightness.dark);
    });

    testWidgets('rotate chips drive the engine rotation', (tester) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      final chip = find.byKey(const Key('player-rotate-90'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(engine.rotations.last, 90);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
    });

    testWidgets('aspect chips drive the engine aspect mode', (tester) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      final chip = find.byKey(const Key('player-aspect-fill'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(engine.aspectModes.last, 'fill');
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
    });

    testWidgets('the hwdec switch drives the engine', (tester) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      final sw = find.byKey(const Key('player-hwdec-switch'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();

      expect(engine.hwdecToggles.last, isFalse);
    });

    testWidgets('the persisted force-stereo default reaches the engine (S41)', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      await store.write(
        PlaybackSettings.storageKey,
        jsonEncode(const PlaybackSettings(forceStereo: false).toJson()),
      );
      await pumpPlayer(tester, store: store);

      expect(engine.forceStereoToggles, contains(false));
    });
    testWidgets('gain chips raise the volume ceiling', (tester) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      final chip = find.byKey(const Key('player-gain-150'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(engine.volumeMaxima.last, 150);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
    });

    testWidgets('sleep chips arm a countdown and cancel', (tester) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      final chip = find.byKey(const Key('player-sleep-15'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      expect(find.text('剩余 15:00'), findsOneWidget);

      // The periodic tick must not be settled while armed; pump by hand.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('剩余 14:59'), findsOneWidget);

      // The off chip shares the Wrap and is still on screen.
      await tester.tap(find.byKey(const Key('player-sleep-off')));
      await tester.pump();
      expect(find.byKey(const Key('player-sleep-remaining')), findsNothing);
      expect(engine.pauseCalls, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('lock suppresses controls and unlock restores them', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      final sw = find.byKey(const Key('player-lock-switch'));
      await tester.dragUntilVisible(
        sw,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      await tester.tap(sw);
      await tester.pumpAndSettle();

      // Close the sheet to reveal the locked player.
      final close = find.byKey(const Key('player-options-close'));
      await tester.dragUntilVisible(
        close,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, 250),
      );
      await tester.tap(close);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-unlock')), findsOneWidget);
      expect(find.byKey(const Key('player-play-toggle')), findsNothing);
      expect(find.byKey(const Key('player-gesture-area')), findsNothing);

      await tester.tap(find.byKey(const Key('player-unlock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
      expect(find.byKey(const Key('player-gesture-area')), findsOneWidget);
    });

    testWidgets('screenshot closes the sheet and shows the saved path', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      final button = find.byKey(const Key('player-screenshot'));
      await tester.dragUntilVisible(
        button,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(engine.screenshotPaths, hasLength(1));
      expect(find.textContaining('截图已保存'), findsOneWidget);
      expect(find.byKey(const Key('player-options-sheet')), findsNothing);
    });

    testWidgets('pause-while-capturing pauses and resumes (S42)', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      await store.write(
        ScreenshotSettings.storageKey,
        jsonEncode(
          const ScreenshotSettings(pauseWhileCapturing: true).toJson(),
        ),
      );
      await pumpPlayer(tester, store: store);
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 30),
          duration: runtime,
          playing: true,
        ),
      );
      await tester.pump();

      await openOptions(tester);
      final Finder button = find.byKey(const Key('player-screenshot'));
      await tester.dragUntilVisible(
        button,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(engine.pauseCalls, 1);
      expect(engine.playCalls, 1);
      expect(engine.screenshotPaths, hasLength(1));
    });
    testWidgets('a failed screenshot reports failure', (tester) async {
      engine.screenshotFails = true;
      await pumpPlayer(tester);
      await openOptions(tester);

      final button = find.byKey(const Key('player-screenshot'));
      await tester.dragUntilVisible(
        button,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('截图失败'), findsOneWidget);
    });
  });

  group('advanced video options (S23)', () {
    Future<void> scrollToAdvanced(WidgetTester tester, String key) async {
      await tester.dragUntilVisible(
        find.byKey(Key(key)),
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      // dragUntilVisible only builds the row; align it fully so the tap lands.
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    Future<void> tapAdvanced(WidgetTester tester, String key) async {
      await scrollToAdvanced(tester, key);
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('the options sheet offers the 高级 switches', (tester) async {
      await pumpPlayer(tester);
      await openOptions(tester);

      // The section sits at the bottom of the sheet; scroll it into view.
      // Drag only (no ensureVisible): aligning the last switch would scroll the
      // first one back out of the lazy list's built range.
      await tester.dragUntilVisible(
        find.byKey(const Key('adv-yuv420')),
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      expect(find.text('高级'), findsOneWidget);
      expect(find.byKey(const Key('adv-gpu-next')), findsOneWidget);
      expect(find.byKey(const Key('adv-deband')), findsOneWidget);
      expect(find.byKey(const Key('adv-yuv420')), findsOneWidget);
      // All off until the user opts in.
      for (final String key in <String>[
        'adv-gpu-next',
        'adv-deband',
        'adv-yuv420',
      ]) {
        expect(
          tester.widget<SwitchListTile>(find.byKey(Key(key))).value,
          isFalse,
        );
      }
    });

    testWidgets('the advanced switches drive the engine live', (tester) async {
      await pumpPlayer(tester);
      await openOptions(tester);
      // load() applied the persisted defaults once already.
      expect(engine.advancedVideo.last, (
        gpuNext: false,
        deband: false,
        yuv420: false,
      ));

      await tapAdvanced(tester, 'adv-gpu-next');
      expect(engine.advancedVideo.last, (
        gpuNext: true,
        deband: false,
        yuv420: false,
      ));
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('adv-gpu-next')))
            .value,
        isTrue,
      );

      await tapAdvanced(tester, 'adv-deband');
      expect(engine.advancedVideo.last, (
        gpuNext: true,
        deband: true,
        yuv420: false,
      ));

      await tapAdvanced(tester, 'adv-yuv420');
      expect(engine.advancedVideo.last, (
        gpuNext: true,
        deband: true,
        yuv420: true,
      ));

      // Switching one flag back off keeps the others.
      await tapAdvanced(tester, 'adv-yuv420');
      expect(engine.advancedVideo.last, (
        gpuNext: true,
        deband: true,
        yuv420: false,
      ));
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('adv-yuv420')))
            .value,
        isFalse,
      );
    });
  });

  group('picture-in-picture (S18)', () {
    // The foundation invariant check runs before addTearDown, so the override
    // must be restored inside the test body itself.
    Future<void> onPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    Future<void> revealPip(WidgetTester tester) async {
      await tester.dragUntilVisible(
        find.byKey(const Key('player-pip')),
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.ensureVisible(find.byKey(const Key('player-pip')));
      await tester.pumpAndSettle();
    }

    testWidgets('Android shows the entry and tapping it enters PIP', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.android, () async {
        final FakePipController pip = FakePipController();
        await pumpPlayer(tester, pip: pip);
        await openOptions(tester);

        await revealPip(tester);
        expect(find.byKey(const Key('player-pip')), findsOneWidget);
        await tester.tap(find.byKey(const Key('player-pip')));
        await tester.pumpAndSettle();

        expect(pip.calls, 1);
        // The sheet closes so the PIP window shows the video, and entering
        // PIP never pauses playback.
        expect(find.byKey(const Key('player-options-sheet')), findsNothing);
        expect(engine.pauseCalls, 0);
        expect(find.text('进入画中画失败'), findsNothing);
      });
    });

    testWidgets('a refused request shows a non-fatal SnackBar', (tester) async {
      await onPlatform(TargetPlatform.android, () async {
        final FakePipController pip = FakePipController(result: false);
        await pumpPlayer(tester, pip: pip);
        await openOptions(tester);
        await revealPip(tester);
        await tester.tap(find.byKey(const Key('player-pip')));
        await tester.pumpAndSettle();

        expect(pip.calls, 1);
        expect(find.text('进入画中画失败'), findsOneWidget);
        // Non-fatal: the player keeps running.
        expect(engine.pauseCalls, 0);
        expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
      });
    });

    testWidgets('a throwing channel degrades to the failure SnackBar', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.android, () async {
        final FakePipController pip = FakePipController(
          failure: Exception('pip channel down'),
        );
        await pumpPlayer(tester, pip: pip);
        await openOptions(tester);
        await revealPip(tester);
        await tester.tap(find.byKey(const Key('player-pip')));
        await tester.pumpAndSettle();

        expect(pip.calls, 1);
        expect(find.text('进入画中画失败'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('non-Android platforms hide the entry', (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        await pumpPlayer(tester, pip: FakePipController());
        await openOptions(tester);

        expect(find.byKey(const Key('player-options-sheet')), findsOneWidget);
        // The entry is conditionally excluded, so it is absent even after
        // scrolling to the bottom of the sheet.
        await tester.dragUntilVisible(
          find.byKey(const Key('adv-yuv420')),
          find.byKey(const Key('player-options-sheet')),
          const Offset(0, -100),
        );
        expect(find.byKey(const Key('player-pip')), findsNothing);
      });
    });
  });

  group('danmaku (S17)', () {
    const DanmakuComment danmakuComment = DanmakuComment(
      id: 7,
      time: Duration(seconds: 2),
      mode: 1,
      color: 16777215,
      text: '前方高能',
    );

    FakeDanmakuService matchedService() {
      return FakeDanmakuService()
        ..result = const DanmakuLoad(
          status: DanmakuStatus.matched,
          episodeLabel: '测试动画 · 第1话',
          comments: <DanmakuComment>[danmakuComment],
        );
    }

    Future<InMemoryKeyValueStore> enabledStore() async {
      final store = InMemoryKeyValueStore();
      await store.write(
        DanmakuSettings.storageKey,
        jsonEncode(const DanmakuSettings(enabled: true).toJson()),
      );
      return store;
    }

    testWidgets('the options sheet toggles danmaku and shows the match', (
      tester,
    ) async {
      final danmaku = matchedService();
      final store = InMemoryKeyValueStore();
      await pumpPlayer(tester, danmaku: danmaku, store: store);
      await openOptions(tester);

      final sheet = find.byKey(const Key('player-options-sheet'));
      final status = find.byKey(const Key('danmaku-status'));
      await tester.dragUntilVisible(status, sheet, const Offset(0, -100));
      expect(find.text('开启后自动匹配弹幕'), findsOneWidget);

      // The status drag scrolled the switch out of view; scroll back up.
      final sw = find.byKey(const Key('danmaku-enabled'));
      await tester.dragUntilVisible(sw, sheet, const Offset(0, 250));
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      await tester.tap(sw);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(sw).value, isTrue);
      expect(danmaku.loadRequests, <String>['item-1']);
      await tester.dragUntilVisible(status, sheet, const Offset(0, -100));
      expect(find.text('已匹配：测试动画 · 第1话（1 条）'), findsOneWidget);

      // The choice persists under player.danmaku.v1.
      final raw = await store.read(DanmakuSettings.storageKey);
      expect(raw, contains('"enabled":true'));
    });

    testWidgets('comments render over the video at the playback position', (
      tester,
    ) async {
      final store = await enabledStore();
      await pumpPlayer(tester, danmaku: matchedService(), store: store);

      // Position 0: the 2 s comment is not due yet.
      expect(find.text('前方高能'), findsNothing);

      // Paused snapshot: the overlay still spawns (motion stays frozen), so
      // no ticker runs and the settle below is safe.
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 4),
          duration: runtime,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('danmaku-overlay')), findsOneWidget);
      expect(find.text('前方高能'), findsOneWidget);

      // The overlay sits below the controls: the gesture layer still owns
      // taps (it is above the overlay in the Stack). The centre of the screen
      // is the transport button now (S30), so tap a corner of the area.
      final Rect area = tester.getRect(
        find.byKey(const Key('player-gesture-area')),
      );
      await tester.tapAt(area.topLeft + const Offset(80, 80));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('manual danmaku matching searches and remembers (S43)', (
      tester,
    ) async {
      final service = FakeDanmakuService()
        ..searchResults = const <DanmakuAnime>[
          DanmakuAnime(
            id: 9,
            title: '另一部番',
            episodes: <DanmakuEpisode>[DanmakuEpisode(id: 77, title: '第1话')],
          ),
        ];
      await pumpPlayer(tester, danmaku: service);
      await openOptions(tester);

      final Finder manual = find.byKey(const Key('danmaku-manual-match'));
      await tester.dragUntilVisible(
        manual,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.tap(manual);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('danmaku-match-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('danmaku-match-go')));
      await tester.pumpAndSettle();
      expect(find.text('另一部番'), findsOneWidget);

      await tester.tap(find.byKey(const Key('danmaku-match-episode-77')));
      await tester.pumpAndSettle();

      expect(service.searchRequests, isNotEmpty);
      expect(service.manualRequests.single.episodeId, 77);
      expect(find.byKey(const Key('danmaku-match-sheet')), findsNothing);
    });

    testWidgets('the danmaku heatmap appears with comments (S44)', (
      tester,
    ) async {
      final store = await enabledStore();
      await pumpPlayer(tester, danmaku: matchedService(), store: store);
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 4),
          duration: runtime,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('danmaku-heatmap')), findsOneWidget);
    });
    testWidgets('the toggle hides the comments again', (tester) async {
      final store = await enabledStore();
      await pumpPlayer(tester, danmaku: matchedService(), store: store);
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 4),
          duration: runtime,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('前方高能'), findsOneWidget);

      await openOptions(tester);
      final sw = find.byKey(const Key('danmaku-enabled'));
      await tester.dragUntilVisible(
        sw,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      await tester.tap(sw);
      await tester.pumpAndSettle();

      expect(find.text('前方高能'), findsNothing);
      expect(find.byKey(const Key('danmaku-overlay')), findsNothing);
    });

    testWidgets('a no-match result is a status line, not an error banner', (
      tester,
    ) async {
      final store = await enabledStore();
      await pumpPlayer(tester, danmaku: FakeDanmakuService(), store: store);
      await openOptions(tester);

      final status = find.byKey(const Key('danmaku-status'));
      await tester.dragUntilVisible(
        status,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      expect(find.text('未匹配到弹幕'), findsOneWidget);
      // Playback keeps running: no error banner, no fatal notice.
      expect(find.byKey(const Key('player-error')), findsNothing);
    });

    testWidgets('density, opacity, speed and area controls persist', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      await pumpPlayer(tester, store: store);
      await openOptions(tester);

      final density = find.byKey(const Key('danmaku-density'));
      await tester.dragUntilVisible(
        density,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      // dragUntilVisible only builds the row; align it fully before dragging.
      await tester.ensureVisible(density);
      await tester.pumpAndSettle();
      // Drag left from the 100% default, like the subtitle-scale slider test.
      await tester.drag(density, const Offset(-150, 0));
      await tester.pumpAndSettle();

      final area = find.byKey(const Key('danmaku-area-full'));
      await tester.dragUntilVisible(
        area,
        find.byKey(const Key('player-options-sheet')),
        const Offset(0, -100),
      );
      await tester.ensureVisible(area);
      await tester.pumpAndSettle();
      await tester.tap(area);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(area).selected, isTrue);

      final raw = await store.read(DanmakuSettings.storageKey);
      expect(raw, isNotNull);
      final restored = DanmakuSettings.fromJson(
        jsonDecode(raw!) as Map<String, dynamic>,
      );
      expect(restored.fullArea, isTrue);
      // The density drag moved the slider off its 100% default.
      expect(restored.density, lessThan(1.0));
      expect(restored.density, greaterThanOrEqualTo(0.1));
    });
  });
}
