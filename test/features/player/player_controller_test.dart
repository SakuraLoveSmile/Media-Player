import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/features/player/player_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';

/// Reports an mpv error while the source is still opening, which is where an
/// unopenable URL shows up.
class OpeningErrorEngine extends FakePlaybackEngine {
  @override
  Future<void> open(PlaybackPlan plan) async {
    emit(PlaybackSnapshot(error: Exception('mpv: cannot open')));
    await super.open(plan);
  }
}

class PendingStopReporter extends FakePlaybackReporter {
  final completion = Completer<void>();

  @override
  Future<void> stopped(PlaybackPlan plan, Duration position) {
    unawaited(super.stopped(plan, position));
    return completion.future;
  }
}

MediaItem testItem({
  String id = 'item-1',
  String type = 'Movie',
  Duration position = Duration.zero,
  bool played = false,
}) {
  return MediaItem(
    id: id,
    name: '测试影片',
    type: type,
    runTimeTicks: const Duration(minutes: 90).inMicroseconds * 10,
    userData: UserItemData(
      played: played,
      positionTicks: position.inMicroseconds * 10,
    ),
  );
}

void main() {
  late FakeLibraryService library;
  late FakePlaybackService playback;
  late FakePlaybackEngine engine;
  late FakePlaybackReporter reporter;
  PlayerController? controller;

  setUp(() {
    library = FakeLibraryService();
    playback = FakePlaybackService();
    engine = FakePlaybackEngine();
    reporter = FakePlaybackReporter();
  });

  tearDown(() => controller?.dispose());

  PlayerController build(MediaItem item) {
    library.itemsByView = <String, List<MediaItem>>{
      fakeMoviesView.id: <MediaItem>[item],
    };
    return controller = PlayerController(
      itemId: item.id,
      library: library,
      playback: playback,
      engine: engine,
      reporter: reporter,
      // Immediate delay so the §10.9 f verdict check does not need a 3 s wait.
      delay: (_) async {},
    );
  }

  test('a stored position past the threshold resumes', () async {
    final player = build(testItem(position: const Duration(seconds: 120)));

    await player.load();

    expect(playback.resolveStartAts, <Duration>[const Duration(seconds: 120)]);
    expect(player.state.resumedFrom, const Duration(seconds: 120));
    expect(player.state.position, const Duration(seconds: 120));
  });

  test('a watched item starts from the beginning', () async {
    final player = build(
      testItem(position: const Duration(seconds: 120), played: true),
    );

    await player.load();

    expect(playback.resolveStartAts, <Duration>[Duration.zero]);
    expect(player.state.resumedFrom, isNull);
  });

  test(
    'a position below the 10 s threshold starts from the beginning',
    () async {
      final player = build(testItem(position: const Duration(seconds: 8)));

      await player.load();

      expect(playback.resolveStartAts, <Duration>[Duration.zero]);
      expect(player.state.resumedFrom, isNull);
    },
  );

  test('a series stops before negotiating', () async {
    final player = build(testItem(type: 'Series'));

    await player.load();

    expect(playback.resolveCalls, 0);
    expect(player.state.unsupported, isTrue);
    expect(player.state.ready, isFalse);
    expect(player.state.error, contains('分集'));
    expect(player.state.selectionSeriesId, 'item-1');
    expect(engine.openedPlans, isEmpty);
    expect(reporter.startedItemIds, isEmpty);
  });

  for (final sample in <({Duration position, bool played, bool resumes})>[
    (position: const Duration(seconds: 8), played: false, resumes: false),
    (position: const Duration(seconds: 10), played: false, resumes: false),
    (
      position: const Duration(seconds: 10, microseconds: 1),
      played: false,
      resumes: true,
    ),
    (position: const Duration(seconds: 125), played: true, resumes: false),
  ]) {
    test('Episode resume boundary: $sample', () async {
      final player = build(
        testItem(
          id: 'episode-42',
          type: 'Episode',
          position: sample.position,
          played: sample.played,
        ),
      );
      await player.load();

      final expected = sample.resumes ? sample.position : Duration.zero;
      expect(playback.resolveItemIds, ['episode-42']);
      expect(playback.resolveStartAts, [expected]);
      expect(engine.openedPlans.single.itemId, 'episode-42');
      expect(engine.openedPlans.single.startAt, expected);
      expect(reporter.startedItemIds, ['episode-42']);
      expect(player.state.selectionSeriesId, isNull);
      await player.seekTo(const Duration(seconds: 30));
      await player.togglePlayPause();
      await player.stop();
      expect(reporter.progressItemIds, ['episode-42', 'episode-42']);
      expect(reporter.stoppedItemIds, ['episode-42']);
    });
  }

  test('a denied direct play is mapped to copy, not thrown', () async {
    final player = build(testItem());
    playback.failure = EmbyException(AppErrorCode.directPlayDenied);

    await player.load();

    expect(player.state.error, contains('直连'));
    expect(player.state.ready, isFalse);
    expect(player.state.unauthorized, isFalse);
    expect(engine.openedPlans, isEmpty);
  });

  test('an expired session flags the state', () async {
    final player = build(testItem());
    playback.failure = EmbyException(AppErrorCode.unauthorized);

    await player.load();

    expect(player.state.unauthorized, isTrue);
    expect(player.state.ready, isFalse);
  });

  test(
    'a successful start opens once and reports the engine position',
    () async {
      final player = build(testItem(position: const Duration(seconds: 120)));

      await player.load();

      expect(engine.openedPlans, hasLength(1));
      expect(engine.openedPlans.single.startAt, const Duration(seconds: 120));
      expect(player.state.ready, isTrue);
      expect(player.state.itemName, '测试影片');
      expect(reporter.startedCalls, 1);
      expect(reporter.startedAt, const Duration(seconds: 120));

      engine.emit(const PlaybackSnapshot(position: Duration(seconds: 42)));
      await pumpEventQueue();

      expect(reporter.positionGetter!(), const Duration(seconds: 42));
    },
  );

  test('the verdict check fills in the confirmed values', () async {
    playback.confirmedPlan = fakePlan(videoDirect: true, audioTranscoded: true);
    final player = build(testItem());

    await player.load();
    await pumpEventQueue();

    expect(playback.confirmCalls, 1);
    expect(player.state.videoDirect, isTrue);
    expect(player.state.audioTranscoded, isTrue);
  });

  test('an unconfirmed verdict stays null', () async {
    final player = build(testItem());

    await player.load();
    await pumpEventQueue();

    expect(playback.confirmCalls, 1);
    expect(player.state.videoDirect, isNull);
  });

  test('dispose reports stopped once and is idempotent', () async {
    final player = build(testItem());
    await player.load();
    engine.emit(const PlaybackSnapshot(position: Duration(seconds: 61)));
    await pumpEventQueue();

    player.dispose();

    expect(reporter.stoppedCalls, 1);
    expect(reporter.stoppedAt, const Duration(seconds: 61));
    expect(engine.disposeCalls, 1);

    player.dispose();

    expect(reporter.stoppedCalls, 1);
    expect(engine.disposeCalls, 1);
  });

  test('dispose retains 100 s after a teardown zero snapshot', () async {
    final player = build(testItem());
    await player.load();
    engine.emit(const PlaybackSnapshot(position: Duration(seconds: 100)));
    await pumpEventQueue();
    engine.emit(const PlaybackSnapshot());
    await pumpEventQueue();
    expect(engine.snapshot.position, Duration.zero);

    player.dispose();

    expect(reporter.stoppedCalls, 1);
    expect(reporter.stoppedAt, const Duration(seconds: 100));
  });

  test('stop then dispose reports stopped only once', () async {
    final player = build(testItem());
    await player.load();
    engine.emit(const PlaybackSnapshot(position: Duration(seconds: 100)));
    await pumpEventQueue();

    await player.stop();
    engine.emit(const PlaybackSnapshot());
    await pumpEventQueue();
    await player.stop();
    player.dispose();

    expect(reporter.stoppedCalls, 1);
    expect(reporter.stoppedAt, const Duration(seconds: 100));
    expect(engine.disposeCalls, 1);
  });

  test(
    'normal stop reports the latest position, including backwards playback',
    () async {
      final player = build(testItem());
      await player.load();
      engine.emit(const PlaybackSnapshot(position: Duration(seconds: 100)));
      await pumpEventQueue();
      engine.emit(const PlaybackSnapshot(position: Duration(seconds: 61)));
      await pumpEventQueue();

      await player.stop();

      expect(reporter.stoppedCalls, 1);
      expect(reporter.stoppedAt, const Duration(seconds: 61));
      expect(engine.disposeCalls, 0);
    },
  );

  test('concurrent stop and dispose share a pending final report', () async {
    final pending = PendingStopReporter();
    reporter = pending;
    final player = build(testItem());
    await player.load();
    engine.emit(const PlaybackSnapshot(position: Duration(seconds: 100)));
    await pumpEventQueue();

    var completed = false;
    final first = player.stop().then((_) => completed = true);
    final second = player.stop();
    player.dispose();
    await pumpEventQueue();

    expect(completed, isFalse);
    expect(reporter.stoppedCalls, 1);
    expect(reporter.stoppedAt, const Duration(seconds: 100));
    expect(engine.disposeCalls, 1);

    pending.completion.complete();
    await Future.wait([first, second]);
    expect(completed, isTrue);
  });

  test(
    'heartbeat and pause retain the same position after a zero snapshot',
    () async {
      final player = build(testItem());
      await player.load();
      engine.emit(
        const PlaybackSnapshot(position: Duration(seconds: 100), playing: true),
      );
      await pumpEventQueue();
      engine.emit(const PlaybackSnapshot());
      await pumpEventQueue();

      expect(reporter.positionGetter!(), const Duration(seconds: 100));
      await player.togglePlayPause();
      expect(
        reporter.progressReports.single.position,
        const Duration(seconds: 100),
      );
      await player.stop();
      expect(reporter.stoppedAt, reporter.positionGetter!());
    },
  );

  test('a completed ready-state seek to zero is trusted', () async {
    final player = build(testItem());
    await player.load();
    engine.emit(const PlaybackSnapshot(position: Duration(seconds: 100)));
    await pumpEventQueue();

    await player.seekTo(Duration.zero);
    engine.emit(const PlaybackSnapshot());
    await pumpEventQueue();

    expect(reporter.progressReports.single.position, Duration.zero);
    expect(reporter.positionGetter!(), Duration.zero);
    await player.stop();
    expect(reporter.stoppedAt, Duration.zero);
  });

  test('open seeds the resume position before a positive snapshot', () async {
    final player = build(testItem(position: const Duration(seconds: 120)));
    await player.load();
    engine.emit(const PlaybackSnapshot());
    await pumpEventQueue();

    expect(reporter.positionGetter!(), const Duration(seconds: 120));
    await player.stop();
    expect(reporter.stoppedAt, const Duration(seconds: 120));
  });

  test('stop before genuine playback preserves zero', () async {
    final player = build(testItem());
    await player.load();
    engine.emit(const PlaybackSnapshot());
    await pumpEventQueue();

    expect(reporter.positionGetter!(), Duration.zero);
    await player.stop();
    expect(reporter.stoppedAt, Duration.zero);
  });

  test('a failed negotiation only disposes the engine', () async {
    final player = build(testItem());
    playback.failure = EmbyException(AppErrorCode.networkUnreachable);
    await player.load();

    player.dispose();

    expect(reporter.stoppedCalls, 0);
    expect(engine.disposeCalls, 1);
  });

  test('pause and resume each report immediately', () async {
    final player = build(testItem());
    await player.load();

    engine.emit(const PlaybackSnapshot(playing: true));
    await pumpEventQueue();
    await player.togglePlayPause();

    expect(engine.pauseCalls, 1);
    expect(reporter.progressReports, hasLength(1));
    expect(reporter.progressReports.single.paused, isTrue);

    engine.emit(const PlaybackSnapshot(playing: false));
    await pumpEventQueue();
    await player.togglePlayPause();

    expect(engine.playCalls, 1);
    expect(reporter.progressReports, hasLength(2));
    expect(reporter.progressReports.last.paused, isFalse);
  });

  test('a finished seek reports the target position', () async {
    final player = build(testItem());
    await player.load();

    await player.seekTo(const Duration(minutes: 5));

    expect(engine.seeks, <Duration>[const Duration(minutes: 5)]);
    expect(reporter.progressReports, hasLength(1));
    expect(
      reporter.progressReports.single.position,
      const Duration(minutes: 5),
    );
    expect(reporter.progressReports.single.paused, isTrue);
    expect(player.state.position, const Duration(minutes: 5));
  });

  test('the volume slider value is scaled to the engine range', () async {
    final player = build(testItem());
    await player.load();

    await player.setVolume(0.4);
    await player.setVolume(2);

    expect(engine.volumes, <double>[40, 100]);
  });

  test('an engine error line alone is not a failure', () async {
    final player = build(testItem());
    await player.load();

    // mpv logs errors for trouble it recovers from; playback keeps going, so
    // the screen must not claim it failed.
    engine.emit(PlaybackSnapshot(playing: true, error: Exception('mpv: boom')));
    await pumpEventQueue();

    expect(player.state.error, isNull);
  });

  test('a stalled playback turns the engine error into copy, never a string',
      () {
    fakeAsync((async) {
      final player = build(testItem());
      player.load();
      async.flushMicrotasks();
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 30),
          playing: true,
        ),
      );
      async.flushMicrotasks();

      engine.emit(
        PlaybackSnapshot(
          position: const Duration(seconds: 30),
          playing: true,
          error: Exception('mpv: boom'),
        ),
      );
      async.flushMicrotasks();
      expect(player.state.error, isNull);

      // No frame for longer than the confirmation window: the line was real.
      async.elapse(const Duration(seconds: 3));
      expect(player.state.error, '播放失败，请重试');
    });
  });

  test('a recovered error never reaches the screen and clears a banner', () {
    fakeAsync((async) {
      final player = build(testItem());
      player.load();
      async.flushMicrotasks();

      engine.emit(
        PlaybackSnapshot(
          position: const Duration(seconds: 10),
          playing: true,
          error: Exception('mpv: boom'),
        ),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 500));
      // Frames resumed before the window closed, so nothing is shown.
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 11),
          playing: true,
        ),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(player.state.error, isNull);

      // A stall that does surface must disappear again once playback recovers.
      engine.emit(
        PlaybackSnapshot(
          position: const Duration(seconds: 11),
          playing: true,
          error: Exception('mpv: boom'),
        ),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(player.state.error, '播放失败，请重试');

      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 12),
          playing: true,
        ),
      );
      async.flushMicrotasks();
      expect(player.state.error, isNull);
    });
  });

  test('a user pause delays the failure claim instead of faking one', () {
    fakeAsync((async) {
      final player = build(testItem());
      player.load();
      async.flushMicrotasks();

      engine.emit(
        const PlaybackSnapshot(position: Duration(seconds: 20), playing: true),
      );
      async.flushMicrotasks();
      player.togglePlayPause();
      async.flushMicrotasks();

      engine.emit(
        PlaybackSnapshot(
          position: const Duration(seconds: 20),
          error: Exception('mpv: boom'),
        ),
      );
      async.flushMicrotasks();
      // Paused is not stuck.
      async.elapse(const Duration(seconds: 5));
      expect(player.state.error, isNull);

      // Resumed but still frozen: now the claim can be confirmed.
      player.togglePlayPause();
      async.flushMicrotasks();
      engine.emit(
        const PlaybackSnapshot(position: Duration(seconds: 20), playing: true),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(player.state.error, '播放失败，请重试');
    });
  });

  test('a buffer fill only fails once it stops recovering', () {
    fakeAsync((async) {
      final player = build(testItem());
      player.load();
      async.flushMicrotasks();

      engine.emit(
        const PlaybackSnapshot(position: Duration(seconds: 40), playing: true),
      );
      async.flushMicrotasks();
      engine.emit(
        PlaybackSnapshot(
          position: const Duration(seconds: 40),
          playing: true,
          buffering: true,
          error: Exception('mpv: boom'),
        ),
      );
      async.flushMicrotasks();

      // A normal stall recovers and must not be called a failure.
      async.elapse(const Duration(seconds: 10));
      expect(player.state.error, isNull);

      // A buffer that never fills does become copy, on the longer window.
      async.elapse(const Duration(seconds: 15));
      expect(player.state.error, '播放失败，请重试');
    });
  });

  test('an engine that stopped without a user pause is a failure', () {
    fakeAsync((async) {
      final player = build(testItem());
      player.load();
      async.flushMicrotasks();

      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 50),
          duration: Duration(minutes: 90),
          playing: true,
        ),
      );
      async.flushMicrotasks();

      // A dead stream drops out of `playing` on its own; only the user's own
      // pause may excuse a frozen position.
      engine.emit(
        PlaybackSnapshot(
          position: const Duration(seconds: 50),
          duration: const Duration(minutes: 90),
          error: Exception('mpv: boom'),
        ),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(player.state.error, '播放失败，请重试');
    });
  });

  test('the end of the runtime is not a failure', () {
    fakeAsync((async) {
      final player = build(testItem());
      player.load();
      async.flushMicrotasks();

      engine.emit(
        PlaybackSnapshot(
          position: const Duration(minutes: 90),
          duration: const Duration(minutes: 90),
          error: Exception('mpv: boom'),
        ),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));

      expect(player.state.error, isNull);
    });
  });

  test('an error line emitted while the source opens is not lost', () {
    fakeAsync((async) {
      // mpv reports an unopenable source before `open` even returns.
      engine = OpeningErrorEngine();
      final player = build(testItem());
      player.load();
      async.flushMicrotasks();

      expect(player.state.ready, isTrue);
      expect(player.state.error, isNull);

      // The source produced no frames and the position never moved.
      async.elapse(const Duration(seconds: 3));
      expect(player.state.error, '播放失败，请重试');
    });
  });

  test('leaving playback cancels the pending failure claim', () {
    fakeAsync((async) {
      final player = build(testItem());
      player.load();
      async.flushMicrotasks();

      engine.emit(
        PlaybackSnapshot(
          position: const Duration(seconds: 30),
          playing: true,
          error: Exception('mpv: boom'),
        ),
      );
      async.flushMicrotasks();
      expect(async.pendingTimers, hasLength(1));

      player.stop();
      async.flushMicrotasks();

      expect(async.pendingTimers, isEmpty);
      expect(player.state.error, isNull);
    });
  });
}
