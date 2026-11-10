import '../../models/json_read.dart';
import 'mp_media_info.dart';

/// One running downloader task from `GET /download/` (plan S3b).
///
/// `progress` is MoviePilot's completion percentage; the unit differs between
/// downloaders (0–1 for qBittorrent-style clients, 0–100 for others), so it is
/// normalized once here instead of at every call site.
class MpDownloaderTorrent {
  const MpDownloaderTorrent({
    this.hash = '',
    this.name = '',
    this.title = '',
    this.year = '',
    this.seasonEpisode = '',
    this.state = '',
    this.progress = 0,
    this.size = 0,
    this.downloadSpeed = '',
    this.leftTime = '',
    this.media,
  });

  static MpDownloaderTorrent? fromJson(Map<String, dynamic> json) {
    final hash = asStringOr(json['hash'], '');
    final name = asStringOr(json['name'] ?? json['title'], '');
    // A task with neither a hash nor a name cannot be matched back to a request.
    if (hash.isEmpty && name.isEmpty) return null;

    final media = asMap(json['media']);
    return MpDownloaderTorrent(
      hash: hash,
      name: name,
      title: asStringOr(json['title'], ''),
      year: asStringOr(json['year'], ''),
      seasonEpisode: asStringOr(json['season_episode'], ''),
      state: asStringOr(json['state'], 'downloading'),
      progress: normalizeProgress(asDoubleOrNull(json['progress'])),
      size: asDoubleOrNull(json['size']) ?? asInt(json['size']).toDouble(),
      downloadSpeed: asStringOr(json['dlspeed'], ''),
      leftTime: asStringOr(json['left_time'], ''),
      media: media.isEmpty ? null : MpDownloadMedia.fromJson(media),
    );
  }

  /// Completed fraction in `0..1`.
  final double progress;

  /// Task hash; the join key for transfer-queue tasks.
  final String hash;
  final String name;
  final String title;
  final String year;

  /// Display text such as `S01E02`; parsed by [season] / [episode].
  final String seasonEpisode;

  /// Downloader state (`downloading`, `seeding`, `paused`, ...).
  final String state;

  /// Size in bytes (0 when the downloader did not report it).
  final double size;

  /// Human-formatted speed/ETA as the downloader printed them; kept verbatim
  /// because parsing every downloader's format adds no value.
  final String downloadSpeed;
  final String leftTime;

  /// Media identity MoviePilot attached to the task, when it could recognize it.
  final MpDownloadMedia? media;

  bool get isComplete => progress >= 1;

  bool get isDownloading => !isComplete;

  /// Season parsed out of `season_episode`, 0 when absent.
  int get season => _seasonFrom(seasonEpisode) ?? media?.season ?? 0;

  /// Episode numbers parsed out of `season_episode`.
  List<int> get episodes => _episodesFrom(seasonEpisode);

  /// Completed percentage for display.
  int get percent => (progress * 100).round().clamp(0, 100);

  static const String _seasonPattern = r'[Ss](\d{1,2})';
  static const String _episodePattern = r'[Ee](\d{1,4})';

  static int? _seasonFrom(String text) {
    final match = RegExp(_seasonPattern).firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static List<int> _episodesFrom(String text) {
    if (text.isEmpty) return const <int>[];
    return <int>[
      for (final match in RegExp(_episodePattern).allMatches(text))
        ?int.tryParse(match.group(1)!),
    ];
  }
}

/// The media summary MoviePilot attaches to a download or transfer task.
///
/// Deliberately separate from [MpMediaRef]: this is a *display* summary whose
/// identity fields may be missing, so matching falls back to the title.
class MpDownloadMedia {
  const MpDownloadMedia({
    required this.ref,
    this.type,
    this.season = 0,
    this.episode = 0,
  });

  factory MpDownloadMedia.fromJson(Map<String, dynamic> json) {
    final seasonValue = json['season'];
    final episodeValue = json['episode'];
    return MpDownloadMedia(
      ref: MpMediaRef.fromJson(json),
      type: MpMediaType.parse(json['type']),
      season: _firstInt(seasonValue),
      episode: _firstInt(episodeValue),
    );
  }

  final MpMediaRef ref;
  final MpMediaType? type;

  /// v3 sends these as an int, a list or a display string, so only the first
  /// number is used.
  final int season;
  final int episode;

  static int _firstInt(Object? value) {
    if (value is List) return value.isEmpty ? 0 : asInt(value.first);
    if (value is int) return value;
    if (value is String) {
      final match = RegExp(r'\d+').firstMatch(value);
      return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
    }
    return asInt(value);
  }
}

/// Clamps MoviePilot's progress to the `0..1` fraction the UI renders.
///
/// Downloader adapters disagree on the unit: anything above `1` is treated as a
/// percentage, and negatives clamp to zero. A value of exactly `1` is a finished
/// download in both conventions, so it stays `1`.
double normalizeProgress(double? value) {
  if (value == null || value.isNaN || value.isInfinite) return 0;
  final fraction = value > 1 ? value / 100 : value;
  return fraction.clamp(0.0, 1.0);
}
