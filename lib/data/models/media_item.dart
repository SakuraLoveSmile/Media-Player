import 'json_read.dart';
import 'media_source.dart';

/// Library list/detail entry (contract §4).
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.seriesId,
    this.seasonId,
    this.indexNumber,
    this.runTimeTicks = 0,
    this.imageTag,
    this.overview,
    this.userData = const UserItemData(),
    this.mediaSources = const <MediaSource>[],
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: asStringOr(json['Id'], ''),
      name: asStringOr(json['Name'], ''),
      type: asStringOr(json['Type'], ''),
      seriesId: asString(json['SeriesId']),
      seasonId: asString(json['SeasonId']),
      indexNumber: asIntOrNull(json['IndexNumber']),
      runTimeTicks: asInt(json['RunTimeTicks']),
      imageTag: asString(asMap(json['ImageTags'])['Primary']),
      overview: asString(json['Overview']),
      userData: UserItemData.fromJson(asMap(json['UserData'])),
      mediaSources: asMapList(json['MediaSources'])
          .map(MediaSource.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final String name;
  final String type;
  final String? seriesId;
  final String? seasonId;
  final int? indexNumber;
  final int runTimeTicks;
  final String? imageTag;
  final String? overview;
  final UserItemData userData;

  /// Present only on the detail response (contract §2).
  final List<MediaSource> mediaSources;

  Duration get duration => Duration(microseconds: runTimeTicks ~/ 10);
}

/// Playback state kept by the server for the current user (contract §4).
class UserItemData {
  const UserItemData({this.played = false, this.positionTicks = 0});

  factory UserItemData.fromJson(Map<String, dynamic> json) {
    return UserItemData(
      played: asBool(json['Played']),
      positionTicks: asInt(json['PlaybackPositionTicks']),
    );
  }

  final bool played;
  final int positionTicks;

  Duration get position => Duration(microseconds: positionTicks ~/ 10);
}
