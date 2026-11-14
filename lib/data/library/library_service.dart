import '../models/items_page.dart';
import '../models/library_view.dart';
import '../models/media_item.dart';

/// Library read model used by the UI (contract §2).
///
/// Declared separately from [LibraryRepository] so pages can be tested with a
/// fake and never touch HTTP.
abstract interface class LibraryService {
  Future<List<LibraryView>> views();

  /// `Movie` / `Series` only, 60 per page by default (contract §2).
  ///
  /// [sortBy] / [sortOrder] map straight onto the Emby query; the home
  /// dashboard reuses this with `DateCreated` / `Descending` for its banner.
  ///
  /// S10 browsing filters, all optional and omitted from the query when null:
  /// [includeItemTypes] overrides the type list (类型 tab), [genreId]
  /// (`GenreIds`) wins over [genre] (`Genres`), [year] maps to `Years` and
  /// [tag] to `Tags` (标签 tab).
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
  });

  /// BoxSet collections (S10 合集 tab): `IncludeItemTypes=BoxSet`, recursive,
  /// paginated and sortable like [items].
  Future<ItemsPage> collections({
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
  });

  /// Genre names for the 全部 筛选 dialog (S10), from `GET /Genres`.
  Future<List<String>> genres();

  /// Tag names for the 标签 tab (S10), from `GET /Tags`.
  Future<List<String>> tags();

  /// Continue-watching row (P1 home): `Filters=IsResumable`, most recently
  /// played first. `Movie` / `Episode` only, with `UserData` + `RunTimeTicks`
  /// so the card can draw a progress bar and the remaining time.
  Future<ItemsPage> resumable({int limit = 20});

  /// Detail with `MediaSources` / `MediaStreams`.
  Future<MediaItem> item(String itemId);

  /// Server display name from `System/Info/Public`, shown in the home header
  /// (S28). Empty when the server does not advertise one.
  Future<String> serverName();

  /// Similar/recommended titles for the detail page's 推荐 row (S28),
  /// from `GET /Items/{id}/Similar`.
  Future<List<MediaItem>> similar(String itemId, {int limit = 12});

  /// Children of a BoxSet collection (S34 合集): `ParentId` scoped, recursive,
  /// Movie/Series only.
  Future<ItemsPage> collectionItems(String collectionId, {int limit = 60});

  /// Titles a person appears in (S34 演员页): `PersonIds` filtered, recursive,
  /// Movie/Series only.
  Future<ItemsPage> itemsByPerson(String personId, {int limit = 60});

  /// Title search across the whole library (search page, S6). [types] is the
  /// `IncludeItemTypes` list; an empty term answers an empty page without a
  /// request.
  Future<ItemsPage> search(
    String term, {
    String types = 'Movie,Series',
    int limit = 60,
  });

  /// Favorites list (S8): `Filters=IsFavorite`, paginated and sortable.
  /// [types] is the `IncludeItemTypes` list; [sortBy] / [sortOrder] map straight
  /// onto the Emby query. [genre] / [year] narrow the list (S39 收藏筛选).
  Future<ItemsPage> favorites({
    String types = 'Movie,Series',
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    String? genre,
    int? year,
  });

  /// Adds ([favorite] true) or clears (false) the favorite mark (S8).
  Future<void> setFavorite(String itemId, bool favorite);

  /// Marks ([played] true) or clears (false) the watched state (S8).
  Future<void> setPlayed(String itemId, bool played);

  Future<List<MediaItem>> seasons(String seriesId);

  Future<List<MediaItem>> episodes({
    required String seriesId,
    required String seasonId,
  });

  /// Finds a movie or series by TMDB id (求片 plan S7).
  ///
  /// Used to promote a finished 求片 to "playable now". Null when the library
  /// does not have it (yet).
  Future<MediaItem?> findByTmdb(int tmdbId, {required bool isSeries});

  /// Finds a movie or series by title, filtering by [year] on the client when
  /// the server ignores it. The fallback for [findByTmdb], and for requests
  /// whose MoviePilot entry has no TMDB id.
  Future<MediaItem?> searchByTitle(
    String title, {
    int? year,
    required bool isSeries,
  });

  /// Item image URL with `api_key` (contract §2). Null when logged out.
  ///
  /// [type] is Emby's image kind (`Primary`, `Backdrop`, ...); [index] picks
  /// one of several backdrops and is omitted for the single-kind images.
  Uri? imageUrl(
    String itemId, {
    String? tag,
    int? maxWidth,
    String type = 'Primary',
    int? index,
  });
}
