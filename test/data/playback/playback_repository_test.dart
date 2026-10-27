import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/api/emby_headers.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/playback_repository.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

import '../../support/fake_emby_server.dart';

Map<String, dynamic> playbackInfo(
  List<Map<String, dynamic>> sources, {
  String? playSessionId,
}) {
  return <String, dynamic>{
    'MediaSources': sources,
    'PlaySessionId': ?playSessionId,
  };
}

Map<String, dynamic> directSource({String? directStreamUrl}) {
  return <String, dynamic>{
    'Id': 'ms-1',
    'Container': 'mkv',
    'Bitrate': 12100000,
    'SupportsDirectPlay': true,
    'SupportsDirectStream': true,
    'DirectStreamUrl': ?directStreamUrl,
  };
}

Map<String, dynamic> directStreamOnlySource() {
  return <String, dynamic>{
    'Id': 'ms-2',
    'Container': 'mp4',
    'Bitrate': 8000000,
    'SupportsDirectPlay': false,
    'SupportsDirectStream': true,
  };
}

Map<String, dynamic> transcodeSource({
  String transcodingUrl = '/videos/ts-1/master.m3u8?MediaSourceId=ms-1',
}) {
  return <String, dynamic>{
    'Id': 'ms-1',
    'Container': 'ts',
    'Bitrate': 12100000,
    'SupportsDirectPlay': false,
    'SupportsDirectStream': false,
    'TranscodingUrl': transcodingUrl,
  };
}

void main() {
  late FakeEmbyServer server;
  late List<String> logs;
  late AuthRepository lanAuth;
  late AuthRepository wanAuth;
  late PlaybackRepository lanPlayback;
  late PlaybackRepository wanPlayback;

  Future<AuthRepository> login(ServerProfile profile) async {
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
    final auth = AuthRepository(
      client: client,
      resolver: resolver,
      tokenStore: TokenStore(kv),
      sessionStore: SessionStore(kv),
      profileStore: ProfileStore(kv),
      deviceId: 'device-1',
      deviceName: 'test',
    );
    await auth.login(username: 'test', password: 'correct', profile: profile);
    return auth;
  }

  int playbackInfoCount() => server.requestLog
      .where((line) => line.endsWith('/PlaybackInfo'))
      .length;

  setUp(() async {
    server = FakeEmbyServer();
    await server.start();
    logs = <String>[];

    lanAuth = await login(
      ServerProfile(serverId: '', name: 'Home', lanUrl: server.base),
    );
    wanAuth = await login(
      ServerProfile(serverId: '', name: 'Home', wanUrl: server.base),
    );
    lanPlayback = PlaybackRepository(lanAuth);
    wanPlayback = PlaybackRepository(wanAuth);
  });

  tearDown(() async {
    await lanAuth.dispose();
    await wanAuth.dispose();
    await server.stop();
  });

  test('sends the contract PlaybackInfo body for the LAN endpoint', () async {
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[directSource()]),
    );

    await lanPlayback.resolve(
      'movie-1',
      startAt: const Duration(minutes: 2, seconds: 3),
    );

    final body = server.playbackInfoBodies.single;
    expect(body['UserId'], 'user-1');
    expect(body['StartTimeTicks'], 1230000000); // 123s in 100ns ticks
    expect(body['IsPlayback'], isTrue);
    expect(body['AutoOpenLiveStream'], isTrue);
    expect(body['EnableDirectPlay'], isTrue);
    expect(body['EnableDirectStream'], isTrue);
    expect(body['EnableTranscoding'], isTrue);
    expect(body['MaxStreamingBitrate'], 1000000000);

    final deviceProfile = body['DeviceProfile'] as Map<String, dynamic>;
    expect(deviceProfile['Name'], 'MediaPlayer-mpv');

    expect(server.requestLog.last, 'POST /Items/movie-1/PlaybackInfo');
    expect(server.lastPlaybackInfoQuery, <String, String>{'UserId': 'user-1'});
    expect(server.lastPlaybackInfoToken, server.token);
  });

  test('carries the top level PlaySessionId into the plan', () async {
    server.playbackInfoResponses.add(
      playbackInfo(
        <Map<String, dynamic>>[directSource()],
        playSessionId: 'ps-1',
      ),
    );

    final plan = await lanPlayback.resolve(
      'movie-1',
      startAt: const Duration(seconds: 42),
    );

    expect(plan.itemId, 'movie-1');
    expect(plan.playSessionId, 'ps-1');
    expect(plan.startAt, const Duration(seconds: 42));
  });

  test('keeps a relative DirectStreamUrl verbatim after absolutizing',
      () async {
    final relative = '/videos/ts-1/stream.mkv?MediaSourceId=ms-1&Static=true'
        '&UserId=user-1&api_key=${server.token}';
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[
        directSource(directStreamUrl: relative),
      ]),
    );

    final plan = await lanPlayback.resolve('ts-1');

    expect(plan.mode, PlaybackMode.direct);
    expect(plan.mediaSourceId, 'ms-1');
    expect(plan.url, '${server.base}$relative');

    final uri = Uri.parse(plan.url);
    final base = Uri.parse(server.base);
    expect(uri.scheme, 'http');
    expect(uri.host, base.host);
    expect(uri.port, base.port);
    expect(uri.path, '/videos/ts-1/stream.mkv');
    expect(uri.queryParameters, <String, String>{
      'MediaSourceId': 'ms-1',
      'Static': 'true',
      'UserId': 'user-1',
      'api_key': server.token,
    });
  });

  test('builds a static stream URL when only DirectStream is supported',
      () async {
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[directStreamOnlySource()]),
    );

    final plan = await lanPlayback.resolve('mv-2');

    expect(plan.mode, PlaybackMode.direct);
    expect(plan.mediaSourceId, 'ms-2');
    final uri = Uri.parse(plan.url);
    expect(uri.path, '/Videos/mv-2/stream');
    expect(uri.queryParameters, <String, String>{
      'Static': 'true',
      'MediaSourceId': 'ms-2',
      'DeviceId': 'device-1',
      'api_key': server.token,
    });
    expect(plan.headers[EmbyHeaders.token], server.token);
    expect(playbackInfoCount(), 1);
  });

  test('uses TranscodingUrl on WAN and appends a missing api_key', () async {
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[transcodeSource()]),
    );

    final plan = await wanPlayback.resolve('ts-1');

    expect(plan.mode, PlaybackMode.transcode);
    expect(plan.endpointKind, EndpointKind.wan);
    expect(
      plan.url,
      '${server.base}/videos/ts-1/master.m3u8?MediaSourceId=ms-1'
      '&api_key=${server.token}',
    );
    // WAN may transcode, so the LAN direct retry must not run (§3.3).
    expect(playbackInfoCount(), 1);
    expect(server.playbackInfoBodies.single['MaxStreamingBitrate'], 30000000);

    server.playbackInfoResponses
      ..clear()
      ..add(
        playbackInfo(<Map<String, dynamic>>[
          transcodeSource(
            transcodingUrl: '/videos/ts-1/master.m3u8?api_key=kept',
          ),
        ]),
      );
    final withKey = await wanPlayback.resolve('ts-1');
    expect(
      withKey.url,
      '${server.base}/videos/ts-1/master.m3u8?api_key=kept',
    );
  });

  test('empty MediaSources maps to playbackUnsupported', () async {
    server.playbackInfoResponses.add(
      playbackInfo(const <Map<String, dynamic>>[]),
    );

    await expectLater(
      wanPlayback.resolve('ts-1'),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.playbackUnsupported)),
    );
    expect(playbackInfoCount(), 1);
  });

  test('LAN retries once without transcoding, then fails as directPlayDenied',
      () async {
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[transcodeSource()]),
    );
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[
        directSource(directStreamUrl: '/videos/ts-1/stream.mkv?api_key=x'),
      ]),
    );

    final plan = await lanPlayback.resolve('ts-1');

    expect(plan.mode, PlaybackMode.direct);
    expect(playbackInfoCount(), 2);
    expect(server.playbackInfoBodies, hasLength(2));
    expect(server.playbackInfoBodies[1]['EnableTranscoding'], isFalse);
    expect(server.playbackInfoBodies[1]['EnableDirectPlay'], isTrue);
    expect(server.playbackInfoBodies[1]['EnableDirectStream'], isTrue);
    expect(server.playbackInfoBodies[1]['MaxStreamingBitrate'], 1000000000);

    server.playbackInfoResponses
      ..clear()
      ..add(playbackInfo(<Map<String, dynamic>>[transcodeSource()]))
      ..add(playbackInfo(<Map<String, dynamic>>[transcodeSource()]));
    server.playbackInfoBodies.clear();
    server.requestLog.clear();

    await expectLater(
      lanPlayback.resolve('ts-1'),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.directPlayDenied)),
    );
    expect(playbackInfoCount(), 2);
  });

  test('LAN sends a single request when the server offers direct play',
      () async {
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[
        directSource(directStreamUrl: '/videos/ts-1/stream.mkv?api_key=x'),
      ]),
    );

    await lanPlayback.resolve('ts-1');

    expect(playbackInfoCount(), 1);
    expect(server.playbackInfoBodies, hasLength(1));
  });

  test('headers carry the token and a logged out session is unauthorized',
      () async {
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[
        directSource(directStreamUrl: '/videos/ts-1/stream.mkv?api_key=x'),
      ]),
    );

    final plan = await lanPlayback.resolve('ts-1');
    expect(plan.headers, <String, String>{EmbyHeaders.token: server.token});
    expect(server.lastPlaybackInfoToken, server.token);

    await lanAuth.logout();
    server.requestLog.clear();

    await expectLater(
      lanPlayback.resolve('ts-1'),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
    );
    expect(server.requestLog, isEmpty);
  });

  test('negotiation logs the path only, never api_key or the token', () async {
    server.playbackInfoResponses.add(
      playbackInfo(<Map<String, dynamic>>[
        directSource(
          directStreamUrl: '/videos/ts-1/stream.mkv?api_key=${server.token}',
        ),
      ]),
    );
    logs.clear();

    final plan = await lanPlayback.resolve('ts-1');

    expect(plan.url, contains('api_key='));
    expect(plan.toString(), isNot(contains('api_key')));
    final joined = logs.join('\n');
    expect(joined, contains('/Items/ts-1/PlaybackInfo'));
    expect(joined, isNot(contains('api_key')));
    expect(joined, isNot(contains(server.token)));
  });
}
