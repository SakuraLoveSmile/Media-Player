// B4 smoke: views -> paged items -> detail -> seasons/episodes -> image.
// Credentials come from the environment and are never written to disk:
//   EMBY_LAN_URL=http://<host>:<port> EMBY_USER=<user> EMBY_PASS=<pass> \
//     dart run tool/b4_smoke.dart
//
// Only counts and booleans are printed; no library names, URLs or tokens.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/library/library_repository.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/device_id_store.dart';
import 'package:media_player/data/storage/file_key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

Future<void> main(List<String> args) async {
  final lanUrl = Platform.environment['EMBY_LAN_URL'];
  final username = Platform.environment['EMBY_USER'];
  final password = Platform.environment['EMBY_PASS'];

  if (lanUrl == null || username == null || password == null) {
    stderr.writeln(
      'usage: EMBY_LAN_URL=... EMBY_USER=... EMBY_PASS=... '
      'dart run tool/b4_smoke.dart',
    );
    exit(2);
  }

  final workspace = await Directory.systemTemp.createTemp('b4_smoke');
  var failures = 0;

  void pass(String message) => stdout.writeln('PASS $message');
  void skip(String message) => stdout.writeln('SKIP $message');
  void fail(String message, Object error) {
    failures++;
    stdout.writeln('FAIL $message: $error');
  }

  stdout.writeln('B4 smoke');

  AuthRepository? auth;
  try {
    final store = FileKeyValueStore(File('${workspace.path}/store.json'));
    final deviceId = await DeviceIdStore(store).getOrCreate();
    final client = EmbyHttpClient(Dio(), deviceId: deviceId);
    final resolver = EndpointResolver(HttpEndpointProbe(client));
    auth = AuthRepository(
      client: client,
      resolver: resolver,
      tokenStore: TokenStore(store),
      sessionStore: SessionStore(store),
      profileStore: ProfileStore(store),
      deviceId: deviceId,
      deviceName: '${Platform.operatingSystem} ${Platform.localHostname}',
    );

    await auth.login(
      username: username,
      password: password,
      profile: ServerProfile(serverId: '', name: 'smoke', lanUrl: lanUrl),
    );

    final library = LibraryRepository(auth);

    // --- views ---------------------------------------------------------
    final views = await library.views();
    final moviesView = views
        .where((v) => v.collectionType == 'movies')
        .firstOrNull;
    final tvView =
        views.where((v) => v.collectionType == 'tvshows').firstOrNull;
    pass(
      'views: ${views.length} '
      '(movies=${views.where((v) => v.collectionType == 'movies').length}, '
      'tvshows=${views.where((v) => v.collectionType == 'tvshows').length})',
    );

    if (moviesView == null) {
      fail('movies view', 'not found');
      return;
    }

    // --- paged items ---------------------------------------------------
    final first = await library.items(moviesView.id);
    final second =
        await library.items(moviesView.id, startIndex: first.nextStartIndex);
    final overlap = first.items
        .map((i) => i.id)
        .toSet()
        .intersection(second.items.map((i) => i.id).toSet());

    pass(
      'items: page0=${first.items.length} page1=${second.items.length} '
      'total=${first.totalRecordCount} overlap=${overlap.length}',
    );
    if (overlap.isNotEmpty) fail('paging', 'overlap ${overlap.length}');

    // --- detail --------------------------------------------------------
    final detail = await library.item(first.items.first.id);
    pass('detail: type=${detail.type} sources=${detail.mediaSources.length}');

    // --- seasons / episodes -------------------------------------------
    if (tvView == null) {
      skip('seasons/episodes: no tvshows view');
    } else {
      final page = await library.items(tvView.id, limit: 5);
      final series = page.items.where((i) => i.type == 'Series').firstOrNull;
      if (series == null) {
        skip('seasons/episodes: no Series in the first page');
      } else {
        final seasons = await library.seasons(series.id);
        if (seasons.isEmpty) {
          skip('seasons/episodes: series has no seasons');
        } else {
          final episodes = await library.episodes(
            seriesId: series.id,
            seasonId: seasons.first.id,
          );
          pass(
            'seasons: ${seasons.length} episodes(season1)=${episodes.length}',
          );
        }
      }
    }

    // --- image ---------------------------------------------------------
    final withImage =
        first.items.where((i) => i.imageTag != null).firstOrNull;
    if (withImage == null) {
      skip('image: no tagged image in the first page');
    } else {
      final uri = library.imageUrl(
        withImage.id,
        tag: withImage.imageTag,
        maxWidth: 320,
      );
      if (uri == null) {
        fail('image', 'no URL while logged in');
      } else {
        final client = HttpClient();
        try {
          final request = await client.getUrl(uri);
          final response = await request.close();
          final bytes = await response.fold<int>(0, (sum, chunk) => sum + chunk.length);
          if (response.statusCode == 200 && bytes > 0) {
            pass('image: ${response.statusCode} bytes=$bytes');
          } else {
            fail('image', 'status=${response.statusCode} bytes=$bytes');
          }
        } finally {
          client.close(force: true);
        }
      }
    }
  } on EmbyException catch (error) {
    fail('emby', error);
  } finally {
    await auth?.dispose();
    await workspace.delete(recursive: true);
  }

  stdout.writeln(failures == 0 ? 'RESULT pass' : 'RESULT fail ($failures)');
  exit(failures == 0 ? 0 : 1);
}
