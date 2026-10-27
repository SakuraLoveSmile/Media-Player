import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/playback_options.dart';

void main() {
  ServerProfile profile({
    int wanBitrateCapMbps = 30,
    bool forceDirectOnWan = false,
  }) {
    return ServerProfile(
      serverId: 'server-1',
      name: 'Home',
      lanUrl: 'http://192.168.1.10:8096',
      wanUrl: 'https://emby.example.com',
      wanBitrateCapMbps: wanBitrateCapMbps,
      forceDirectOnWan: forceDirectOnWan,
    );
  }

  test('LAN always asks for the highest bitrate with transcoding enabled', () {
    final options = PlaybackOptions.forEndpoint(
      EndpointKind.lan,
      profile(wanBitrateCapMbps: 30),
    );

    expect(options.maxStreamingBitrate, 1000000000);
    expect(options.enableTranscoding, isTrue);
  });

  test('WAN caps the bitrate at wanBitrateCapMbps megabytes per second', () {
    final options = PlaybackOptions.forEndpoint(
      EndpointKind.wan,
      profile(wanBitrateCapMbps: 30),
    );

    expect(options.maxStreamingBitrate, 30000000);
    expect(options.enableTranscoding, isTrue);
  });

  test('WAN with forceDirectOnWan raises the cap and disables transcoding', () {
    final options = PlaybackOptions.forEndpoint(
      EndpointKind.wan,
      profile(wanBitrateCapMbps: 30, forceDirectOnWan: true),
    );

    expect(options.maxStreamingBitrate, 1000000000);
    expect(options.enableTranscoding, isFalse);
  });

  test('a zero cap or a missing profile falls back to LAN behaviour', () {
    final zeroCap = PlaybackOptions.forEndpoint(
      EndpointKind.wan,
      profile(wanBitrateCapMbps: 0),
    );
    final noProfile = PlaybackOptions.forEndpoint(EndpointKind.wan, null);

    expect(zeroCap.maxStreamingBitrate, 1000000000);
    expect(zeroCap.enableTranscoding, isTrue);
    expect(noProfile.maxStreamingBitrate, 1000000000);
    expect(noProfile.enableTranscoding, isTrue);
  });
}
