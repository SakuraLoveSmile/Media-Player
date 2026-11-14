/// App-wide playback engine preferences (S13 / S16 / S23): hardware decoding,
/// volume gain, demuxer cache sizing and advanced mpv video options.
///
/// Persisted as one JSON blob under [storageKey]. The player controller loads
/// it at startup and applies it on open; the settings page edits the same key
/// so changes take effect on the next playback. Living in the data layer keeps
/// the two features from importing each other (tool/check_layering.sh).
class PlaybackSettings {
  const PlaybackSettings({
    this.hwdecEnabled = true,
    this.volumeGainPercent = 100,
    this.cacheSecs = 30,
    this.demuxerMaxBytes = 157286400,
    this.gpuNext = false,
    this.deband = false,
    this.yuv420 = false,
    this.seekOnDrag = false,
    this.autoPlayNext = true,
    this.forceStereo = true,
  });

  /// KeyValueStore key shared by the player controller and the settings page.
  static const String storageKey = 'player.playbackSettings.v1';

  /// 150 MiB, mpv's own demuxer cache default.
  static const int defaultDemuxerMaxBytes = 157286400;

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    return PlaybackSettings(
      hwdecEnabled: json['hwdecEnabled'] as bool? ?? true,
      volumeGainPercent: (json['volumeGainPercent'] as num?)?.toDouble() ?? 100,
      cacheSecs: (json['cacheSecs'] as num?)?.toInt() ?? 30,
      demuxerMaxBytes:
          (json['demuxerMaxBytes'] as num?)?.toInt() ?? defaultDemuxerMaxBytes,
      // Absent in blobs written before S23; the advanced options stay off.
      gpuNext: json['gpuNext'] as bool? ?? false,
      deband: json['deband'] as bool? ?? false,
      yuv420: json['yuv420'] as bool? ?? false,
      // S33: absent in older blobs; yamby-like defaults.
      seekOnDrag: json['seekOnDrag'] as bool? ?? false,
      autoPlayNext: json['autoPlayNext'] as bool? ?? true,
      forceStereo: json['forceStereo'] as bool? ?? true,
    );
  }

  /// Hardware decoding (mpv `hwdec`); on by default.
  final bool hwdecEnabled;

  /// Volume ceiling in percent (mpv `volume-max`); 100 means no gain.
  final double volumeGainPercent;

  /// How many seconds of media the demuxer keeps ahead (mpv `cache-secs`).
  final int cacheSecs;

  /// Demuxer cache byte budget (mpv `demuxer-max-bytes`).
  final int demuxerMaxBytes;

  /// S23: render through mpv's `gpu-next` video output instead of `gpu`.
  final bool gpuNext;

  /// S23: mpv `deband` filter, reduces colour banding at a small GPU cost.
  final bool deband;

  /// S23: force the video chain to `format=yuv420p` (mpv `vf`), a
  /// compatibility fallback for renderers that reject other pixel formats.
  final bool yuv420;

  /// S33: seeking follows the thumb while dragging (Yamby's 拖拽进度条时快速
  /// 跳转); off by default so one drag still reports a single seek.
  final bool seekOnDrag;

  /// S33: a finished episode advances to the next one (Yamby's 自动连播).
  final bool autoPlayNext;

  /// S41: downmix multichannel audio to stereo (mpv `audio-channels`), Yamby's
  /// 强制输出立体声.
  final bool forceStereo;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'hwdecEnabled': hwdecEnabled,
    'volumeGainPercent': volumeGainPercent,
    'cacheSecs': cacheSecs,
    'demuxerMaxBytes': demuxerMaxBytes,
    'gpuNext': gpuNext,
    'deband': deband,
    'yuv420': yuv420,
    'seekOnDrag': seekOnDrag,
    'autoPlayNext': autoPlayNext,
    'forceStereo': forceStereo,
  };

  PlaybackSettings copyWith({
    bool? hwdecEnabled,
    double? volumeGainPercent,
    int? cacheSecs,
    int? demuxerMaxBytes,
    bool? gpuNext,
    bool? deband,
    bool? yuv420,
    bool? seekOnDrag,
    bool? autoPlayNext,
    bool? forceStereo,
  }) {
    return PlaybackSettings(
      hwdecEnabled: hwdecEnabled ?? this.hwdecEnabled,
      volumeGainPercent: volumeGainPercent ?? this.volumeGainPercent,
      cacheSecs: cacheSecs ?? this.cacheSecs,
      demuxerMaxBytes: demuxerMaxBytes ?? this.demuxerMaxBytes,
      gpuNext: gpuNext ?? this.gpuNext,
      deband: deband ?? this.deband,
      yuv420: yuv420 ?? this.yuv420,
      seekOnDrag: seekOnDrag ?? this.seekOnDrag,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      forceStereo: forceStereo ?? this.forceStereo,
    );
  }
}
