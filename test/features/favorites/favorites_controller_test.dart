import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/items_page.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/features/favorites/favorites_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_poster_cache.dart';

/// Gates every favorites request behind a completer so a test can finish an
/// older page after a newer one and prove the stale answer is discarded.
class GatedFavorites extends FakeLibraryService {
  final List<Completer<ItemsPage>> gates = <Completer<ItemsPage>>[];

  @override
  Future<ItemsPage> favorites({
    String types = 'Movie,Series',
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    String? genre,
    int? year,
  }) {
    unawaited(
      super.favorites(
        types: types,
        startIndex: startIndex,
        limit: limit,
        sortBy: sortBy,
        sortOrder: sortOrder,
        genre: genre,
        year: year,
      ),
    );
    final gate = Completer<ItemsPage>();
    gates.add(gate);
    return gate.future;
  }
}

MediaItem item(String id, {String type = 'Movie'}) {
  return MediaItem(id: id, name: 'Item $id', type: type);
}

void main() {
  late FakeLibraryService library;
  late FavoritesController controller;

  setUp(() {
    library = FakeLibraryService();
    controller = FavoritesController(library, FakePosterCache());
  });

  tearDown(() => controller.dispose());

  test(
    'load fetches the first page with the default filter and sort',
    () async {
      library.favoriteResults = <MediaItem>[
        item('m-1'),
        item('s-1', type: 'Series'),
      ];

      await controller.load();

      final state = controller.state;
      expect(state.items, hasLength(2));
      expect(state.total, 2);
      expect(state.loaded, isTrue);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
      final request = library.favoritesRequests.single;
      expect(request.types, 'Movie,Series,BoxSet,Person');
      expect(request.sortBy, 'DateCreated');
      expect(request.sortOrder, 'Descending');
      expect(request.startIndex, 0);
    },
  );

  test('the type tab narrows the request and the result', () async {
    library.favoriteResults = <MediaItem>[
      item('m-1'),
      item('s-1', type: 'Series'),
    ];
    await controller.load();

    controller.setFilter(FavoritesFilter.series);
    await Future<void>.delayed(Duration.zero);

    expect(library.favoritesRequests.last.types, 'Series');
    expect(controller.state.items.single.id, 's-1');

    controller.setFilter(FavoritesFilter.movies);
    await Future<void>.delayed(Duration.zero);
    expect(library.favoritesRequests.last.types, 'Movie');
    expect(controller.state.items.single.id, 'm-1');
  });

  test('the sort preset changes SortBy and SortOrder', () async {
    library.favoriteResults = <MediaItem>[item('m-1')];
    await controller.load();

    controller.setSort(FavoritesSort.dateAdded);
    await Future<void>.delayed(Duration.zero);
    expect(library.favoritesRequests.last.sortBy, 'DateCreated');
    expect(library.favoritesRequests.last.sortOrder, 'Descending');

    controller.setSort(FavoritesSort.rating);
    await Future<void>.delayed(Duration.zero);
    expect(library.favoritesRequests.last.sortBy, 'CommunityRating');
    expect(library.favoritesRequests.last.sortOrder, 'Descending');
  });

  test('filters re-query with genre and year (S39)', () async {
    library.favoriteResults = <MediaItem>[item('m-1')];
    library.genreNames = const <String>['动作'];
    await controller.load();

    controller.applyFilters('动作', 2024);
    await Future<void>.delayed(Duration.zero);
    expect(library.favoritesRequests.last.genre, '动作');
    expect(library.favoritesRequests.last.year, 2024);

    controller.applyFilters(null, null);
    await Future<void>.delayed(Duration.zero);
    expect(library.favoritesRequests.last.genre, isNull);
    expect(library.favoritesRequests.last.year, isNull);

    await controller.loadGenres();
    expect(controller.state.genres, <String>['动作']);
  });
  test('loadMore appends until the total is reached', () async {
    library.favoriteResults = List<MediaItem>.generate(
      75,
      (index) => item('${index + 1}'),
    );

    await controller.load();
    expect(controller.state.items, hasLength(60));
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();
    expect(controller.state.items, hasLength(75));
    expect(controller.state.hasMore, isFalse);
    expect(library.favoritesRequests.last.startIndex, 60);

    await controller.loadMore();
    expect(
      library.favoritesRequests,
      hasLength(2),
      reason: 'no request past the last page',
    );
  });

  test('a stale page never overwrites a newer filter', () async {
    final gated = GatedFavorites();
    final stale = FavoritesController(gated, FakePosterCache());
    addTearDown(stale.dispose);

    final first = stale.load();
    stale.setFilter(FavoritesFilter.movies);
    expect(gated.gates, hasLength(2));

    gated.gates[1].complete(
      ItemsPage(
        items: <MediaItem>[item('m-new')],
        totalRecordCount: 1,
        startIndex: 0,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(stale.state.items.single.id, 'm-new');

    gated.gates[0].complete(
      ItemsPage(
        items: <MediaItem>[item('m-old')],
        totalRecordCount: 1,
        startIndex: 0,
      ),
    );
    await first;
    expect(stale.state.items.single.id, 'm-new');
  });

  test('an empty favorites list loads into the empty state', () async {
    library.favoriteResults = const <MediaItem>[];

    await controller.load();

    expect(controller.state.items, isEmpty);
    expect(controller.state.loaded, isTrue);
    expect(controller.state.error, isNull);
  });

  test('a network failure becomes copy, not an exception string', () async {
    library.favoritesFailure = EmbyException(AppErrorCode.networkUnreachable);

    await controller.load();

    expect(controller.state.error, '无法连接服务器，请检查网络');
    expect(controller.state.unauthorized, isFalse);
    expect(controller.state.loaded, isTrue);
  });

  test('a 401 flags unauthorized for the login redirect', () async {
    library.favoritesFailure = EmbyException(AppErrorCode.unauthorized);

    await controller.load();

    expect(controller.state.unauthorized, isTrue);
    expect(controller.state.error, isNull);
  });
}
