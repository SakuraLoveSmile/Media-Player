import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/playback_plan.dart';
import 'playback_engine.dart';

/// Dev-only engine diagnostics (same flag as the session reporter); track
/// titles/ids carry no credentials.
const bool _kTrace = bool.fromEnvironment('PLAYBACK_TRACE');

/// media_kit implementation of [PlaybackEngine] (contract §5).
///
/// This is the only file allowed to mention media_kit types: `tool/
/// check_layering.sh` keeps them out of `lib/features` (§10.9 b).
class MediaKitEngine implements PlaybackEngine {
  MediaKitEngine() {
    // Same wiring as the verified M0 spike (spike/windows_smoke). libass must
    // be on: media_kit ties `sub-ass` AND `sub-visibility` to it, so the
    // default (false) hides every subtitle, embedded or external, PGS included.
    _player = Player(
      configuration: PlayerConfiguration(
        libass: true,
        // Trace builds raise mpv's own log level so VO/hwdec selection is
        // visible in logcat when diagnosing native playback crashes.
        logLevel: _kTrace ? MPVLogLevel.debug : MPVLogLevel.warn,
      ),
    );
    _controller = VideoController(_player);
    _states = StreamController<PlaybackSnapshot>.broadcast();
    _bind<Duration>(_player.stream.position, (s, v) => s.copyWith(position: v));
    _bind<Duration>(_player.stream.duration, (s, v) => s.copyWith(duration: v));
    _bind<bool>(_player.stream.buffering, (s, v) => s.copyWith(buffering: v));
    _bind<bool>(_player.stream.playing, (s, v) => s.copyWith(playing: v));
    _bind<int?>(_player.stream.width, (s, v) => s.copyWith(videoWidth: v ?? 0));
    _bind<int?>(
      _player.stream.height,
      (s, v) => s.copyWith(videoHeight: v ?? 0),
    );
    _bind<String>(
      _player.stream.error,
      // The raw mpv line can embed the media URL, `api_key` included, and mpv
      // reaches this stream from `stream`/`tcp:`/`file` log prefixes. Only the
      // failure class crosses the boundary (contract §10.6).
      //
      // The line is an event, not a state: mpv logs errors for trouble it
      // recovers from (a retried range request, a skipped frame) and keeps
      // playing, so it must not stick to every later snapshot (contract §6).
      (s, _) => s.copyWith(error: const _PlaybackFailure()),
      transient: true,
    );
    if (_kTrace) {
      _subscriptions.add(
        _player.stream.log.listen((log) {
          // mpv lines can embed the media URL with its token (contract §10.6).
          final text = log.text.replaceAll(
            RegExp(r'(api_key|token)=[^&\s]+'),
            r'$1=<redacted>',
          );
          debugPrint('[mpv] ${log.prefix}/${log.level}: $text');
        }),
      );
    }
  }

  late final Player _player;
  late final VideoController _controller;
  late final StreamController<PlaybackSnapshot> _states;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  bool _disposed = false;

  @override
  Stream<PlaybackSnapshot> get state => _states.stream;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<void> open(PlaybackPlan plan) async {
    // Resume through `Media.start` rather than open-then-seek: mpv applies
    // `start` while loading, so no seek can race the demuxer (contract §10.9 d).
    final media = Media(
      plan.url,
      httpHeaders: plan.headers,
      start: plan.startAt > Duration.zero ? plan.startAt : null,
    );
    // A new item must not inherit the previous item's position or error, and
    // copyWith cannot clear `error`.
    _snapshot = const PlaybackSnapshot();
    _emit();
    await _player.open(media, play: true);
    if (_kTrace) {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        final vo = await platform.getProperty('current-vo');
        final hwdec = await platform.getProperty('hwdec-current');
        final vis = await platform.getProperty('sub-visibility');
        final ao = await platform.getProperty('current-ao');
        final vol = await platform.getProperty('volume');
        final mute = await platform.getProperty('mute');
        debugPrint(
          '[engine] vo=$vo hwdec=$hwdec sub-visibility=$vis '
          'ao=$ao volume=$vol mute=$mute',
        );
        // Audio output initializes after open returns; sample it once settled.
        Future<void>.delayed(const Duration(seconds: 4), () async {
          if (_disposed) return;
          final aoNow = await platform.getProperty('current-ao');
          final codec = await platform.getProperty('audio-codec');
          final params = await platform.getProperty('audio-params');
          final tracks = await platform.getProperty('track-list');
          final aid = await platform.getProperty('aid');
          final sid = await platform.getProperty('sid');
          final vis = await platform.getProperty('sub-visibility');
          debugPrint('[engine] audio ao=$aoNow codec=$codec params=$params');
          debugPrint('[engine] aid=$aid sid=$sid vis=$vis tracks=$tracks');
        });
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> selectAudioTrack(int index) async {
    // Same pseudo-track offset as subtitles: `auto` / `no` are not streams.
    final tracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    // Out of range is a no-op, not an error (§5 only asks for selection).
    if (index < 0 || index >= tracks.length) return;
    await _player.setAudioTrack(tracks[index]);
  }

  @override
  Future<void> selectSubtitleTrack(int? index, {String? externalPath}) async {
    if (externalPath != null) {
      // media_kit 1.2.6 exposes the external-file factory as `uri` (the M0
      // spike used it); B6 mounts downloaded subtitle files through this.
      await _player.setSubtitleTrack(SubtitleTrack.uri(externalPath));
      if (_kTrace) debugPrint('[engine] sub external=$externalPath');
      return;
    }
    if (index == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      if (_kTrace) debugPrint('[engine] sub off');
      return;
    }
    // media_kit lists the `auto` / `no` pseudo tracks first; server stream
    // order maps onto the real tracks only, otherwise every pick is off by
    // two (and `auto` silently re-picks the default).
    final tracks = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    if (_kTrace) {
      debugPrint(
        '[engine] sub tracks=${tracks.map((t) => '${t.id}:${t.title}').join('|')} '
        'pick=$index',
      );
    }
    if (index < 0 || index >= tracks.length) return;
    await _player.setSubtitleTrack(tracks[index]);
    if (_kTrace) {
      debugPrint('[engine] sub now=${_player.state.track.subtitle.id}');
    }
  }

  @override
  Future<void> setSubtitleBottomMargin(double pixels) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('sub-margin-y', pixels.round().toString());
    }
  }

  @override
  Future<void> setSubtitleMarginsEnabled(bool enabled) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final String margins = enabled ? 'yes' : 'no';
    await platform.setProperty('sub-use-margins', margins);
    await platform.setProperty('sub-ass-use-margins', margins);
  }

  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty(
      'sub-font',
      style.font.isEmpty ? 'sans-serif' : style.font,
    );
    await platform.setProperty('sub-scale', style.scale.toString());
    await platform.setProperty(
      'sub-delay',
      (style.delay.inMilliseconds / 1000).toString(),
    );
    await platform.setProperty('sub-border-size', style.borderSize.toString());
    await platform.setProperty(
      'sub-shadow-offset',
      style.shadowOffset.toString(),
    );
    // `scale` keeps ASS script styles but lets the size slider apply; `force`
    // hands ASS over to the text style entirely.
    await platform.setProperty(
      'sub-ass-override',
      style.overrideAss ? 'force' : 'scale',
    );
    // Yamby "ASS 黑边": render subtitles into the black borders instead of
    // over the picture. mpv splits the flag between text and ASS subtitles,
    // so both follow the one toggle.
    final String margins = style.useMargins ? 'yes' : 'no';
    await platform.setProperty('sub-use-margins', margins);
    await platform.setProperty('sub-ass-use-margins', margins);
  }

  @override
  Future<PlaybackStats> readStats() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return const PlaybackStats();

    // A property can be unavailable (no video yet) or error mid-teardown; the
    // debug panel must degrade to placeholders, never throw.
    Future<String?> p(String name) async {
      try {
        return await platform.getProperty(name);
      } catch (_) {
        return null;
      }
    }

    final List<String?> r = await Future.wait(<Future<String?>>[
      p('video-codec'),
      p('audio-codec'),
      p('width'),
      p('height'),
      p('container-fps'),
      p('estimated-vf-fps'),
      p('video-bitrate'),
      p('audio-bitrate'),
      p('cache-speed'),
      p('demuxer-cache-state'),
      p('decoder-frame-drop-count'),
      p('frame-drop-count'),
      p('hwdec-current'),
      p('current-vo'),
      p('current-ao'),
      p('audio-params'),
      p('speed'),
    ]);

    double? d(int idx) => double.tryParse(r[idx] ?? '');
    int? i(int idx) => int.tryParse(r[idx] ?? '');
    Map<String, dynamic> j(int idx) {
      final String? raw = r[idx];
      if (raw == null || raw.isEmpty) return const <String, dynamic>{};
      try {
        final Object? v = jsonDecode(raw);
        if (v is Map<String, dynamic>) return v;
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
      return const <String, dynamic>{};
    }

    final Map<String, dynamic> cache = j(9);
    final Map<String, dynamic> audio = j(15);
    return PlaybackStats(
      videoCodec: r[0],
      audioCodec: r[1],
      width: i(2) ?? 0,
      height: i(3) ?? 0,
      containerFps: d(4),
      estimatedFps: d(5),
      videoBitrate: i(6),
      audioBitrate: i(7),
      cacheSpeed: i(8),
      cacheSeconds: (cache['cache-duration'] as num?)?.toDouble(),
      decoderDroppedFrames: i(10),
      voDroppedFrames: i(11),
      hwdec: r[12],
      vo: r[13],
      ao: r[14],
      audioSampleRate: (audio['samplerate'] as num?)?.toInt(),
      audioChannels: audio['channels'] as String?,
      speed: d(16),
    );
  }

  @override
  Widget createSurface() => Video(
    controller: _controller,
    // S79: media_kit's Video mounts its own Material controls by default, and
    // they draw a CircularProgressIndicator whenever the stream buffers. The
    // player renders its own chrome (S30/S78), so those built-in controls only
    // showed up as a stray spinner on top of 外观 → 加载动画.
    controls: NoVideoControls,
  );

  @override
  Future<void> setVideoRotation(int degrees) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    // mpv only accepts 0..359; normalize so any step count stays valid.
    final int normalized = ((degrees % 360) + 360) % 360;
    await platform.setProperty('video-rotate', normalized.toString());
  }

  @override
  Future<void> setAspectMode(String mode) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    switch (mode) {
      case 'fill':
        // Stretch to the surface: aspect keeping must be off, and any ratio
        // override from a previous mode must not fight it.
        await platform.setProperty('video-aspect-override', '-1');
        await platform.setProperty('keepaspect', 'no');
      case 'default':
        await platform.setProperty('keepaspect', 'yes');
        await platform.setProperty('video-aspect-override', '-1');
      default:
        // '16:9' / '4:3' / '2.35:1' are accepted verbatim by mpv.
        await platform.setProperty('keepaspect', 'yes');
        await platform.setProperty('video-aspect-override', mode);
    }
  }

  @override
  Future<void> setHwdecEnabled(bool enabled) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('hwdec', enabled ? 'auto' : 'no');
  }

  @override
  Future<void> setForceStereo(bool stereo) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('audio-channels', stereo ? 'stereo' : 'auto');
  }

  @override
  Future<void> setAdvancedVideo({
    required bool gpuNext,
    required bool deband,
    required bool yuv420,
    bool applyVo = true,
  }) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    // Switching the VO or rebuilding the filter chain can be rejected on a
    // live pipeline (renderer unavailable, format unsupported); a toggle must
    // never crash the player, so failures degrade to keeping the old setup.
    try {
      // The VO may only be (re)selected once media_kit has attached the Android
      // surface (wid). Forcing vo=gpu at load, before wid is set, aborts on
      // libmpv's vo_android_init WinID assertion. The load pass skips this and
      // lets media_kit's wid-listener choose the VO; live toggles are safe.
      if (applyVo) {
        await platform.setProperty('vo', gpuNext ? 'gpu-next' : 'gpu');
      }
      await platform.setProperty('deband', deband ? 'yes' : 'no');
      await platform.setProperty('vf', yuv420 ? 'format=yuv420p' : '');
    } catch (_) {
      // mpv logged the rejection; playback continues with the previous value.
    }
  }

  @override
  Future<void> setVolumeMax(double percent) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('volume-max', percent.toString());
  }

  @override
  Future<void> setCacheConfig({int? cacheSecs, int? demuxerMaxBytes}) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    if (cacheSecs != null) {
      await platform.setProperty('cache-secs', cacheSecs.toString());
    }
    if (demuxerMaxBytes != null) {
      await platform.setProperty(
        'demuxer-max-bytes',
        demuxerMaxBytes.toString(),
      );
    }
  }

  @override
  Future<String?> takeScreenshot(String destPath) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return null;
    try {
      // 'subtitles' burns the rendered subtitle band into the capture, the
      // same frame the user sees (Yamby parity).
      await platform.command(<String>[
        'screenshot-to-file',
        destPath,
        'subtitles',
      ]);
      return destPath;
    } catch (_) {
      // A missing directory or a dead pipeline must not crash the player.
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _states.close();
    await _player.dispose();
  }

  void _bind<T>(
    Stream<T> source,
    PlaybackSnapshot Function(PlaybackSnapshot snapshot, T value) update, {

    /// Emit the updated snapshot without folding it into [_snapshot]: the
    /// value is a one-off event (an mpv error line), not a player state.
    bool transient = false,
  }) {
    _subscriptions.add(
      source.listen((value) {
        final next = update(_snapshot, value);
        if (transient) {
          _emit(next);
          return;
        }
        _snapshot = next;
        _emit();
      }),
    );
  }

  void _emit([PlaybackSnapshot? snapshot]) {
    if (_states.isClosed) return;
    _states.add(snapshot ?? _snapshot);
  }
}

/// Redacted stand-in for an mpv error line: the raw text can carry the media
/// URL and token, so the UI only gets the failure class (contract §6, §10.6).
class _PlaybackFailure {
  const _PlaybackFailure();

  @override
  String toString() => 'playback failed';
}
