import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/session_reporter.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

import '../../support/fake_emby_server.dart';

void main() {
  late FakeEmbyServer server;
  late List<String> logs;
  late AuthRepository auth;
  late StreamController<void> heartbeat;

  PlaybackPlan plan({PlaybackMode mode = PlaybackMode.direct}) {
    return PlaybackPlan(
      itemId: 'movie-1',
      mode: mode,
      endpointKind: EndpointKind.lan,
      url: '${server.base}/videos/movie-1/stream?api_key=secret',
      headers: const <String, String>{},
      mediaSourceId: 'ms-1',
      playSessionId: 'ps-1',
    );
  }

  SessionReporter reporter() {
    return SessionReporter(
      auth,
      heartbeat: heartbeat.stream,
      delay: (Duration _) async {},
      logSink: logs.add,
    );
  }

  Future<void> waitForReports(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (server.sessionReportPaths.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $count session reports');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  List<Map<String, dynamic>> progressBodies() {
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < server.sessionReportPaths.length; i++) {
      if (server.sessionReportPaths[i].endsWith('/Progress')) {
        result.add(server.sessionBodies[i]);
      }
    }
    return result;
  }

  int reportCount(String path) => server.requestLog
      .where((line) => line == 'POST $path')
      .length;

  setUp(() async {
    server = FakeEmbyServer();
    await server.start();
    logs = <String>[];
    heartbeat = StreamController<void>.broadcast();

    final kv = InMemoryKeyValueStore();
    final client = EmbyHttpClient(
      Dio(),
      deviceId: 'device-1',
      logSink: logs.add,
    );
    final resolver = EndpointResolver(
      HttpEndpointProbe(client),
      lanTimeout: const Duration(seconds: 1),
      wanTimeout: const Duration(seconds: 1),
    );
    auth = AuthRepository(
      client: client,
      resolver: resolver,
      tokenStore: TokenStore(kv),
      sessionStore: SessionStore(kv),
      profileStore: ProfileStore(kv),
      deviceId: 'device-1',
      deviceName: 'test',
    );
    await auth.login(
      username: 'test',
      password: 'correct',
      profile: ServerProfile(serverId: '', name: 'Home', lanUrl: server.base),
    );
  });

  tearDown(() async {
    await heartbeat.close();
    await auth.dispose();
    await server.stop();
  });

  test('reports Playing, two Progress ticks and Stopped in order', () async {
    final reporterUnderTest = reporter();
    await reporterUnderTest.started(
      plan(),
      Duration.zero,
      position: () => Duration.zero,
    );

    heartbeat.add(null);
    await waitForReports(2);
    heartbeat.add(null);
    await waitForReports(3);
    await reporterUnderTest.stopped(plan(), const Duration(seconds: 3));

    expect(server.sessionReportPaths, <String>[
      '/Sessions/Playing',
      '/Sessions/Playing/Progress',
      '/Sessions/Playing/Progress',
      '/Sessions/Playing/Stopped',
    ]);
  });

  test('Playing carries the seven contract fields', () async {
    final reporterUnderTest = reporter();
    await reporterUnderTest.started(
      plan(),
      const Duration(minutes: 1, seconds: 2, milliseconds: 3),
      position: () => Duration.zero,
    );

    final body = server.sessionBodies.single;
    expect(body['ItemId'], 'movie-1');
    expect(body['MediaSourceId'], 'ms-1');
    expect(body['PlaySessionId'], 'ps-1');
    expect(body['PositionTicks'], 620030000); // 62.003 s in 100 ns ticks
    expect(body['IsPaused'], isFalse);
    expect(body['PlayMethod'], 'DirectPlay');
    expect(body['CanSeek'], isTrue);
  });

  test('the heartbeat reads the current position on every tick', () async {
    var tick = 0;
    final reporterUnderTest = reporter();
    await reporterUnderTest.started(
      plan(),
      Duration.zero,
      position: () => Duration(seconds: 10 * ++tick),
    );

    heartbeat.add(null);
    await waitForReports(2);
    heartbeat.add(null);
    await waitForReports(3);

    final bodies = progressBodies();
    expect(bodies, hasLength(2));
    expect(bodies[0]['PositionTicks'], 100000000);
    expect(bodies[1]['PositionTicks'], 200000000);
    expect(
      bodies[1]['PositionTicks'] as int,
      greaterThan(bodies[0]['PositionTicks'] as int),
    );
  });

  test('the heartbeat keeps the latest pause state from progress', () async {
    final reporterUnderTest = reporter();
    await reporterUnderTest.started(
      plan(),
      Duration.zero,
      position: () => Duration.zero,
    );

    await reporterUnderTest.progress(
      plan(),
      const Duration(seconds: 1),
      paused: true,
    );
    heartbeat.add(null);
    await waitForReports(3);
    expect(progressBodies().last['IsPaused'], isTrue);

    await reporterUnderTest.progress(
      plan(),
      const Duration(seconds: 2),
      paused: false,
    );
    heartbeat.add(null);
    await waitForReports(5);
    expect(progressBodies().last['IsPaused'], isFalse);
  });

  test('a transcode plan reports PlayMethod Transcode', () async {
    final reporterUnderTest = reporter();
    await reporterUnderTest.started(
      plan(mode: PlaybackMode.transcode),
      Duration.zero,
      position: () => Duration.zero,
    );

    expect(server.sessionBodies.single['PlayMethod'], 'Transcode');
  });

  test('a 500 is retried once, logged once and never rethrown', () async {
    server.failingSessionPaths.add('/Sessions/Playing');
    final reporterUnderTest = reporter();

    await reporterUnderTest.started(
      plan(),
      Duration.zero,
      position: () => Duration.zero,
    );

    expect(reportCount('/Sessions/Playing'), 2);
    final warns = logs.where((line) => line.startsWith('WARN')).toList();
    expect(warns, hasLength(1));
    expect(warns.single, isNot(contains('secret')));
    expect(warns.single, isNot(contains('api_key')));
  });

  test('stopped is idempotent', () async {
    final reporterUnderTest = reporter();
    await reporterUnderTest.started(
      plan(),
      Duration.zero,
      position: () => Duration.zero,
    );

    await reporterUnderTest.stopped(plan(), Duration.zero);
    await reporterUnderTest.stopped(plan(), Duration.zero);

    expect(reportCount('/Sessions/Playing/Stopped'), 1);
  });

  test('ticks after stopped do not send requests', () async {
    final reporterUnderTest = reporter();
    await reporterUnderTest.started(
      plan(),
      Duration.zero,
      position: () => Duration.zero,
    );
    await reporterUnderTest.stopped(plan(), Duration.zero);

    final before = server.sessionReportPaths.length;
    heartbeat.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(server.sessionReportPaths.length, before);
  });

  test('reports stay serialized while a slow Progress is in flight', () async {
    final gate = Completer<void>();
    server.progressHold = gate.future;
    final reporterUnderTest = reporter();
    await reporterUnderTest.started(
      plan(),
      Duration.zero,
      position: () => Duration.zero,
    );

    final first = reporterUnderTest.progress(
      plan(),
      const Duration(seconds: 1),
      paused: false,
    );
    final second = reporterUnderTest.progress(
      plan(),
      const Duration(seconds: 2),
      paused: false,
    );

    await waitForReports(2);
    // The second report must not reach the server until the first replies.
    expect(progressBodies(), hasLength(1));

    gate.complete();
    await Future.wait(<Future<void>>[first, second]);

    final positions =
        progressBodies().map((body) => body['PositionTicks']).toList();
    expect(positions, <int>[10000000, 20000000]);
  });
}
