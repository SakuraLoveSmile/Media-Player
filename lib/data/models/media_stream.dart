import 'json_read.dart';

/// Media stream entry (contract §4).
enum MediaStreamType { video, audio, subtitle, unknown }

class MediaStream {
  const MediaStream({
    required this.type,
    required this.index,
    this.codec,
    this.language,
    this.displayTitle,
    this.isDefault = false,
    this.isExternal = false,
    this.deliveryUrl,
  });

  factory MediaStream.fromJson(Map<String, dynamic> json) {
    return MediaStream(
      type: _typeFromName(asString(json['Type'])),
      index: asInt(json['Index']),
      codec: asString(json['Codec']),
      language: asString(json['Language']),
      displayTitle: asString(json['DisplayTitle']),
      isDefault: asBool(json['IsDefault']),
      isExternal: asBool(json['IsExternal']),
      deliveryUrl: asString(json['DeliveryUrl']),
    );
  }

  final MediaStreamType type;
  final int index;
  final String? codec;
  final String? language;
  final String? displayTitle;
  final bool isDefault;
  final bool isExternal;
  final String? deliveryUrl;

  static MediaStreamType _typeFromName(String? name) {
    switch (name?.toLowerCase()) {
      case 'video':
        return MediaStreamType.video;
      case 'audio':
        return MediaStreamType.audio;
      case 'subtitle':
        return MediaStreamType.subtitle;
      default:
        return MediaStreamType.unknown;
    }
  }
}
