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
    this.title,
    this.displayLanguage,
    this.videoRange,
    this.profile,
    this.width,
    this.height,
    this.frameRate,
    this.bitRate,
    this.bitDepth,
    this.colorSpace,
    this.pixelFormat,
    this.channels,
    this.channelLayout,
    this.isForced = false,
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
      title: asString(json['Title']),
      displayLanguage: asString(json['DisplayLanguage']),
      videoRange: asString(json['VideoRange']),
      profile: asString(json['Profile']),
      width: asIntOrNull(json['Width']),
      height: asIntOrNull(json['Height']),
      frameRate: asDoubleOrNull(json['FrameRate']),
      bitRate: asIntOrNull(json['BitRate']),
      bitDepth: asIntOrNull(json['BitDepth']),
      colorSpace: asString(json['ColorSpace']),
      pixelFormat: asString(json['PixelFormat']),
      channels: asIntOrNull(json['Channels']),
      channelLayout: asString(json['ChannelLayout']),
      isForced: asBool(json['IsForced']),
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

  /// Detail/媒体信息 fields (S28): everything the server publishes about a
  /// stream. All optional; the detail page only renders what it received.
  final String? title;
  final String? displayLanguage;
  final String? videoRange;
  final String? profile;
  final int? width;
  final int? height;
  final double? frameRate;
  final int? bitRate;
  final int? bitDepth;
  final String? colorSpace;
  final String? pixelFormat;
  final int? channels;
  final String? channelLayout;
  final bool isForced;

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
