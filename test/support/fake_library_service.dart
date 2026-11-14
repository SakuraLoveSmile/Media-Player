import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/library/library_service.dart';
import 'package:media_player/data/models/items_page.dart';
import 'package:media_player/data/models/library_view.dart';
import 'package:media_player/data/models/media_item.dart';

/// Configurable library double for widget/controller tests.
class FakeLibraryService implements LibraryService {
  FakeLibraryService({
    List<LibraryView>? viewList,
    Map<String, List<MediaItem>>? itemsByView,
    Map<String, MediaItem>? itemsById,
    Map<String, List<MediaItem>>? seasonsBySeries,
    Map<String, List<MediaItem>>? episodesBySeason,
    this.failure,
    this.unauthorized = false,
  }) : viewList = viewList ?? <LibraryView>[],
       itemsByView = itemsByView ?? <String, List<MediaItem>>{},
       itemsById = itemsById ?? <String, MediaItem>{},
       seasonsBySeries = seasonsBySeries ?? <String, List<MediaItem>>{},
       episodesBySeason = episodesBySeason ?? <String, List<MediaItem>>{};

  List<LibraryView> viewList;
  Map<String, List<MediaItem>> itemsByView;
  Map<String, MediaItem> itemsById;
  Map<String, List<MediaItem>> seasonsBySeries;
  Map<String, List<MediaItem>> episodesBySeason;
  final List<String> detailRequests = <String>[];
  final List<String> seasonsRequests = <String>[];
  final List<({String seriesId, String seasonId})> episodeRequests = [];
  EmbyException? failure;
  bool unauthorized;

  /// Null keeps [imageUrl] null so cards render their placeholder. Set it to
  /// exercise the poster path.
  String? imageHost;

  /// Mirrors a re-login: every image URL changes, the item identity does not.
  String imageToken = 'token-1';

  int viewCalls = 0;
  int itemCalls = 0;

  /// Sort arguments of every [items] call in order, so the home banner can
  /// assert it asked for `DateCreated` / `Descending` (the first call).
  final List<({String sortBy, String sortOrder})> itemsSorts =
      <({String sortBy, String sortOrder})>[];

  /// `Filters` values passed to [items] (S45).
  final List<String> itemsFilters = <String>[];

  /// `StudioIds` values passed to [items] (S60).
  final List<String> itemsStudioIds = <String>[];

  /// `Studios` names passed to [items] (S60 fallback when no id).
  final List<String> itemsStudios = <String>[];

  /// Full arguments of every [items] call in order (P1 library sort/paging,
  /// S10 genre/year/type/tag filters).
  final List<
    ({
      String viewId,
      int startIndex,
      int limit,
      String sortBy,
      String sortOrder,
      String? genreId,
      String? genre,
      int? year,
      String? tag,
      String? includeItemTypes,
    })
  >
  itemsRequests =
      <
        ({
          String viewId,
          int startIndex,
          int limit,
          String sortBy,
          String sortOrder,
          String? genreId,
          String? genre,
          int? year,
          String? tag,
          String? includeItemTypes,
        })
      >[];

  @override
  Future<List<LibraryView>> views() async {
    viewCalls++;
    _maybeThrow();
    return viewList;
  }

  @override
  Future<ItemsPage> items(
    String viewId, {
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    String? genreId,
    String? genre,
    int? year,
    String? tag,
    String? includeItemTypes,
    String? filters,
    String? studioId,
    String? studio,
  }) async {
    itemCalls++;
    if (filters != null) itemsFilters.add(filters);
    if (studioId != null) itemsStudioIds.add(studioId);
    if (studio != null) itemsStudios.add(studio);
    itemsSorts.add((sortBy: sortBy, sortOrder: sortOrder));
    itemsRequests.add((
      viewId: viewId,
      startIndex: startIndex,
      limit: limit,
      sortBy: sortBy,
      sortOrder: sortOrder,
      genreId: genreId,
      genre: genre,
      year: year,
      tag: tag,
      includeItemTypes: includeItemTypes,
    ));
    _maybeThrow();
    // S10: mirror the server-side type/genre/year/tag narrowing. [genreId]
    // is recorded only; the fake has no genre id index.
    final wanted = (includeItemTypes ?? 'Movie,Series').split(',');
    final all = (itemsByView[viewId] ?? const <MediaItem>[])
        .where((item) => wanted.contains(item.type))
        .where((item) => genre == null || item.genres.contains(genre))
        .where((item) => year == null || item.productionYear == year)
        .where((item) => tag == null || item.tags.contains(tag))
        .toList(growable: false);
    final slice = all.skip(startIndex).take(limit).toList(growable: false);
    return ItemsPage(
      items: slice,
      totalRecordCount: all.length,
      startIndex: startIndex,
    );
  }

  /// Collections double (S10 合集): [collectionResults] paginated and sorted
  /// like the favorites double; [collectionsFailure] drives the error path.
  List<MediaItem> collectionResults = const <MediaItem>[];
  Object? collectionsFailure;
  final List<({int startIndex, int limit, String sortBy, String sortOrder})>
  collectionsRequests =
      <({int startIndex, int limit, String sortBy, String sortOrder})>[];

  @override
  Future<ItemsPage> collections({
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
  }) async {
    collectionsRequests.add((
      startIndex: startIndex,
      limit: limit,
      sortBy: sortBy,
      sortOrder: sortOrder,
    ));
    final error = collectionsFailure;
    if (error != null) throw error;
    _maybeThrow();
    final slice = collectionResults
        .skip(startIndex)
        .take(limit)
        .toList(growable: false);
    return ItemsPage(
      items: slice,
      totalRecordCount: collectionResults.length,
      startIndex: startIndex,
    );
  }

  /// Facet doubles (S10): names returned verbatim; the failure fields drive
  /// the error paths and the call counters prove caching.
  List<String> genreNames = const <String>[];
  List<String> tagNames = const <String>[];
  Object? genresFailure;
  Object? tagsFailure;
  int genreCalls = 0;
  int tagCalls = 0;

  @override
  Future<List<String>> genres() async {
    genreCalls++;
    final error = genresFailure;
    if (error != null) throw error;
    _maybeThrow();
    return genreNames;
  }

  @override
  Future<List<String>> tags() async {
    tagCalls++;
    final error = tagsFailure;
    if (error != null) throw error;
    _maybeThrow();
    return tagNames;
  }

  /// Continue-watching double (P1 home): [resumableResults] returned verbatim
  /// (already most-recently-played first), or [resumableFailure] to drive the
  /// error path.
  List<MediaItem> resumableResults = const <MediaItem>[];
  Object? resumableFailure;
  final List<int> resumableRequests = <int>[];

  @override
  Future<ItemsPage> resumable({int limit = 20}) async {
    resumableRequests.add(limit);
    final error = resumableFailure;
    if (error != null) throw error;
    _maybeThrow();
    final slice = resumableResults.take(limit).toList(growable: false);
    return ItemsPage(
      items: slice,
      totalRecordCount: resumableResults.length,
      startIndex: 0,
    );
  }

  /// `System/Info/Public` display name for the home header (S28); empty
  /// drives the no-name fallback.
  String serverNameValue = 'Test Server';
  int serverNameCalls = 0;

  @override
  Future<String> serverName() async {
    serverNameCalls++;
    _maybeThrow();
    return serverNameValue;
  }

  /// BoxSet children + person credits doubles (S34); the request lists record
  /// every call so pages can assert what they asked for.
  Map<String, List<MediaItem>> collectionItemsById =
      <String, List<MediaItem>>{};
  Map<String, List<MediaItem>> personItemsById = <String, List<MediaItem>>{};
  final List<String> collectionItemRequests = <String>[];
  final List<String> personItemRequests = <String>[];

  @override
  Future<ItemsPage> collectionItems(
    String collectionId, {
    int limit = 60,
  }) async {
    collectionItemRequests.add(collectionId);
    _maybeThrow();
    final List<MediaItem> items =
        collectionItemsById[collectionId] ?? const <MediaItem>[];
    return ItemsPage(
      items: items.take(limit).toList(growable: false),
      totalRecordCount: items.length,
      startIndex: 0,
    );
  }

  @override
  Future<ItemsPage> itemsByPerson(String personId, {int limit = 60}) async {
    personItemRequests.add(personId);
    _maybeThrow();
    final List<MediaItem> items =
        personItemsById[personId] ?? const <MediaItem>[];
    return ItemsPage(
      items: items.take(limit).toList(growable: false),
      totalRecordCount: items.length,
      startIndex: 0,
    );
  }

  /// Similar-items double (S28 推荐 row); [similarFailure] drives the
  /// non-fatal error path.
  List<MediaItem> similarResults = const <MediaItem>[];
  Object? similarFailure;
  final List<({String itemId, int limit})> similarRequests =
      <({String itemId, int limit})>[];

  @override
  Future<List<MediaItem>> similar(String itemId, {int limit = 12}) async {
    similarRequests.add((itemId: itemId, limit: limit));
    final error = similarFailure;
    if (error != null) throw error;
    _maybeThrow();
    return similarResults.take(limit).toList(growable: false);
  }

  @override
  Future<MediaItem> item(String itemId) async {
    detailRequests.add(itemId);
    _maybeThrow();
    final detail = itemsById[itemId];
    if (detail != null) return detail;
    return itemsByView.values
        .expand((items) => items)
        .firstWhere((item) => item.id == itemId);
  }

  /// Search double: [searchResults] filtered by the requested types, in the
  /// given order; [searchFailure] drives the error path.
  List<MediaItem> searchResults = const <MediaItem>[];
  Object? searchFailure;
  final List<({String term, String types})> searchRequests =
      <({String term, String types})>[];

  @override
  Future<ItemsPage> search(
    String term, {
    String types = 'Movie,Series',
    int limit = 60,
  }) async {
    searchRequests.add((term: term, types: types));
    final error = searchFailure;
    if (error != null) throw error;
    final wanted = types.split(',');
    final matches = searchResults
        .where((item) => wanted.contains(item.type))
        .take(limit)
        .toList(growable: false);
    return ItemsPage(
      items: matches,
      totalRecordCount: matches.length,
      startIndex: 0,
    );
  }

  /// Favorites double (S8/S39): [favoriteResults] filtered by the requested
  /// types/genre/year and paginated, or [favoritesPage] returned verbatim when
  /// set. [favoritesFailure] drives the error path.
  List<MediaItem> favoriteResults = const <MediaItem>[];
  ItemsPage? favoritesPage;
  Object? favoritesFailure;
  final List<
    ({
      String types,
      int startIndex,
      int limit,
      String sortBy,
      String sortOrder,
      String? genre,
      int? year,
    })
  >
  favoritesRequests =
      <
        ({
          String types,
          int startIndex,
          int limit,
          String sortBy,
          String sortOrder,
          String? genre,
          int? year,
        })
      >[];

  @override
  Future<ItemsPage> favorites({
    String types = 'Movie,Series',
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    String? genre,
    int? year,
  }) async {
    favoritesRequests.add((
      types: types,
      startIndex: startIndex,
      limit: limit,
      sortBy: sortBy,
      sortOrder: sortOrder,
      genre: genre,
      year: year,
    ));
    final error = favoritesFailure;
    if (error != null) throw error;
    _maybeThrow();
    final override = favoritesPage;
    if (override != null) return override;
    final wanted = types.split(',');
    final matches = favoriteResults
        .where((item) => wanted.contains(item.type))
        .where((item) => genre == null || item.genres.contains(genre))
        .where((item) => year == null || item.productionYear == year)
        .toList(growable: false);
    final slice = matches.skip(startIndex).take(limit).toList(growable: false);
    return ItemsPage(
      items: slice,
      totalRecordCount: matches.length,
      startIndex: startIndex,
    );
  }

  /// Recorded favorite/played writes (S8); [writeFailure] drives their error
  /// path.
  final List<({String itemId, bool favorite})> favoriteWrites =
      <({String itemId, bool favorite})>[];
  final List<({String itemId, bool played})> playedWrites =
      <({String itemId, bool played})>[];
  Object? writeFailure;

  @override
  Future<void> setFavorite(String itemId, bool favorite) async {
    favoriteWrites.add((itemId: itemId, favorite: favorite));
    final error = writeFailure;
    if (error != null) throw error;
    _maybeThrow();
  }

  @override
  Future<void> setPlayed(String itemId, bool played) async {
    playedWrites.add((itemId: itemId, played: played));
    final error = writeFailure;
    if (error != null) throw error;
    _maybeThrow();
  }

  @override
  Future<List<MediaItem>> seasons(String seriesId) async {
    seasonsRequests.add(seriesId);
    _maybeThrow();
    return seasonsBySeries[seriesId] ?? const [];
  }

  /// Season-episode double failure (P1 continuous play): only [episodes]
  /// throws it, so a broken neighbor fetch can be tested while the detail
  /// fetch and negotiation keep working.
  Object? episodesFailure;

  @override
  Future<List<MediaItem>> episodes({
    required String seriesId,
    required String seasonId,
  }) async {
    episodeRequests.add((seriesId: seriesId, seasonId: seasonId));
    final error = episodesFailure;
    if (error != null) throw error;
    _maybeThrow();
    return episodesBySeason[seasonId] ?? const [];
  }

  /// Items the 求片 lookup may find, with the queries that asked for them.
  List<MediaItem> lookupItems = const <MediaItem>[];
  Object? lookupFailure;
  final List<int> tmdbLookups = <int>[];
  final List<String> titleLookups = <String>[];

  @override
  Future<MediaItem?> findByTmdb(int tmdbId, {required bool isSeries}) async {
    tmdbLookups.add(tmdbId);
    final error = lookupFailure;
    if (error != null) throw error;
    for (final item in lookupItems) {
      if (item.type == (isSeries ? 'Series' : 'Movie')) return item;
    }
    return null;
  }

  @override
  Future<MediaItem?> searchByTitle(
    String title, {
    int? year,
    required bool isSeries,
  }) async {
    titleLookups.add(title);
    final error = lookupFailure;
    if (error != null) throw error;
    for (final item in lookupItems) {
      if (item.type != (isSeries ? 'Series' : 'Movie')) continue;
      if (year != null &&
          item.productionYear != null &&
          item.productionYear != year) {
        continue;
      }
      return item;
    }
    return null;
  }

  @override
  Uri? imageUrl(
    String itemId, {
    String? tag,
    int? maxWidth,
    String type = 'Primary',
    int? index,
  }) {
    final host = imageHost;
    if (host == null) return null;
    final String path = index == null
        ? '/Items/$itemId/Images/$type'
        : '/Items/$itemId/Images/$type/$index';
    return Uri.parse(
      'http://$host$path'
      '?maxWidth=${maxWidth ?? ''}&tag=${tag ?? ''}&api_key=$imageToken',
    );
  }

  void _maybeThrow() {
    if (unauthorized) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    final error = failure;
    if (error != null) throw error;
  }
}

MediaItem fakeItem(String id, {String name = '', bool played = false}) {
  return MediaItem(
    id: id,
    name: name.isEmpty ? 'Item $id' : name,
    type: 'Movie',
    imageTag: null,
    userData: UserItemData(played: played),
  );
}

const fakeMoviesView = LibraryView(
  id: 'view-movies',
  name: 'Movies',
  collectionType: 'movies',
);

const fakeShowsView = LibraryView(
  id: 'view-shows',
  name: 'Shows',
  collectionType: 'tvshows',
);
