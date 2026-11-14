import '../../models/json_read.dart';
import 'mp_downloader_torrent.dart';

/// One entry of `GET /transfer/queue` (plan S3b).
///
/// A queued job is "the download finished and MoviePilot is moving or renaming
/// the files"; the app shows 整理中 while one of these matches a request.
class MpTransferJob {
  const MpTransferJob({
    this.season = 0,
    this.media,
    this.tasks = const <MpTransferTask>[],
  });

  factory MpTransferJob.fromJson(Map<String, dynamic> json) {
    final media = asMap(json['media']);
    return MpTransferJob(
      season: asInt(json['season']),
      media: media.isEmpty ? null : MpDownloadMedia.fromJson(media),
      tasks: asMapList(json['tasks'])
          .map(MpTransferTask.fromJson)
          .toList(growable: false),
    );
  }

  final int season;
  final MpDownloadMedia? media;
  final List<MpTransferTask> tasks;

  /// Season of the job: the explicit field first, then the media summary.
  int get effectiveSeason => season != 0 ? season : (media?.season ?? 0);

  /// Download hashes this job is working on; the join key against
  /// `/download/` so a job can be tied to a request even when `media` is
  /// missing.
  Set<String> get hashes => <String>{
    for (final task in tasks)
      if (task.downloadHash.isNotEmpty) task.downloadHash,
  };

  bool get failed => tasks.any((task) => task.failed);
}

/// One file inside a [MpTransferJob].
class MpTransferTask {
  const MpTransferTask({this.state = '', this.downloadHash = ''});

  factory MpTransferTask.fromJson(Map<String, dynamic> json) {
    return MpTransferTask(
      state: asStringOr(json['state'], ''),
      downloadHash: asStringOr(json['download_hash'], ''),
    );
  }

  final String state;
  final String downloadHash;

  bool get failed => state.toLowerCase().contains('fail');
}
