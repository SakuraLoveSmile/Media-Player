import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:media_player/data/models/server_profile.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';

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
  }) =>
      throw UnimplementedError();

  @override
  Future<ServerProfile> adoptAddress({
    required ServerProfile profile,
    required EndpointKind kind,
    required String rawUrl,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> handleUnauthorized() async {}
}

const Duration runtime = Duration(minutes: 90);

MediaItem playerItem({Duration position = Duration.zero}) {
  return MediaItem(
    id: 'item-1',
    name: '测试影片',
    type: 'Movie',
    runTimeTicks: runtime.inMicroseconds * 10,
    userData: UserItemData(positionTicks: position.inMicroseconds * 10),
  );
}

void main() {
  late FakePlaybackEngine engine;
  late FakePlaybackReporter reporter;
  late FakePlaybackService playback;

  setUp(() {
    engine = FakePlaybackEngine();
    reporter = FakePlaybackReporter();
    playback = FakePlaybackService();
  });

  /// Opens the library, taps the poster and settles on the player page. The
  /// extra 4 s covers the §10.9 f verdict check scheduled 3 s after start.
  /// [createEngine] / [createReporter] default to the shared doubles; the
  /// retry tests pass factories so each playback gets its own pair.
  Future<void> pumpPlayer(
    WidgetTester tester, {
    MediaItem? item,
    FakePlaybackEngine Function()? createEngine,
    FakePlaybackReporter Function()? createReporter,
  }) async {
    final media = item ?? playerItem();
    final library = FakeLibraryService(
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
              playback: playback,
              createEngine: createEngine ?? () => engine,
              createReporter: createReporter ?? () => reporter,
            ),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(media.name));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec()
          .encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

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

  testWidgets('the back button reports stopped exactly once', (tester) async {
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const Key('player-back')));
    await tester.pumpAndSettle();

    expect(find.text('媒体库'), findsOneWidget);
    expect(reporter.stoppedCalls, 1);
    expect(engine.disposeCalls, 1);
  });

  testWidgets('a system back reports stopped exactly once', (tester) async {
    await pumpPlayer(tester);

    await systemBack(tester);
    await systemBack(tester);

    expect(find.text('媒体库'), findsOneWidget);
    expect(reporter.stoppedCalls, 1);
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

  testWidgets('a failure shows mapped copy without an exception string',
      (tester) async {
    playback.failure = EmbyException(AppErrorCode.playbackUnsupported);
    await pumpPlayer(tester);

    expect(find.byKey(const Key('player-error')), findsOneWidget);
    expect(find.text('这个片源无法播放'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('EmbyException'), findsNothing);
  });

  testWidgets('a resumed playback states where it continued from',
      (tester) async {
    await pumpPlayer(tester, item: playerItem(position: const Duration(seconds: 125)));

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

    testWidgets('closes the failed session and builds a new pair',
        (tester) async {
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
}
