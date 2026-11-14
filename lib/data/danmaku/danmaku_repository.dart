import 'dart:convert';

import '../library/library_service.dart';
import '../models/media_item.dart';
import '../storage/key_value_store.dart';
import 'api/dandanplay_client.dart';
import 'models/danmaku_anime.dart';
import 'models/danmaku_comment.dart';

/// Match outcome surfaced to the player (S17). Never fatal: every failure is
/// a status line beside the 弹幕 toggle, playback keeps running.
enum DanmakuStatus { idle, loading, matched, noMatch, error }

/// One completed danmaku load: the status, the matched episode label (for the
/// status line) and the time-sorted comments.
class DanmakuLoad {
  const DanmakuLoad({
    required this.status,
    this.episodeLabel,
    this.comments = const <DanmakuComment>[],
  });

  final DanmakuStatus status;
  final String? episodeLabel;
  final List<DanmakuComment> comments;
}

/// A user-picked episode, remembered per Emby item (S43 手动匹配记忆).
class DanmakuManualMatch {
  const DanmakuManualMatch({required this.episodeId, required this.label});

  factory DanmakuManualMatch.fromJson(Map<String, dynamic> json) {
    return DanmakuManualMatch(
      episodeId: (json['episodeId'] as num?)?.toInt() ?? 0,
      label: json['label'] as String? ?? '',
    );
  }

  final int episodeId;
  final String label;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'episodeId': episodeId,
    'label': label,
  };
}

/// Danmaku delivery for one media item (S17). The player depends only on this
/// interface; tests inject a double instead of the HTTP-backed repository.
abstract interface class DanmakuService {
  /// Matches [item] against DandanPlay and fetches its comments. Never throws:
  /// failures come back as [DanmakuStatus.error] with an empty comment list.
  Future<DanmakuLoad> loadFor(MediaItem item);

  /// Free-text anime search for the manual-match sheet (S43).
  Future<List<DanmakuAnime>> search(String title);

  /// Remembers [episode] for [item] and returns its comments; a transport
  /// failure is reported as [DanmakuStatus.error] and nothing is stored.
  Future<DanmakuLoad> applyManual(
    MediaItem item,
    DanmakuAnime anime,
    DanmakuEpisode episode,
  );

  /// Forgets the manual match for [item] so the automatic match applies again.
  Future<void> clearManual(String itemId);

  /// True when [item] already has a remembered manual match.
  Future<bool> isManual(MediaItem item);
}

/// Matches a [MediaItem] to a DandanPlay episode and caches the comments in
/// memory per item (S17/S43):
///
/// - a remembered manual match wins over the automatic match;
/// - movies search by their own title, no episode filter;
/// - episodes search by the *series* title (resolved through [LibraryService],
///   because the episode's own `name` is the episode title) plus the 1-based
///   `indexNumber`.
///
/// All transport failures are swallowed into [DanmakuStatus.error] — danmaku
/// must never interrupt playback. Errors are not cached so a later retry can
/// succeed; matched / no-match results are.
class DanmakuRepository implements DanmakuService {
  // Public named parameters (`client`, `library`, `store`) with private
  // fields, the same trade-off as PlayerController's constructor.
  // ignore_for_file: prefer_initializing_formals
  DanmakuRepository({
    required DandanPlayClient client,
    LibraryService? library,
    KeyValueStore? store,
  }) : _client = client,
       _library = library,
       _store = store;

  /// KeyValueStore key for the remember-match map (`itemId` → match).
  static const String manualMatchesKey = 'danmaku.manualMatches.v1';

  final DandanPlayClient _client;
  final LibraryService? _library;
  final KeyValueStore? _store;
  final Map<String, DanmakuLoad> _cache = <String, DanmakuLoad>{};
  Map<String, DanmakuManualMatch>? _manual;

  @override
  Future<DanmakuLoad> loadFor(MediaItem item) async {
    final DanmakuLoad? cached = _cache[item.id];
    if (cached != null) return cached;

    final Map<String, DanmakuManualMatch> manual = await _manualMatches();
    final DanmakuManualMatch? picked = manual[item.id];
    if (picked != null) {
      final DanmakuLoad load = await _commentsFor(
        picked.episodeId,
        picked.label,
      );
      if (load.status != DanmakuStatus.error) _cache[item.id] = load;
      return load;
    }

    final DanmakuLoad load;
    try {
      final (String title, String? episode) = await _queryFor(item);
      final DanmakuMatch? match = await _client.matchEpisode(
        title,
        episode: episode,
      );
      if (match == null) {
        load = const DanmakuLoad(status: DanmakuStatus.noMatch);
      } else {
        final List<DanmakuComment> comments = await _client.fetchComments(
          match.episodeId,
        );
        load = DanmakuLoad(
          status: DanmakuStatus.matched,
          episodeLabel: match.episodeTitle.isEmpty
              ? match.animeTitle
              : '${match.animeTitle} · ${match.episodeTitle}',
          comments: comments,
        );
      }
    } catch (_) {
      // Non-fatal by contract; not cached so the next open can retry.
      return const DanmakuLoad(status: DanmakuStatus.error);
    }
    _cache[item.id] = load;
    return load;
  }

  @override
  Future<List<DanmakuAnime>> search(String title) async {
    final String term = title.trim();
    if (term.isEmpty) return const <DanmakuAnime>[];
    return _client.searchEpisodes(term);
  }

  @override
  Future<DanmakuLoad> applyManual(
    MediaItem item,
    DanmakuAnime anime,
    DanmakuEpisode episode,
  ) async {
    final String label = episode.title.isEmpty
        ? anime.title
        : '${anime.title} · ${episode.title}';
    final DanmakuLoad load = await _commentsFor(episode.id, label);
    if (load.status == DanmakuStatus.error) return load;
    final Map<String, DanmakuManualMatch> manual = <String, DanmakuManualMatch>{
      ...await _manualMatches(),
      item.id: DanmakuManualMatch(episodeId: episode.id, label: label),
    };
    _manual = manual;
    _cache[item.id] = load;
    await _persistManual(manual);
    return load;
  }

  @override
  Future<void> clearManual(String itemId) async {
    final Map<String, DanmakuManualMatch> manual = <String, DanmakuManualMatch>{
      ...await _manualMatches(),
    }..remove(itemId);
    _manual = manual;
    _cache.remove(itemId);
    await _persistManual(manual);
  }

  @override
  Future<bool> isManual(MediaItem item) async =>
      (await _manualMatches()).containsKey(item.id);

  Future<DanmakuLoad> _commentsFor(int episodeId, String label) async {
    try {
      final List<DanmakuComment> comments = await _client.fetchComments(
        episodeId,
      );
      return DanmakuLoad(
        status: DanmakuStatus.matched,
        episodeLabel: label,
        comments: comments,
      );
    } catch (_) {
      return const DanmakuLoad(status: DanmakuStatus.error);
    }
  }

  Future<Map<String, DanmakuManualMatch>> _manualMatches() async {
    final Map<String, DanmakuManualMatch>? loaded = _manual;
    if (loaded != null) return loaded;
    final KeyValueStore? store = _store;
    final Map<String, DanmakuManualMatch> result =
        <String, DanmakuManualMatch>{};
    if (store != null) {
      try {
        final String? raw = await store.read(manualMatchesKey);
        if (raw != null && raw.isNotEmpty) {
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            for (final MapEntry<String, dynamic> entry in decoded.entries) {
              if (entry.value is Map<String, dynamic>) {
                result[entry.key] = DanmakuManualMatch.fromJson(
                  entry.value as Map<String, dynamic>,
                );
              }
            }
          }
        }
      } catch (_) {
        // A corrupt map means no manual matches.
      }
    }
    _manual = result;
    return result;
  }

  Future<void> _persistManual(Map<String, DanmakuManualMatch> manual) async {
    final KeyValueStore? store = _store;
    if (store == null) return;
    try {
      await store.write(
        manualMatchesKey,
        jsonEncode(<String, dynamic>{
          for (final MapEntry<String, DanmakuManualMatch> entry
              in manual.entries)
            entry.key: entry.value.toJson(),
        }),
      );
    } catch (_) {
      // A failed write only loses the memory across restarts.
    }
  }

  /// Derives the search arguments from the item kind. A missing series name
  /// (no library wired, or the lookup failed) falls back to the episode's own
  /// title — a worse match, but never a broken load.
  Future<(String, String?)> _queryFor(MediaItem item) async {
    if (item.type != 'Episode') return (item.name, null);
    final int? index = item.indexNumber;
    final String? episode = index == null ? null : '$index';
    String title = item.name;
    final String? seriesId = item.seriesId;
    final LibraryService? library = _library;
    if (seriesId != null && library != null) {
      try {
        final MediaItem series = await library.item(seriesId);
        if (series.name.isNotEmpty) title = series.name;
      } catch (_) {
        // Best-effort: keep the episode title as the search term.
      }
    }
    return (title, episode);
  }
}
