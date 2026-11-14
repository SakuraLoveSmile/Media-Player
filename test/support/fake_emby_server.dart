import 'dart:convert';
import 'dart:io';

/// Minimal Emby surface used by B3 tests (contract §1.3, §1.4, §2).
class FakeEmbyServer {
  FakeEmbyServer({
    this.serverId = 'server-1',
    this.serverName = 'Home',
    this.password = 'correct',
  });

  final String serverId;
  final String serverName;
  final String password;

  late HttpServer _server;

  int authRequests = 0;
  int viewRequests = 0;
  int expiredRequests = 0;
  int imageRequests = 0;
  bool revokeToken = false;
  String? lastAuthorizationHeader;
  Map<String, String>? lastItemsQuery;
  Map<String, String>? lastPlaybackInfoQuery;
  String? lastPlaybackInfoToken;
  final List<String> requestLog = <String>[];

  /// PlaybackInfo replies (contract §3.1), consumed in order; the last entry
  /// repeats when more requests arrive. Empty means "no playable sources".
  final List<Map<String, dynamic>> playbackInfoResponses =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> playbackInfoBodies =
      <Map<String, dynamic>>[];

  /// `GET /Sessions` reply (contract §3.5): the sessions to return.
  List<Map<String, dynamic>> sessionsResponse = <Map<String, dynamic>>[];
  int sessionsStatus = 200;
  int lookupRequests = 0;

  /// `GET /System/Info` reply (S24 服务器信息); null answers a default built
  /// from [serverName].
  Map<String, dynamic>? systemInfoResponse;
  int systemInfoStatus = 200;

  /// `GET /Users` reply (S24 用户), served as a bare array like real Emby.
  List<Map<String, dynamic>> usersResponse = <Map<String, dynamic>>[];
  int usersStatus = 200;

  /// `GET /Users/user-1` reply (S24): the signed-in user, including the
  /// `Policy.IsAdministrator` flag the admin gate reads.
  Map<String, dynamic> currentUserResponse = <String, dynamic>{
    'Id': 'user-1',
    'Name': 'test',
    'Policy': <String, dynamic>{'IsAdministrator': true},
  };

  /// Session reports in arrival order, with their bodies (contract §3.6).
  final List<String> sessionReportPaths = <String>[];
  final List<Map<String, dynamic>> sessionBodies = <Map<String, dynamic>>[];

  /// Paths that answer 500 so retry/failure handling can be exercised.
  final Set<String> failingSessionPaths = <String>{};

  /// When set, `/Sessions/Playing/Progress` waits for it before replying, so
  /// tests can prove reports are serialized (contract §10.9 c).
  Future<void>? progressHold;

  /// Replies for a library lookup (`SearchTerm` / `AnyProviderIdEquals`), used
  /// by the 求片 "is it in the library?" check.
  List<Map<String, dynamic>> lookupItems = <Map<String, dynamic>>[];

  /// When set, the lookup paths answer this status instead.
  int? lookupStatus;

  /// Reply for a title search specifically, so a test can model the real
  /// behaviour where Emby answers "流浪地球" with "流浪地球2 (2023)".
  List<Map<String, dynamic>>? titleSearchItems;

  /// 130 movies so paging can be exercised with 60-item pages.
  final List<Map<String, dynamic>> movieItems =
      List<Map<String, dynamic>>.generate(
        130,
        (index) => <String, dynamic>{
          'Id': 'movie-${index + 1}',
          'Name': 'Movie ${index + 1}',
          'Type': 'Movie',
          'RunTimeTicks': 6000000000,
        },
      );

  /// Reply for a favorites query (`Filters=IsFavorite`, S8).
  List<Map<String, dynamic>> favoriteItems = <Map<String, dynamic>>[];

  /// Reply for a continue-watching query (`Filters=IsResumable`, P1 home).
  List<Map<String, dynamic>> resumableItems = <Map<String, dynamic>>[];

  /// Reply for the BoxSet collections query (S10 合集).
  List<Map<String, dynamic>> boxsetItems = <Map<String, dynamic>>[];

  /// Replies for `GET /Genres` / `GET /Tags` (S10), served as `Items[].Name`.
  List<String> genreNames = <String>[];
  List<String> tagNames = <String>[];
  Map<String, String>? lastGenresQuery;
  Map<String, String>? lastTagsQuery;

  /// Replies for `GET /LiveTv/Channels` / `GET /LiveTv/Programs` (S21).
  List<Map<String, dynamic>> liveTvChannels = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> liveTvPrograms = <Map<String, dynamic>>[];
  Map<String, String>? lastLiveTvChannelsQuery;
  Map<String, String>? lastLiveTvProgramsQuery;

  /// When set, the LiveTv paths answer this status instead, so the empty/error
  /// surface can be exercised (e.g. a server without Live TV enabled).
  int? liveTvStatus;

  /// Favorite/played writes in arrival order, as `METHOD path` (S8).
  final List<String> favoriteWrites = <String>[];
  final List<String> playedWrites = <String>[];

  String get base => 'http://127.0.0.1:${_server.port}';

  String get token => 'token-$serverId';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    requestLog.add('${request.method} $path');

    try {
      if (request.method == 'GET' && path == '/System/Info/Public') {
        await _json(response, 200, <String, dynamic>{
          'Id': serverId,
          'ServerName': serverName,
          'Version': '4.10.1.0',
        });
        return;
      }

      if (request.method == 'GET' && path == '/System/Info') {
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        if (systemInfoStatus != 200) {
          await _json(response, systemInfoStatus, <String, dynamic>{
            'error': 'system info failed',
          });
          return;
        }
        await _json(
          response,
          200,
          systemInfoResponse ??
              <String, dynamic>{
                'ServerName': serverName,
                'Version': '4.10.1.0',
                'OperatingSystem': 'Linux',
                'HasPendingRestart': false,
              },
        );
        return;
      }

      if (request.method == 'GET' && path == '/Users') {
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        if (usersStatus != 200) {
          await _json(response, usersStatus, <String, dynamic>{
            'error': 'users failed',
          });
          return;
        }
        await _jsonList(response, 200, usersResponse);
        return;
      }

      if (request.method == 'GET' && path == '/Users/user-1') {
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        await _json(response, 200, currentUserResponse);
        return;
      }

      if (request.method == 'POST' && path == '/Users/AuthenticateByName') {
        authRequests++;
        lastAuthorizationHeader = request.headers.value('X-Emby-Authorization');
        final body = await utf8.decoder.bind(request).join();
        final map = jsonDecode(body) as Map<String, dynamic>;
        final headerOk =
            lastAuthorizationHeader?.startsWith('MediaBrowser ') ?? false;

        if (map['Pw'] == password && headerOk) {
          await _json(response, 200, <String, dynamic>{
            'User': <String, dynamic>{'Id': 'user-1', 'Name': 'test'},
            'AccessToken': token,
            'ServerId': serverId,
          });
          return;
        }
        await _json(response, 401, <String, dynamic>{'error': 'bad login'});
        return;
      }

      if (request.method == 'GET' && path == '/Users/user-1/Views') {
        viewRequests++;
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        await _json(response, 200, <String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 'view-1',
              'Name': 'Movies',
              'CollectionType': 'movies',
            },
          ],
          'TotalRecordCount': 1,
        });
        return;
      }

      if (request.method == 'GET' && path == '/Users/user-1/Items') {
        lastItemsQuery = request.uri.queryParameters;
        final isFavorites =
            request.uri.queryParameters['Filters'] == 'IsFavorite';
        if (isFavorites) {
          final start =
              int.tryParse(request.uri.queryParameters['StartIndex'] ?? '') ??
              0;
          final limit =
              int.tryParse(request.uri.queryParameters['Limit'] ?? '') ?? 60;
          final slice = favoriteItems
              .skip(start)
              .take(limit)
              .toList(growable: false);
          await _json(response, 200, <String, dynamic>{
            'Items': slice,
            'TotalRecordCount': favoriteItems.length,
            'StartIndex': start,
          });
          return;
        }
        final isResumable =
            request.uri.queryParameters['Filters'] == 'IsResumable';
        if (isResumable) {
          final limit =
              int.tryParse(request.uri.queryParameters['Limit'] ?? '') ?? 20;
          final slice = resumableItems.take(limit).toList(growable: false);
          await _json(response, 200, <String, dynamic>{
            'Items': slice,
            'TotalRecordCount': resumableItems.length,
            'StartIndex': 0,
          });
          return;
        }
        final isBoxSet =
            request.uri.queryParameters['IncludeItemTypes'] == 'BoxSet';
        if (isBoxSet) {
          final start =
              int.tryParse(request.uri.queryParameters['StartIndex'] ?? '') ??
              0;
          final limit =
              int.tryParse(request.uri.queryParameters['Limit'] ?? '') ?? 60;
          final slice = boxsetItems
              .skip(start)
              .take(limit)
              .toList(growable: false);
          await _json(response, 200, <String, dynamic>{
            'Items': slice,
            'TotalRecordCount': boxsetItems.length,
            'StartIndex': start,
          });
          return;
        }
        final isLookup =
            request.uri.queryParameters.containsKey('SearchTerm') ||
            request.uri.queryParameters.containsKey('AnyProviderIdEquals');
        if (isLookup) {
          lookupRequests++;
          final status = lookupStatus;
          if (status != null) {
            await _json(response, status, <String, dynamic>{'error': 'lookup'});
            return;
          }
          final byTitle = titleSearchItems;
          final items = request.uri.queryParameters.containsKey('SearchTerm')
              ? (byTitle ?? lookupItems)
              : lookupItems;
          await _json(response, 200, <String, dynamic>{
            'Items': items,
            'TotalRecordCount': items.length,
          });
          return;
        }
        final parentId = request.uri.queryParameters['ParentId'];
        final start =
            int.tryParse(request.uri.queryParameters['StartIndex'] ?? '') ?? 0;
        final limit =
            int.tryParse(request.uri.queryParameters['Limit'] ?? '') ?? 60;
        var all = parentId == 'view-1'
            ? movieItems
            : const <Map<String, dynamic>>[];
        // S10 browsing filters: type / year / genre / tag narrowing.
        final types = request.uri.queryParameters['IncludeItemTypes'];
        if (types != null && types != 'Movie,Series') {
          final wanted = types.split(',');
          all = all
              .where((item) => wanted.contains(item['Type']))
              .toList(growable: false);
        }
        final years = request.uri.queryParameters['Years'];
        if (years != null) {
          all = all
              .where((item) => '${item['ProductionYear']}' == years)
              .toList(growable: false);
        }
        final genres = request.uri.queryParameters['Genres'];
        if (genres != null) {
          all = all
              .where(
                (item) => (item['Genres'] as List? ?? const <Object?>[])
                    .contains(genres),
              )
              .toList(growable: false);
        }
        final tags = request.uri.queryParameters['Tags'];
        if (tags != null) {
          all = all
              .where(
                (item) =>
                    (item['Tags'] as List? ?? const <Object?>[]).contains(tags),
              )
              .toList(growable: false);
        }
        final slice = all.skip(start).take(limit).toList(growable: false);

        await _json(response, 200, <String, dynamic>{
          'Items': slice,
          'TotalRecordCount': all.length,
          'StartIndex': start,
        });
        return;
      }

      if (request.method == 'GET' && path == '/Genres') {
        lastGenresQuery = request.uri.queryParameters;
        await _json(response, 200, <String, dynamic>{
          'Items': <Map<String, dynamic>>[
            for (final String name in genreNames)
              <String, dynamic>{'Name': name},
          ],
          'TotalRecordCount': genreNames.length,
        });
        return;
      }

      if (request.method == 'GET' && path == '/Tags') {
        lastTagsQuery = request.uri.queryParameters;
        await _json(response, 200, <String, dynamic>{
          'Items': <Map<String, dynamic>>[
            for (final String name in tagNames) <String, dynamic>{'Name': name},
          ],
          'TotalRecordCount': tagNames.length,
        });
        return;
      }

      if (request.method == 'GET' && path == '/LiveTv/Channels') {
        lastLiveTvChannelsQuery = request.uri.queryParameters;
        final status = liveTvStatus;
        if (status != null) {
          await _json(response, status, <String, dynamic>{'error': 'livetv'});
          return;
        }
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        await _json(response, 200, <String, dynamic>{
          'Items': liveTvChannels,
          'TotalRecordCount': liveTvChannels.length,
        });
        return;
      }

      if (request.method == 'GET' && path == '/LiveTv/Programs') {
        lastLiveTvProgramsQuery = request.uri.queryParameters;
        final status = liveTvStatus;
        if (status != null) {
          await _json(response, status, <String, dynamic>{'error': 'livetv'});
          return;
        }
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        // ChannelIds narrows the guide to one channel, mirroring the server.
        final channelIds = request.uri.queryParameters['ChannelIds'];
        final items = channelIds == null || channelIds.isEmpty
            ? liveTvPrograms
            : liveTvPrograms
                  .where((p) => '${p['ChannelId']}' == channelIds)
                  .toList(growable: false);
        await _json(response, 200, <String, dynamic>{
          'Items': items,
          'TotalRecordCount': items.length,
        });
        return;
      }

      if (request.method == 'GET' && path.startsWith('/Users/user-1/Items/')) {
        final id = path.split('/').last;
        await _json(response, 200, <String, dynamic>{
          'Id': id,
          'Name': 'Detail $id',
          'Type': 'Movie',
          'MediaSources': <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 'source-1',
              'Container': 'mkv',
              'Bitrate': 12100000,
              'SupportsDirectPlay': true,
              'SupportsDirectStream': true,
              'DirectStreamUrl': '/videos/$id/stream.mkv?Static=true',
              'MediaStreams': <Map<String, dynamic>>[
                <String, dynamic>{'Type': 'Video', 'Index': 0, 'Codec': 'hevc'},
              ],
            },
          ],
        });
        return;
      }

      if (request.method == 'GET' && path == '/Shows/series-1/Seasons') {
        await _json(response, 200, <String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 'season-1',
              'Name': 'Season 1',
              'Type': 'Season',
              'SeriesId': 'series-1',
              'IndexNumber': 1,
            },
            <String, dynamic>{
              'Id': 'season-2',
              'Name': 'Season 2',
              'Type': 'Season',
              'SeriesId': 'series-1',
              'IndexNumber': 2,
            },
          ],
          'TotalRecordCount': 2,
        });
        return;
      }

      if (request.method == 'GET' && path == '/Shows/series-1/Episodes') {
        final seasonId = request.uri.queryParameters['SeasonId'];
        final all = <Map<String, dynamic>>[
          <String, dynamic>{
            'Id': 'ep-1',
            'Name': 'Episode 1',
            'Type': 'Episode',
            'SeriesId': 'series-1',
            'SeasonId': 'season-1',
            'IndexNumber': 1,
          },
          <String, dynamic>{
            'Id': 'ep-2',
            'Name': 'Episode 2',
            'Type': 'Episode',
            'SeriesId': 'series-1',
            'SeasonId': 'season-1',
            'IndexNumber': 2,
          },
          <String, dynamic>{
            'Id': 'ep-3',
            'Name': 'Episode 3',
            'Type': 'Episode',
            'SeriesId': 'series-1',
            'SeasonId': 'season-2',
            'IndexNumber': 1,
          },
        ];
        await _json(response, 200, <String, dynamic>{
          'Items': all
              .where((e) => seasonId == null || e['SeasonId'] == seasonId)
              .toList(),
          'TotalRecordCount': all.length,
        });
        return;
      }

      if (request.method == 'GET' &&
          path.startsWith('/Items/') &&
          path.endsWith('/Images/Primary')) {
        imageRequests++;
        response.statusCode = 200;
        response.headers.contentType = ContentType('image', 'png');
        response.add(<int>[0x89, 0x50, 0x4E, 0x47]);
        await response.close();
        return;
      }

      if (request.method == 'POST' &&
          path.startsWith('/Items/') &&
          path.endsWith('/PlaybackInfo')) {
        lastPlaybackInfoQuery = request.uri.queryParameters;
        lastPlaybackInfoToken = request.headers.value('X-Emby-Token');
        final body = await utf8.decoder.bind(request).join();
        playbackInfoBodies.add(jsonDecode(body) as Map<String, dynamic>);

        final index = playbackInfoBodies.length - 1;
        final reply = playbackInfoResponses.isEmpty
            ? <String, dynamic>{'MediaSources': <Map<String, dynamic>>[]}
            : playbackInfoResponses[index < playbackInfoResponses.length
                  ? index
                  : playbackInfoResponses.length - 1];
        await _json(response, 200, reply);
        return;
      }

      if (request.method == 'GET' && path == '/Sessions') {
        if (sessionsStatus != 200) {
          await _json(response, sessionsStatus, <String, dynamic>{
            'error': 'sessions failed',
          });
          return;
        }
        await _jsonList(response, 200, sessionsResponse);
        return;
      }

      if (request.method == 'POST' &&
          (path == '/Sessions/Playing' ||
              path == '/Sessions/Playing/Progress' ||
              path == '/Sessions/Playing/Stopped')) {
        final raw = await utf8.decoder.bind(request).join();
        sessionReportPaths.add(path);
        sessionBodies.add(
          raw.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (path == '/Sessions/Playing/Progress' && progressHold != null) {
          await progressHold;
        }
        if (failingSessionPaths.contains(path)) {
          await _json(response, 500, <String, dynamic>{
            'error': 'report failed',
          });
          return;
        }
        await _json(response, 200, <String, dynamic>{});
        return;
      }

      if (request.method == 'GET' && path == '/expired') {
        expiredRequests++;
        await _json(response, 401, <String, dynamic>{'error': 'expired'});
        return;
      }

      if ((request.method == 'POST' || request.method == 'DELETE') &&
          path.startsWith('/Users/user-1/FavoriteItems/')) {
        favoriteWrites.add('${request.method} $path');
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        await _json(response, 200, <String, dynamic>{});
        return;
      }

      if ((request.method == 'POST' || request.method == 'DELETE') &&
          path.startsWith('/Users/user-1/PlayedItems/')) {
        playedWrites.add('${request.method} $path');
        if (revokeToken || request.headers.value('X-Emby-Token') != token) {
          await _json(response, 401, <String, dynamic>{'error': 'no token'});
          return;
        }
        await _json(response, 200, <String, dynamic>{});
        return;
      }

      await _json(response, 404, <String, dynamic>{'error': 'not found'});
    } catch (_) {
      response.statusCode = 500;
      response.write('{"error":"fake server failure"}');
      await response.close();
    }
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _jsonList(
    HttpResponse response,
    int status,
    List<Map<String, dynamic>> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
