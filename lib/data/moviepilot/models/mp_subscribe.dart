import '../../models/json_read.dart';
import 'mp_media_info.dart';

/// Current execution state attached to an active subscription (plan S3a).
///
/// Every field is optional: v3 only attaches `execution_status` when a batch
/// record exists, so older or freshly created subscriptions have none.
/// `submittedCount` is the decisive signal — it separates "found nothing yet"
/// from "already handed downloads to the downloader".
class MpExecutionStatus {
  const MpExecutionStatus({
    this.state = '',
    this.phase = '',
    this.error = '',
    this.submittedCount = 0,
    this.updatedAt = '',
    this.nextRunAt = '',
    this.canCancel = false,
  });

  factory MpExecutionStatus.fromJson(Map<String, dynamic> json) {
    return MpExecutionStatus(
      state: asStringOr(json['state'], ''),
      phase: asStringOr(json['phase'], ''),
      error: asStringOr(json['error'], ''),
      submittedCount: asInt(json['submitted_count']),
      updatedAt: asStringOr(json['updated_at'], ''),
      nextRunAt: asStringOr(json['next_run_at'], ''),
      canCancel: asBoolLoose(json['can_cancel']),
    );
  }

  /// Raw business state. `R` running, `S` paused, `P` failed.
  final String state;

  /// Finer phase inside [state]; unknown values are treated as "searching".
  final String phase;

  /// Non-empty when the last round failed, e.g. no site could be searched.
  final String error;

  /// Downloads this round added. `0` with a running state means "still
  /// searching", above `0` means "handed to the downloader".
  final int submittedCount;
  final String updatedAt;
  final String nextRunAt;
  final bool canCancel;

  bool get hasError => error.isNotEmpty;

  /// The execution round is in progress.
  ///
  /// v3 spells this `running` (observed on 3.2.5); a bare `R` is the older
  /// spelling and still appears in some payloads, so both count.
  bool get isRunning => state == 'running' || state == 'R';

  /// The round finished. This says the *round* ended, never that the
  /// subscription is done: a finished round can have found nothing.
  bool get isCompletedRound => state == 'completed';

  /// The subscription is paused.
  bool get isPaused => state == 'S' || state == 'paused';

  /// A round that did not find anything: `P` is v3's "failed / gave up".
  bool get failed => state == 'P' || state == 'failed';

  /// True while the round is looking for a resource rather than downloading.
  bool get isSearching => submittedCount == 0;

  static const MpExecutionStatus empty = MpExecutionStatus();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'state': state,
    'phase': phase,
    'error': error,
    'submitted_count': submittedCount,
    'updated_at': updatedAt,
    'next_run_at': nextRunAt,
    'can_cancel': canCancel,
  };
}

/// One subscription as `GET /subscribe/` and its history return it (plan S3a).
class MpSubscribe {
  const MpSubscribe({
    required this.id,
    required this.ref,
    this.name = '',
    this.year = '',
    this.type,
    this.season = 0,
    this.totalEpisode = 0,
    this.lackEpisode = 0,
    this.completedEpisode = 0,
    this.state = 'R',
    this.poster = '',
    this.vote = 0,
    this.overview = '',
    this.executionStatus = MpExecutionStatus.empty,
  });

  static MpSubscribe? fromJson(Map<String, dynamic> json) {
    final id = asIntOrNull(json['id']);
    if (id == null) return null;
    final type = MpMediaType.parse(json['type']);
    return MpSubscribe(
      id: id,
      ref: MpMediaRef.fromJson(json),
      name: asStringOr(json['name'], ''),
      year: asStringOr(json['year'], ''),
      type: type,
      season: asInt(json['season']),
      totalEpisode: asInt(json['total_episode']),
      lackEpisode: asInt(json['lack_episode']),
      completedEpisode: asInt(json['completed_episode']),
      state: asStringOr(json['state'], 'R'),
      poster: asStringOr(json['poster'], ''),
      vote: asDouble(json['vote']),
      overview: asStringOr(json['description'], ''),
      executionStatus: MpExecutionStatus.fromJson(
        asMap(json['execution_status']),
      ),
    );
  }

  final int id;
  final MpMediaRef ref;
  final String name;
  final String year;
  final MpMediaType? type;

  /// Season for a series subscription; 0 for a movie or "all seasons".
  final int season;
  final int totalEpisode;
  final int lackEpisode;
  final int completedEpisode;

  /// v3 subscription state: `N` new, `R` running, `S` paused, `P` failed.
  final String state;
  final String poster;
  final double vote;
  final String overview;
  final MpExecutionStatus executionStatus;

  bool get isSeries => type == MpMediaType.series;

  /// The subscription itself is paused (`S` on 3.2.5).
  bool get isPaused => state == 'S' || state == 'paused';

  /// Episodes already in the library, preferring v3's derived value and
  /// falling back to `total - lack` for older payloads.
  int get effectiveCompletedEpisode {
    if (completedEpisode > 0) return completedEpisode;
    if (totalEpisode > 0) {
      return (totalEpisode - lackEpisode).clamp(0, totalEpisode);
    }
    return 0;
  }

  /// The key 求片 records are matched on: a season-specific subscription and a
  /// whole-series one must not collide.
  String? get matchKey {
    final identity = ref.identityKey;
    if (identity == null) return null;
    return '$identity#s$season';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'year': year,
    if (type != null) 'type': type!.wire,
    'season': season,
    'total_episode': totalEpisode,
    'lack_episode': lackEpisode,
    'completed_episode': completedEpisode,
    'state': state,
    'poster': poster,
    'vote': vote,
    'description': overview,
    'execution_status': executionStatus.toJson(),
    ...ref.toJson(),
  };
}

/// Body of `POST /subscribe/` (plan S3a).
///
/// v3 takes the very same shape it returns, and the media identity pair is
/// mandatory: `media_source` and `media_id` must both be present.
class MpSubscribeDraft {
  const MpSubscribeDraft({
    required this.ref,
    required this.type,
    required this.name,
    this.year = '',
    this.season = 0,
  });

  factory MpSubscribeDraft.fromMedia(MpMediaInfo media, {int season = 0}) {
    final type = media.type;
    if (type == null) {
      throw ArgumentError.value(media, 'media', 'missing movie/series type');
    }
    return MpSubscribeDraft(
      ref: media.ref,
      type: type,
      name: media.title,
      year: media.year,
      season: type == MpMediaType.series ? season : 0,
    );
  }

  final MpMediaRef ref;
  final MpMediaType type;
  final String name;
  final String year;
  final int season;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'year': year,
    'type': type.wire,
    'media_source': ref.source.wire,
    'media_id': ref.mediaId,
    if (type == MpMediaType.series) 'season': season,
    if (ref.tmdbId != null) 'tmdbid': ref.tmdbId,
  };
}
