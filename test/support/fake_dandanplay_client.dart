import 'package:dio/dio.dart';
import 'package:media_player/data/danmaku/api/dandanplay_client.dart';
import 'package:media_player/data/danmaku/models/danmaku_anime.dart';
import 'package:media_player/data/danmaku/models/danmaku_comment.dart';

/// DandanPlay client double for the repository tests (S17): no HTTP. The
/// unused [Dio] is never called because every public method is overridden.
class FakeDandanPlayClient extends DandanPlayClient {
  FakeDandanPlayClient() : super(Dio());

  /// Returned by [matchEpisode]; null drives the no-match path.
  DanmakuMatch? matchResult;

  /// Thrown by [matchEpisode] when set (transport failure).
  Object? matchFailure;

  /// Returned by [fetchComments].
  List<DanmakuComment> comments = <DanmakuComment>[];

  /// Thrown by [fetchComments] when set.
  Object? commentsFailure;

  /// Every match call, in order, so tests can assert the movie-vs-series
  /// search arguments.
  final List<({String title, String? episode})> matchRequests =
      <({String title, String? episode})>[];

  /// Every comment fetch, in order.
  final List<int> commentRequests = <int>[];

  @override
  Future<DanmakuMatch?> matchEpisode(String title, {String? episode}) async {
    matchRequests.add((title: title, episode: episode));
    final Object? error = matchFailure;
    if (error != null) throw error;
    return matchResult;
  }

  @override
  Future<int?> match(String title, {String? episode}) async =>
      (await matchEpisode(title, episode: episode))?.episodeId;

  @override
  Future<List<DanmakuComment>> fetchComments(int episodeId) async {
    commentRequests.add(episodeId);
    final Object? error = commentsFailure;
    if (error != null) throw error;
    return comments;
  }
}
