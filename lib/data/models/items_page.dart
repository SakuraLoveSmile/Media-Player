import 'json_read.dart';
import 'media_item.dart';

/// One page of `GET /Users/{userId}/Items` (contract §2).
///
/// Pagination is driven by `TotalRecordCount` and the caller's `StartIndex`
/// cursor; the repository never re-sorts or de-duplicates client side.
class ItemsPage {
  const ItemsPage({
    required this.items,
    required this.totalRecordCount,
    required this.startIndex,
  });

  factory ItemsPage.fromJson(
    Map<String, dynamic> json, {
    int fallbackStartIndex = 0,
  }) {
    final items =
        asMapList(json['Items']).map(MediaItem.fromJson).toList(growable: false);
    return ItemsPage(
      items: items,
      totalRecordCount: asInt(json['TotalRecordCount'], fallback: items.length),
      startIndex: asInt(json['StartIndex'], fallback: fallbackStartIndex),
    );
  }

  final List<MediaItem> items;
  final int totalRecordCount;
  final int startIndex;

  bool get isLast => startIndex + items.length >= totalRecordCount;

  int get nextStartIndex => startIndex + items.length;
}
