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
  Future<ItemsPage> items(
    String viewId, {
    int startIndex = 0,
    int limit = 60,
  });

  /// Detail with `MediaSources` / `MediaStreams`.
  Future<MediaItem> item(String itemId);

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

  /// Primary image URL with `api_key` (contract §2). Null when logged out.
  Uri? imageUrl(String itemId, {String? tag, int? maxWidth});
}
