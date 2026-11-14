import '../../models/json_read.dart';

/// Which MoviePilot media source an entry came from (求片 plan S3a).
///
/// v3 identifies media by the pair `(media_source, media_id)`: a TMDB id is
/// only meaningful together with `themoviedb`. The app asks for TMDB first
/// because that is what Emby's `AnyProviderIdEquals=tmdbid.*` lookup uses, so a
/// later "is it in the library?" check can reuse the same id.
enum MpMediaSource {
  tmdb('themoviedb'),
  douban('douban'),
  bangumi('bangumi'),
  anilist('anilist'),
  unknown('');

  const MpMediaSource(this.wire);

  /// The value MoviePilot uses in JSON and query strings.
  final String wire;

  static MpMediaSource parse(Object? value) {
    final text = asString(value)?.toLowerCase();
    if (text == null) return MpMediaSource.unknown;
    for (final source in MpMediaSource.values) {
      if (source.wire == text) return source;
    }
    return MpMediaSource.unknown;
  }
}

/// 电影 / 电视剧 as MoviePilot spells them (求片 plan S3a).
///
/// v3 sends and expects the Chinese labels literally, both in `type` fields and
/// in the `mtype` query of `/mediaserver/exists`.
enum MpMediaType {
  movie('电影'),
  series('电视剧');

  const MpMediaType(this.wire);

  final String wire;

  /// Null when MoviePilot reports something the app does not handle (music,
  /// collections), so a stray result is dropped instead of mislabelled.
  static MpMediaType? parse(Object? value) {
    final text = asString(value);
    if (text == null) return null;
    for (final type in MpMediaType.values) {
      if (type.wire == text) return type;
    }
    return null;
  }
}

/// Immutable media identity: what makes two MoviePilot entries "the same title"
/// (求片 plan S6 primary key).
class MpMediaRef {
  const MpMediaRef({
    required this.source,
    required this.mediaId,
    this.tmdbId,
    this.title = '',
    this.year = '',
  });

  factory MpMediaRef.fromJson(Map<String, dynamic> json) {
    return MpMediaRef(
      source: MpMediaSource.parse(json['media_source']),
      mediaId: _id(json['media_id']),
      tmdbId: asIntOrNull(json['tmdb_id']) ?? asIntOrNull(json['tmdbid']),
      title: asStringOr(json['title'], ''),
      year: asStringOr(json['year'], ''),
    );
  }

  /// `media_id` arrives as a string from TMDB/Douban and as a number from some
  /// plugin sources; the identity key must be the same string either way.
  static String _id(Object? value) {
    if (value is num) return value.toInt().toString();
    return asStringOr(value, '').trim();
  }

  final MpMediaSource source;
  final String mediaId;

  /// Auxiliary TMDB id; v3 returns it as `tmdb_id` and older payloads use
  /// `tmdbid`. Only used to look the item up in Emby, never as the primary key.
  final int? tmdbId;
  final String title;
  final String year;

  /// True when the pair v3 treats as an identity is present.
  bool get isIdentified =>
      source != MpMediaSource.unknown && mediaId.isNotEmpty;

  /// The key two entries must share to be the same media. Null when the entry
  /// is not identified, so callers fall back to title/year matching instead.
  String? get identityKey => isIdentified ? '${source.wire}:$mediaId' : null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'media_source': source.wire,
    'media_id': mediaId,
    if (tmdbId != null) 'tmdb_id': tmdbId,
    'title': title,
    'year': year,
  };

  @override
  String toString() => 'MpMediaRef(${identityKey ?? title}/$year)';
}

/// One `/media/search` hit (求片 plan S3a).
///
/// v3 answers with a partial `MediaInfo`, so every field is optional and the
/// entry is dropped when it carries neither an identity nor a title.
class MpMediaInfo {
  const MpMediaInfo({
    required this.ref,
    this.type,
    this.poster,
    this.backdrop,
    this.overview = '',
    this.vote = 0,
    this.numberOfSeasons = 0,
    this.numberOfEpisodes = 0,
    this.season = 0,
    this.year = '',
    this.title = '',
  });

  /// Returns null for a result the app cannot act on (music, a person, an entry
  /// with no identity and no title).
  static MpMediaInfo? fromJson(Map<String, dynamic> json) {
    final type = MpMediaType.parse(json['type']);
    if (type == null) return null;

    final ref = MpMediaRef.fromJson(json);
    final title = asStringOr(json['title'], ref.title);
    if (!ref.isIdentified && title.isEmpty) return null;

    return MpMediaInfo(
      ref: ref,
      type: type,
      title: title,
      year: asStringOr(json['year'], ref.year),
      poster: _image(json['poster_path'] ?? json['poster']),
      backdrop: _image(json['backdrop_path'] ?? json['backdrop']),
      overview: asStringOr(json['overview'], ''),
      vote: asDouble(json['vote_average']),
      numberOfSeasons: asInt(json['number_of_seasons']),
      numberOfEpisodes: asInt(json['number_of_episodes']),
      season: asInt(json['season']),
    );
  }

  final MpMediaRef ref;
  final MpMediaType? type;
  final String title;
  final String year;

  /// Absolute poster URL when the source returned one; TMDB gives a path, so a
  /// bare path stays as-is and the card falls back to a placeholder.
  final String? poster;
  final String? backdrop;
  final String overview;
  final double vote;
  final int numberOfSeasons;
  final int numberOfEpisodes;

  /// Season the source resolved by itself (0 when it did not).
  final int season;

  bool get isMovie => type == MpMediaType.movie;

  bool get isSeries => type == MpMediaType.series;

  /// Poster URL usable by `Image.network`, or null when there is none.
  Uri? get posterUri {
    final raw = poster;
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.hasScheme) return uri;
    return Uri.tryParse('https://image.tmdb.org/t/p/w342$raw');
  }

  static String? _image(Object? value) {
    final text = asString(value);
    return text;
  }
}
