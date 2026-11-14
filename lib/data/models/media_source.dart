import 'json_read.dart';
import 'media_stream.dart';

/// One playable version of an item (contract §4, §3.1).
class MediaSource {
  const MediaSource({
    required this.id,
    required this.container,
    required this.bitrate,
    required this.supportsDirectPlay,
    required this.supportsDirectStream,
    this.name,
    this.directStreamUrl,
    this.transcodingUrl,
    this.playSessionId,
    this.mediaSourceType,
    this.streams = const <MediaStream>[],
    this.size = 0,
  });

  factory MediaSource.fromJson(
    Map<String, dynamic> json, {
    String? topLevelPlaySessionId,
  }) {
    return MediaSource(
      id: asStringOr(json['Id'], ''),
      container: asStringOr(json['Container'], ''),
      bitrate: asInt(json['Bitrate']),
      supportsDirectPlay: asBool(json['SupportsDirectPlay']),
      supportsDirectStream: asBool(json['SupportsDirectStream']),
      name: asString(json['Name']),
      directStreamUrl: asString(json['DirectStreamUrl']),
      transcodingUrl: asString(json['TranscodingUrl']),
      // Emby 4.10.1 returns PlaySessionId at the response top level only.
      playSessionId: asString(json['PlaySessionId']) ?? topLevelPlaySessionId,
      // `LiveTv` for a channel source (S21); absent/`Default` for library items.
      mediaSourceType: asString(json['MediaSourceType']),
      streams: asMapList(json['MediaStreams'])
          .map(MediaStream.fromJson)
          .toList(growable: false),
      size: asInt(json['Size']),
    );
  }

  final String id;
  final String container;
  final int bitrate;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;

  /// Server-given version label (S7 detail picker); null when unnamed.
  final String? name;
  final String? directStreamUrl;
  final String? transcodingUrl;
  final String? playSessionId;

  /// `LiveTv` when the source is a live channel (S21), null/`Default` for a
  /// library item. Negotiation is type-agnostic; this only labels the source.
  final String? mediaSourceType;
  final List<MediaStream> streams;

  /// File size in bytes (`Size`); used by the detail page's 媒体信息 card.
  final int size;

  /// True when this source is a live channel stream (S21).
  bool get isLiveTv => mediaSourceType == 'LiveTv';

  Iterable<MediaStream> get audios =>
      streams.where((s) => s.type == MediaStreamType.audio);

  Iterable<MediaStream> get subtitles =>
      streams.where((s) => s.type == MediaStreamType.subtitle);
}
