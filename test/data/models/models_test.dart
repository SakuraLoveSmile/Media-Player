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

      final restored = AuthSession.fromMetaJson(
        meta,
        accessToken: 'secret-token',
      );
      expect(restored.userName, 'test');
      expect(restored.accessToken, 'secret-token');
    });
  });

  group('MediaItem artwork and badges (S28)', () {
    test('reads the backdrop pair, unplayed count and detail links', () {
      final item = MediaItem.fromJson(<String, dynamic>{
        'Id': 'ep-1',
        'Name': 'Ep',
        'Type': 'Episode',
        'BackdropImageTags': <String>['ep-backdrop'],
        'ParentBackdropItemId': 'series-1',
        'ParentBackdropImageTags': <String>['series-backdrop'],
        'UserData': <String, dynamic>{'UnplayedItemCount': 7},
        'Studios': <dynamic>[
          <String, dynamic>{'Name': 'Studio A', 'Id': 'studio-1'},
        ],
        'ExternalUrls': <dynamic>[
          <String, dynamic>{'Name': 'IMDb', 'Url': 'https://imdb.test/x'},
        ],
        'RemoteTrailers': <dynamic>[
          <String, dynamic>{'Url': 'https://youtube.test/x'},
        ],
      });

      expect(item.backdropTag, 'ep-backdrop');
      expect(item.parentBackdropItemId, 'series-1');
      expect(item.parentBackdropTag, 'series-backdrop');
      expect(item.hasBackdrop, isTrue);
      expect(item.userData.unplayedItemCount, 7);
      expect(item.studios.single.name, 'Studio A');
      expect(item.studios.single.target, 'studio-1');
      expect(item.externalUrls.single.target, 'https://imdb.test/x');
      expect(item.remoteTrailers.single, 'https://youtube.test/x');
    });

    test('an item without artwork has no backdrop to request', () {
      final item = MediaItem.fromJson(<String, dynamic>{
        'Id': 'm-1',
        'Name': 'Movie',
        'Type': 'Movie',
      });

      expect(item.hasBackdrop, isFalse);
      expect(item.userData.unplayedItemCount, 0);
    });

    test('yearLabel renders movies and series ranges', () {
      const movie = MediaItem(
        id: 'm',
        name: 'Movie',
        type: 'Movie',
        productionYear: 2024,
      );
      expect(movie.yearLabel, '2024');

      const running = MediaItem(
        id: 's1',
        name: 'Show',
        type: 'Series',
        productionYear: 2004,
        status: 'Continuing',
      );
      expect(running.yearLabel, '2004 - 现在');

      const ended = MediaItem(
        id: 's2',
        name: 'Show',
        type: 'Series',
        productionYear: 2004,
        status: 'Ended',
        endDate: '2008-03-01T00:00:00.0000000Z',
      );
      expect(ended.yearLabel, '2004 - 2008');

      const sameYear = MediaItem(
        id: 's3',
        name: 'Show',
        type: 'Series',
        productionYear: 2004,
        status: 'Ended',
        endDate: '2004-12-31T00:00:00.0000000Z',
      );
      expect(sameYear.yearLabel, '2004');

      const unknown = MediaItem(id: 'x', name: 'X', type: 'Movie');
      expect(unknown.yearLabel, isNull);
    });
  });

  group('MediaSource', () {
    test('reads top-level PlaySessionId and subtitle streams', () {
      final source = MediaSource.fromJson(<String, dynamic>{
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
      }, topLevelPlaySessionId: 'ps-1');

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
      expect(source.name, isNull);
    });

    test('reads the version name (S7)', () {
      final source = MediaSource.fromJson(<String, dynamic>{
        'Id': 'src1',
        'Name': '1080p 重制',
        'Container': 'mkv',
        'Bitrate': 12000000,
      });

      expect(source.name, '1080p 重制');
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

    test('parses the S7 detail fields', () {
      final item = MediaItem.fromJson(<String, dynamic>{
        'Id': '1',
        'Name': 'Movie',
        'Type': 'Movie',
        'Tagline': '一句标语',
        'CommunityRating': 8.6,
        'OfficialRating': 'PG-13',
        'Genres': <dynamic>['科幻', '冒险'],
        'People': <dynamic>[
          <String, dynamic>{
            'Name': '演员甲',
            'Role': '角色甲',
            'Type': 'Actor',
            'Id': 'p-1',
            'PrimaryImageTag': 'ptag',
          },
          <String, dynamic>{'Name': '导演乙', 'Type': 'Director'},
        ],
        'RemoteTrailer': 'https://example.com/trailer',
      });

      expect(item.tagline, '一句标语');
      expect(item.communityRating, 8.6);
      expect(item.officialRating, 'PG-13');
      expect(item.genres, <String>['科幻', '冒险']);
      expect(item.people, hasLength(2));
      expect(item.people.first.name, '演员甲');
      expect(item.people.first.role, '角色甲');
      expect(item.people.first.type, 'Actor');
      expect(item.people.first.id, 'p-1');
      expect(item.people.first.imageTag, 'ptag');
      expect(item.people.last.role, isNull);
      expect(item.remoteTrailer, 'https://example.com/trailer');
    });

    test('detail fields stay optional and tolerant', () {
      final item = MediaItem.fromJson(<String, dynamic>{
        'Id': '1',
        'Name': 'Movie',
        'Type': 'Movie',
        'CommunityRating': '7.9',
        'Genres': 'not-a-list',
        'People': null,
        'Tagline': '',
      });

      expect(item.tagline, isNull);
      expect(item.communityRating, 7.9);
      expect(item.officialRating, isNull);
      expect(item.genres, isEmpty);
      expect(item.people, isEmpty);
      expect(item.remoteTrailer, isNull);
    });

    test('parses the transparent logo pair (S78)', () {
      final episode = MediaItem.fromJson(<String, dynamic>{
        'Id': 'e1',
        'Name': 'Episode',
        'Type': 'Episode',
        'ParentLogoItemId': 'show',
        'ParentLogoImageTag': 'logo-tag',
      });
      expect(episode.logoTag, isNull);
      expect(episode.parentLogoItemId, 'show');
      expect(episode.parentLogoTag, 'logo-tag');

      final movie = MediaItem.fromJson(<String, dynamic>{
        'Id': 'm1',
        'Name': 'Movie',
        'Type': 'Movie',
        'ImageTags': <String, dynamic>{'Primary': 'p', 'Logo': 'own-logo'},
      });
      expect(movie.logoTag, 'own-logo');
      expect(movie.parentLogoItemId, isNull);
      expect(movie.parentLogoTag, isNull);

      // copyWith must keep the logo pair when the user data flips.
      final flipped = episode.copyWith(
        userData: episode.userData.copyWith(played: true),
      );
      expect(flipped.parentLogoItemId, 'show');
      expect(flipped.parentLogoTag, 'logo-tag');
    });

    test('copyWith flips user data and keeps the rest', () {
      const item = MediaItem(
        id: '1',
        name: 'Movie',
        type: 'Movie',
        tagline: '标语',
        userData: UserItemData(),
      );

      final flipped = item.copyWith(
        userData: item.userData.copyWith(isFavorite: true, played: true),
      );

      expect(flipped.userData.isFavorite, isTrue);
      expect(flipped.userData.played, isTrue);
      expect(flipped.name, 'Movie');
      expect(flipped.tagline, '标语');
      expect(item.userData.isFavorite, isFalse);
    });
  });

  test('device profile matches contract §3.2', () {
    expect(kDeviceProfile['Name'], 'MediaPlayer-mpv');
    final direct =
        (kDeviceProfile['DirectPlayProfiles'] as List).single
            as Map<String, dynamic>;
    expect(direct['VideoCodec'], contains('hevc'));
    expect(direct['Container'], contains('mkv'));
    final subs = kDeviceProfile['SubtitleProfiles'] as List;
    expect(subs.length, 4);
  });

  test('device profile hides TrueHD so the server transcodes that track', () {
    final direct =
        (kDeviceProfile['DirectPlayProfiles'] as List).single
            as Map<String, dynamic>;
    // The player has no TrueHD decoder and no passthrough, so claiming it
    // would leave such titles silent; the server has to transcode instead.
    expect(direct['AudioCodec'], isNot(contains('truehd')));
    expect(direct['AudioCodec'], isNot(contains('mlp')));
    // The codecs it can decode stay direct, so normal titles are unaffected.
    expect(direct['AudioCodec'], contains('dts'));
    expect(direct['AudioCodec'], contains('ac3'));

    // A transcode target has to be offered, or the server has nowhere to put
    // the track it rejects.
    final transcode =
        (kDeviceProfile['TranscodingProfiles'] as List).single
            as Map<String, dynamic>;
    expect(transcode['AudioCodec'], 'aac');
    expect(transcode['Protocol'], 'hls');
  });

  test('EmbyException stringifies without payload details', () {
    final error = EmbyException(AppErrorCode.unauthorized, message: 'HTTP 401');
    expect(error.toString(), contains('unauthorized'));
    expect(error.toString(), isNot(contains('token')));
  });
}
