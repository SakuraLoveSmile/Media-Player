import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/features/player/player_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';

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

  test('a position below the 10 s threshold starts from the beginning',
      () async {
    final player = build(testItem(position: const Duration(seconds: 8)));

    await player.load();

    expect(playback.resolveStartAts, <Duration>[Duration.zero]);
    expect(player.state.resumedFrom, isNull);
  });

  test('a series stops before negotiating', () async {
    final player = build(testItem(type: 'Series'));

    await player.load();

    expect(playback.resolveCalls, 0);
    expect(player.state.unsupported, isTrue);
    expect(player.state.ready, isFalse);
    expect(player.state.error, contains('分集'));
  });

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

  test('a successful start opens once and reports the engine position',
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
  });

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
    expect(reporter.progressReports.single.position, const Duration(minutes: 5));
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

  test('an engine error becomes copy, never a toString', () async {
    final player = build(testItem());
    await player.load();

    engine.emit(PlaybackSnapshot(error: Exception('mpv: boom')));
    await pumpEventQueue();

    expect(player.state.error, '播放失败，请重试');
  });
}
