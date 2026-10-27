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
      'AudioCodec': 'aac,ac3,eac3,dts,truehd,flac,opus,vorbis,mp3',
    },
  ],
  'SubtitleProfiles': <Map<String, dynamic>>[
    <String, dynamic>{'Format': 'srt', 'Method': 'External'},
    <String, dynamic>{'Format': 'ass', 'Method': 'External'},
    <String, dynamic>{'Format': 'pgssub', 'Method': 'Embed'},
    <String, dynamic>{'Format': 'dvdsub', 'Method': 'Embed'},
  ],
};
