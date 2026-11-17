import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/watch_together/watch_together_client.dart';
import 'package:media_player/features/player/player_controller.dart';
import 'package:media_player/features/player/watch_playback_coordinator.dart';

import '../../data/offline/offline_test_session.dart';
import '../../support/fake_library_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';

WatchRoom makeRoom({
  int revision = 1,
  String state = 'paused',
  int position = 10000,
  int anchor = 100000,
  String source = 'source',
}) => WatchRoom(
  roomId: 'room',
  code: 'ABC123',
  capacity: 8,
  ownerMemberId: 'member',
  media: WatchMedia(
    itemId: 'movie',
    mediaSourceId: source,
    title: 'Movie',
    type: 'Movie',
    runTimeMs: 600000,
  ),
  playback: WatchPlayback(
    revision: revision,
    state: state,
    positionMs: position,
    serverTime: anchor,
    waitingMemberIds: const [],
  ),
  members: const [],
);

class RoomClient extends WatchTogetherClient {
  RoomClient()
    : super(
        session: OfflineTestSession('https://emby.example'),
        store: InMemoryKeyValueStore(),
      );
  WatchRoom? current = makeRoom();
  bool online = true;
  int now = 100000;
  final commands = <String>[];
  final statuses = <({String status, int position})>[];
  bool echoStatus = false;
  @override
  WatchRoom? get room => current;
  @override
  bool get connected => online;
  @override
  int get serverNowMs => now;
  @override
  Future<void> command(String action, {int? positionMs}) async {
    commands.add(action);
  }

  @override
  void reportStatus(String status, {int positionMs = 0}) {
    statuses.add((status: status, position: positionMs));
    if (echoStatus) notifyListeners();
  }

  void update(WatchRoom? value) {
    current = value;
    notifyListeners();
  }

  void disconnect() {
    online = false;
    notifyListeners();
  }
}

class RoomEngine extends FakePlaybackEngine implements PausedOpenEngine {
  int pausedOpens = 0;
  Completer<void>? seekGate;
  Completer<void>? seekStarted;
  bool bufferOnSeek = false;
  @override
  Future<void> openPaused(PlaybackPlan plan) async {
    pausedOpens++;
    await super.open(plan);
  }

  @override
  Future<void> seekTo(Duration position) async {
    await super.seekTo(position);
    if (bufferOnSeek) {
      emit(PlaybackSnapshot(position: position, buffering: true));
      await Future<void>.delayed(Duration.zero);
    }
    if (seekStarted?.isCompleted == false) seekStarted!.complete();
    await seekGate?.future;
  }
}

Future<void> settle([bool Function()? condition]) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (condition == null || condition()) return;
  }
  fail('Playback did not settle');
}

void main() {
  late RoomClient client;
  late RoomEngine engine;
  late FakePlaybackReporter reporter;
  late PlayerController player;
  WatchPlaybackCoordinator? coordinator;
  setUp(() {
    client = RoomClient();
    engine = RoomEngine();
    reporter = FakePlaybackReporter();
    final library = FakeLibraryService()
      ..itemsByView = {
        fakeMoviesView.id: [
          MediaItem(
            id: 'movie',
            name: 'Movie',
            type: 'Movie',
            runTimeTicks: 6000000000,
            userData: const UserItemData(positionTicks: 900000000),
          ),
        ],
      };
    player = PlayerController(
      itemId: 'movie',
      library: library,
      playback: FakePlaybackService(),
      engine: engine,
      reporter: reporter,
      delay: (_) async {},
    );
  });
  tearDown(() async {
    await coordinator?.close();
    coordinator?.dispose();
    coordinator = null;
    player.dispose();
    client.dispose();
  });
  WatchPlaybackCoordinator bind() => coordinator = WatchPlaybackCoordinator(
    client: client,
    controller: player,
    roomId: 'room',
    itemId: 'movie',
  );

  test(
    'room start overrides personal resume and opens paused before ready',
    () async {
      bind();
      await player.load();
      expect(engine.pausedOpens, 1);
      expect(engine.openedPlans.single.startAt, const Duration(seconds: 10));
      expect(player.state.resumedFrom, isNull);
      expect(player.state.playing, isFalse);
      expect(engine.playCalls, 0);
      expect(reporter.startedAt, const Duration(seconds: 10));
    },
  );

  test('user controls issue commands; remote apply never echoes and reports locally', () async {
    bind();
    await player.load();
    await player.togglePlayPause();
    await player.seekTo(const Duration(seconds: 20));
    expect(client.commands, ['play', 'seek']);
    expect(engine.playCalls, 0);
    expect(engine.seeks, isEmpty);
    await player.setRate(1.5);
    expect(coordinator!.notice, contains('固定'));
    expect(engine.rates, isNot(contains(1.5)));
    client.current = makeRoom(state: 'playing');
    await player.applyWatchState(
      playing: true,
      position: const Duration(seconds: 30),
    );
    expect(engine.playCalls, 1);
    expect(engine.seeks.last, const Duration(seconds: 30));
    expect(client.commands, ['play', 'seek']);
    expect(reporter.progressReports.last.paused, isFalse);
  });

  test(
    'drift uses a small rate correction and hard seeks past two seconds',
    () async {
      final sync = bind();
      await player.load();
      client.current = makeRoom(state: 'playing', position: 11000);
      await sync.start();
      expect(engine.rates.last, 1.05);
      expect(engine.seeks, isEmpty);
      client.update(makeRoom(revision: 2, state: 'playing', position: 15000));
      await settle(() => engine.seeks.isNotEmpty);
      expect(engine.seeks.last, const Duration(seconds: 15));
      expect(engine.rates.last, 1);
      expect(client.commands, isEmpty);
    },
  );

  test('future anchors remain paused', () async {
    final sync = bind();
    await player.load();
    client.current = makeRoom(state: 'playing', anchor: 100500);
    await sync.start();
    expect(engine.playCalls, 0);
    expect(player.state.playing, isFalse);
  });

  test(
    'waiting readiness is sent after seek and uses the new buffering state',
    () async {
      final sync = bind();
      await player.load();
      engine.bufferOnSeek = true;
      client.current = makeRoom(state: 'waiting', position: 30000);
      await sync.start();
      expect(engine.seeks.last, const Duration(seconds: 30));
      expect(client.statuses.map((s) => s.status), isNot(contains('ready')));
      expect(client.statuses.last.status, 'buffering');
      expect(engine.playCalls, 0);
    },
  );

  test('background loading retains away and sends no loading/ready', () async {
    final sync = bind();
    sync.setForeground(false);
    await sync.start();
    await player.load();
    client.notifyListeners();
    await settle();
    expect(client.statuses.map((s) => s.status).toList(), ['away']);
    expect(engine.playCalls, 0);
  });

  test('loading and error status echo is bounded per revision', () async {
    final sync = bind();
    client.echoStatus = true;
    await sync.start();
    for (var i = 0; i < 20; i++) {
      client.notifyListeners();
    }
    await settle();
    expect(client.statuses, hasLength(1));
    engine.openError = StateError('cannot open');
    await player.load();
    client.notifyListeners();
    await settle(() => client.statuses.length > 1);
    expect(client.statuses.map((s) => s.status).toList(), ['loading', 'error']);
  });

  test(
    'same item changed source pauses old player without claiming readiness',
    () async {
      final sync = bind();
      await player.load();
      client.current = makeRoom(state: 'playing');
      await sync.start();
      expect(player.state.playing, isTrue);
      client.statuses.clear();
      client.update(
        makeRoom(revision: 2, state: 'waiting', source: 'other-source'),
      );
      await settle(() => !player.state.playing);
      expect(engine.pauseCalls, greaterThan(0));
      expect(client.statuses, isEmpty);
      await sync.close();
      expect(client.statuses, isEmpty);
    },
  );

  test(
    'closing during a pending seek never resumes and does not pause the room',
    () async {
      final sync = bind();
      await player.load();
      engine.seekStarted = Completer<void>();
      engine.seekGate = Completer<void>();
      client.current = makeRoom(state: 'playing', position: 30000);
      final starting = sync.start();
      await engine.seekStarted!.future;
      final closing = sync.close();
      engine.seekGate!.complete();
      await Future.wait([starting, closing]);
      expect(engine.playCalls, 0);
      expect(player.state.playing, isFalse);
      expect(client.commands, isEmpty);
      expect(client.statuses.last.status, 'away');
    },
  );

  test(
    'sleep timer marks this viewer away and room ticks cannot resume it',
    () async {
      final sync = bind();
      await player.load();
      client.current = makeRoom(state: 'playing');
      await sync.start();
      player.setSleepTimer(const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await settle(() => !player.state.playing);
      final plays = engine.playCalls;
      client.notifyListeners();
      await settle();
      expect(player.state.playing, isFalse);
      expect(engine.playCalls, plays);
      expect(client.statuses.last.status, 'away');
      expect(client.commands, isEmpty);
      expect(sync.notice, contains('睡眠'));
    },
  );

  test(
    'background and disconnection pause locally without sending room pause',
    () async {
      final sync = bind();
      await player.load();
      client.current = makeRoom(state: 'playing');
      await sync.start();
      sync.setForeground(false);
      await settle(() => !player.state.playing);
      expect(client.statuses.last.status, 'away');
      sync.setForeground(true);
      await settle(() => player.state.playing);
      client.disconnect();
      await settle(() => !player.state.playing);
      expect(client.commands, isEmpty);
    },
  );
}
