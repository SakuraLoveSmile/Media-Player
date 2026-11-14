import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/errors/dandanplay_exception.dart';
import '../../../core/logging/redact.dart';
import '../../models/json_read.dart';
import '../models/danmaku_anime.dart';
import '../models/danmaku_comment.dart';

typedef DandanPlayLogSink = void Function(String line);

/// Sole outbound HTTP path for the public DandanPlay API (S17 弹幕).
///
/// Same shape as [EmbyHttpClient] / [MoviePilotHttpClient]: absolute [Uri] per
/// request, plain-text responses decoded here so a malformed body maps to
/// `serverError`, redacted log line per request, explicit connect/receive
/// timeouts. DandanPlay needs no auth and no Emby session, so this client is
/// deliberately separate from the Emby one. Transport failures surface as
/// [DandanPlayException]; [DanmakuRepository] is the non-fatal boundary that
/// turns them into an empty load.
class DandanPlayClient {
  DandanPlayClient(
    this._dio, {
    this.baseUrl = 'https://api.dandanplay.net',
    this.defaultConnectTimeout = const Duration(seconds: 5),
    this.defaultReceiveTimeout = const Duration(seconds: 10),
    DandanPlayLogSink? logSink,
  }) : _log = logSink ?? _discard;

  final Dio _dio;
  final String baseUrl;
  final Duration defaultConnectTimeout;
  final Duration defaultReceiveTimeout;
  final DandanPlayLogSink _log;

  static void _discard(String _) {}

  /// `GET /api/v2/search/episodes?anime={title}&episode={ep}`. The optional
  /// [episode] narrows the reply server-side (a plain number like `3` works).
  Future<List<DanmakuAnime>> searchEpisodes(
    String title, {
    String? episode,
  }) async {
    final Object? body = await _getJson(
      Uri.parse('$baseUrl/api/v2/search/episodes').replace(
        queryParameters: <String, String>{
          'anime': title,
          if (episode != null && episode.isNotEmpty) 'episode': episode,
        },
      ),
    );
    return asMapList(asMap(body)['animes'])
        .map(DanmakuAnime.fromJson)
        .toList(growable: false);
  }

  /// Matches [title] (and an optional 1-based [episode] number) to a comment
  /// endpoint id, or null when nothing matches. Transport failures throw
  /// [DandanPlayException]; the repository guards them.
  Future<int?> match(String title, {String? episode}) async =>
      (await matchEpisode(title, episode: episode))?.episodeId;

  /// [match] with the labels kept, so the player can surface which episode
  /// was matched (S17 status line).
  Future<DanmakuMatch?> matchEpisode(String title, {String? episode}) async {
    final List<DanmakuAnime> animes = await searchEpisodes(
      title,
      episode: episode,
    );
    if (animes.isEmpty) return null;
    // The API ranks by relevance; an exact title wins over the first hit.
    final DanmakuAnime anime = animes.firstWhere(
      (DanmakuAnime a) => a.title == title,
      orElse: () => animes.first,
    );
    if (anime.episodes.isEmpty) return null;

    DanmakuEpisode? picked;
    final int? wanted = episode == null ? null : int.tryParse(episode);
    if (wanted != null) {
      // Prefer the episode whose title carries the requested number ("第2话",
      // "02", ...); the server filter can still return neighbors.
      for (final DanmakuEpisode ep in anime.episodes) {
        if (_episodeNumber(ep.title) == wanted) {
          picked = ep;
          break;
        }
      }
      // Titles without numbers (OVA / SP names): fall back to the 1-based
      // position in the returned list.
      if (picked == null && wanted >= 1 && wanted <= anime.episodes.length) {
        picked = anime.episodes[wanted - 1];
      }
    }
    picked ??= anime.episodes.first;
    return DanmakuMatch(
      episodeId: picked.id,
      animeTitle: anime.title,
      episodeTitle: picked.title,
    );
  }

  /// `GET /api/v2/comment/{episodeId}?withRelated=true`, sorted by time so the
  /// overlay can spawn with a single forward cursor. Malformed entries are
  /// skipped, never fatal.
  Future<List<DanmakuComment>> fetchComments(int episodeId) async {
    final Object? body = await _getJson(
      Uri.parse(
        '$baseUrl/api/v2/comment/$episodeId',
      ).replace(queryParameters: const <String, String>{'withRelated': 'true'}),
    );
    final List<DanmakuComment> comments =
        asMapList(asMap(body)['comments'])
            .map(DanmakuComment.fromJson)
            .whereType<DanmakuComment>()
            .toList()
          ..sort(
            (DanmakuComment a, DanmakuComment b) => a.time.compareTo(b.time),
          );
    return comments;
  }

  /// First number in an episode title ("第12话" → 12); null when there is none.
  static int? _episodeNumber(String title) {
    final Match? match = RegExp(r'\d+').firstMatch(title);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  Future<Object?> _getJson(Uri url) async {
    // Path only: the query carries the title the user is watching.
    _log('GET ${redactUrl(url.toString())}');

    try {
      final Response<Object?> response = await _dio.requestUri<Object?>(
        url,
        options: Options(
          method: 'GET',
          headers: <String, String>{
            Headers.acceptHeader: Headers.jsonContentType,
          },
          // Decode ourselves so a malformed body maps to serverError instead
          // of surfacing as an adapter-level "unknown" network failure.
          responseType: ResponseType.plain,
          followRedirects: true,
          maxRedirects: 5,
          connectTimeout: defaultConnectTimeout,
          receiveTimeout: defaultReceiveTimeout,
          sendTimeout: defaultReceiveTimeout,
        ),
      );
      return _decode(response.data);
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  Object? _decode(Object? data) {
    if (data is Map || data is List) return data;
    if (data is String) {
      if (data.trim().isEmpty) return null;
      try {
        return jsonDecode(data);
      } on FormatException {
        throw DandanPlayException(
          AppErrorCode.serverError,
          message: 'invalid JSON response',
        );
      }
    }
    return null;
  }

  DandanPlayException _map(DioException error) {
    switch (error.type) {
      case DioExceptionType.badCertificate:
        return DandanPlayException(
          AppErrorCode.tlsUntrusted,
          message: 'bad certificate',
        );
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return DandanPlayException(
          AppErrorCode.networkUnreachable,
          message: error.type.name,
        );
      case DioExceptionType.cancel:
        return DandanPlayException(
          AppErrorCode.networkUnreachable,
          message: 'cancelled',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        if (_isTls(error.error)) {
          return DandanPlayException(
            AppErrorCode.tlsUntrusted,
            message: 'TLS handshake failed',
          );
        }
        return DandanPlayException(
          AppErrorCode.networkUnreachable,
          message: error.type.name,
        );
      case DioExceptionType.badResponse:
        final int status = error.response?.statusCode ?? 0;
        return DandanPlayException(
          status == 404 ? AppErrorCode.notFound : AppErrorCode.serverError,
          message: 'HTTP $status',
        );
    }
  }

  static bool _isTls(Object? error) =>
      error is HandshakeException || error is TlsException;
}
