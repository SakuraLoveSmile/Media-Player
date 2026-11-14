import 'json_read.dart';

/// A top-level library view from `GET /Users/{userId}/Views` (contract §2).
class LibraryView {
  const LibraryView({
    required this.id,
    required this.name,
    this.collectionType,
    this.imageTag,
    this.itemCount,
  });

  factory LibraryView.fromJson(Map<String, dynamic> json) {
    return LibraryView(
      id: asStringOr(json['Id'], ''),
      name: asStringOr(json['Name'], ''),
      collectionType: asString(json['CollectionType']),
      imageTag: asString(asMap(json['ImageTags'])['Primary']),
      itemCount: _itemCount(json),
    );
  }

  /// `Views` answers carry `ChildCount` / `RecursiveItemCount`; the library
  /// strip badge shows how many titles live in the library (S28).
  static int? _itemCount(Map<String, dynamic> json) {
    final int recursive = asInt(json['RecursiveItemCount'], fallback: -1);
    if (recursive >= 0) return recursive;
    final int child = asInt(json['ChildCount'], fallback: -1);
    return child >= 0 ? child : null;
  }

  final String id;
  final String name;
  final String? collectionType;

  /// `ImageTags.Primary` of the view itself; null when the library has no
  /// custom image (the strip then falls back to a poster of its first item).
  final String? imageTag;

  /// Title count for the strip badge; null when the server does not report one.
  final int? itemCount;
}
