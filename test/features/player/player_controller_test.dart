import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/device/local_subtitle_picker.dart';
import 'package:media_player/core/device/pip.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/danmaku/danmaku_repository.dart';
import 'package:media_player/data/danmaku/danmaku_settings.dart';
import 'package:media_player/data/danmaku/models/danmaku_comment.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/media_source.dart';
import 'package:media_player/data/models/media_stream.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/data/playback/playback_settings.dart';
import 'package:media_player/data/playback/subtitle_repository.dart';
import 'package:media_player/data/playback/track_prefs.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/player/player_controller.dart';

import '../../support/fake_danmaku_service.dart';
import '../../support/fake_library_service.dart';
import '../../support/fake_local_subtitle_picker.dart';
import '../../support/fake_pip_controller.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';
import '../../support/fake_subtitle_service.dart';

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
  List<MediaSource> mediaSources = const <MediaSource>[],
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
    mediaSources: mediaSources,
  );
}

MediaSource sourceWithStreams(List<MediaStream> streams) {
  return MediaSource(
    id: 'source-1',
    container: 'mkv',
    bitrate: 12000000,
    supportsDirectPlay: true,
    supportsDirectStream: true,
    streams: streams,
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

  PlayerController build(
    MediaItem item, {
    SubtitleService? subtitles,
    LocalSubtitlePicker? localPicker,
    PipController? pip,
    DanmakuService? danmaku,
    KeyValueStore? store,
    String? preferredSourceId,
    Directory? screenshotDirectory,
  }) {
    library.itemsByView = <String, List<MediaItem>>{
      fakeMoviesView.id: <MediaItem>[item],
    };
    return controller = PlayerController(
      itemId: item.id,
      library: library,
      playback: playback,
      engine: engine,
      reporter: reporter,
      subtitles: subtitles,
      localSubtitlePicker: localPicker,
      pip: pip,
      danmaku: danmaku,
      store: store,
      preferredSourceId: preferredSourceId,
      screenshotDirectory: screenshotDirectory,
      // Immediate delay so the §10.9 f verdict check does not need a 3 s wait.
      delay: (_) async {},
    );
  }

  test(
    'a preferred version reaches negotiation (S7 detail pass-through)',
    () async {
      final player = build(testItem(), preferredSourceId: 'source-2');

      await player.load();

      expect(playback.resolveSourceIds, <String?>['source-2']);
      expect(engine.openedPlans.single.mediaSourceId, 'source-2');
      expect(player.state.ready, isTrue);
    },
  );

  test('without a preferred version the server default is kept', () async {
    final player = build(testItem());

    await player.load();

    expect(playback.resolveSourceIds, <String?>[null]);
    expect(engine.openedPlans.single.mediaSourceId, 'source-1');
  });

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

  test(
    'a stalled playback turns the engine error into copy, never a string',
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
    },
  );

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
        const PlaybackSnapshot(position: Duration(seconds: 11), playing: true),
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
        const PlaybackSnapshot(position: Duration(seconds: 12), playing: true),
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

  group('subtitle selection (B6)', () {
    const embedded = MediaStream(
      type: MediaStreamType.subtitle,
      index: 2,
      codec: 'subrip',
      language: 'chi',
      displayTitle: '中文',
    );
    const external = MediaStream(
      type: MediaStreamType.subtitle,
      index: 3,
      codec: 'ass',
      isExternal: true,
      displayTitle: '简体中文（外挂）',
    );

    PlayerController buildSubtitlePlayer({SubtitleService? subtitles}) {
      playback.plan = fakePlan(subtitles: <MediaStream>[embedded, external]);
      return build(testItem(), subtitles: subtitles);
    }

    test('load exposes the negotiated subtitle streams', () async {
      final player = buildSubtitlePlayer();

      await player.load();

      expect(player.state.subtitleStreams, <MediaStream>[embedded, external]);
      expect(player.state.selectedSubtitle, isNull);
      expect(player.state.subtitleNotice, isNull);
    });

    test('turning subtitles off clears the selection and notice', () async {
      final player = buildSubtitlePlayer();
      await player.load();
      await player.selectSubtitle(0);

      await player.selectSubtitle(null);

      expect(engine.subtitleTracks.last, isNull);
      expect(player.state.selectedSubtitle, isNull);
      expect(player.state.subtitleNotice, isNull);
    });

    test('an embedded stream selects the engine track by list order', () async {
      final player = buildSubtitlePlayer();
      await player.load();

      await player.selectSubtitle(0);

      expect(engine.subtitleTracks, <int?>[0]);
      expect(engine.externalSubtitlePaths, isEmpty);
      expect(player.state.selectedSubtitle, 0);
    });

    test(
      'an external stream downloads once and mounts the local file',
      () async {
        final subtitles = FakeSubtitleService();
        final player = buildSubtitlePlayer(subtitles: subtitles);
        await player.load();

        await player.selectSubtitle(1);

        expect(subtitles.requests, hasLength(1));
        expect(subtitles.requests.single.itemId, 'item-1');
        expect(subtitles.requests.single.mediaSourceId, 'source-1');
        expect(subtitles.requests.single.index, 3);
        expect(engine.subtitleTracks.last, isNull);
        expect(engine.externalSubtitlePaths, <String>[subtitles.path]);
        expect(player.state.selectedSubtitle, 1);
        expect(player.state.subtitleNotice, isNull);
      },
    );

    test(
      'a download failure only shows a notice; video keeps playing',
      () async {
        final subtitles = FakeSubtitleService(
          failure: EmbyException(AppErrorCode.subtitleFailed),
        );
        final player = buildSubtitlePlayer(subtitles: subtitles);
        await player.load();

        await player.selectSubtitle(1);

        expect(player.state.subtitleNotice, '字幕加载失败');
        expect(player.state.selectedSubtitle, isNull);
        expect(player.state.ready, isTrue);
        expect(player.state.error, isNull);
        expect(engine.externalSubtitlePaths, isEmpty);
      },
    );

    test('a successful retry after a failure clears the notice', () async {
      final subtitles = FakeSubtitleService(
        failure: EmbyException(AppErrorCode.subtitleFailed),
      );
      final player = buildSubtitlePlayer(subtitles: subtitles);
      await player.load();
      await player.selectSubtitle(1);
      expect(player.state.subtitleNotice, isNotNull);

      subtitles.failure = null;
      await player.selectSubtitle(1);

      expect(player.state.subtitleNotice, isNull);
      expect(player.state.selectedSubtitle, 1);
    });

    test('external subtitles without a service surface a notice', () async {
      final player = buildSubtitlePlayer();
      await player.load();

      await player.selectSubtitle(1);

      expect(player.state.subtitleNotice, '外挂字幕不可用');
      expect(player.state.selectedSubtitle, isNull);
      expect(engine.subtitleTracks, isEmpty);
    });

    test('an out-of-range index is a no-op', () async {
      final player = buildSubtitlePlayer();
      await player.load();

      await player.selectSubtitle(2);
      await player.selectSubtitle(-1);

      expect(engine.subtitleTracks, isEmpty);
      expect(player.state.selectedSubtitle, isNull);
    });
  });

  group('local subtitle file (添加本地字幕)', () {
    const embedded = MediaStream(
      type: MediaStreamType.subtitle,
      index: 2,
      codec: 'subrip',
      language: 'chi',
      displayTitle: '中文',
    );

    test(
      'a picked file mounts directly, never through the download cache',
      () async {
        final picker = FakeLocalSubtitlePicker();
        final subtitles = FakeSubtitleService();
        final player = build(
          testItem(),
          subtitles: subtitles,
          localPicker: picker,
        );
        await player.load();

        await player.addLocalSubtitle();

        expect(picker.calls, 1);
        expect(engine.externalSubtitlePaths, <String>[picker.path!]);
        expect(engine.subtitleTracks.last, isNull);
        expect(subtitles.requests, isEmpty);
        expect(player.state.localSubtitlePath, picker.path);
        expect(player.state.selectedSubtitle, isNull);
        expect(player.state.subtitleNotice, isNull);
      },
    );

    test('a cancelled picker changes nothing', () async {
      final picker = FakeLocalSubtitlePicker(path: null);
      final player = build(testItem(), localPicker: picker);
      await player.load();

      await player.addLocalSubtitle();

      expect(picker.calls, 1);
      expect(engine.externalSubtitlePaths, isEmpty);
      expect(engine.subtitleTracks, isEmpty);
      expect(player.state.localSubtitlePath, isNull);
      expect(player.state.subtitleNotice, isNull);
    });

    test('a picker failure only shows a notice; video keeps playing', () async {
      final picker = FakeLocalSubtitlePicker(failure: Exception('dialog'));
      final player = build(testItem(), localPicker: picker);
      await player.load();

      await player.addLocalSubtitle();

      expect(player.state.subtitleNotice, '字幕加载失败');
      expect(player.state.localSubtitlePath, isNull);
      expect(player.state.ready, isTrue);
      expect(player.state.error, isNull);
      expect(engine.externalSubtitlePaths, isEmpty);
    });

    test('a mount failure only shows a notice', () async {
      final picker = FakeLocalSubtitlePicker();
      final player = build(testItem(), localPicker: picker);
      await player.load();
      engine.subtitleMountError = Exception('mpv: cannot mount');

      await player.addLocalSubtitle();

      expect(player.state.subtitleNotice, '字幕加载失败');
      expect(player.state.localSubtitlePath, isNull);
      expect(player.state.ready, isTrue);
    });

    test('without a picker the entry surfaces a notice', () async {
      final player = build(testItem());
      await player.load();

      await player.addLocalSubtitle();

      expect(player.state.subtitleNotice, '本地字幕不可用');
      expect(engine.externalSubtitlePaths, isEmpty);
    });

    test('a later server pick replaces the local selection', () async {
      playback.plan = fakePlan(subtitles: <MediaStream>[embedded]);
      final picker = FakeLocalSubtitlePicker();
      final player = build(testItem(), localPicker: picker);
      await player.load();
      await player.addLocalSubtitle();
      expect(player.state.localSubtitlePath, picker.path);

      await player.selectSubtitle(0);

      expect(player.state.localSubtitlePath, isNull);
      expect(player.state.selectedSubtitle, 0);
      expect(engine.subtitleTracks.last, 0);
    });

    test('turning subtitles off clears the local selection', () async {
      final picker = FakeLocalSubtitlePicker();
      final player = build(testItem(), localPicker: picker);
      await player.load();
      await player.addLocalSubtitle();

      await player.selectSubtitle(null);

      expect(player.state.localSubtitlePath, isNull);
      expect(engine.subtitleTracks.last, isNull);
    });

    test('selectLocalSubtitle re-mounts the stored path', () async {
      final picker = FakeLocalSubtitlePicker();
      final player = build(testItem(), localPicker: picker);
      await player.load();
      await player.addLocalSubtitle();

      await player.selectLocalSubtitle();

      expect(picker.calls, 1);
      expect(engine.externalSubtitlePaths, <String>[
        picker.path!,
        picker.path!,
      ]);
      expect(player.state.localSubtitlePath, picker.path);
    });

    test('selectLocalSubtitle without a local file is a no-op', () async {
      final player = build(testItem());
      await player.load();

      await player.selectLocalSubtitle();

      expect(engine.subtitleTracks, isEmpty);
      expect(engine.externalSubtitlePaths, isEmpty);
    });
  });

  group('picture-in-picture (S18)', () {
    test('enterPip delegates to the injected controller', () async {
      final pip = FakePipController();
      final player = build(testItem(), pip: pip);
      await player.load();

      expect(await player.enterPip(), isTrue);
      expect(pip.calls, 1);
      // Entering PIP never pauses playback.
      expect(engine.pauseCalls, 0);
    });

    test('enterPip without a wired controller returns false', () async {
      final player = build(testItem());
      await player.load();

      expect(await player.enterPip(), isFalse);
    });

    test('enterPip reports a platform refusal as false', () async {
      final pip = FakePipController(result: false);
      final player = build(testItem(), pip: pip);
      await player.load();

      expect(await player.enterPip(), isFalse);
      expect(pip.calls, 1);
    });

    test('enterPip swallows a throwing channel', () async {
      final pip = FakePipController(failure: Exception('channel down'));
      final player = build(testItem(), pip: pip);
      await player.load();

      expect(await player.enterPip(), isFalse);
    });

    test(
      'enterPip after stop returns false without calling the channel',
      () async {
        final pip = FakePipController();
        final player = build(testItem(), pip: pip);
        await player.load();
        await player.stop();

        expect(await player.enterPip(), isFalse);
        expect(pip.calls, 0);
      },
    );
  });

  group('subtitle style (S4)', () {
    test('load applies the default style to the engine', () async {
      final player = build(testItem());

      await player.load();

      expect(engine.subtitleStyles, hasLength(1));
      expect(engine.subtitleStyles.single.scale, 1.0);
      expect(engine.subtitleStyles.single.overrideAss, isFalse);
      expect(player.state.subtitleStyle.scale, 1.0);
    });

    test('a style change reaches state, engine and the store', () async {
      final store = InMemoryKeyValueStore();
      final player = build(testItem(), store: store);
      await player.load();

      await player.setSubtitleStyle(
        const SubtitleStyle(scale: 1.5, overrideAss: true),
      );

      expect(player.state.subtitleStyle.scale, 1.5);
      expect(engine.subtitleStyles.last.scale, 1.5);
      expect(engine.subtitleStyles.last.overrideAss, isTrue);
      final raw = await store.read(PlayerController.styleKey);
      expect(raw, contains('1.5'));
      expect(raw, contains('"overrideAss":true'));
    });

    test('the next playback restores the persisted style', () async {
      final store = InMemoryKeyValueStore();
      final first = build(testItem(), store: store);
      await first.load();
      await first.setSubtitleStyle(const SubtitleStyle(scale: 1.75));
      first.dispose();
      controller = null;

      engine = FakePlaybackEngine();
      final second = build(testItem(), store: store);
      await second.load();

      expect(second.state.subtitleStyle.scale, 1.75);
      expect(engine.subtitleStyles.last.scale, 1.75);
    });

    test('corrupt persisted style falls back to the default', () async {
      final store = InMemoryKeyValueStore();
      await store.write(PlayerController.styleKey, '{not json');
      final player = build(testItem(), store: store);

      await player.load();

      expect(player.state.subtitleStyle.scale, 1.0);
      expect(engine.subtitleStyles.last.scale, 1.0);
    });

    test('the margins toggle reaches state, engine and the store', () async {
      final store = InMemoryKeyValueStore();
      final player = build(testItem(), store: store);
      await player.load();

      await player.setSubtitleStyle(const SubtitleStyle(useMargins: true));

      expect(player.state.subtitleStyle.useMargins, isTrue);
      expect(engine.subtitleStyles.last.useMargins, isTrue);
      final raw = await store.read(PlayerController.styleKey);
      expect(raw, contains('"useMargins":true'));
    });

    test(
      'persisted style JSON without useMargins loads with margins off',
      () async {
        final store = InMemoryKeyValueStore();
        // The exact shape written before the margins toggle existed.
        await store.write(
          PlayerController.styleKey,
          '{"font":"serif","scale":1.25,"delayMs":500,"borderSize":3.0,'
          '"shadowOffset":0.0,"overrideAss":true}',
        );
        final player = build(testItem(), store: store);

        await player.load();

        expect(player.state.subtitleStyle.useMargins, isFalse);
        expect(player.state.subtitleStyle.font, 'serif');
        expect(player.state.subtitleStyle.scale, 1.25);
        expect(engine.subtitleStyles.last.useMargins, isFalse);
      },
    );
  });

  group('track preferences (S5)', () {
    const chiAudio = MediaStream(
      type: MediaStreamType.audio,
      index: 1,
      codec: 'aac',
      language: 'chi',
      displayTitle: '国语',
    );
    const engAudio = MediaStream(
      type: MediaStreamType.audio,
      index: 2,
      codec: 'aac',
      language: 'eng',
      displayTitle: '英语',
    );
    const engSub = MediaStream(
      type: MediaStreamType.subtitle,
      index: 3,
      codec: 'subrip',
      language: 'eng',
      displayTitle: 'English',
    );
    const chiSub = MediaStream(
      type: MediaStreamType.subtitle,
      index: 4,
      codec: 'subrip',
      language: 'chi',
      displayTitle: '中文',
    );

    PlayerController buildTrackPlayer({
      KeyValueStore? store,
      SubtitleService? subtitles,
      List<MediaStream> audios = const <MediaStream>[chiAudio, engAudio],
      List<MediaStream> subs = const <MediaStream>[engSub, chiSub],
    }) {
      playback.plan = fakePlan(audios: audios, subtitles: subs);
      return build(testItem(), store: store, subtitles: subtitles);
    }

    Future<void> writePrefs(KeyValueStore store, TrackPrefs prefs) =>
        store.write(PlayerController.trackPrefsKey, jsonEncode(prefs.toJson()));

    test('load exposes the negotiated audio streams', () async {
      final player = buildTrackPlayer();

      await player.load();

      expect(player.state.audioStreams, <MediaStream>[chiAudio, engAudio]);
      expect(player.state.selectedAudio, isNull);
      expect(engine.audioTracks, isEmpty);
    });

    test(
      'a preferred audio language selects the matching track on load',
      () async {
        final store = InMemoryKeyValueStore();
        await writePrefs(store, const TrackPrefs(audioLanguage: 'eng'));
        final player = buildTrackPlayer(store: store);

        await player.load();

        expect(engine.audioTracks, <int>[1]);
        expect(player.state.selectedAudio, 1);
      },
    );

    test(
      'a preferred subtitle language selects the matching track on load',
      () async {
        final store = InMemoryKeyValueStore();
        await writePrefs(store, const TrackPrefs(subtitleLanguage: 'chi'));
        final player = buildTrackPlayer(store: store);

        await player.load();

        expect(engine.subtitleTracks, <int?>[1]);
        expect(player.state.selectedSubtitle, 1);
      },
    );

    test('empty preferences leave the engine defaults alone', () async {
      final store = InMemoryKeyValueStore();
      await writePrefs(store, const TrackPrefs());
      final player = buildTrackPlayer(store: store);

      await player.load();

      expect(engine.audioTracks, isEmpty);
      expect(engine.subtitleTracks, isEmpty);
      expect(player.state.selectedAudio, isNull);
      expect(player.state.selectedSubtitle, isNull);
    });

    test('a preference without a matching stream selects nothing', () async {
      final store = InMemoryKeyValueStore();
      await writePrefs(
        store,
        const TrackPrefs(audioLanguage: 'jpn', subtitleLanguage: 'jpn'),
      );
      final player = buildTrackPlayer(store: store);

      await player.load();

      expect(engine.audioTracks, isEmpty);
      expect(engine.subtitleTracks, isEmpty);
      expect(player.state.selectedAudio, isNull);
      expect(player.state.selectedSubtitle, isNull);
    });

    test('language aliases match across ISO spellings', () async {
      const zhoAudio = MediaStream(
        type: MediaStreamType.audio,
        index: 1,
        language: 'zho',
      );
      final store = InMemoryKeyValueStore();
      await writePrefs(store, const TrackPrefs(audioLanguage: 'chi'));
      final player = buildTrackPlayer(
        store: store,
        audios: <MediaStream>[zhoAudio],
      );

      await player.load();

      expect(engine.audioTracks, <int>[0]);
      expect(player.state.selectedAudio, 0);
    });

    test(
      'selectAudio drives the engine and state; out of range is a no-op',
      () async {
        final player = buildTrackPlayer();
        await player.load();

        await player.selectAudio(1);

        expect(engine.audioTracks, <int>[1]);
        expect(player.state.selectedAudio, 1);

        await player.selectAudio(5);
        await player.selectAudio(-1);

        expect(engine.audioTracks, <int>[1]);
        expect(player.state.selectedAudio, 1);
      },
    );

    test(
      'an explicit selection is not overridden by re-applied preferences',
      () async {
        final store = InMemoryKeyValueStore();
        const prefs = TrackPrefs(audioLanguage: 'eng', subtitleLanguage: 'chi');
        await writePrefs(store, prefs);
        final player = buildTrackPlayer(store: store);
        await player.load();
        expect(player.state.selectedAudio, 1);
        expect(player.state.selectedSubtitle, 1);

        await player.selectAudio(0);
        await player.selectSubtitle(0);
        await player.setTrackPrefs(prefs);

        expect(player.state.selectedAudio, 0);
        expect(player.state.selectedSubtitle, 0);
        expect(engine.audioTracks, <int>[1, 0]);
        expect(engine.subtitleTracks, <int?>[1, 0]);
      },
    );

    test('turning subtitles off explicitly also outranks auto-match', () async {
      final store = InMemoryKeyValueStore();
      const prefs = TrackPrefs(subtitleLanguage: 'chi');
      await writePrefs(store, prefs);
      final player = buildTrackPlayer(store: store);
      await player.load();
      expect(player.state.selectedSubtitle, 1);

      await player.selectSubtitle(null);
      await player.setTrackPrefs(prefs);

      expect(player.state.selectedSubtitle, isNull);
      expect(engine.subtitleTracks, <int?>[1, null]);
    });

    test('setTrackPrefs persists and re-applies auto-match', () async {
      final store = InMemoryKeyValueStore();
      final player = buildTrackPlayer(store: store);
      await player.load();
      expect(engine.audioTracks, isEmpty);
      expect(engine.subtitleTracks, isEmpty);

      await player.setTrackPrefs(
        const TrackPrefs(audioLanguage: 'eng', subtitleLanguage: 'chi'),
      );

      expect(engine.audioTracks, <int>[1]);
      expect(engine.subtitleTracks, <int?>[1]);
      expect(player.state.trackPrefs.audioLanguage, 'eng');
      expect(player.state.trackPrefs.subtitleLanguage, 'chi');
      final raw = await store.read(PlayerController.trackPrefsKey);
      expect(raw, contains('"audioLanguage":"eng"'));
      expect(raw, contains('"subtitleLanguage":"chi"'));
    });

    test('the next playback restores the persisted preferences', () async {
      final store = InMemoryKeyValueStore();
      final first = buildTrackPlayer(store: store);
      await first.load();
      await first.setTrackPrefs(const TrackPrefs(audioLanguage: 'eng'));
      first.dispose();
      controller = null;

      engine = FakePlaybackEngine();
      final second = buildTrackPlayer(store: store);
      await second.load();

      expect(second.state.trackPrefs.audioLanguage, 'eng');
      expect(engine.audioTracks, <int>[1]);
      expect(second.state.selectedAudio, 1);
    });

    test('corrupt persisted preferences fall back to auto', () async {
      final store = InMemoryKeyValueStore();
      await store.write(PlayerController.trackPrefsKey, '{not json');
      final player = buildTrackPlayer(store: store);

      await player.load();

      expect(player.state.trackPrefs.audioLanguage, '');
      expect(player.state.trackPrefs.subtitleLanguage, '');
      expect(engine.audioTracks, isEmpty);
      expect(engine.subtitleTracks, isEmpty);
    });

    test(
      'auto-match mounts a matching external subtitle through the service',
      () async {
        const externalChi = MediaStream(
          type: MediaStreamType.subtitle,
          index: 5,
          codec: 'ass',
          language: 'chi',
          isExternal: true,
          displayTitle: '简体中文',
        );
        final subtitles = FakeSubtitleService();
        final store = InMemoryKeyValueStore();
        await writePrefs(store, const TrackPrefs(subtitleLanguage: 'chi'));
        final player = buildTrackPlayer(
          store: store,
          subtitles: subtitles,
          subs: <MediaStream>[externalChi],
        );

        await player.load();

        expect(subtitles.requests, hasLength(1));
        expect(engine.externalSubtitlePaths, <String>[subtitles.path]);
        expect(player.state.selectedSubtitle, 0);
        expect(player.state.subtitleNotice, isNull);
      },
    );

    test('TrackPrefs round-trips through JSON and copyWith', () {
      const prefs = TrackPrefs(audioLanguage: 'chi', subtitleLanguage: 'eng');
      final restored = TrackPrefs.fromJson(
        jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>,
      );
      expect(restored.audioLanguage, 'chi');
      expect(restored.subtitleLanguage, 'eng');
      expect(const TrackPrefs().toJson(), <String, dynamic>{
        'audioLanguage': '',
        'subtitleLanguage': '',
      });
      expect(prefs.copyWith(audioLanguage: '').audioLanguage, '');
      expect(prefs.copyWith(subtitleLanguage: 'jpn').audioLanguage, 'chi');
      expect(prefs.copyWith(subtitleLanguage: 'jpn').subtitleLanguage, 'jpn');
    });
  });

  group('PGS subtitles mount on the full-decoder kernel', () {
    const pgs = MediaStream(
      type: MediaStreamType.subtitle,
      index: 2,
      codec: 'pgssub',
      displayTitle: 'Chinese (PGSSUB)',
    );

    test('selecting PGS mounts the embedded track without a notice', () async {
      playback.plan = fakePlan(subtitles: <MediaStream>[pgs]);
      final player = build(testItem());
      await player.load();

      await player.selectSubtitle(0);

      expect(engine.subtitleTracks, <int?>[0]);
      expect(player.state.selectedSubtitle, 0);
      expect(player.state.subtitleNotice, isNull);
    });
  });

  group('continuous play (P1)', () {
    const seriesId = 'series-1';
    const seasonId = 'season-1';
    const episodeRuntime = Duration(minutes: 24);

    MediaItem episode(String id, int? index, {String? season = seasonId}) {
      return MediaItem(
        id: id,
        name: '分集 $id',
        type: 'Episode',
        seriesId: seriesId,
        seasonId: season,
        indexNumber: index,
        runTimeTicks: episodeRuntime.inMicroseconds * 10,
      );
    }

    PlayerController buildEpisode(
      MediaItem item, {
      List<MediaItem>? season,
      KeyValueStore? store,
      String? preferredSourceId,
    }) {
      library.episodesBySeason = <String, List<MediaItem>>{
        seasonId:
            season ??
            <MediaItem>[
              episode('ep1', 1),
              episode('ep2', 2),
              episode('ep3', 3),
            ],
      };
      return build(item, store: store, preferredSourceId: preferredSourceId);
    }

    test(
      'episode neighbors follow indexNumber order, not server order',
      () async {
        final player = buildEpisode(
          episode('ep2', 2),
          season: <MediaItem>[
            episode('ep3', 3),
            episode('ep1', 1),
            episode('ep2', 2),
          ],
        );

        await player.load();
        await pumpEventQueue();

        expect(library.episodeRequests, <({String seriesId, String seasonId})>[
          (seriesId: seriesId, seasonId: seasonId),
        ]);
        expect(player.state.hasPrevious, isTrue);
        expect(player.state.hasNext, isTrue);
        expect(player.state.previousEpisodeId, 'ep1');
        expect(player.state.nextEpisodeId, 'ep3');
        expect(player.playPrevious(), 'ep1');
        expect(player.playNext(), 'ep3');
      },
    );

    test('the first episode has no previous', () async {
      final player = buildEpisode(episode('ep1', 1));

      await player.load();
      await pumpEventQueue();

      expect(player.state.hasPrevious, isFalse);
      expect(player.state.previousEpisodeId, isNull);
      expect(player.playPrevious(), isNull);
      expect(player.state.hasNext, isTrue);
      expect(player.playNext(), 'ep2');
    });

    test('the last episode has no next', () async {
      final player = buildEpisode(episode('ep3', 3));

      await player.load();
      await pumpEventQueue();

      expect(player.state.hasNext, isFalse);
      expect(player.state.nextEpisodeId, isNull);
      expect(player.playNext(), isNull);
      expect(player.state.hasPrevious, isTrue);
      expect(player.playPrevious(), 'ep2');
    });

    test(
      'episodes without an indexNumber keep server order at the end',
      () async {
        final player = buildEpisode(
          episode('ep2', 2),
          season: <MediaItem>[
            episode('extra-a', null),
            episode('ep3', 3),
            episode('ep1', 1),
            episode('ep2', 2),
            episode('extra-b', null),
          ],
        );

        await player.load();
        await pumpEventQueue();

        expect(player.playPrevious(), 'ep1');
        expect(player.playNext(), 'ep3');
      },
    );

    test('an episode missing from its season list has no neighbors', () async {
      final player = buildEpisode(
        episode('special', 5),
        season: <MediaItem>[episode('ep1', 1), episode('ep2', 2)],
      );

      await player.load();
      await pumpEventQueue();

      expect(player.state.hasPrevious, isFalse);
      expect(player.state.hasNext, isFalse);
      expect(player.playPrevious(), isNull);
      expect(player.playNext(), isNull);
    });

    test('a movie has no neighbors and never fetches a season', () async {
      final player = build(testItem());

      await player.load();
      await pumpEventQueue();

      expect(player.state.hasPrevious, isFalse);
      expect(player.state.hasNext, isFalse);
      expect(player.state.previousEpisodeId, isNull);
      expect(player.state.nextEpisodeId, isNull);
      expect(player.playPrevious(), isNull);
      expect(player.playNext(), isNull);
      expect(library.episodeRequests, isEmpty);
    });

    test('an episode without a season id has no neighbors', () async {
      final player = buildEpisode(episode('ep2', 2, season: null));

      await player.load();
      await pumpEventQueue();

      expect(library.episodeRequests, isEmpty);
      expect(player.state.hasPrevious, isFalse);
      expect(player.state.hasNext, isFalse);
    });

    test(
      'a failed season fetch leaves playback working without neighbors',
      () async {
        library.episodesFailure = EmbyException(
          AppErrorCode.networkUnreachable,
        );
        final player = buildEpisode(episode('ep2', 2));

        await player.load();
        await pumpEventQueue();

        expect(player.state.ready, isTrue);
        expect(player.state.error, isNull);
        expect(player.state.hasPrevious, isFalse);
        expect(player.state.hasNext, isFalse);
      },
    );

    test('the pinned version is exposed for episode navigation', () async {
      final player = buildEpisode(
        episode('ep2', 2),
        preferredSourceId: 'source-2',
      );

      await player.load();

      expect(player.preferredSourceId, 'source-2');
      expect(playback.resolveSourceIds, <String?>['source-2']);
    });

    test(
      'completion fires once when the end is reached while playing',
      () async {
        final player = buildEpisode(episode('ep2', 2));
        await player.load();
        var transitions = 0;
        var last = player.state.completed;
        player.addListener(() {
          final now = player.state.completed;
          if (now && !last) transitions++;
          last = now;
        });

        engine.emit(
          const PlaybackSnapshot(
            position: Duration(minutes: 23),
            duration: episodeRuntime,
            playing: true,
          ),
        );
        await pumpEventQueue();
        expect(player.state.completed, isFalse);

        engine.emit(
          const PlaybackSnapshot(
            position: episodeRuntime,
            duration: episodeRuntime,
            playing: true,
          ),
        );
        await pumpEventQueue();
        expect(player.state.completed, isTrue);
        expect(transitions, 1);

        // The engine keeps emitting end snapshots (and may drop `playing` on
        // the last one); the flag must not fire a second time.
        engine.emit(
          const PlaybackSnapshot(
            position: episodeRuntime,
            duration: episodeRuntime,
          ),
        );
        await pumpEventQueue();
        engine.emit(
          const PlaybackSnapshot(
            position: episodeRuntime,
            duration: episodeRuntime,
            playing: true,
          ),
        );
        await pumpEventQueue();
        expect(player.state.completed, isTrue);
        expect(transitions, 1);
      },
    );

    test(
      'the last half second counts as the end, earlier positions do not',
      () async {
        final player = buildEpisode(episode('ep2', 2));
        await player.load();

        engine.emit(
          PlaybackSnapshot(
            position: episodeRuntime - const Duration(seconds: 2),
            duration: episodeRuntime,
            playing: true,
          ),
        );
        await pumpEventQueue();
        expect(player.state.completed, isFalse);

        engine.emit(
          PlaybackSnapshot(
            position: episodeRuntime - const Duration(milliseconds: 200),
            duration: episodeRuntime,
            playing: true,
          ),
        );
        await pumpEventQueue();
        expect(player.state.completed, isTrue);
      },
    );

    test('a paused end position does not complete', () async {
      final player = buildEpisode(episode('ep2', 2));
      await player.load();

      // Never played: a seek to the end while paused is not a completion.
      engine.emit(
        const PlaybackSnapshot(
          position: episodeRuntime,
          duration: episodeRuntime,
        ),
      );
      await pumpEventQueue();
      expect(player.state.completed, isFalse);

      // Played, then user-paused at the end: still not a completion.
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(minutes: 23),
          duration: episodeRuntime,
          playing: true,
        ),
      );
      await pumpEventQueue();
      await player.togglePlayPause();
      engine.emit(
        const PlaybackSnapshot(
          position: episodeRuntime,
          duration: episodeRuntime,
        ),
      );
      await pumpEventQueue();
      expect(player.state.completed, isFalse);
    });

    test(
      'buffering at the end does not complete until playback resumes',
      () async {
        final player = buildEpisode(episode('ep2', 2));
        await player.load();

        engine.emit(
          const PlaybackSnapshot(
            position: episodeRuntime,
            duration: episodeRuntime,
            playing: true,
            buffering: true,
          ),
        );
        await pumpEventQueue();
        expect(player.state.completed, isFalse);

        engine.emit(
          const PlaybackSnapshot(
            position: episodeRuntime,
            duration: episodeRuntime,
            playing: true,
          ),
        );
        await pumpEventQueue();
        expect(player.state.completed, isTrue);
      },
    );

    test('an unknown runtime never completes', () async {
      final player = buildEpisode(
        const MediaItem(
          id: 'ep2',
          name: '分集 ep2',
          type: 'Episode',
          seriesId: seriesId,
          seasonId: seasonId,
          indexNumber: 2,
        ),
      );
      await player.load();

      engine.emit(
        const PlaybackSnapshot(position: Duration(minutes: 24), playing: true),
      );
      await pumpEventQueue();

      expect(player.state.duration, Duration.zero);
      expect(player.state.completed, isFalse);
    });

    test(
      'a new episode re-applies auto-match instead of carrying explicit picks',
      () async {
        const chiAudio = MediaStream(
          type: MediaStreamType.audio,
          index: 1,
          codec: 'aac',
          language: 'chi',
        );
        const engAudio = MediaStream(
          type: MediaStreamType.audio,
          index: 2,
          codec: 'aac',
          language: 'eng',
        );
        playback.plan = fakePlan(audios: <MediaStream>[chiAudio, engAudio]);
        final store = InMemoryKeyValueStore();
        await store.write(
          PlayerController.trackPrefsKey,
          jsonEncode(const TrackPrefs(audioLanguage: 'eng').toJson()),
        );

        final first = buildEpisode(episode('ep2', 2), store: store);
        await first.load();
        expect(first.state.selectedAudio, 1);
        await first.selectAudio(0);
        expect(first.state.selectedAudio, 0);
        first.dispose();
        controller = null;

        engine = FakePlaybackEngine();
        final second = buildEpisode(episode('ep3', 3), store: store);
        await second.load();

        // The explicit pick belonged to the previous session; the persisted
        // preference auto-matches again on the next episode.
        expect(second.state.selectedAudio, 1);
        expect(engine.audioTracks, <int>[1]);
      },
    );
  });

  group('playback stats (debug panel)', () {
    test('readStats delegates to the engine', () async {
      engine.stats = const PlaybackStats(
        videoCodec: 'hevc',
        estimatedFps: 23.976,
        videoBitrate: 45000000,
      );
      final player = build(testItem());
      await player.load();

      final stats = await player.readStats();

      expect(engine.statsCalls, 1);
      expect(stats.videoCodec, 'hevc');
      expect(stats.estimatedFps, 23.976);
      expect(stats.videoBitrate, 45000000);
    });
  });

  group('player misc (S16)', () {
    test('rotateVideo steps through 90° and wraps', () async {
      final player = build(testItem());
      await player.load();

      await player.rotateVideo();
      expect(player.state.videoRotation, 90);
      await player.rotateVideo();
      await player.rotateVideo();
      expect(player.state.videoRotation, 270);
      await player.rotateVideo();
      expect(player.state.videoRotation, 0);
      expect(engine.rotations, <int>[90, 180, 270, 0]);
    });

    test('setVideoRotation normalizes any angle', () async {
      final player = build(testItem());
      await player.load();

      await player.setVideoRotation(360);
      expect(player.state.videoRotation, 0);
      await player.setVideoRotation(-90);
      expect(player.state.videoRotation, 270);
      expect(engine.rotations, <int>[0, 270]);
    });

    test('setAspectMode delegates and updates state', () async {
      final player = build(testItem());
      await player.load();

      await player.setAspectMode('fill');
      expect(player.state.aspectMode, 'fill');
      await player.setAspectMode('16:9');
      expect(player.state.aspectMode, '16:9');
      expect(engine.aspectModes, <String>['fill', '16:9']);
    });

    test('toggleLock flips the lock state', () async {
      final player = build(testItem());
      await player.load();

      expect(player.state.locked, isFalse);
      player.toggleLock();
      expect(player.state.locked, isTrue);
      player.toggleLock();
      expect(player.state.locked, isFalse);
    });

    test(
      'takeScreenshot writes into the cache dir and returns the path',
      () async {
        final dir = await Directory.systemTemp.createTemp('player_shot');
        addTearDown(() => dir.delete(recursive: true));
        final player = build(testItem(), screenshotDirectory: dir);
        await player.load();

        final path = await player.takeScreenshot();

        expect(path, isNotNull);
        expect(path, startsWith(dir.path));
        expect(path, endsWith('.png'));
        expect(engine.screenshotPaths.single, path);
      },
    );

    test('takeScreenshot returns null when the engine fails', () async {
      engine.screenshotFails = true;
      final player = build(testItem());
      await player.load();

      final path = await player.takeScreenshot();

      expect(path, isNull);
      expect(engine.screenshotPaths, hasLength(1));
    });

    test('the sleep timer counts down, then pauses and clears', () {
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

        player.setSleepTimer(const Duration(minutes: 15));
        async.flushMicrotasks();
        expect(player.state.sleepRemaining, const Duration(minutes: 15));
        expect(player.state.sleepDuration, const Duration(minutes: 15));

        // Just before the deadline: still armed and counting down.
        async.elapse(const Duration(minutes: 14, seconds: 59));
        expect(player.state.sleepRemaining, const Duration(seconds: 1));
        expect(engine.pauseCalls, 0);

        // The final tick fires: pause once, clear the countdown.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(engine.pauseCalls, 1);
        expect(player.state.sleepRemaining, isNull);
        expect(player.state.sleepDuration, isNull);
        expect(player.state.playing, isFalse);
        expect(reporter.progressReports.last.paused, isTrue);
      });
    });

    test('cancelling the sleep timer prevents the pause', () {
      fakeAsync((async) {
        final player = build(testItem());
        player.load();
        async.flushMicrotasks();

        player.setSleepTimer(const Duration(minutes: 15));
        async.flushMicrotasks();
        player.cancelSleepTimer();
        async.flushMicrotasks();
        expect(player.state.sleepRemaining, isNull);

        async.elapse(const Duration(minutes: 20));
        expect(engine.pauseCalls, 0);
      });
    });

    test('re-arming the sleep timer replaces the countdown', () {
      fakeAsync((async) {
        final player = build(testItem());
        player.load();
        async.flushMicrotasks();

        player.setSleepTimer(const Duration(minutes: 15));
        async.elapse(const Duration(minutes: 5));
        expect(player.state.sleepRemaining, const Duration(minutes: 10));

        player.setSleepTimer(const Duration(minutes: 30));
        async.flushMicrotasks();
        expect(player.state.sleepRemaining, const Duration(minutes: 30));

        async.elapse(const Duration(minutes: 30));
        async.flushMicrotasks();
        expect(engine.pauseCalls, 1);
      });
    });

    test('leaving playback cancels the sleep timer', () {
      fakeAsync((async) {
        final player = build(testItem());
        player.load();
        async.flushMicrotasks();
        player.setSleepTimer(const Duration(minutes: 15));
        async.flushMicrotasks();

        player.stop();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 20));
        expect(engine.pauseCalls, 0);
      });
    });
  });

  group('playback settings (S13)', () {
    test('load applies the default engine settings', () async {
      final player = build(testItem());
      await player.load();

      expect(engine.hwdecToggles, <bool>[true]);
      expect(engine.volumeMaxima, <double>[100]);
      expect(engine.cacheConfigs.single.cacheSecs, 30);
      expect(engine.cacheConfigs.single.demuxerMaxBytes, 157286400);
      expect(player.state.playbackSettings.hwdecEnabled, isTrue);
    });

    test('toggleHwdec flips state, engine and the store', () async {
      final store = InMemoryKeyValueStore();
      final player = build(testItem(), store: store);
      await player.load();

      await player.toggleHwdec();

      expect(player.state.playbackSettings.hwdecEnabled, isFalse);
      expect(engine.hwdecToggles.last, isFalse);
      final raw = await store.read(PlayerController.playbackSettingsKey);
      expect(raw, contains('"hwdecEnabled":false'));
    });

    test('setVolumeGain raises the ceiling and scales the slider', () async {
      final store = InMemoryKeyValueStore();
      final player = build(testItem(), store: store);
      await player.load();

      await player.setVolumeGain(200);
      expect(engine.volumeMaxima.last, 200);
      expect(player.state.playbackSettings.volumeGainPercent, 200);

      // The slider spans the gained range: 0.5 of 200% is 100.
      await player.setVolume(0.5);
      expect(engine.volumes.last, 100);

      final raw = await store.read(PlayerController.playbackSettingsKey);
      expect(raw, contains('"volumeGainPercent":200'));
    });

    test('the next playback restores the persisted settings', () async {
      final store = InMemoryKeyValueStore();
      final first = build(testItem(), store: store);
      await first.load();
      await first.toggleHwdec();
      await first.setVolumeGain(150);
      first.dispose();
      controller = null;

      engine = FakePlaybackEngine();
      final second = build(testItem(), store: store);
      await second.load();

      expect(second.state.playbackSettings.hwdecEnabled, isFalse);
      expect(second.state.playbackSettings.volumeGainPercent, 150);
      expect(engine.hwdecToggles, <bool>[false]);
      expect(engine.volumeMaxima, <double>[150]);
    });

    test('corrupt persisted settings fall back to the defaults', () async {
      final store = InMemoryKeyValueStore();
      await store.write(PlayerController.playbackSettingsKey, '{not json');
      final player = build(testItem(), store: store);

      await player.load();

      expect(player.state.playbackSettings.hwdecEnabled, isTrue);
      expect(player.state.playbackSettings.cacheSecs, 30);
      expect(engine.hwdecToggles, <bool>[true]);
    });

    test('PlaybackSettings round-trips through JSON and copyWith', () {
      const settings = PlaybackSettings(
        hwdecEnabled: false,
        volumeGainPercent: 150,
        cacheSecs: 45,
        demuxerMaxBytes: 209715200,
      );
      final restored = PlaybackSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.hwdecEnabled, isFalse);
      expect(restored.volumeGainPercent, 150);
      expect(restored.cacheSecs, 45);
      expect(restored.demuxerMaxBytes, 209715200);
      expect(settings.copyWith(cacheSecs: 60).cacheSecs, 60);
      expect(settings.copyWith(cacheSecs: 60).hwdecEnabled, isFalse);
    });
  });

  group('advanced video (S23)', () {
    test('load applies the advanced video defaults (all off)', () async {
      final player = build(testItem());
      await player.load();

      expect(engine.advancedVideo.single, (
        gpuNext: false,
        deband: false,
        yuv420: false,
      ));
      expect(player.state.playbackSettings.gpuNext, isFalse);
      expect(player.state.playbackSettings.deband, isFalse);
      expect(player.state.playbackSettings.yuv420, isFalse);
    });

    test('load applies the persisted advanced flags', () async {
      final store = InMemoryKeyValueStore();
      await store.write(
        PlayerController.playbackSettingsKey,
        jsonEncode(
          const PlaybackSettings(
            gpuNext: true,
            deband: true,
            yuv420: true,
          ).toJson(),
        ),
      );
      final player = build(testItem(), store: store);
      await player.load();

      expect(engine.advancedVideo.single, (
        gpuNext: true,
        deband: true,
        yuv420: true,
      ));
      expect(player.state.playbackSettings.gpuNext, isTrue);
      expect(player.state.playbackSettings.deband, isTrue);
      expect(player.state.playbackSettings.yuv420, isTrue);
    });

    test('a pre-S23 blob keeps the advanced flags off', () async {
      final store = InMemoryKeyValueStore();
      await store.write(
        PlayerController.playbackSettingsKey,
        '{"hwdecEnabled":false,"volumeGainPercent":150,'
        '"cacheSecs":45,"demuxerMaxBytes":209715200}',
      );
      final player = build(testItem(), store: store);
      await player.load();

      expect(player.state.playbackSettings.hwdecEnabled, isFalse);
      expect(player.state.playbackSettings.gpuNext, isFalse);
      expect(player.state.playbackSettings.deband, isFalse);
      expect(player.state.playbackSettings.yuv420, isFalse);
      expect(engine.advancedVideo.single, (
        gpuNext: false,
        deband: false,
        yuv420: false,
      ));
    });

    test(
      'setAdvancedVideo applies live, persists and keeps other flags',
      () async {
        final store = InMemoryKeyValueStore();
        final player = build(testItem(), store: store);
        await player.load();

        await player.setAdvancedVideo(gpuNext: true);
        expect(player.state.playbackSettings.gpuNext, isTrue);
        expect(engine.advancedVideo.last, (
          gpuNext: true,
          deband: false,
          yuv420: false,
        ));
        var raw = await store.read(PlayerController.playbackSettingsKey);
        expect(raw, contains('"gpuNext":true'));

        // A second switch must not clear the first one.
        await player.setAdvancedVideo(deband: true);
        expect(engine.advancedVideo.last, (
          gpuNext: true,
          deband: true,
          yuv420: false,
        ));

        // Turning a flag back off restores the engine default for it.
        await player.setAdvancedVideo(gpuNext: false);
        expect(player.state.playbackSettings.gpuNext, isFalse);
        expect(player.state.playbackSettings.deband, isTrue);
        expect(engine.advancedVideo.last, (
          gpuNext: false,
          deband: true,
          yuv420: false,
        ));
        raw = await store.read(PlayerController.playbackSettingsKey);
        expect(raw, contains('"gpuNext":false'));
        expect(raw, contains('"deband":true'));
      },
    );

    test('the next playback restores the advanced flags', () async {
      final store = InMemoryKeyValueStore();
      final first = build(testItem(), store: store);
      await first.load();
      await first.setAdvancedVideo(gpuNext: true, yuv420: true);
      first.dispose();
      controller = null;

      engine = FakePlaybackEngine();
      final second = build(testItem(), store: store);
      await second.load();

      expect(second.state.playbackSettings.gpuNext, isTrue);
      expect(second.state.playbackSettings.yuv420, isTrue);
      expect(engine.advancedVideo.single, (
        gpuNext: true,
        deband: false,
        yuv420: true,
      ));
    });

    test('PlaybackSettings round-trips the advanced flags', () {
      const settings = PlaybackSettings(
        gpuNext: true,
        deband: true,
        yuv420: true,
      );
      final restored = PlaybackSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.gpuNext, isTrue);
      expect(restored.deband, isTrue);
      expect(restored.yuv420, isTrue);
      // copyWith only touches the named flag.
      final partial = settings.copyWith(deband: false);
      expect(partial.deband, isFalse);
      expect(partial.gpuNext, isTrue);
      expect(partial.yuv420, isTrue);
    });

    test('fromJson defaults the advanced flags on a legacy blob', () {
      final legacy = PlaybackSettings.fromJson(<String, dynamic>{
        'hwdecEnabled': false,
        'volumeGainPercent': 150,
        'cacheSecs': 45,
        'demuxerMaxBytes': 209715200,
      });
      expect(legacy.hwdecEnabled, isFalse);
      expect(legacy.gpuNext, isFalse);
      expect(legacy.deband, isFalse);
      expect(legacy.yuv420, isFalse);
    });
  });

  group('danmaku (S17)', () {
    const DanmakuComment danmakuComment = DanmakuComment(
      time: Duration(seconds: 2),
      mode: 1,
      color: 16777215,
      text: '弹幕',
    );

    FakeDanmakuService matchedService() {
      return FakeDanmakuService()
        ..result = const DanmakuLoad(
          status: DanmakuStatus.matched,
          episodeLabel: '测试动画 · 第1话',
          comments: <DanmakuComment>[danmakuComment],
        );
    }

    Future<void> writeSettings(KeyValueStore store, DanmakuSettings settings) =>
        store.write(
          PlayerController.danmakuSettingsKey,
          jsonEncode(settings.toJson()),
        );

    test('danmaku is off by default and never auto-matches', () async {
      final danmaku = matchedService();
      final player = build(testItem(), danmaku: danmaku);
      await player.load();

      expect(player.state.danmakuSettings.enabled, isFalse);
      expect(player.state.danmakuStatus, DanmakuStatus.idle);
      expect(danmaku.loadRequests, isEmpty);
    });

    test('a persisted enabled flag auto-matches on load', () async {
      final store = InMemoryKeyValueStore();
      await writeSettings(store, const DanmakuSettings(enabled: true));
      final danmaku = matchedService();
      final player = build(testItem(), danmaku: danmaku, store: store);

      await player.load();
      await Future<void>.delayed(Duration.zero);

      expect(player.state.danmakuSettings.enabled, isTrue);
      expect(danmaku.loadRequests, <String>['item-1']);
      expect(player.state.danmakuStatus, DanmakuStatus.matched);
      expect(player.state.danmakuComments, <DanmakuComment>[danmakuComment]);
      expect(player.state.danmakuEpisodeLabel, '测试动画 · 第1话');
      // Playback is unaffected by the danmaku path.
      expect(player.state.ready, isTrue);
      expect(player.state.error, isNull);
    });

    test('the loading status is visible while the match runs', () async {
      final store = InMemoryKeyValueStore();
      await writeSettings(store, const DanmakuSettings(enabled: true));
      final danmaku = matchedService()..gate = Completer<void>();
      final player = build(testItem(), danmaku: danmaku, store: store);

      await player.load();
      expect(player.state.danmakuStatus, DanmakuStatus.loading);

      danmaku.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.state.danmakuStatus, DanmakuStatus.matched);
    });

    test('enabling mid-session starts the match once', () async {
      final danmaku = matchedService();
      final player = build(testItem(), danmaku: danmaku);
      await player.load();
      expect(danmaku.loadRequests, isEmpty);

      await player.toggleDanmaku();
      await Future<void>.delayed(Duration.zero);

      expect(player.state.danmakuSettings.enabled, isTrue);
      expect(danmaku.loadRequests, <String>['item-1']);
      expect(player.state.danmakuStatus, DanmakuStatus.matched);

      // Off hides the overlay but keeps the cached comments; on again does
      // not re-fetch.
      await player.toggleDanmaku();
      expect(player.state.danmakuSettings.enabled, isFalse);
      expect(player.state.danmakuComments, <DanmakuComment>[danmakuComment]);
      await player.toggleDanmaku();
      await Future<void>.delayed(Duration.zero);
      expect(danmaku.loadRequests, hasLength(1));
    });

    test('a match failure is a non-fatal error status', () async {
      final store = InMemoryKeyValueStore();
      await writeSettings(store, const DanmakuSettings(enabled: true));
      final danmaku = matchedService()..failure = Exception('dandanplay down');
      final player = build(testItem(), danmaku: danmaku, store: store);

      await player.load();
      await Future<void>.delayed(Duration.zero);

      expect(player.state.danmakuStatus, DanmakuStatus.error);
      expect(player.state.danmakuComments, isEmpty);
      expect(player.state.ready, isTrue);
      expect(player.state.error, isNull);
    });

    test('a no-match result is surfaced without comments', () async {
      final store = InMemoryKeyValueStore();
      await writeSettings(store, const DanmakuSettings(enabled: true));
      final danmaku = FakeDanmakuService();
      final player = build(testItem(), danmaku: danmaku, store: store);

      await player.load();
      await Future<void>.delayed(Duration.zero);

      expect(player.state.danmakuStatus, DanmakuStatus.noMatch);
      expect(player.state.danmakuComments, isEmpty);
    });

    test('settings changes reach state and the store', () async {
      final store = InMemoryKeyValueStore();
      final player = build(testItem(), store: store);
      await player.load();

      await player.setDanmakuSettings(
        const DanmakuSettings(
          enabled: true,
          density: 0.5,
          opacity: 0.4,
          speed: 1.5,
          fullArea: true,
        ),
      );

      expect(player.state.danmakuSettings.density, 0.5);
      final raw = await store.read(PlayerController.danmakuSettingsKey);
      expect(raw, isNotNull);
      final restored = DanmakuSettings.fromJson(
        jsonDecode(raw!) as Map<String, dynamic>,
      );
      expect(restored.enabled, isTrue);
      expect(restored.density, 0.5);
      expect(restored.opacity, 0.4);
      expect(restored.speed, 1.5);
      expect(restored.fullArea, isTrue);
    });

    test('the next playback restores the persisted settings', () async {
      final store = InMemoryKeyValueStore();
      final first = build(testItem(), store: store);
      await first.load();
      await first.setDanmakuSettings(
        const DanmakuSettings(enabled: true, opacity: 0.3),
      );
      first.dispose();
      controller = null;

      engine = FakePlaybackEngine();
      final second = build(testItem(), store: store);
      await second.load();

      expect(second.state.danmakuSettings.enabled, isTrue);
      expect(second.state.danmakuSettings.opacity, 0.3);
    });

    test('a corrupt settings blob falls back to the defaults', () async {
      final store = InMemoryKeyValueStore();
      await store.write(PlayerController.danmakuSettingsKey, '{not json');
      final player = build(testItem(), store: store);
      await player.load();

      expect(player.state.danmakuSettings.enabled, isFalse);
      expect(player.state.danmakuSettings.density, 1.0);
    });

    test('no danmaku service wired keeps the toggle harmless', () async {
      final player = build(testItem());
      await player.load();

      await player.toggleDanmaku();
      await Future<void>.delayed(Duration.zero);

      expect(player.state.danmakuSettings.enabled, isTrue);
      expect(player.state.danmakuStatus, DanmakuStatus.idle);
      expect(player.state.ready, isTrue);
    });

    test('DanmakuSettings round-trips and clamps out-of-range values', () {
      const settings = DanmakuSettings(
        enabled: true,
        density: 0.5,
        opacity: 0.4,
        speed: 1.5,
        fullArea: true,
      );
      final restored = DanmakuSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.enabled, isTrue);
      expect(restored.density, 0.5);
      expect(restored.opacity, 0.4);
      expect(restored.speed, 1.5);
      expect(restored.fullArea, isTrue);

      final clamped = DanmakuSettings.fromJson(<String, dynamic>{
        'density': 5,
        'opacity': -1,
        'speed': 99,
      });
      expect(clamped.density, 1.0);
      expect(clamped.opacity, 0.1);
      expect(clamped.speed, 2.0);
      // copyWith only touches the named field.
      final partial = settings.copyWith(opacity: 0.9);
      expect(partial.opacity, 0.9);
      expect(partial.density, 0.5);
      expect(partial.enabled, isTrue);
    });
  });
}
