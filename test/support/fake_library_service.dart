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
    this.failure,
    this.unauthorized = false,
  })  : viewList = viewList ?? const <LibraryView>[],
        itemsByView = itemsByView ?? const <String, List<MediaItem>>{};

  List<LibraryView> viewList;
  Map<String, List<MediaItem>> itemsByView;
  EmbyException? failure;
  bool unauthorized;

  int viewCalls = 0;
  int itemCalls = 0;

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
  }) async {
    itemCalls++;
    _maybeThrow();
    final all = itemsByView[viewId] ?? const <MediaItem>[];
    final slice = all.skip(startIndex).take(limit).toList(growable: false);
    return ItemsPage(
      items: slice,
      totalRecordCount: all.length,
      startIndex: startIndex,
    );
  }

  @override
  Future<MediaItem> item(String itemId) async {
    _maybeThrow();
    return itemsByView.values
        .expand((items) => items)
        .firstWhere((item) => item.id == itemId);
  }

  @override
  Future<List<MediaItem>> seasons(String seriesId) async => const [];

  @override
  Future<List<MediaItem>> episodes({
    required String seriesId,
    required String seasonId,
  }) async =>
      const [];

  @override
  Uri? imageUrl(String itemId, {String? tag, int? maxWidth}) => null;

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
