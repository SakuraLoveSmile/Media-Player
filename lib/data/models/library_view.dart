import 'json_read.dart';

/// A top-level library view from `GET /Users/{userId}/Views` (contract §2).
class LibraryView {
  const LibraryView({
    required this.id,
    required this.name,
    this.collectionType,
  });

  factory LibraryView.fromJson(Map<String, dynamic> json) {
    return LibraryView(
      id: asStringOr(json['Id'], ''),
      name: asStringOr(json['Name'], ''),
      collectionType: asString(json['CollectionType']),
    );
  }

  final String id;
  final String name;
  final String? collectionType;
}
