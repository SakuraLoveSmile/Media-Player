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
    this.directStreamUrl,
    this.transcodingUrl,
    this.playSessionId,
    this.streams = const <MediaStream>[],
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
      directStreamUrl: asString(json['DirectStreamUrl']),
      transcodingUrl: asString(json['TranscodingUrl']),
      // Emby 4.10.1 returns PlaySessionId at the response top level only.
      playSessionId:
          asString(json['PlaySessionId']) ?? topLevelPlaySessionId,
      streams: asMapList(json['MediaStreams'])
          .map(MediaStream.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final String container;
  final int bitrate;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;
  final String? directStreamUrl;
  final String? transcodingUrl;
  final String? playSessionId;
  final List<MediaStream> streams;

  Iterable<MediaStream> get subtitles =>
      streams.where((s) => s.type == MediaStreamType.subtitle);
}
