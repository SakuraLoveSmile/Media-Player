import 'json_read.dart';

/// One cast/crew entry of the detail response's `People` list (S7).
///
/// [role] is the character name for actors and the job title for crew; [type]
/// keeps the server's own classification (`Actor`, `Director`, ...). [id] and
/// [imageTag] address the person's primary image through the same
/// `/Items/<id>/Images/Primary` endpoint as library posters.
class Person {
  const Person({
    required this.name,
    this.role,
    this.type,
    this.id,
    this.imageTag,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      name: asStringOr(json['Name'], ''),
      role: asString(json['Role']),
      type: asString(json['Type']),
      id: asString(json['Id']),
      imageTag: asString(json['PrimaryImageTag']),
    );
  }

  final String name;
  final String? role;
  final String? type;
  final String? id;
  final String? imageTag;
}
