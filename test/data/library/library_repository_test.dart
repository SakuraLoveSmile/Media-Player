import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/library/library_repository.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

import '../../support/fake_emby_server.dart';

void main() {
  late FakeEmbyServer server;
  late InMemoryKeyValueStore kv;
  late AuthRepository auth;
  late LibraryRepository library;

  Future<AuthRepository> buildAuth() async {
    final client = EmbyHttpClient(Dio(), deviceId: 'device-1');
    final resolver = EndpointResolver(
      HttpEndpointProbe(client),
      lanTimeout: const Duration(seconds: 1),
      wanTimeout: const Duration(seconds: 1),
    );
    return AuthRepository(
      client: client,
      resolver: resolver,
      tokenStore: TokenStore(kv),
      sessionStore: SessionStore(kv),
      profileStore: ProfileStore(kv),
      deviceId: 'device-1',
      deviceName: 'test',
    );
  }

  setUp(() async {
    server = FakeEmbyServer();
    await server.start();
    kv = InMemoryKeyValueStore();
    auth = await buildAuth();
    await auth.login(
      username: 'test',
      password: 'correct',
      profile: ServerProfile(serverId: '', name: 'Home', lanUrl: server.base),
    );
    library = LibraryRepository(auth);
  });

  tearDown(() async {
    await auth.dispose();
    await server.stop();
  });

  test('views parses id, name and collection type', () async {
    final views = await library.views();

    expect(views, hasLength(1));
    expect(views.single.id, 'view-1');
    expect(views.single.name, 'Movies');
    expect(views.single.collectionType, 'movies');
  });

  test('items sends the contract query and omits media sources', () async {
    final page = await library.items('view-1');

    expect(page.items, hasLength(60));
    expect(page.totalRecordCount, 130);
    expect(page.startIndex, 0);
    expect(page.isLast, isFalse);

    final query = server.lastItemsQuery!;
    expect(query['ParentId'], 'view-1');
    expect(query['Recursive'], 'true');
    expect(query['IncludeItemTypes'], 'Movie,Series');
    expect(query['SortBy'], 'SortName');
    expect(query['SortOrder'], 'Ascending');
    expect(query['StartIndex'], '0');
    expect(query['Limit'], '60');
    expect(query['Fields'], contains('Overview'));
    expect(query['Fields'], contains('RunTimeTicks'));
    expect(query['Fields'], isNot(contains('MediaSources')));
    expect(query['Fields'], isNot(contains('MediaStreams')));
  });

  test('paging covers every row exactly once', () async {
    final first = await library.items('view-1');
    final second = await library.items('view-1', startIndex: first.nextStartIndex);
    final third = await library.items('view-1', startIndex: second.nextStartIndex);

    final ids = <String>[
      ...first.items.map((i) => i.id),
      ...second.items.map((i) => i.id),
      ...third.items.map((i) => i.id),
    ];

    expect(ids, hasLength(130));
    expect(ids.toSet(), hasLength(130));
    expect(first.isLast, isFalse);
    expect(second.isLast, isFalse);
    expect(third.isLast, isTrue);
    expect(third.startIndex, 120);
  });

  test('rejects invalid paging arguments without a request', () async {
    server.requestLog.clear();

    await expectLater(library.items('view-1', startIndex: -1), throwsArgumentError);
    await expectLater(library.items('view-1', limit: 0), throwsArgumentError);
    expect(server.requestLog, isEmpty);
  });

  test('item detail includes media sources', () async {
    server.requestLog.clear();

    final item = await library.item('movie-1');

    expect(item.id, 'movie-1');
    expect(item.type, 'Movie');
    expect(item.mediaSources, hasLength(1));
    expect(item.mediaSources.single.directStreamUrl, contains('/stream.mkv'));
    expect(server.requestLog, <String>['GET /Users/user-1/Items/movie-1']);
  });

  test('seasons and episodes are filtered by season', () async {
    final seasons = await library.seasons('series-1');
    final firstSeason = await library.episodes(
      seriesId: 'series-1',
      seasonId: 'season-1',
    );
    final secondSeason = await library.episodes(
      seriesId: 'series-1',
      seasonId: 'season-2',
    );

    expect(seasons.map((s) => s.id), <String>['season-1', 'season-2']);
    expect(seasons.first.indexNumber, 1);
    expect(firstSeason.map((e) => e.id), <String>['ep-1', 'ep-2']);
    expect(secondSeason.map((e) => e.id), <String>['ep-3']);
  });

  test('image URL carries size, tag, quality and api key', () async {
    final uri = library.imageUrl('movie-1', tag: 'tag 1', maxWidth: 320);

    expect(uri, isNotNull);
    expect(uri!.path, '/Items/movie-1/Images/Primary');
    final query = uri.queryParameters;
    expect(query['maxWidth'], '320');
    expect(query['tag'], 'tag 1');
    expect(query['quality'], '90');
    expect(query['api_key'], server.token);
    expect(uri.toString(), contains('tag=tag+1'));
  });

  test('image URL is null after logout', () async {
    await auth.logout();

    expect(library.imageUrl('movie-1'), isNull);
  });

  test('a revoked token clears the session exactly once', () async {
    server.revokeToken = true;

    await expectLater(
      library.views(),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
    );

    expect(auth.current, isNull);
    expect(await kv.read(TokenStore.key), isNull);
  });

  test('queries without a session fail before any request', () async {
    await auth.logout();
    final callsBefore = server.requestLog.length;

    await expectLater(
      library.views(),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
    );
    expect(server.requestLog.length, callsBefore);
  });
}
