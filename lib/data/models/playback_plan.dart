import '../../core/network/endpoint_kind.dart';

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
    );
  }

  /// Omits [url] and [headers]: both carry the access token.
  @override
  String toString() => 'PlaybackPlan($itemId, ${mode.name}, '
      '${endpointKind.name}, source=$mediaSourceId, session=$playSessionId, '
      'startAt=$startAt, videoDirect=$videoDirect, '
      'audioTranscoded=$audioTranscoded)';
}
