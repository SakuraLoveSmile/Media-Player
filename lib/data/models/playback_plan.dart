import '../../core/network/endpoint_kind.dart';
import '../api/emby_headers.dart';
import 'media_stream.dart';

/// How the server delivers the item (contract §3.4).
enum PlaybackMode { direct, transcode }

/// Everything the player and the session reporter need to start an item
/// (contract §3.4).
///
/// [itemId] lives here because the §3.6 reports take it from the plan, and the
/// media URL path shape is chosen by the server so it cannot be parsed back
/// (contract §10.9 a).
class PlaybackPlan {
  const PlaybackPlan({
    required this.itemId,
    required this.mode,
    required this.endpointKind,
    required this.url,
    required this.headers,
    required this.mediaSourceId,
    required this.playSessionId,
    this.startAt = Duration.zero,
    this.videoDirect,
    this.audioTranscoded = false,
    this.transcodingReasons = const <String>[],
    this.audios = const <MediaStream>[],
    this.subtitles = const <MediaStream>[],
  });

  final String itemId;
  final PlaybackMode mode;
  final EndpointKind endpointKind;

  /// Media URL. Fallback branches carry `api_key`, so it must never be logged
  /// (contract §10.6).
  final String url;

  /// Header authentication, preferred by the player over the URL token
  /// (contract §3.4).
  final Map<String, String> headers;
  final String mediaSourceId;

  /// Empty when the server did not send one; reporting still proceeds
  /// (contract §3.6, §10.9 a).
  final String playSessionId;
  final Duration startAt;

  /// Null until `/Sessions` confirms the play method; never guessed from the
  /// URL shape (contract §10.9 f).
  final bool? videoDirect;
  final bool audioTranscoded;

  /// Populated only when the server names a reason; the field name is still
  /// unverified (contract §3.4).
  final List<String> transcodingReasons;

  /// Audio streams of the negotiated source, in server order (S5). The
  /// in-playback track panel and language auto-match follow this list.
  final List<MediaStream> audios;

  /// Subtitle streams of the negotiated source. PlaybackInfo probes lazily
  /// probed sources (STRM), so its stream indices — not the detail response's
  /// — are the ones the subtitle delivery URLs accept.
  final List<MediaStream> subtitles;

  /// [url] with `api_key` guaranteed in the query (S19/S38): DLNA renderers
  /// fetch the URL themselves and cannot send the auth header.
  String get castUrl {
    final Uri uri = Uri.parse(url);
    if (uri.queryParameters.containsKey('api_key')) return url;
    final String? token = headers[EmbyHeaders.token];
    if (token == null || token.isEmpty) return url;
    final String separator = uri.hasQuery ? '&' : '?';
    return '$url$separator api_key=${Uri.encodeQueryComponent(token)}';
  }

  PlaybackPlan copyWith({
    String? itemId,
    PlaybackMode? mode,
    EndpointKind? endpointKind,
    String? url,
    Map<String, String>? headers,
    String? mediaSourceId,
    String? playSessionId,
    Duration? startAt,
    bool? videoDirect,
    bool? audioTranscoded,
    List<String>? transcodingReasons,
    List<MediaStream>? audios,
    List<MediaStream>? subtitles,
  }) {
    return PlaybackPlan(
      itemId: itemId ?? this.itemId,
      mode: mode ?? this.mode,
      endpointKind: endpointKind ?? this.endpointKind,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      mediaSourceId: mediaSourceId ?? this.mediaSourceId,
      playSessionId: playSessionId ?? this.playSessionId,
      startAt: startAt ?? this.startAt,
      videoDirect: videoDirect ?? this.videoDirect,
      audioTranscoded: audioTranscoded ?? this.audioTranscoded,
      transcodingReasons: transcodingReasons ?? this.transcodingReasons,
      audios: audios ?? this.audios,
      subtitles: subtitles ?? this.subtitles,
    );
  }

  /// Omits [url] and [headers]: both carry the access token.
  @override
  String toString() =>
      'PlaybackPlan($itemId, ${mode.name}, '
      '${endpointKind.name}, source=$mediaSourceId, session=$playSessionId, '
      'startAt=$startAt, videoDirect=$videoDirect, '
      'audioTranscoded=$audioTranscoded)';
}
