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
    final second = await library.items(
      'view-1',
      startIndex: first.nextStartIndex,
    );
    final third = await library.items(
      'view-1',
      startIndex: second.nextStartIndex,
    );

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

  group('lookup for 求片', () {
    test('findByTmdb sends AnyProviderIdEquals and parses the hit', () async {
      server.lookupItems = <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'emby-99',
          'Name': 'Dune: Part Two',
          'Type': 'Movie',
          'ProductionYear': 2024,
        },
      ];

      final item = await library.findByTmdb(693134, isSeries: false);

      final query = server.lastItemsQuery!;
      expect(query['AnyProviderIdEquals'], 'tmdbid.693134');
      expect(query['IncludeItemTypes'], 'Movie');
      expect(query['Recursive'], 'true');
      expect(query['Fields'], contains('ProductionYear'));
      expect(item, isNotNull);
      expect(item!.id, 'emby-99');
      expect(item.productionYear, 2024);
    });

    test('findByTmdb asks for Series when the title is a show', () async {
      await library.findByTmdb(1399, isSeries: true);

      expect(server.lastItemsQuery!['IncludeItemTypes'], 'Series');
    });

    test('findByTmdb returns null when the library has nothing', () async {
      expect(await library.findByTmdb(1, isSeries: false), isNull);
    });

    test('findByTmdb ignores an item of the wrong type', () async {
      server.lookupItems = <Map<String, dynamic>>[
        <String, dynamic>{'Id': 'season-1', 'Type': 'Season'},
      ];

      expect(await library.findByTmdb(1, isSeries: false), isNull);
    });

    test(
      'searchByTitle sends SearchTerm and prefers the matching year',
      () async {
        server.lookupItems = <Map<String, dynamic>>[
          <String, dynamic>{
            'Id': 'old',
            'Name': 'Dune',
            'Type': 'Movie',
            'ProductionYear': 1984,
          },
          <String, dynamic>{
            'Id': 'new',
            'Name': 'Dune',
            'Type': 'Movie',
            'ProductionYear': 2021,
          },
        ];

        final item = await library.searchByTitle(
          'Dune',
          year: 2021,
          isSeries: false,
        );

        expect(server.lastItemsQuery!['SearchTerm'], 'Dune');
        expect(item!.id, 'new');
      },
    );

    test('searchByTitle refuses a different year (sequel trap)', () async {
      // Observed on a real Emby 4.10.1: searching "流浪地球" answered with
      // "流浪地球2 (2023)" and nothing else. Playing the sequel of the film the
      // user asked for is worse than playing nothing, so a year mismatch must
      // be rejected even when it is the only hit.
      server.titleSearchItems = <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'sequel',
          'Name': '流浪地球2',
          'Type': 'Movie',
          'ProductionYear': 2023,
        },
      ];

      final item = await library.searchByTitle(
        '流浪地球',
        year: 2019,
        isSeries: false,
      );

      expect(item, isNull);
    });

    test('searchByTitle takes the right year out of mixed hits', () async {
      server.titleSearchItems = <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'sequel',
          'Name': '流浪地球2',
          'Type': 'Movie',
          'ProductionYear': 2023,
        },
        <String, dynamic>{
          'Id': 'original',
          'Name': '流浪地球',
          'Type': 'Movie',
          'ProductionYear': 2019,
        },
      ];

      final item = await library.searchByTitle(
        '流浪地球',
        year: 2019,
        isSeries: false,
      );

      expect(item!.id, 'original');
    });

    test(
      'searchByTitle falls back to the only hit when years are unknown',
      () async {
        server.lookupItems = <Map<String, dynamic>>[
          <String, dynamic>{'Id': 'only', 'Name': 'Dune', 'Type': 'Movie'},
        ];

        final item = await library.searchByTitle('Dune', isSeries: false);

        expect(item!.id, 'only');
      },
    );

    test('searchByTitle with a blank title makes no request', () async {
      final before = server.lookupRequests;

      expect(await library.searchByTitle('   ', isSeries: false), isNull);
      expect(server.lookupRequests, before);
    });

    test('a failing lookup surfaces as an EmbyException', () async {
      server.lookupStatus = 500;

      await expectLater(
        library.findByTmdb(1, isSeries: false),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.serverError,
          ),
        ),
      );
    });
  });

  test('rejects invalid paging arguments without a request', () async {
    server.requestLog.clear();

    await expectLater(
      library.items('view-1', startIndex: -1),
      throwsArgumentError,
    );
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

  test('image URLs carry the image kind and index (S28)', () async {
    final backdrop = library.imageUrl(
      'movie-1',
      type: 'Backdrop',
      index: 2,
      tag: 'b1',
      maxWidth: 640,
    );
    expect(backdrop, isNotNull);
    expect(backdrop!.path, '/Items/movie-1/Images/Backdrop/2');
    expect(backdrop.queryParameters['tag'], 'b1');
    expect(backdrop.queryParameters['maxWidth'], '640');

    final primary = library.imageUrl('movie-1', type: 'Primary', tag: 'p1');
    expect(primary!.path, '/Items/movie-1/Images/Primary');
  });

  test(
    'collection children and person credits are scoped queries (S34)',
    () async {
      await library.collectionItems('box-1');
      expect(server.lastItemsQuery!['ParentId'], 'box-1');
      expect(server.lastItemsQuery!['IncludeItemTypes'], 'Movie,Series');
      expect(server.lastItemsQuery!['Recursive'], 'true');

      await library.itemsByPerson('person-1');
      expect(server.lastItemsQuery!['PersonIds'], 'person-1');
      expect(server.lastItemsQuery!['IncludeItemTypes'], 'Movie,Series');
    },
  );
  test('the server name comes from System/Info/Public', () async {
    expect(await library.serverName(), server.serverName);
    expect(server.requestLog, contains('GET /System/Info/Public'));
  });

  test('image URL is null after logout', () async {
    await auth.logout();

    expect(library.imageUrl('movie-1'), isNull);
  });

  test('a revoked token clears the session exactly once', () async {
    server.revokeToken = true;

    await expectLater(
      library.views(),
      throwsA(
        isA<EmbyException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      ),
    );

    expect(auth.current, isNull);
    expect(await kv.read(TokenStore.key), isNull);
  });

  test('queries without a session fail before any request', () async {
    await auth.logout();
    final callsBefore = server.requestLog.length;

    await expectLater(
      library.views(),
      throwsA(
        isA<EmbyException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      ),
    );
    expect(server.requestLog.length, callsBefore);
  });

  test('search sends SearchTerm with both types and list fields', () async {
    server.titleSearchItems = <Map<String, dynamic>>[
      <String, dynamic>{'Id': 's-9', 'Name': '冰海战记', 'Type': 'Series'},
      <String, dynamic>{'Id': 'm-8', 'Name': '冰海战记 剧场版', 'Type': 'Movie'},
    ];

    final page = await library.search('冰海');

    expect(page.items.map((i) => i.id), <String>['s-9', 'm-8']);
    final query = server.lastItemsQuery!;
    expect(query['SearchTerm'], '冰海');
    expect(query['Recursive'], 'true');
    expect(query['IncludeItemTypes'], 'Movie,Series');
    expect(query['Limit'], '60');
    expect(query['Fields'], isNot(contains('MediaSources')));
  });

  test('search respects the type filter', () async {
    server.titleSearchItems = <Map<String, dynamic>>[];

    await library.search('冰海', types: 'Series');

    expect(server.lastItemsQuery!['IncludeItemTypes'], 'Series');
  });

  test('search trims the term', () async {
    server.titleSearchItems = <Map<String, dynamic>>[];

    await library.search('  冰海  ');

    expect(server.lastItemsQuery!['SearchTerm'], '冰海');
  });

  test('an empty term answers an empty page without a request', () async {
    final callsBefore = server.requestLog.length;

    final page = await library.search('   ');

    expect(page.items, isEmpty);
    expect(page.totalRecordCount, 0);
    expect(server.requestLog.length, callsBefore);
  });

  test('a 401 during search clears the session', () async {
    server.lookupStatus = 401;

    await expectLater(
      library.search('冰海'),
      throwsA(
        isA<EmbyException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      ),
    );
    expect(auth.current, isNull);
  });

  group('favorites (S8)', () {
    test(
      'favorites sends Filters=IsFavorite with the contract query',
      () async {
        server.favoriteItems = <Map<String, dynamic>>[
          <String, dynamic>{
            'Id': 'fav-1',
            'Name': '收藏影片',
            'Type': 'Movie',
            'UserData': <String, dynamic>{'IsFavorite': true, 'Played': false},
          },
        ];

        final page = await library.favorites();

        expect(page.items.single.id, 'fav-1');
        expect(page.items.single.userData.isFavorite, isTrue);
        final query = server.lastItemsQuery!;
        expect(query['Filters'], 'IsFavorite');
        expect(query['Recursive'], 'true');
        expect(query['IncludeItemTypes'], 'Movie,Series');
        expect(query['SortBy'], 'SortName');
        expect(query['SortOrder'], 'Ascending');
        expect(query['StartIndex'], '0');
        expect(query['Limit'], '60');
        expect(query['Fields'], contains('UserData'));
        expect(query['Fields'], isNot(contains('MediaSources')));
      },
    );

    test('favorites honors types, sort and paging', () async {
      server.favoriteItems = <Map<String, dynamic>>[];

      await library.favorites(
        types: 'Series',
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
        startIndex: 60,
        limit: 30,
      );

      final query = server.lastItemsQuery!;
      expect(query['Filters'], 'IsFavorite');
      expect(query['IncludeItemTypes'], 'Series');
      expect(query['SortBy'], 'DateCreated');
      expect(query['SortOrder'], 'Descending');
      expect(query['StartIndex'], '60');
      expect(query['Limit'], '30');
    });

    test('favorites pages cover every row exactly once', () async {
      server.favoriteItems = List<Map<String, dynamic>>.generate(
        130,
        (index) => <String, dynamic>{
          'Id': 'fav-${index + 1}',
          'Name': 'Fav ${index + 1}',
          'Type': 'Movie',
        },
      );

      final first = await library.favorites();
      final second = await library.favorites(startIndex: first.nextStartIndex);
      final third = await library.favorites(startIndex: second.nextStartIndex);

      final ids = <String>[
        ...first.items.map((i) => i.id),
        ...second.items.map((i) => i.id),
        ...third.items.map((i) => i.id),
      ];
      expect(ids, hasLength(130));
      expect(ids.toSet(), hasLength(130));
      expect(third.isLast, isTrue);
    });

    test('favorites rejects invalid paging without a request', () async {
      server.requestLog.clear();

      await expectLater(library.favorites(startIndex: -1), throwsArgumentError);
      await expectLater(library.favorites(limit: 0), throwsArgumentError);
      expect(server.requestLog, isEmpty);
    });
  });

  group('favorite / played writes (S8)', () {
    test(
      'setFavorite true POSTs and false DELETEs the favorite path',
      () async {
        await library.setFavorite('movie-1', true);
        await library.setFavorite('movie-1', false);

        expect(server.favoriteWrites, <String>[
          'POST /Users/user-1/FavoriteItems/movie-1',
          'DELETE /Users/user-1/FavoriteItems/movie-1',
        ]);
      },
    );

    test('setPlayed true POSTs and false DELETEs the played path', () async {
      await library.setPlayed('movie-1', true);
      await library.setPlayed('movie-1', false);

      expect(server.playedWrites, <String>[
        'POST /Users/user-1/PlayedItems/movie-1',
        'DELETE /Users/user-1/PlayedItems/movie-1',
      ]);
    });

    test('a 401 on un-favorite clears the session', () async {
      server.revokeToken = true;

      await expectLater(
        library.setFavorite('movie-1', false),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
      expect(auth.current, isNull);
    });

    test('writes without a session fail before any request', () async {
      await auth.logout();
      final callsBefore = server.requestLog.length;

      await expectLater(
        library.setPlayed('movie-1', true),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
      expect(server.requestLog.length, callsBefore);
    });
  });

  test('items forwards a custom sort for the home banner', () async {
    await library.items(
      'view-1',
      limit: 5,
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
    );

    final query = server.lastItemsQuery!;
    expect(query['ParentId'], 'view-1');
    expect(query['SortBy'], 'DateCreated');
    expect(query['SortOrder'], 'Descending');
    expect(query['Limit'], '5');
  });

  group('resumable (P1 home)', () {
    test(
      'resumable sends Filters=IsResumable with the contract query',
      () async {
        server.resumableItems = <Map<String, dynamic>>[
          <String, dynamic>{
            'Id': 'res-1',
            'Name': '继续观看影片',
            'Type': 'Movie',
            'RunTimeTicks': 6000000000,
            'UserData': <String, dynamic>{
              'PlaybackPositionTicks': 1200000000,
              'Played': false,
            },
          },
        ];

        final page = await library.resumable();

        expect(page.items.single.id, 'res-1');
        expect(page.items.single.runTimeTicks, 6000000000);
        expect(page.items.single.userData.positionTicks, 1200000000);
        final query = server.lastItemsQuery!;
        expect(query['Filters'], 'IsResumable');
        expect(query['Recursive'], 'true');
        expect(query['IncludeItemTypes'], 'Movie,Episode');
        expect(query['SortBy'], 'DatePlayed');
        expect(query['SortOrder'], 'Descending');
        expect(query['Limit'], '20');
        expect(query['Fields'], contains('UserData'));
        expect(query['Fields'], contains('RunTimeTicks'));
        expect(query['Fields'], isNot(contains('MediaSources')));
      },
    );

    test('resumable honors a custom limit', () async {
      server.resumableItems = <Map<String, dynamic>>[];

      await library.resumable(limit: 8);

      expect(server.lastItemsQuery!['Limit'], '8');
    });

    test('resumable rejects an invalid limit without a request', () async {
      server.requestLog.clear();

      await expectLater(library.resumable(limit: 0), throwsArgumentError);
      expect(server.requestLog, isEmpty);
    });
  });

  group('collections / genres / tags (S10)', () {
    test(
      'collections sends IncludeItemTypes=BoxSet with the contract query',
      () async {
        server.boxsetItems = <Map<String, dynamic>>[
          <String, dynamic>{'Id': 'box-1', 'Name': '漫威合集', 'Type': 'BoxSet'},
        ];

        final page = await library.collections();

        expect(page.items.single.id, 'box-1');
        expect(page.items.single.type, 'BoxSet');
        final query = server.lastItemsQuery!;
        expect(query['IncludeItemTypes'], 'BoxSet');
        expect(query['Recursive'], 'true');
        expect(query['SortBy'], 'SortName');
        expect(query['SortOrder'], 'Ascending');
        expect(query['StartIndex'], '0');
        expect(query['Limit'], '60');
        expect(query['Fields'], contains('Overview'));
        expect(query['Fields'], isNot(contains('MediaSources')));
        expect(query.containsKey('ParentId'), isFalse);
      },
    );

    test('collections honors sort and paging', () async {
      server.boxsetItems = List<Map<String, dynamic>>.generate(
        130,
        (index) => <String, dynamic>{
          'Id': 'box-${index + 1}',
          'Name': 'Box ${index + 1}',
          'Type': 'BoxSet',
        },
      );

      final first = await library.collections(
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
      );
      expect(server.lastItemsQuery!['SortBy'], 'DateCreated');
      expect(server.lastItemsQuery!['SortOrder'], 'Descending');
      final second = await library.collections(
        startIndex: first.nextStartIndex,
        limit: 30,
      );

      final query = server.lastItemsQuery!;
      expect(query['StartIndex'], '60');
      expect(query['Limit'], '30');
      expect(first.items, hasLength(60));
      expect(second.items, hasLength(30));
      expect(second.totalRecordCount, 130);
    });

    test('collections rejects invalid paging without a request', () async {
      server.requestLog.clear();

      await expectLater(
        library.collections(startIndex: -1),
        throwsArgumentError,
      );
      await expectLater(library.collections(limit: 0), throwsArgumentError);
      expect(server.requestLog, isEmpty);
    });

    test('genres reads Names from GET /Genres with the user id', () async {
      server.genreNames = <String>['动作', '科幻', ''];

      final names = await library.genres();

      expect(names, <String>['动作', '科幻']);
      expect(server.lastGenresQuery!['UserId'], 'user-1');
      expect(server.requestLog, contains('GET /Genres'));
    });

    test('tags reads Names from GET /Tags with the user id', () async {
      server.tagNames = <String>['4K', '杜比视界'];

      final names = await library.tags();

      expect(names, <String>['4K', '杜比视界']);
      expect(server.lastTagsQuery!['UserId'], 'user-1');
      expect(server.requestLog, contains('GET /Tags'));
    });

    test('facets without a session fail before any request', () async {
      await auth.logout();
      final callsBefore = server.requestLog.length;

      await expectLater(
        library.genres(),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
      await expectLater(
        library.tags(),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.unauthorized,
          ),
        ),
      );
      expect(server.requestLog.length, callsBefore);
    });
  });

  group('items browsing filters (S10)', () {
    test('the default query carries no filter parameters', () async {
      await library.items('view-1');

      final query = server.lastItemsQuery!;
      expect(query['IncludeItemTypes'], 'Movie,Series');
      expect(query.containsKey('Genres'), isFalse);
      expect(query.containsKey('GenreIds'), isFalse);
      expect(query.containsKey('Years'), isFalse);
      expect(query.containsKey('Tags'), isFalse);
    });

    test('genre name maps to Genres and year to Years', () async {
      await library.items('view-1', genre: '动作', year: 2024);

      final query = server.lastItemsQuery!;
      expect(query['Genres'], '动作');
      expect(query['Years'], '2024');
      expect(query.containsKey('GenreIds'), isFalse);
    });

    test('genreId maps to GenreIds and wins over the name', () async {
      await library.items('view-1', genreId: 'g-1', genre: '动作');

      final query = server.lastItemsQuery!;
      expect(query['GenreIds'], 'g-1');
      expect(query.containsKey('Genres'), isFalse);
    });

    test('includeItemTypes overrides the type list', () async {
      await library.items('view-1', includeItemTypes: 'Movie');

      expect(server.lastItemsQuery!['IncludeItemTypes'], 'Movie');
    });

    test('tag maps to Tags', () async {
      await library.items('view-1', tag: '4K');

      expect(server.lastItemsQuery!['Tags'], '4K');
    });

    test('filters combine with sort and paging', () async {
      await library.items(
        'view-1',
        startIndex: 60,
        limit: 30,
        sortBy: 'ProductionYear',
        sortOrder: 'Descending',
        genre: '科幻',
        year: 2021,
        includeItemTypes: 'Series',
        tag: '完结',
      );

      final query = server.lastItemsQuery!;
      expect(query['ParentId'], 'view-1');
      expect(query['StartIndex'], '60');
      expect(query['Limit'], '30');
      expect(query['SortBy'], 'ProductionYear');
      expect(query['SortOrder'], 'Descending');
      expect(query['Genres'], '科幻');
      expect(query['Years'], '2021');
      expect(query['IncludeItemTypes'], 'Series');
      expect(query['Tags'], '完结');
    });

    test('the server narrows rows by year, genre, tag and type', () async {
      server.movieItems.add(<String, dynamic>{
        'Id': 'movie-2024',
        'Name': '沙丘2',
        'Type': 'Movie',
        'ProductionYear': 2024,
        'Genres': <String>['科幻'],
        'Tags': <String>['4K'],
      });

      final byYear = await library.items('view-1', year: 2024);
      expect(byYear.items.single.id, 'movie-2024');

      final byGenre = await library.items('view-1', genre: '科幻');
      expect(byGenre.items.single.id, 'movie-2024');

      final byTag = await library.items('view-1', tag: '4K');
      expect(byTag.items.single.id, 'movie-2024');

      final byType = await library.items('view-1', includeItemTypes: 'Series');
      expect(byType.items, isEmpty);
    });
  });
}
