import '../../models/json_read.dart';

/// One episode of a DandanPlay anime (S17): the id comments are fetched by.
class DanmakuEpisode {
  const DanmakuEpisode({required this.id, required this.title});

  factory DanmakuEpisode.fromJson(Map<String, dynamic> json) {
    return DanmakuEpisode(
      id: asInt(json['episodeId']),
      title: asStringOr(json['episodeTitle'], ''),
    );
  }

  final int id;
  final String title;
}

/// One anime entry of the `search/episodes` reply (S17), in the API's own
/// relevance order.
class DanmakuAnime {
  const DanmakuAnime({
    required this.id,
    required this.title,
    required this.episodes,
  });

  factory DanmakuAnime.fromJson(Map<String, dynamic> json) {
    return DanmakuAnime(
      id: asInt(json['animeId']),
      title: asStringOr(json['animeTitle'], ''),
      episodes: asMapList(json['episodes'])
          .map(DanmakuEpisode.fromJson)
          .toList(growable: false),
    );
  }

  final int id;
  final String title;
  final List<DanmakuEpisode> episodes;
}

/// A successful title/episode match: the comment endpoint id plus the labels
/// the player surfaces as the non-fatal match status (S17).
class DanmakuMatch {
  const DanmakuMatch({
    required this.episodeId,
    required this.animeTitle,
    required this.episodeTitle,
  });

  final int episodeId;
  final String animeTitle;
  final String episodeTitle;
}
