import 'package:flutter/widgets.dart';

import '../models/playback_plan.dart';

/// Player abstraction from contract §5; the playback page (F3) depends only
/// on this interface, never on the player package.
abstract interface class PlaybackEngine {
  /// Opens [plan] using its `url`, `headers` and `startAt`.
  Future<void> open(PlaybackPlan plan);

  /// Broadcast snapshot stream; safe to listen to more than once.
  Stream<PlaybackSnapshot> get state;

  /// Current value read synchronously.
  ///
  /// B5-6's `SessionReporter.started(..., position: () => ...)` needs the
  /// position at heartbeat time; caching it from [state] would add one more
  /// piece of mutable state for the same value.
  PlaybackSnapshot get snapshot;

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> selectAudioTrack(int index);
  Future<void> selectSubtitleTrack(int? index, {String? externalPath});

  /// Reserved bottom margin (logical px) for the subtitle band, so the control
  /// bar sits above it and never covers subtitles (Yamby parity).
  Future<void> setSubtitleBottomMargin(double pixels);

  /// S78: whether [setSubtitleBottomMargin] may move ASS dialogue as well as
  /// plain text. The portrait player turns margins on so its subtitle band
  /// clears the dock title row; landscape keeps the user's 黑边 setting.
  Future<void> setSubtitleMarginsEnabled(bool enabled);

  /// Text-subtitle rendering style (S4); engines without property access
  /// degrade to a no-op.
  Future<void> setSubtitleStyle(SubtitleStyle style);

  /// Live decoder/render diagnostics for the debug panel (播放详情). Engines
  /// without property access return an empty [PlaybackStats].
  Future<PlaybackStats> readStats();

  /// S16: rotate the video output by [degrees] (0 / 90 / 180 / 270).
  Future<void> setVideoRotation(int degrees);

  /// S16: display aspect mode — `default`, `16:9`, `4:3`, `2.35:1` or `fill`
  /// (fill stretches the frame to the surface).
  Future<void> setAspectMode(String mode);

  /// S13: hardware decoding on / off.
  Future<void> setHwdecEnabled(bool enabled);

  /// S41: downmix to stereo (mpv `audio-channels`); false restores `auto`.
  Future<void> setForceStereo(bool stereo);

  /// S23: advanced mpv video options — the `gpu-next` renderer, the `deband`
  /// filter and a forced `format=yuv420p` video chain. Engines without
  /// property access degrade to a no-op; a rejected property must not throw.
  ///
  /// [applyVo] gates the `vo` switch: on Android the VO may only be (re)selected
  /// once the surface (`wid`) is attached, otherwise libmpv aborts on the
  /// `vo_android_init` WinID assertion. The load pass sets it false and lets
  /// media_kit's wid-listener pick the VO; live toggles keep the default true.
  Future<void> setAdvancedVideo({
    required bool gpuNext,
    required bool deband,
    required bool yuv420,
    bool applyVo = true,
  });

  /// S16: volume ceiling in percent; values above 100 enable volume gain.
  Future<void> setVolumeMax(double percent);

  /// S13: demuxer cache sizing. Null fields keep the engine's own default.
  Future<void> setCacheConfig({int? cacheSecs, int? demuxerMaxBytes});

  /// S16: write the current frame (subtitles included) to [destPath].
  /// Returns [destPath] on success, null on any failure.
  Future<String?> takeScreenshot(String destPath);

  /// §10.9 (b): the engine owns the render widget so features never import
  /// the player package.
  Widget createSurface();

  Future<void> dispose();
}

/// What the UI renders (contract §5).
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.playing = false,
    this.error,
    this.videoWidth = 0,
    this.videoHeight = 0,
  });

  final Duration position;
  final Duration duration;
  final bool buffering;
  final bool playing;

  /// Decoded video dimensions; 0 until the demuxer reports them. Used to size
  /// the portrait video box so subtitles sit at the video's own bottom edge.
  final int videoWidth;
  final int videoHeight;

  /// The engine's latest error event, or null.
  ///
  /// Engines report errors as events rather than as latched state: mpv logs
  /// one for problems it recovers from, so the UI must not read this as "the
  /// player is broken" on its own (contract §6).
  final Object? error;

  PlaybackSnapshot copyWith({
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? playing,
    Object? error,
    int? videoWidth,
    int? videoHeight,
  }) {
    return PlaybackSnapshot(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffering: buffering ?? this.buffering,
      playing: playing ?? this.playing,
      error: error ?? this.error,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
    );
  }
}

/// User subtitle rendering preferences (S4), mapped onto mpv text-subtitle
/// properties. [overrideAss] decides whether ASS scripts keep their authored
/// styles (`scale`: only the size applies) or take the full text style
/// (`force`). [useMargins] is the Yamby "ASS 黑边" toggle: subtitles render
/// into the black borders instead of over the picture.
class SubtitleStyle {
  /// KeyValueStore key shared by the player controller and the settings page.
  static const String storageKey = 'player.subtitleStyle.v1';

  const SubtitleStyle({
    this.font = '',
    this.scale = 1.0,
    this.delay = Duration.zero,
    this.borderSize = 3.0,
    this.shadowOffset = 0.0,
    this.overrideAss = false,
    this.useMargins = false,
  });

  factory SubtitleStyle.fromJson(Map<String, dynamic> json) {
    return SubtitleStyle(
      font: json['font'] as String? ?? '',
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      delay: Duration(milliseconds: (json['delayMs'] as num?)?.toInt() ?? 0),
      borderSize: (json['borderSize'] as num?)?.toDouble() ?? 3.0,
      shadowOffset: (json['shadowOffset'] as num?)?.toDouble() ?? 0.0,
      overrideAss: json['overrideAss'] as bool? ?? false,
      // Absent in style JSON written before the margins toggle existed.
      useMargins: json['useMargins'] as bool? ?? false,
    );
  }

  /// Empty means the engine default family.
  final String font;
  final double scale;
  final Duration delay;
  final double borderSize;
  final double shadowOffset;
  final bool overrideAss;

  /// Place subtitles in the black borders (mpv `sub-use-margins` /
  /// `sub-ass-use-margins`) rather than over the video.
  final bool useMargins;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'font': font,
    'scale': scale,
    'delayMs': delay.inMilliseconds,
    'borderSize': borderSize,
    'shadowOffset': shadowOffset,
    'overrideAss': overrideAss,
    'useMargins': useMargins,
  };

  SubtitleStyle copyWith({
    String? font,
    double? scale,
    Duration? delay,
    double? borderSize,
    double? shadowOffset,
    bool? overrideAss,
    bool? useMargins,
  }) {
    return SubtitleStyle(
      font: font ?? this.font,
      scale: scale ?? this.scale,
      delay: delay ?? this.delay,
      borderSize: borderSize ?? this.borderSize,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      overrideAss: overrideAss ?? this.overrideAss,
      useMargins: useMargins ?? this.useMargins,
    );
  }
}

/// Live player diagnostics for the debug panel (播放详情). Every field is
/// optional: mpv only reports a property once the corresponding pipeline stage
/// is up, so the panel shows a placeholder until then.
class PlaybackStats {
  const PlaybackStats({
    this.videoCodec,
    this.audioCodec,
    this.width = 0,
    this.height = 0,
    this.containerFps,
    this.estimatedFps,
    this.videoBitrate,
    this.audioBitrate,
    this.cacheSpeed,
    this.cacheSeconds,
    this.decoderDroppedFrames,
    this.voDroppedFrames,
    this.hwdec,
    this.vo,
    this.ao,
    this.audioSampleRate,
    this.audioChannels,
    this.speed,
  });

  final String? videoCodec;
  final String? audioCodec;
  final int width;
  final int height;

  /// Container-declared frame rate vs the rate actually reaching the video
  /// chain (drops / interpolation show up as a difference).
  final double? containerFps;
  final double? estimatedFps;

  /// Real-time throughput in bits/s (video/audio) and bytes/s (network cache).
  final int? videoBitrate;
  final int? audioBitrate;
  final int? cacheSpeed;
  final double? cacheSeconds;

  final int? decoderDroppedFrames;
  final int? voDroppedFrames;
  final String? hwdec;
  final String? vo;
  final String? ao;
  final int? audioSampleRate;
  final String? audioChannels;
  final double? speed;
}
