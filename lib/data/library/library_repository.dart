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

  static const String listFields =
      'Overview,PrimaryImageAspectRatio,UserData,ProductionYear,RunTimeTicks';
  static const String detailFields =
      'Overview,MediaSources,MediaStreams,People,Genres,UserData';

  @override
  Future<List<LibraryView>> views() async {
    final json = await _session.authorizedGet(
      _uri('/Users/$_userId/Views'),
    );
    return asMapList(json['Items'])
        .map(LibraryView.fromJson)
        .toList(growable: false);
  }

  @override
  Future<ItemsPage> items(
    String viewId, {
    int startIndex = 0,
    int limit = 60,
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
        'IncludeItemTypes': 'Movie,Series',
        'Fields': listFields,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'StartIndex': '$startIndex',
        'Limit': '$limit',
      }),
    );
    return ItemsPage.fromJson(json, fallbackStartIndex: startIndex);
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
  Future<List<MediaItem>> seasons(String seriesId) async {
    final json = await _session.authorizedGet(
      _uri('/Shows/$seriesId/Seasons', <String, String>{
        'UserId': _userId,
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
  Uri? imageUrl(String itemId, {String? tag, int? maxWidth}) {
    final endpoint = _session.endpoint;
    final token = _session.accessToken;
    if (endpoint == null || token == null) return null;

    return endpoint
        .resolve('/Items/$itemId/Images/Primary')
        .replace(queryParameters: <String, String>{
      if (maxWidth != null) 'maxWidth': '$maxWidth',
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      'quality': '90',
      'api_key': token,
    });
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
