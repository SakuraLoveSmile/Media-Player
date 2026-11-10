import '../models/media_request.dart';
import '../models/mp_downloader_torrent.dart';
import '../models/mp_subscribe.dart';
import '../models/mp_transfer_job.dart';
import 'poll_snapshot.dart';
import 'request_matcher.dart';

/// Derives one request's stage from one poll snapshot (plan S6).
///
/// Pure: same record + same snapshot -> same result, no IO, no clock of its
/// own (the grace window is passed in), so every rule is testable in isolation
/// and the whole derivation can be replayed from a persisted snapshot.
class RequestProgressEngine {
  const RequestProgressEngine({this.graceWindow = const Duration(seconds: 60)});

  /// How long a just-created request stays "submitted" while MoviePilot has not
  /// listed it yet. MoviePilot's list is eventually consistent right after
  /// `POST /subscribe/`, and showing "no resource" in that window would be a
  /// lie the user cannot act on.
  final Duration graceWindow;

  /// Derives the request's stage and the values the card renders.
  ///
  /// [now] is only used for the grace window; [embyItemId] is the verified
  /// library lookup result, if the controller already performed one.
  RequestProgress derive(
    MediaRequest request,
    PollSnapshot snapshot, {
    required DateTime now,
    String? embyItemId,
  }) {
    // A cancelled request never moves again: the user's decision outranks any
    // late poll answer.
    if (request.isCancelled) {
      return RequestProgress(stage: RequestStage.cancelled, message: '已取消求片');
    }

    // The verified Emby hit wins over everything: the item is playable, which
    // is the only thing the user ultimately wants.
    final libraryId = embyItemId ?? request.embyItemId;
    if (libraryId != null && libraryId.isNotEmpty) {
      return RequestProgress(
        stage: RequestStage.inLibrary,
        message: '已入库，可以播放',
        embyItemId: libraryId,
        archived: true,
      );
    }

    final matcher = RequestMatcher(snapshot);
    final active = matcher.subscription(request);
    final archived = matcher.archived(request);
    final downloads = matcher.downloads(request);
    final jobs = matcher.transferJobs(request);
    final transfers = matcher.transfers(request);

    // 1. Organizing beats downloading: once files are being moved, the download
    //    is finished and the queue is the newer signal.
    if (jobs.isNotEmpty && !matcher.hasActiveDownload(request)) {
      return _organizing(jobs);
    }

    // 2. A successful transfer means the files reached the library; Emby still
    //    has to scan them, so the stage stays pending until the lookup hits.
    if (transfers.isNotEmpty) {
      return RequestProgress(
        stage: RequestStage.organizedPendingLibrary,
        message: '整理完成，等待 Emby 入库',
        archived: active == null,
        transferHash: transfers.first.downloadHash,
      );
    }

    // 3. Downloads in flight, or already submitted to the downloader.
    if (downloads.isNotEmpty) {
      return _downloading(downloads, request, active: active);
    }

    // 4. Subscription state. `submitted_count` separates "still looking" from
    //    "handed to the downloader": a submitted download can take a while to
    //    appear in `/download/`, and pretending otherwise would show
    //    "no resource" for a request that is actually progressing.
    if (active != null) {
      return _fromSubscription(active, request, now: now, jobs: jobs);
    }

    // 5. Gone from the active list. If it is in the history it finished; if it
    //    is nowhere and past the grace window, MoviePilot dropped it.
    if (archived != null) {
      return RequestProgress(
        stage: RequestStage.organizedPendingLibrary,
        message: '订阅已完成，等待 Emby 入库',
        archived: true,
        completedEpisodes: archived.effectiveCompletedEpisode,
        totalEpisodes: archived.totalEpisode,
      );
    }

    final age = now.difference(request.createdAt);
    if (age < graceWindow) {
      return RequestProgress(
        stage: RequestStage.submitted,
        message: '已提交，等待 MoviePilot 搜索',
      );
    }

    // Nothing anywhere: the subscription was deleted outside the app, or the
    // create call never really landed.
    return RequestProgress(
      stage: request.stage == RequestStage.noResource
          ? RequestStage.noResource
          : RequestStage.searching,
      message: '尚未在 MoviePilot 中看到该订阅',
      stale: true,
    );
  }

  RequestProgress _organizing(List<MpTransferJob> jobs) {
    final failed = jobs.any((job) => job.failed);
    return RequestProgress(
      stage: RequestStage.organizing,
      message: failed ? '整理遇到问题，MoviePilot 正在重试' : '正在整理文件到媒体库',
    );
  }

  RequestProgress _downloading(
    List<MpDownloaderTorrent> downloads,
    MediaRequest request, {
    required MpSubscribe? active,
  }) {
    // Weighted by size so two uneven episodes do not read as 50% each; when no
    // size is known the tasks are weighted equally.
    final totalSize = downloads.fold<double>(
      0,
      (sum, torrent) => sum + (torrent.size > 0 ? torrent.size : 1),
    );
    final done = downloads.fold<double>(
      0,
      (sum, torrent) => sum + torrent.progress * (torrent.size > 0 ? torrent.size : 1),
    );
    final fraction = totalSize <= 0 ? 0.0 : (done / totalSize).clamp(0.0, 1.0);

    final speed = downloads
        .map((torrent) => torrent.downloadSpeed)
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final eta = downloads
        .map((torrent) => torrent.leftTime)
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    return RequestProgress(
      stage: RequestStage.downloading,
      // Even at 100% the files are not usable yet: MoviePilot still has to move
      // them, and the next stage follows in a later round.
      message: fraction >= 1 ? '下载完成，等待整理' : '正在下载',
      progress: fraction,
      downloadSpeed: speed,
      eta: eta,
      activeTaskCount: downloads.length,
      completedEpisodes: request.isSeries
          ? _completedEpisodes(downloads)
          : 0,
      totalEpisodes: active?.totalEpisode ?? request.totalEpisodes,
    );
  }

  RequestProgress _fromSubscription(
    MpSubscribe subscribe,
    MediaRequest request, {
    required DateTime now,
    required List<MpTransferJob> jobs,
  }) {
    final status = subscribe.executionStatus;

    if (subscribe.isPaused) {
      return RequestProgress(
        stage: RequestStage.paused,
        message: '已在 MoviePilot 中暂停',
      );
    }
    if (status.hasError || status.failed) {
      return RequestProgress(
        stage: RequestStage.noResource,
        message: status.hasError
            ? '搜索出错，将持续重试'
            : '暂未找到资源，持续订阅中',
        canSearchNow: true,
        completedEpisodes: subscribe.effectiveCompletedEpisode,
        totalEpisodes: subscribe.totalEpisode,
      );
    }
    if (status.submittedCount > 0) {
      // The round added downloads but `/download/` does not show them yet.
      return RequestProgress(
        stage: RequestStage.downloading,
        message: '已添加下载，等待下载器',
        progress: null,
        completedEpisodes: subscribe.effectiveCompletedEpisode,
        totalEpisodes: subscribe.totalEpisode,
      );
    }
    if (jobs.isNotEmpty) {
      return const RequestProgress(
        stage: RequestStage.organizing,
        message: '正在整理文件到媒体库',
      );
    }
    // v3 reports a finished round as state/phase "completed", which means the
    // round ended — not that the subscription is done. A finished round that
    // submitted nothing found no resource; saying "已提交，等待搜索" forever
    // would hide the one fact the user can act on.
    final roundFinished =
        status.isCompletedRound || status.phase == 'completed';
    if (status.isRunning || roundFinished) {
      return RequestProgress(
        // A run in progress is searching; a finished round with nothing
        // submitted is "没找到资源，等下一次".
        stage: status.isRunning
            ? RequestStage.searching
            : RequestStage.noResource,
        message: status.isRunning
            ? (status.phase == 'submitting' ? '正在提交下载' : '正在搜索资源')
            : '这一轮没有找到资源，会继续搜索',
        canSearchNow: true,
        completedEpisodes: subscribe.effectiveCompletedEpisode,
        totalEpisodes: subscribe.totalEpisode,
        nextRunAt: status.nextRunAt,
      );
    }

    // A new subscription (`N`) or a state the app does not know yet: it exists,
    // nothing is happening, so it is queued for the next round.
    return RequestProgress(
      stage: RequestStage.submitted,
      message: '已提交，等待 MoviePilot 搜索',
      canSearchNow: true,
      completedEpisodes: subscribe.effectiveCompletedEpisode,
      totalEpisodes: subscribe.totalEpisode,
    );
  }

  /// Episodes this round's tasks have finished, capped at the season's total.
  int _completedEpisodes(List<MpDownloaderTorrent> downloads) {
    final episodes = <int>{};
    for (final torrent in downloads) {
      if (!torrent.isComplete) continue;
      episodes.addAll(torrent.episodes);
    }
    return episodes.length;
  }
}

/// The result of one derivation, ready for the card and for persistence.
class RequestProgress {
  const RequestProgress({
    required this.stage,
    this.message = '',
    this.progress,
    this.downloadSpeed = '',
    this.eta = '',
    this.activeTaskCount = 0,
    this.completedEpisodes = 0,
    this.totalEpisodes = 0,
    this.canSearchNow = false,
    this.embyItemId,
    this.archived = false,
    this.stale = false,
    this.nextRunAt = '',
    this.transferHash = '',
  });

  final RequestStage stage;

  /// One line of user-facing copy explaining the stage.
  final String message;

  /// Download fraction in `0..1`; null means "not determined yet".
  final double? progress;
  final String downloadSpeed;
  final String eta;
  final int activeTaskCount;
  final int completedEpisodes;
  final int totalEpisodes;

  /// Whether the "立即搜索" action makes sense right now.
  final bool canSearchNow;

  /// Verified Emby item id, once the library lookup succeeded.
  final String? embyItemId;

  /// The subscription has left MoviePilot's active list.
  final bool archived;

  /// The request is no longer visible in MoviePilot at all.
  final bool stale;

  /// MoviePilot's next scheduled search, for the searching stage.
  final String nextRunAt;

  /// Transfer row this derivation matched, kept for diagnostics.
  final String transferHash;

  /// Writes the derived values onto the stored record.
  MediaRequest applyTo(MediaRequest request) {
    return request.copyWith(
      stage: stage,
      message: message,
      progressPercent: progress,
      downloadSpeed: downloadSpeed,
      eta: eta,
      activeTaskCount: activeTaskCount,
      completedEpisodes: completedEpisodes,
      totalEpisodes: totalEpisodes,
      embyItemId: embyItemId ?? request.embyItemId,
      archived: archived || stage == RequestStage.inLibrary,
      lastUpdatedAt: request.lastUpdatedAt,
    );
  }
}
