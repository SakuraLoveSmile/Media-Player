import 'json_read.dart';
import 'media_source.dart';
import 'person.dart';

/// Library list/detail entry (contract §4).
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.seriesId,
    this.seasonId,
    this.indexNumber,
    this.parentIndexNumber,
    this.seriesName,
    this.productionYear,
    this.runTimeTicks = 0,
    this.childCount = 0,
    this.imageTag,
    this.overview,
    this.userData = const UserItemData(),
    this.mediaSources = const <MediaSource>[],
    this.tagline,
    this.communityRating,
    this.officialRating,
    this.genres = const <String>[],
    this.tags = const <String>[],
    this.people = const <Person>[],
    this.remoteTrailer,
    this.chapters = const <Chapter>[],
    this.backdropTag,
    this.backdropTags = const <String>[],
    this.parentBackdropItemId,
    this.parentBackdropTag,
    this.parentThumbItemId,
    this.parentThumbTag,
    this.logoTag,
    this.parentLogoItemId,
    this.parentLogoTag,
    this.status,
    this.endDate,
    this.studios = const <NamedLink>[],
    this.externalUrls = const <NamedLink>[],
    this.remoteTrailers = const <String>[],
    this.dateCreated,
    this.premiereDate,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: asStringOr(json['Id'], ''),
      name: asStringOr(json['Name'], ''),
      type: asStringOr(json['Type'], ''),
      seriesId: asString(json['SeriesId']),
      seasonId: asString(json['SeasonId']),
      indexNumber: asIntOrNull(json['IndexNumber']),
      parentIndexNumber: asIntOrNull(json['ParentIndexNumber']),
      seriesName: asString(json['SeriesName']),
      productionYear: asIntOrNull(json['ProductionYear']),
      runTimeTicks: asInt(json['RunTimeTicks']),
      childCount: asInt(json['ChildCount']),
      imageTag: asString(asMap(json['ImageTags'])['Primary']),
      overview: asString(json['Overview']),
      userData: UserItemData.fromJson(asMap(json['UserData'])),
      mediaSources: asMapList(json['MediaSources'])
          .map(MediaSource.fromJson)
          .toList(growable: false),
      tagline: asString(json['Tagline']),
      communityRating: asDoubleOrNull(json['CommunityRating']),
      officialRating: asString(json['OfficialRating']),
      genres: _stringList(json['Genres']),
      tags: _stringList(json['Tags']),
      people: asMapList(json['People'])
          .map(Person.fromJson)
          .toList(growable: false),
      remoteTrailer: asString(json['RemoteTrailer']),
      chapters: asMapList(json['Chapters'])
          .map(Chapter.fromJson)
          .toList(growable: false),
      backdropTag: _firstString(json['BackdropImageTags']),
      backdropTags: _stringList(json['BackdropImageTags']),
      parentBackdropItemId: asString(json['ParentBackdropItemId']),
      parentBackdropTag: _firstString(json['ParentBackdropImageTags']),
      parentThumbItemId: asString(json['ParentThumbItemId']),
      // Emby sends the singular field on list payloads and an array elsewhere.
      parentThumbTag:
          asString(json['ParentThumbImageTag']) ??
          _firstString(json['ParentThumbImageTags']),
      // Transparent series/movie logo (S78): episodes point at the parent
      // series through ParentLogoItemId; movies carry their own ImageTags.Logo.
      logoTag: asString(asMap(json['ImageTags'])['Logo']),
      parentLogoItemId: asString(json['ParentLogoItemId']),
      parentLogoTag:
          asString(json['ParentLogoImageTag']) ??
          _firstString(json['ParentLogoImageTags']),
      status: asString(json['Status']),
      endDate: asString(json['EndDate']),
      studios: _namedLinks(json['Studios']),
      externalUrls: _namedLinks(json['ExternalUrls']),
      remoteTrailers: _trailerUrls(json['RemoteTrailers']),
      dateCreated: asString(json['DateCreated']),
      premiereDate: asString(json['PremiereDate']),
    );
  }

  final String id;
  final String name;
  final String type;
  final String? seriesId;
  final String? seasonId;
  final int? indexNumber;

  /// Season number for an episode (`ParentIndexNumber`); used by the home
  /// 继续观看 card to show `S1E2：title` like Yamby (S68).
  final int? parentIndexNumber;

  /// Series title for an episode (`SeriesName`); the home 继续观看 card shows
  /// it as the main label with `S1E2：episode` beneath (S68).
  final String? seriesName;

  /// Release year; requested via [LibraryRepository.listFields] and used by the
  /// 求片 lookup to tell a remake from the original.
  final int? productionYear;
  final int runTimeTicks;

  /// Number of direct children (S78): a season's episode count, requested via
  /// `Fields=ChildCount` and shown as the badge on a season card. 0 when the
  /// server did not send it, which hides the badge instead of inventing a count.
  final int childCount;
  final String? imageTag;
  final String? overview;
  final UserItemData userData;

  /// Present only on the detail response (contract §2).
  final List<MediaSource> mediaSources;

  /// Detail-only fields (S7); all optional because list responses omit them.
  final String? tagline;
  final double? communityRating;
  final String? officialRating;
  final List<String> genres;

  /// Server tags (S10 标签 tab); present when the response carries `Tags`.
  final List<String> tags;
  final List<Person> people;
  final String? remoteTrailer;

  /// Named chapter markers (S12); used to offer skip intro/credits.
  final List<Chapter> chapters;

  /// Wide artwork used by the continue-watching cards and the detail hero
  /// (S28). Episodes usually carry no backdrop of their own; the server then
  /// points at the parent series through [parentBackdropItemId].
  final String? backdropTag;

  /// Every backdrop tag, for the detail page's 艺术图 row (S28).
  final List<String> backdropTags;
  final String? parentBackdropItemId;
  final String? parentBackdropTag;

  /// Episode still (S47): the series-level Thumb image Emby exposes on
  /// episodes that have no Primary of their own.
  final String? parentThumbItemId;
  final String? parentThumbTag;

  /// Transparent title art (S78): the portrait player's top bar shows it in
  /// place of the plain title text, like Yamby. Movies carry [logoTag] on
  /// their own ImageTags; episodes point at the series logo through
  /// [parentLogoItemId] / [parentLogoTag].
  final String? logoTag;
  final String? parentLogoItemId;
  final String? parentLogoTag;

  /// Series airing state (`Continuing` / `Ended`) and last air date; used for
  /// the `2004 - 现在` subtitle under a series poster (S28).
  final String? status;
  final String? endDate;

  /// `DateCreated` for the detail page's 媒体信息 line (S28).
  final String? dateCreated;

  /// ISO premiere date (`PremiereDate`), used by the 即将上映 tab (S45).
  final String? premiereDate;

  /// [premiereDate] parsed; null when absent or malformed.
  DateTime? get premiereAt {
    final String? raw = premiereDate;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Detail-only links: production studios and IMDb/TMDb/... buttons.
  final List<NamedLink> studios;
  final List<NamedLink> externalUrls;
  final List<String> remoteTrailers;

  Duration get duration => Duration(microseconds: runTimeTicks ~/ 10);

  /// `2004 - 现在` for a running series, `2004 - 2008` when it ended, a single
  /// year for movies; null when the year is unknown.
  String? get yearLabel {
    final int? year = productionYear;
    if (year == null) return null;
    if (type != 'Series') return '$year';
    if (status == 'Continuing') return '$year - 现在';
    final DateTime? ended = endDate == null
        ? null
        : DateTime.tryParse(endDate!);
    if (ended != null && ended.year != year) return '$year - ${ended.year}';
    return '$year';
  }

  /// True when a wide backdrop can be requested for this item (own or parent).
  bool get hasBackdrop =>
      (backdropTag?.isNotEmpty ?? false) ||
      (parentBackdropTag?.isNotEmpty ?? false);

  /// Optimistic favorite/played flips (S7) rebuild the item with fresh user
  /// data; every other field stays server-owned.
  MediaItem copyWith({UserItemData? userData}) {
    return MediaItem(
      id: id,
      name: name,
      type: type,
      seriesId: seriesId,
      seasonId: seasonId,
      indexNumber: indexNumber,
      parentIndexNumber: parentIndexNumber,
      seriesName: seriesName,
      productionYear: productionYear,
      runTimeTicks: runTimeTicks,
      childCount: childCount,
      imageTag: imageTag,
      overview: overview,
      userData: userData ?? this.userData,
      mediaSources: mediaSources,
      tagline: tagline,
      communityRating: communityRating,
      officialRating: officialRating,
      genres: genres,
      tags: tags,
      people: people,
      remoteTrailer: remoteTrailer,
      chapters: chapters,
      backdropTag: backdropTag,
      backdropTags: backdropTags,
      parentBackdropItemId: parentBackdropItemId,
      parentBackdropTag: parentBackdropTag,
      parentThumbItemId: parentThumbItemId,
      parentThumbTag: parentThumbTag,
      logoTag: logoTag,
      parentLogoItemId: parentLogoItemId,
      parentLogoTag: parentLogoTag,
      status: status,
      endDate: endDate,
      studios: studios,
      externalUrls: externalUrls,
      remoteTrailers: remoteTrailers,
      dateCreated: dateCreated,
      premiereDate: premiereDate,
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

String? _firstString(Object? value) {
  final List<String> values = _stringList(value);
  return values.isEmpty ? null : values.first;
}

List<NamedLink> _namedLinks(Object? value) {
  if (value is! List) return const <NamedLink>[];
  return value
      .whereType<Map<String, dynamic>>()
      .map(NamedLink.fromJson)
      .where((link) => link.name.isNotEmpty)
      .toList(growable: false);
}

List<String> _trailerUrls(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<Map<String, dynamic>>()
      .map((entry) => asString(entry['Url']))
      .whereType<String>()
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
}

/// A name plus a target: Emby's `Studios` (`{Name, Id}`) and `ExternalUrls`
/// (`{Name, Url}`) share this shape on the detail response (S7/S28).
class NamedLink {
  const NamedLink({required this.name, this.target});

  factory NamedLink.fromJson(Map<String, dynamic> json) {
    return NamedLink(
      name: asStringOr(json['Name'], ''),
      target: asString(json['Url']) ?? asString(json['Id']),
    );
  }

  final String name;
  final String? target;
}

/// Playback state kept by the server for the current user (contract §4).
class UserItemData {
  const UserItemData({
    this.played = false,
    this.positionTicks = 0,
    this.isFavorite = false,
    this.unplayedItemCount = 0,
  });

  factory UserItemData.fromJson(Map<String, dynamic> json) {
    return UserItemData(
      played: asBool(json['Played']),
      positionTicks: asInt(json['PlaybackPositionTicks']),
      isFavorite: asBool(json['IsFavorite']),
      unplayedItemCount: asInt(json['UnplayedItemCount']),
    );
  }

  final bool played;
  final int positionTicks;

  /// Favorite mark (S8); `IsFavorite` in the server's `UserData`.
  final bool isFavorite;

  /// Episodes still unwatched (`UnplayedItemCount`), shown as a badge on a
  /// series poster (S28).
  final int unplayedItemCount;

  Duration get position => Duration(microseconds: positionTicks ~/ 10);

  UserItemData copyWith({bool? played, int? positionTicks, bool? isFavorite}) {
    return UserItemData(
      played: played ?? this.played,
      positionTicks: positionTicks ?? this.positionTicks,
      isFavorite: isFavorite ?? this.isFavorite,
      unplayedItemCount: unplayedItemCount,
    );
  }
}

/// A named chapter marker (S12). [start] is the chapter's start position.
class Chapter {
  const Chapter({required this.name, required this.startTicks});

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      name: asStringOr(json['Name'], ''),
      startTicks: asInt(json['StartPositionTicks']),
    );
  }

  final String name;
  final int startTicks;

  Duration get start => Duration(microseconds: startTicks ~/ 10);
}
