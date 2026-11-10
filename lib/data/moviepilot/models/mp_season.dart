import '../../models/json_read.dart';

/// One season of a searched series (`GET /media/seasons`, plan S3a).
///
/// MoviePilot resolves the season list from the same `MediaInfo` it returned
/// for a search, so the picker can offer "第 1 季 (10 集)" without a second
/// search.
class MpSeason {
  const MpSeason({
    required this.seasonNumber,
    this.name = '',
    this.episodeCount = 0,
    this.airDate = '',
    this.poster = '',
    this.overview = '',
    this.vote = 0,
  });

  static MpSeason? fromJson(Map<String, dynamic> json) {
    final number =
        asIntOrNull(json['season_number']) ?? asIntOrNull(json['season']);
    if (number == null) return null;
    return MpSeason(
      seasonNumber: number,
      name: asStringOr(json['name'], ''),
      episodeCount: asIntOrNull(json['episode_count']) ?? _episodeCount(json),
      airDate: asStringOr(json['air_date'], ''),
      poster: asStringOr(json['poster_path'] ?? json['poster'], ''),
      overview: asStringOr(json['overview'], ''),
      vote: asDouble(json['vote_average']),
    );
  }

  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String airDate;
  final String poster;
  final String overview;
  final double vote;

  /// Label for the picker: `第 1 季`, plus the episode count when known.
  String get label {
    final base = name.isNotEmpty && name != '第 $seasonNumber 季'
        ? '第 $seasonNumber 季 · $name'
        : '第 $seasonNumber 季';
    return episodeCount > 0 ? '$base（$episodeCount 集）' : base;
  }

  static int _episodeCount(Map<String, dynamic> json) {
    final episodes = json['episodes'];
    if (episodes is List) return episodes.length;
    return 0;
  }
}
