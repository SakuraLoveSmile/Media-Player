import '../models/media_request.dart';
import '../models/mp_downloader_torrent.dart';
import '../models/mp_media_info.dart';
import '../models/mp_subscribe.dart';
import '../models/mp_transfer_history.dart';
import '../models/mp_transfer_job.dart';
import 'poll_snapshot.dart';

/// Ties a stored [MediaRequest] to what MoviePilot currently reports (plan S6).
///
/// Matching is layered on purpose, because a wrong match shows another title's
/// progress under this request — the most confusing failure this feature can
/// have. Order: exact identity pair + season, then TMDB id + season, then — only
/// for requests whose identity is missing — normalized title + year + season.
/// Download and transfer tasks additionally join on `download_hash`.
class RequestMatcher {
  const RequestMatcher(this._snapshot);

  final PollSnapshot _snapshot;

  /// The active subscription belonging to [request], or null.
  ///
  /// Prefers the recorded subscription id: it is exact, and it survives a
  /// title becoming ambiguous (a remake with the same name).
  MpSubscribe? subscription(MediaRequest request) {
    final id = request.subscribeId;
    if (id != null) {
      for (final subscribe in _snapshot.subscribes) {
        if (subscribe.id == id) return subscribe;
      }
    }
    return _best(_snapshot.subscribes, request);
  }

  /// The archived subscription belonging to [request], or null.
  ///
  /// Only the history of the request's own media type is consulted, so a movie
  /// request can never match a series archive.
  MpSubscribe? archived(MediaRequest request) {
    final candidates = request.isMovie
        ? _snapshot.movieHistory
        : _snapshot.seriesHistory;
    return _best(candidates, request);
  }

  /// Downloader tasks belonging to [request], newest signal first.
  ///
  /// A series request aggregates every episode task of its season, so "3 of 10
  /// episodes" is the sum of what the downloader is working on.
  List<MpDownloaderTorrent> downloads(MediaRequest request) {
    final matched = <MpDownloaderTorrent>[];
    for (final torrent in _snapshot.downloads) {
      if (!_downloadBelongs(torrent, request)) continue;
      matched.add(torrent);
    }
    return matched;
  }

  /// Transfer-queue jobs belonging to [request].
  ///
  /// A job matches on the media identity *or* on a `download_hash` that already
  /// matched this request, because MoviePilot often drops `media` once the file
  /// is being moved.
  List<MpTransferJob> transferJobs(MediaRequest request) {
    final hashes = <String>{
      for (final torrent in downloads(request))
        if (torrent.hash.isNotEmpty) torrent.hash,
    };

    return <MpTransferJob>[
      for (final job in _snapshot.transferQueue)
        if (_jobBelongs(job, request, hashes)) job,
    ];
  }

  /// Successful transfers belonging to [request].
  List<MpTransferHistory> transfers(MediaRequest request) {
    final hashes = <String>{
      for (final torrent in downloads(request))
        if (torrent.hash.isNotEmpty) torrent.hash,
    };

    return <MpTransferHistory>[
      for (final row in _snapshot.transferHistory)
        if (row.succeeded && _historyBelongs(row, request, hashes)) row,
    ];
  }

  /// Whether the request has any download task that is still transferring.
  bool hasActiveDownload(MediaRequest request) =>
      downloads(request).any((torrent) => torrent.isDownloading);

  bool _downloadBelongs(MpDownloaderTorrent torrent, MediaRequest request) {
    final media = torrent.media;
    if (media != null && _refBelongs(media.ref, request)) {
      return _seasonBelongs(media.season, request) ||
          _seasonBelongs(torrent.season, request);
    }
    // Without a media summary the only usable keys are the season/episode text
    // and the title, and neither is conclusive on its own.
    if (media == null) {
      if (request.isSeries) {
        final season = torrent.season;
        // A series download is only attributable when it names the season.
        if (season == 0 || !_seasonBelongs(season, request)) return false;
        return _titleLooksLike(torrent.title.isNotEmpty ? torrent.title : torrent.name, request);
      }
      if (torrent.season != 0) return false;
      return _titleBelongs(torrent.title, torrent.name, torrent.year, request);
    }
    // A media summary exists but points at another title.
    return false;
  }

  bool _jobBelongs(
    MpTransferJob job,
    MediaRequest request,
    Set<String> hashes,
  ) {
    if (job.hashes.any(hashes.contains)) return true;

    final media = job.media;
    if (media == null) return false;
    if (!_refBelongs(media.ref, request)) return false;
    return _seasonBelongs(job.effectiveSeason, request) ||
        _seasonBelongs(media.season, request);
  }

  bool _historyBelongs(
    MpTransferHistory row,
    MediaRequest request,
    Set<String> hashes,
  ) {
    if (row.downloadHash.isNotEmpty && hashes.contains(row.downloadHash)) {
      return true;
    }
    if (!_refBelongs(row.ref, request)) return false;
    return _seasonBelongs(row.season, request);
  }

  /// Layered identity check for anything carrying an [MpMediaRef].
  bool _refBelongs(MpMediaRef ref, MediaRequest request) {
    final wanted = request.ref;
    if (wanted.identityKey != null && ref.identityKey != null) {
      return wanted.identityKey == ref.identityKey;
    }
    if (wanted.tmdbId != null && ref.tmdbId != null) {
      return wanted.tmdbId == ref.tmdbId;
    }
    // Only now fall back to the title, and only when at least one side is
    // unidentified: two different TMDB entries are never the same title.
    if (wanted.identityKey != null && ref.identityKey != null) return false;
    return _titleBelongs(
      ref.title,
      ref.title,
      ref.year.isNotEmpty ? ref.year : request.year,
      request,
    );
  }

  /// Whether [season] satisfies the request's season.
  ///
  /// Season 0 means "the whole title": a movie has only one season, and a
  /// whole-series subscription accepts any season's download.
  bool _seasonBelongs(int season, MediaRequest request) {
    if (request.season == 0) return true;
    if (season == 0) return true;
    return season == request.season;
  }

  /// Title comparison that tolerates case, spacing and punctuation but not a
  /// different year.
  bool _titleBelongs(
    String title,
    String fallback,
    String year,
    MediaRequest request,
  ) {
    final candidate = title.isNotEmpty ? title : fallback;
    if (year.isNotEmpty && request.year.isNotEmpty && year != request.year) {
      return false;
    }
    return _titleLooksLike(candidate, request);
  }

  static bool _titleLooksLike(String candidate, MediaRequest request) {
    final left = _normalize(candidate);
    final right = _normalize(request.title);
    if (left.isEmpty || right.isEmpty) return false;
    return left == right || left.contains(right) || right.contains(left);
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '')
        .trim();
  }

  /// Picks the highest-scoring candidate; returns null when nothing scores.
  MpSubscribe? _best(List<MpSubscribe> items, MediaRequest request) {
    MpSubscribe? best;
    var bestScore = 0;
    for (final item in items) {
      if (item.type != null && item.type != request.type) continue;
      final score = _score(item.ref, item.season, request);
      // A later, equally good candidate does not replace the earlier one, so
      // the result is stable across rounds.
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return best;
  }

  int _score(MpMediaRef ref, int season, MediaRequest request) {
    final wanted = request.ref;
    var score = 0;

    if (wanted.identityKey != null && ref.identityKey != null) {
      if (wanted.identityKey != ref.identityKey) return 0;
      score = 100;
    } else if (wanted.tmdbId != null && ref.tmdbId != null) {
      if (wanted.tmdbId != ref.tmdbId) return 0;
      score = 80;
    } else {
      if (ref.year.isNotEmpty &&
          request.year.isNotEmpty &&
          ref.year != request.year) {
        return 0;
      }
      if (!_titleLooksLike(ref.title, request)) return 0;
      score = 40;
    }

    // A season-specific match beats a whole-title one, so two subscriptions of
    // the same show resolve to the right card.
    if (request.season != 0 && season == request.season) {
      score += 20;
    } else if (request.season != 0 && season != 0) {
      // Explicitly another season: this is not our subscription.
      return 0;
    }
    return score;
  }
}
