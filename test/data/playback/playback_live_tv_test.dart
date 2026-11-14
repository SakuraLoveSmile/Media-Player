import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/models/media_source.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/playback_repository.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

import '../../support/fake_emby_server.dart';

/// S21: PlaybackInfo negotiation is type-agnostic, so a LiveTv channel id must
/// negotiate exactly like a library item. These tests pin that tolerance: the
/// channel id reaches `/Items/{id}/PlaybackInfo`, the body opens the live
/// stream, and the server-provided live URL is used verbatim.
void main() {
  late FakeEmbyServer server;
  late AuthRepository lanAuth;
  late AuthRepository wanAuth;
  late PlaybackRepository lanPlayback;
  late PlaybackRepository wanPlayback;

  Future<AuthRepository> login(ServerProfile profile) async {
    final kv = InMemoryKeyValueStore();
    final client = EmbyHttpClient(Dio(), deviceId: 'device-1');
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

  setUp(() async {
    server = FakeEmbyServer();
    await server.start();
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

  test(
    'a live channel id negotiates a direct plan from the live stream URL',
    () async {
      const liveUrl = '/LiveTv/channels/channel-1/stream.ts?api_key=kept';
      server.playbackInfoResponses.add(<String, dynamic>{
        'MediaSources': <Map<String, dynamic>>[
          <String, dynamic>{
            'Id': 'live-ms-1',
            'Container': 'ts',
            'Bitrate': 8000000,
            'SupportsDirectPlay': true,
            'SupportsDirectStream': true,
            'MediaSourceType': 'LiveTv',
            'DirectStreamUrl': liveUrl,
          },
        ],
        'PlaySessionId': 'live-ps-1',
      });

      final plan = await lanPlayback.resolve('channel-1');

      expect(plan.itemId, 'channel-1');
      expect(plan.mode, PlaybackMode.direct);
      expect(plan.url, '${server.base}$liveUrl');
      expect(plan.mediaSourceId, 'live-ms-1');
      expect(plan.playSessionId, 'live-ps-1');
      // The channel id reached PlaybackInfo and the body opens the live stream.
      expect(server.requestLog.last, 'POST /Items/channel-1/PlaybackInfo');
      expect(server.playbackInfoBodies.single['AutoOpenLiveStream'], isTrue);
      expect(server.playbackInfoBodies.single['UserId'], 'user-1');
    },
  );

  test(
    'a live transcode-only source uses the server TranscodingUrl on WAN',
    () async {
      server.playbackInfoResponses.add(<String, dynamic>{
        'MediaSources': <Map<String, dynamic>>[
          <String, dynamic>{
            'Id': 'live-ms-2',
            'Container': 'ts',
            'Bitrate': 8000000,
            'SupportsDirectPlay': false,
            'SupportsDirectStream': false,
            'MediaSourceType': 'LiveTv',
            'TranscodingUrl': '/LiveTv/channels/channel-1/master.m3u8',
          },
        ],
      });

      final plan = await wanPlayback.resolve('channel-1');

      expect(plan.mode, PlaybackMode.transcode);
      expect(plan.endpointKind, EndpointKind.wan);
      expect(
        plan.url,
        '${server.base}/LiveTv/channels/channel-1/master.m3u8'
        '?api_key=${server.token}',
      );
    },
  );

  test('MediaSource labels a LiveTv source and a library source', () {
    final live = MediaSource.fromJson(<String, dynamic>{
      'Id': 'live-ms-1',
      'MediaSourceType': 'LiveTv',
      'SupportsDirectPlay': true,
      'SupportsDirectStream': true,
    });
    expect(live.isLiveTv, isTrue);
    expect(live.mediaSourceType, 'LiveTv');

    final library = MediaSource.fromJson(<String, dynamic>{
      'Id': 'ms-1',
      'SupportsDirectPlay': true,
      'SupportsDirectStream': true,
    });
    expect(library.isLiveTv, isFalse);
    expect(library.mediaSourceType, isNull);
  });
}
