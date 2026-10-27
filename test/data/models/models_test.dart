import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/api/device_profile.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/media_source.dart';
import 'package:media_player/data/models/server_profile.dart';

void main() {
  group('ServerProfile', () {
    test('round-trips through JSON with defaults', () {
      const profile = ServerProfile(
        serverId: 'abc',
        name: 'Home',
        lanUrl: 'http://192.168.1.10:8096',
        wanUrl: 'https://emby.example.com',
      );

      final restored = ServerProfile.fromJson(profile.toJson());

      expect(restored.serverId, 'abc');
      expect(restored.name, 'Home');
      expect(restored.lanUrl, 'http://192.168.1.10:8096');
      expect(restored.wanUrl, 'https://emby.example.com');
      expect(restored.preference, EndpointPreference.auto);
      expect(restored.wanBitrateCapMbps, 30);
      expect(restored.forceDirectOnWan, isFalse);
      expect(restored.lastGoodEndpoint, isNull);
    });

    test('survives missing and unknown fields', () {
      final profile = ServerProfile.fromJson(<String, dynamic>{
        'serverId': null,
        'name': 'Home',
        'preference': 'nonsense',
        'wanBitrateCapMbps': '45',
        'lastGoodEndpoint': 'satellite',
        'unknownFutureField': true,
      });

      expect(profile.serverId, '');
      expect(profile.preference, EndpointPreference.auto);
      expect(profile.wanBitrateCapMbps, 45);
      expect(profile.lastGoodEndpoint, isNull);
      expect(profile.hasAnyAddress, isFalse);
    });

    test('copyWith keeps values and clears on empty string', () {
      const profile = ServerProfile(
        serverId: 'abc',
        name: 'Home',
        lanUrl: 'http://lan',
        wanUrl: 'https://wan',
      );

      final updated = profile.copyWith(
        wanUrl: '',
        lastGoodEndpoint: EndpointKind.wan,
      );

      expect(updated.lanUrl, 'http://lan');
      expect(updated.wanUrl, isNull);
      expect(updated.lastGoodEndpoint, EndpointKind.wan);
      expect(updated.serverId, 'abc');
    });
  });

  group('AuthSession', () {
    test('meta JSON never contains the token', () {
      const session = AuthSession(
        userId: 'u1',
        userName: 'test',
        accessToken: 'secret-token',
        deviceId: 'd1',
      );

      final meta = session.toMetaJson();

      expect(meta.containsKey('accessToken'), isFalse);
      expect(meta.containsKey('token'), isFalse);
      expect(meta.toString().contains('secret-token'), isFalse);

      final restored =
          AuthSession.fromMetaJson(meta, accessToken: 'secret-token');
      expect(restored.userName, 'test');
      expect(restored.accessToken, 'secret-token');
    });
  });

  group('MediaSource', () {
    test('reads top-level PlaySessionId and subtitle streams', () {
      final source = MediaSource.fromJson(
        <String, dynamic>{
          'Id': 'src1',
          'Container': 'mkv',
          'Bitrate': 12100000,
          'SupportsDirectPlay': true,
          'SupportsDirectStream': true,
          'DirectStreamUrl': '/videos/1/stream.mkv?Static=true',
          'MediaStreams': <dynamic>[
            <String, dynamic>{'Type': 'Video', 'Index': 0, 'Codec': 'hevc'},
            <String, dynamic>{'Type': 'Audio', 'Index': 1, 'Codec': 'aac'},
            <String, dynamic>{
              'Type': 'Subtitle',
              'Index': 2,
              'Codec': 'subrip',
              'IsExternal': false,
            },
          ],
        },
        topLevelPlaySessionId: 'ps-1',
      );

      expect(source.playSessionId, 'ps-1');
      expect(source.bitrate, 12100000);
      expect(source.directStreamUrl, '/videos/1/stream.mkv?Static=true');
      expect(source.streams.length, 3);
      expect(source.subtitles.single.index, 2);
    });

    test('tolerates garbage', () {
      final source = MediaSource.fromJson(<String, dynamic>{
        'SupportsDirectPlay': 'yes',
        'MediaStreams': 'not-a-list',
        'Bitrate': null,
      });

      expect(source.id, '');
      expect(source.supportsDirectPlay, isFalse);
      expect(source.streams, isEmpty);
      expect(source.bitrate, 0);
    });
  });

  group('MediaItem', () {
    test('parses ticks, image tag and user data', () {
      final item = MediaItem.fromJson(<String, dynamic>{
        'Id': '1',
        'Name': 'Movie',
        'Type': 'Movie',
        'RunTimeTicks': '49244180000',
        'ImageTags': <String, dynamic>{'Primary': 'tag1'},
        'UserData': <String, dynamic>{
          'Played': false,
          'PlaybackPositionTicks': 131600000,
        },
      });

      expect(item.duration, const Duration(milliseconds: 4924418));
      expect(item.imageTag, 'tag1');
      expect(item.userData.position, const Duration(milliseconds: 13160));
    });
  });

  test('device profile matches contract §3.2', () {
    expect(kDeviceProfile['Name'], 'MediaPlayer-mpv');
    final direct = (kDeviceProfile['DirectPlayProfiles'] as List).single
        as Map<String, dynamic>;
    expect(direct['VideoCodec'], contains('hevc'));
    expect(direct['Container'], contains('mkv'));
    final subs = kDeviceProfile['SubtitleProfiles'] as List;
    expect(subs.length, 4);
  });

  test('EmbyException stringifies without payload details', () {
    final error = EmbyException(
      AppErrorCode.unauthorized,
      message: 'HTTP 401',
    );
    expect(error.toString(), contains('unauthorized'));
    expect(error.toString(), isNot(contains('token')));
  });
}
