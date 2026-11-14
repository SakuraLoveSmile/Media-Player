import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../auth/api_session.dart';
import '../models/items_page.dart';
import '../models/json_read.dart';
import '../models/library_view.dart';
import '../models/media_item.dart';
import 'library_service.dart';

/// Emby library queries (contract §2).
///
/// Every request is derived from the session's resolved endpoint, so LAN and
/// WAN URLs cannot mix. List requests deliberately do not ask for
/// `MediaSources` / `MediaStreams`; only detail and playback do.
class LibraryRepository implements LibraryService {
  LibraryRepository(this._session);

  final ApiSession _session;

  /// List fields (S28): `CommunityRating` feeds the poster badge, `Genres`
  /// the banner pill and `Status` / `EndDate` the series year range.
  static const String listFields =
      'Overview,PrimaryImageAspectRatio,UserData,ProductionYear,RunTimeTicks,'
      'CommunityRating,Genres,Status,EndDate,PremiereDate,ParentIndexNumber';
  static const String detailFields =
      'Overview,MediaSources,MediaStreams,People,Genres,UserData,Chapters,'
      'Tagline,CommunityRating,OfficialRating,ProductionYear,RunTimeTicks,'
      'RemoteTrailer,Studios,ExternalUrls,RemoteTrailers,Status,EndDate';

  @override
  Future<List<LibraryView>> views() async {
    final json = await _session.authorizedGet(_uri('/Users/$_userId/Views'));
    return asMapList(json['Items'])
        .map(LibraryView.fromJson)
        .toList(growable: false);
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
    if (startIndex < 0) {
      throw ArgumentError.value(startIndex, 'startIndex', 'must be >= 0');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be > 0');
    }

    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'ParentId': viewId,
        'Recursive': 'true',
        'IncludeItemTypes': includeItemTypes ?? 'Movie,Series',
        'Fields': listFields,
        'SortBy': sortBy,
        'SortOrder': sortOrder,
        'StartIndex': '$startIndex',
        'Limit': '$limit',
        // An exact genre id wins over the name; both are optional (S10).
        if (genreId != null && genreId.isNotEmpty)
          'GenreIds': genreId
        else if (genre != null && genre.isNotEmpty)
          'Genres': genre,
        if (year != null) 'Years': '$year',
        if (tag != null && tag.isNotEmpty) 'Tags': tag,
        if (filters != null && filters.isNotEmpty) 'Filters': filters,
        // Emby accepts ids or, when the detail payload has none, names (S60).
        if (studioId != null && studioId.isNotEmpty)
          'StudioIds': studioId
        else if (studio != null && studio.isNotEmpty)
          'Studios': studio,
      }),
    );
    return ItemsPage.fromJson(json, fallbackStartIndex: startIndex);
  }

  @override
  Future<ItemsPage> collections({
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
  }) async {
    if (startIndex < 0) {
      throw ArgumentError.value(startIndex, 'startIndex', 'must be >= 0');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be > 0');
    }

    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'Recursive': 'true',
        'IncludeItemTypes': 'BoxSet',
        'Fields': listFields,
        'SortBy': sortBy,
        'SortOrder': sortOrder,
        'StartIndex': '$startIndex',
        'Limit': '$limit',
      }),
    );
    return ItemsPage.fromJson(json, fallbackStartIndex: startIndex);
  }

  @override
  Future<List<String>> genres() => _facetNames('/Genres');

  @override
  Future<List<String>> tags() => _facetNames('/Tags');

  /// `GET /Genres` / `GET /Tags` answer `Items[].Name` (S10). Blank names are
  /// dropped so a chip row never renders an empty label.
  Future<List<String>> _facetNames(String path) async {
    final json = await _session.authorizedGet(
      _uri(path, <String, String>{'UserId': _userId}),
    );
    return asMapList(json['Items'])
        .map((item) => asStringOr(item['Name'], ''))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<ItemsPage> resumable({int limit = 20}) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be > 0');
    }

    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'Filters': 'IsResumable',
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Episode',
        'Fields': listFields,
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Limit': '$limit',
      }),
    );
    return ItemsPage.fromJson(json);
  }

  @override
  Future<MediaItem> item(String itemId) async {
    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items/$itemId', <String, String>{
        'Fields': detailFields,
      }),
    );
    return MediaItem.fromJson(json);
  }

  @override
  Future<List<MediaItem>> similar(String itemId, {int limit = 12}) async {
    if (itemId.isEmpty || limit <= 0) return const <MediaItem>[];
    final json = await _session.authorizedGet(
      _uri('/Items/$itemId/Similar', <String, String>{
        'UserId': _userId,
        'Limit': '$limit',
        'Fields': listFields,
      }),
    );
    return asMapList(json['Items'])
        .map(MediaItem.fromJson)
        .toList(growable: false);
  }

  @override
  Future<ItemsPage> collectionItems(
    String collectionId, {
    int limit = 60,
  }) async {
    if (collectionId.isEmpty || limit <= 0) {
      return const ItemsPage(
        items: <MediaItem>[],
        totalRecordCount: 0,
        startIndex: 0,
      );
    }
    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'ParentId': collectionId,
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Series',
        'Fields': listFields,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': '$limit',
      }),
    );
    return ItemsPage.fromJson(json);
  }

  @override
  Future<ItemsPage> itemsByPerson(String personId, {int limit = 60}) async {
    if (personId.isEmpty || limit <= 0) {
      return const ItemsPage(
        items: <MediaItem>[],
        totalRecordCount: 0,
        startIndex: 0,
      );
    }
    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'PersonIds': personId,
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Series',
        'Fields': listFields,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': '$limit',
      }),
    );
    return ItemsPage.fromJson(json);
  }

  @override
  Future<String> serverName() async {
    final json = await _session.authorizedGet(_uri('/System/Info/Public'));
    return asStringOr(json['ServerName'], '');
  }

  @override
  Future<ItemsPage> search(
    String term, {
    String types = 'Movie,Series',
    int limit = 60,
  }) async {
    final String query = term.trim();
    if (query.isEmpty) {
      return const ItemsPage(
        items: <MediaItem>[],
        totalRecordCount: 0,
        startIndex: 0,
      );
    }
    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'Recursive': 'true',
        'IncludeItemTypes': types,
        'SearchTerm': query,
        'Fields': listFields,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': '$limit',
      }),
    );
    return ItemsPage.fromJson(json);
  }

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
    if (startIndex < 0) {
      throw ArgumentError.value(startIndex, 'startIndex', 'must be >= 0');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be > 0');
    }

    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'Filters': 'IsFavorite',
        'Recursive': 'true',
        'IncludeItemTypes': types,
        'Fields': listFields,
        'SortBy': sortBy,
        'SortOrder': sortOrder,
        'StartIndex': '$startIndex',
        'Limit': '$limit',
        if (genre != null && genre.isNotEmpty) 'Genres': genre,
        if (year != null) 'Years': '$year',
      }),
    );
    return ItemsPage.fromJson(json, fallbackStartIndex: startIndex);
  }

  @override
  Future<void> setFavorite(String itemId, bool favorite) async {
    final url = _uri('/Users/$_userId/FavoriteItems/$itemId');
    if (favorite) {
      await _session.authorizedPost(url);
    } else {
      await _session.authorizedDelete(url);
    }
  }

  @override
  Future<void> setPlayed(String itemId, bool played) async {
    final url = _uri('/Users/$_userId/PlayedItems/$itemId');
    if (played) {
      await _session.authorizedPost(url);
    } else {
      await _session.authorizedDelete(url);
    }
  }

  @override
  Future<List<MediaItem>> seasons(String seriesId) async {
    final json = await _session.authorizedGet(
      _uri('/Shows/$seriesId/Seasons', <String, String>{
        'UserId': _userId,
        // S78: the episode count shown on a season card; the series page must
        // not fetch every season's episodes just to count them.
        'Fields': 'ChildCount',
      }),
    );
    return asMapList(json['Items'])
        .map(MediaItem.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<MediaItem>> episodes({
    required String seriesId,
    required String seasonId,
  }) async {
    final json = await _session.authorizedGet(
      _uri('/Shows/$seriesId/Episodes', <String, String>{
        'UserId': _userId,
        'SeasonId': seasonId,
        'Fields': 'Overview,MediaSources,UserData',
      }),
    );
    return asMapList(json['Items'])
        .map(MediaItem.fromJson)
        .toList(growable: false);
  }

  @override
  Future<MediaItem?> findByTmdb(int tmdbId, {required bool isSeries}) async {
    // `AnyProviderIdEquals` takes `<provider>.<id>`; Emby stores TMDB ids under
    // the `tmdbid` provider. Versions that do not know the parameter ignore it
    // and answer the whole library, so the result is filtered by year and type
    // on the client before it is trusted.
    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'Recursive': 'true',
        'IncludeItemTypes': isSeries ? 'Series' : 'Movie',
        'AnyProviderIdEquals': 'tmdbid.$tmdbId',
        'Fields': listFields,
        'Limit': '5',
      }),
    );
    // An id match needs no year check: the id is exact. An empty answer means
    // this server does not index that provider id, and the caller falls back to
    // the title search.
    return _firstMatching(
      asMapList(json['Items']).map(MediaItem.fromJson),
      isSeries: isSeries,
      year: null,
    );
  }

  @override
  Future<MediaItem?> searchByTitle(
    String title, {
    int? year,
    required bool isSeries,
  }) async {
    if (title.trim().isEmpty) return null;
    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Items', <String, String>{
        'Recursive': 'true',
        'IncludeItemTypes': isSeries ? 'Series' : 'Movie',
        'SearchTerm': title,
        'Fields': listFields,
        'Limit': '10',
      }),
    );
    return _firstMatching(
      asMapList(json['Items']).map(MediaItem.fromJson),
      isSeries: isSeries,
      year: year,
    );
  }

  /// Picks an item of the right type whose year agrees with [year].
  ///
  /// Year agreement is required, not preferred. Emby's title search is not a
  /// precision tool — searching "流浪地球" on a real library answered with
  /// "流浪地球2 (2023)" and nothing else — so accepting a mismatched year is
  /// how the app ends up playing the sequel of the film the user asked for.
  /// When no year is known the first candidate of the right type is used,
  /// because there is nothing better to go on.
  MediaItem? _firstMatching(
    Iterable<MediaItem> items, {
    required bool isSeries,
    required int? year,
  }) {
    final wanted = isSeries ? 'Series' : 'Movie';
    MediaItem? untyped;
    for (final item in items) {
      if (item.id.isEmpty) continue;
      if (item.type.isNotEmpty && item.type != wanted) continue;
      if (year != null && item.productionYear != null) {
        if (item.productionYear != year) continue;
        return item;
      }
      // Either side lacks a year: usable only when nothing carries one.
      untyped ??= item;
    }
    return untyped;
  }

  @override
  Uri? imageUrl(
    String itemId, {
    String? tag,
    int? maxWidth,
    String type = 'Primary',
    int? index,
  }) {
    final endpoint = _session.endpoint;
    final token = _session.accessToken;
    if (endpoint == null || token == null) return null;

    // Backdrop and other multi-image kinds take an index; Primary does not.
    final String path = index == null
        ? '/Items/$itemId/Images/$type'
        : '/Items/$itemId/Images/$type/$index';
    return endpoint
        .resolve(path)
        .replace(
          queryParameters: <String, String>{
            if (maxWidth != null) 'maxWidth': '$maxWidth',
            if (tag != null && tag.isNotEmpty) 'tag': tag,
            'quality': '90',
            'api_key': token,
          },
        );
  }

  String get _userId {
    final id = _session.userId;
    if (id == null || id.isEmpty) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    return id;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final endpoint = _session.endpoint;
    if (endpoint == null) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    final uri = endpoint.resolve(path);
    return query == null ? uri : uri.replace(queryParameters: query);
  }
}
