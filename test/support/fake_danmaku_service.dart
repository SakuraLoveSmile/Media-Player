import 'dart:async';

import 'package:media_player/data/danmaku/danmaku_repository.dart';
import 'package:media_player/data/danmaku/models/danmaku_anime.dart';
import 'package:media_player/data/models/media_item.dart';

/// Danmaku service double for the player controller/page tests (S17/S43): no
/// HTTP, programmable result. [gate] holds the load open so tests can observe
/// the loading status; [failure] drives the controller's defensive catch.
class FakeDanmakuService implements DanmakuService {
  DanmakuLoad result = const DanmakuLoad(status: DanmakuStatus.noMatch);

  /// Thrown by [loadFor] when set. The real repository never throws; this
  /// proves the controller keeps a broken service non-fatal too.
  Object? failure;

  /// When set, [loadFor] waits for it before answering.
  Completer<void>? gate;

  /// Item ids of every [loadFor] call, in order.
  final List<String> loadRequests = <String>[];

  /// Manual-match doubles (S43).
  List<DanmakuAnime> searchResults = const <DanmakuAnime>[];
  DanmakuLoad manualResult = const DanmakuLoad(
    status: DanmakuStatus.matched,
    episodeLabel: '手动匹配 · 第 1 话',
  );
  final List<String> searchRequests = <String>[];
  final List<({String itemId, int episodeId})> manualRequests =
      <({String itemId, int episodeId})>[];
  final List<String> clearedItems = <String>[];

  @override
  Future<DanmakuLoad> loadFor(MediaItem item) async {
    loadRequests.add(item.id);
    final Completer<void>? gate = this.gate;
    if (gate != null) await gate.future;
    final Object? error = failure;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<List<DanmakuAnime>> search(String title) async {
    searchRequests.add(title);
    final Object? error = failure;
    if (error != null) throw error;
    return searchResults;
  }

  @override
  Future<DanmakuLoad> applyManual(
    MediaItem item,
    DanmakuAnime anime,
    DanmakuEpisode episode,
  ) async {
    manualRequests.add((itemId: item.id, episodeId: episode.id));
    return manualResult;
  }

  @override
  Future<void> clearManual(String itemId) async {
    clearedItems.add(itemId);
  }

  @override
  Future<bool> isManual(MediaItem item) async => false;
}
