import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/direct_play_probe.dart';
import 'package:media_player/data/playback/playback_repository.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

import '../../support/fake_emby_server.dart';

Map<String, dynamic> sessionJson({
  String deviceId = 'device-1',
  String? playMethod = 'DirectPlay',
  bool? videoDirect,
  bool withPlayState = true,
  bool withTranscodingInfo = false,
}) {
  return <String, dynamic>{
    'DeviceId': deviceId,
    if (withPlayState)
      'PlayState': <String, dynamic>{'PlayMethod': ?playMethod},
    if (withTranscodingInfo)
      'TranscodingInfo': <String, dynamic>{'IsVideoDirect': ?videoDirect},
  };
}

void main() {
  late FakeEmbyServer server;
  late List<String> logs;
  late AuthRepository auth;
  late DirectPlayProbe probe;

  PlaybackPlan plan() {
    return PlaybackPlan(
      itemId: 'movie-1',
      mode: PlaybackMode.direct,
      endpointKind: EndpointKind.lan,
      url: '${server.base}/videos/movie-1/stream?api_key=secret',
      headers: const <String, String>{},
      mediaSourceId: 'ms-1',
      playSessionId: 'ps-1',
    );
  }

  setUp(() async {
    server = FakeEmbyServer();
    await server.start();
    logs = <String>[];

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
    probe = DirectPlayProbe(auth, logSink: logs.add);
  });

  tearDown(() async {
    await auth.dispose();
    await server.stop();
  });

  test('DirectPlay confirms direct video without audio transcoding', () async {
    server.sessionsResponse = <Map<String, dynamic>>[sessionJson()];

    final confirmed = await probe.confirm(plan());

    expect(confirmed.videoDirect, isTrue);
    expect(confirmed.audioTranscoded, isFalse);
    expect(confirmed.transcodingReasons, isEmpty);
  });

  test('DirectStream counts as direct video', () async {
    server.sessionsResponse = <Map<String, dynamic>>[
      sessionJson(playMethod: 'DirectStream'),
    ];

    final confirmed = await probe.confirm(plan());

    expect(confirmed.videoDirect, isTrue);
    expect(confirmed.audioTranscoded, isFalse);
    expect(confirmed.transcodingReasons, isEmpty);
  });

  test('Transcode with IsVideoDirect true keeps video direct', () async {
    server.sessionsResponse = <Map<String, dynamic>>[
      sessionJson(
        playMethod: 'Transcode',
        videoDirect: true,
        withTranscodingInfo: true,
      ),
    ];

    final confirmed = await probe.confirm(plan());

    expect(confirmed.videoDirect, isTrue);
    expect(confirmed.audioTranscoded, isTrue);
    expect(confirmed.transcodingReasons, isEmpty);
  });

  test('Transcode with IsVideoDirect false flags video transcoding', () async {
    server.sessionsResponse = <Map<String, dynamic>>[
      sessionJson(
        playMethod: 'Transcode',
        videoDirect: false,
        withTranscodingInfo: true,
      ),
    ];

    final confirmed = await probe.confirm(plan());

    expect(confirmed.videoDirect, isFalse);
    expect(confirmed.audioTranscoded, isTrue);
    expect(confirmed.transcodingReasons, isEmpty);
  });

  test('a different DeviceId leaves the verdict unconfirmed', () async {
    server.sessionsResponse = <Map<String, dynamic>>[
      sessionJson(deviceId: 'other-device'),
    ];

    final confirmed = await probe.confirm(plan());

    expect(confirmed.videoDirect, isNull);
    expect(confirmed.transcodingReasons, isEmpty);
  });

  test('missing PlayState and unknown PlayMethod stay unconfirmed', () async {
    server.sessionsResponse = <Map<String, dynamic>>[
      sessionJson(withPlayState: false),
    ];
    expect((await probe.confirm(plan())).videoDirect, isNull);

    server.sessionsResponse = <Map<String, dynamic>>[
      sessionJson(playMethod: 'SomethingElse'),
    ];
    final unknown = await probe.confirm(plan());
    expect(unknown.videoDirect, isNull);
    expect(unknown.transcodingReasons, isEmpty);
  });

  test('Transcode without IsVideoDirect stays unconfirmed', () async {
    server.sessionsResponse = <Map<String, dynamic>>[
      sessionJson(playMethod: 'Transcode'),
    ];

    final confirmed = await probe.confirm(plan());

    expect(confirmed.videoDirect, isNull);
    expect(confirmed.transcodingReasons, isEmpty);
  });

  test('a 500 returns the original plan instead of throwing', () async {
    server.sessionsStatus = 500;

    final confirmed = await probe.confirm(plan());

    expect(confirmed.videoDirect, isNull);
    expect(confirmed.transcodingReasons, isEmpty);
  });

  test('PlaybackRepository.confirmDirect delegates to the probe', () async {
    server.sessionsResponse = <Map<String, dynamic>>[sessionJson()];
    final repository = PlaybackRepository(auth);

    final confirmed = await repository.confirmDirect(plan());

    expect(confirmed.videoDirect, isTrue);
    expect(confirmed.audioTranscoded, isFalse);
  });
}
