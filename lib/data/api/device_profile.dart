/// Audio codecs this player can decode straight from the container.
///
/// TrueHD/MLP is deliberately absent: the macOS libmpv build used before the
/// `video-full` switch had no TrueHD decoder and played such tracks as
/// silence, and passthrough is not configured on any platform. Leaving it out
/// makes the server transcode that one track to AAC instead (contract §3.2,
/// §3.3) — the same request that produced `TranscodeReasons=AudioCodecNotSupported`.
///
/// Note: a source the app plays as an opaque direct link (a strm pointing at a
/// CDN) is not transcoded by the server no matter what is declared here; the
/// decoder fix is what covers those.
const String _kDirectPlayAudioCodecs = 'aac,ac3,eac3,dts,flac,opus,vorbis,mp3';

/// DeviceProfile sent with PlaybackInfo and `/Sessions/Capabilities/Full`
/// (contract §3.2). Verified in B2 against Emby 4.10.1: H.264 1080p,
/// HEVC Main 4K and HEVC Main10 4K all come back as direct play.
const Map<String, dynamic> kDeviceProfile = <String, dynamic>{
  'Name': 'MediaPlayer-mpv',
  'DirectPlayProfiles': <Map<String, dynamic>>[
    <String, dynamic>{
      'Container': 'mkv,mp4,m4v,mov,ts,webm',
      'Type': 'Video',
      'VideoCodec': 'h264,hevc,av1,vp9,mpeg2video',
      'AudioCodec': _kDirectPlayAudioCodecs,
    },
  ],
  // Without a transcoding profile the server cannot honour a codec it thinks
  // the device rejects, and answers with the original stream instead.
  'TranscodingProfiles': <Map<String, dynamic>>[
    <String, dynamic>{
      'Container': 'ts',
      'Type': 'Video',
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      'Context': 'Streaming',
      'Protocol': 'hls',
      'MaxAudioChannels': '2',
      'MinSegments': '1',
      'BreakOnNonKeyFrames': true,
    },
  ],
  'SubtitleProfiles': <Map<String, dynamic>>[
    <String, dynamic>{'Format': 'srt', 'Method': 'External'},
    <String, dynamic>{'Format': 'ass', 'Method': 'External'},
    <String, dynamic>{'Format': 'pgssub', 'Method': 'Embed'},
    <String, dynamic>{'Format': 'dvdsub', 'Method': 'Embed'},
  ],
};
