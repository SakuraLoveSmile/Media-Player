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

  /// Primary image URL with `api_key` (contract §2). Null when logged out.
  Uri? imageUrl(String itemId, {String? tag, int? maxWidth});
}
