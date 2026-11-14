import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../core/device/local_subtitle_picker.dart';
import '../../core/device/pip.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/cast/dlna_cast_service.dart';
import '../../data/cast/dlna_device.dart';
import '../../data/danmaku/danmaku_repository.dart';
import '../../data/danmaku/danmaku_settings.dart';
import '../../data/danmaku/models/danmaku_anime.dart';
import '../../data/danmaku/models/danmaku_comment.dart';
import '../../data/library/library_service.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_stream.dart';
import '../../data/models/playback_plan.dart';
import '../../data/playback/playback_engine.dart';
import '../../data/playback/playback_service.dart';
import '../../data/playback/playback_settings.dart';
import '../../data/playback/session_reporter.dart';
import '../../data/playback/subtitle_repository.dart';
import '../../data/playback/track_prefs.dart';
import '../../data/storage/key_value_store.dart';
import 'chapter_skip.dart';

// The constructor exposes public names (`itemId`, `library`, ...) while the
// fields stay private, the same trade-off as `AuthRepository.deviceId`.
// ignore_for_file: prefer_initializing_formals

class PlayerState {
  const PlayerState({
    this.itemName = '',
    this.productionYear,
    this.loading = false,
    this.ready = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.playing = false,
    this.rate = 1.0,
    this.resumedFrom,
    this.videoDirect,
    this.audioTranscoded = false,
    this.error,
    this.unsupported = false,
    this.selectionSeriesId,
    this.unauthorized = false,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.overview,
    this.audioStreams = const <MediaStream>[],
    this.selectedAudio,
    this.subtitleStreams = const <MediaStream>[],
    this.selectedSubtitle,
    this.localSubtitlePath,
    this.subtitleNotice,
    this.subtitleStyle = const SubtitleStyle(),
    this.trackPrefs = const TrackPrefs(),
    this.hasPrevious = false,
    this.hasNext = false,
    this.previousEpisodeId,
    this.nextEpisodeId,
    this.completed = false,
    this.canSkipIntro = false,
    this.canSkipCredits = false,
    this.videoRotation = 0,
    this.aspectMode = 'default',
    this.locked = false,
    this.sleepRemaining,
    this.sleepDuration,
    this.playbackSettings = const PlaybackSettings(),
    this.danmakuSettings = const DanmakuSettings(),
    this.danmakuStatus = DanmakuStatus.idle,
    this.danmakuComments = const <DanmakuComment>[],
    this.danmakuEpisodeLabel,
    this.castDiscovering = false,
    this.castDevices = const <DlnaDevice>[],
    this.castingTo,
    this.castError,
  });

  final String itemName;

  /// Release year, shown in the landscape bottom title `(2004) 名字`.
  final int? productionYear;

  /// Detail fetch plus negotiation are one visible step for the user.
  final bool loading;
  final bool ready;
  final Duration position;
  final Duration duration;
  final bool buffering;
  final bool playing;

  /// Current playback rate (1.0 = normal).
  final double rate;

  /// Non-null when playback started from a stored position (contract §10.9 d),
  /// which the UI has to state explicitly.
  final Duration? resumedFrom;

  /// Null means "not confirmed yet"; never guessed from the URL shape
  /// (contract §10.9 f).
  final bool? videoDirect;
  final bool audioTranscoded;

  /// Already mapped to user-facing Chinese text; raw exceptions never reach
  /// the screen (contract §6).
  final String? error;

  /// The item cannot be played as-is, e.g. a series needs an episode first.
  final bool unsupported;
  final String? selectionSeriesId;
  final bool unauthorized;

  /// Decoded video size for the portrait video box (0 until reported).
  final int videoWidth;
  final int videoHeight;
  final String? overview;

  /// Audio streams of the chosen version, in server order (S5).
  final List<MediaStream> audioStreams;

  /// Index into [audioStreams]; null = the engine's own default track.
  final int? selectedAudio;

  /// Subtitle streams of the chosen version, in server order (B6).
  final List<MediaStream> subtitleStreams;

  /// Index into [subtitleStreams]; null = subtitles off.
  final int? selectedSubtitle;

  /// Local subtitle file mounted this session (添加本地字幕), used directly
  /// without the download cache. Non-null means it is the active selection;
  /// [selectedSubtitle] stays null because the file is not a server stream.
  final String? localSubtitlePath;

  /// Non-fatal subtitle copy (download failure must not interrupt video).
  final String? subtitleNotice;

  /// Rendering preferences (S4), persisted app-wide.
  final SubtitleStyle subtitleStyle;

  /// Track language preferences (S5), persisted app-wide.
  final TrackPrefs trackPrefs;

  /// Continuous play (P1): ordered season neighbors of the loaded episode,
  /// computed by `indexNumber`. Both false for anything that is not an
  /// episode with a resolvable season position.
  final bool hasPrevious;
  final bool hasNext;
  final String? previousEpisodeId;
  final String? nextEpisodeId;

  /// Playback reached the end of the runtime while playing (P1). Latched once
  /// per item; the page listens and decides whether to auto-advance.
  final bool completed;

  /// S12: position currently inside a named intro / credits chapter.
  final bool canSkipIntro;
  final bool canSkipCredits;

  /// Video rotation in degrees (S16): 0 / 90 / 180 / 270, per session.
  final int videoRotation;

  /// Display aspect mode (S16): default / 16:9 / 4:3 / 2.35:1 / fill.
  final String aspectMode;

  /// Interface lock (S16): gestures and the control bar are suppressed while
  /// locked; only the unlock affordance stays live. Per session.
  final bool locked;

  /// Time left on the sleep timer (S16), null when no timer is armed. Ticks
  /// down about once a second so the options sheet can show a countdown.
  final Duration? sleepRemaining;

  /// The originally requested sleep duration (S16), kept so the preset chip
  /// stays selected while [sleepRemaining] counts down. Null when off.
  final Duration? sleepDuration;

  /// App-wide engine preferences (S13 / S16), persisted and applied on open.
  final PlaybackSettings playbackSettings;

  /// Danmaku rendering preferences (S17), persisted app-wide.
  final DanmakuSettings danmakuSettings;

  /// DandanPlay match outcome (S17); a failure is a status line, never an
  /// error banner — playback keeps running.
  final DanmakuStatus danmakuStatus;

  /// Time-sorted comments of the matched episode (S17); empty until matched.
  final List<DanmakuComment> danmakuComments;

  /// The matched anime/episode label for the status line (S17).
  final String? danmakuEpisodeLabel;

  /// DLNA cast (S19): a scan in flight, the renderers found, the one currently
  /// receiving the stream, and a non-fatal error line for the picker.
  final bool castDiscovering;
  final List<DlnaDevice> castDevices;
  final DlnaDevice? castingTo;
  final String? castError;

  static const Object _unset = Object();

  PlayerState copyWith({
    String? itemName,
    bool? loading,
    bool? ready,
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? playing,
    double? rate,
    Object? resumedFrom = _unset,
    Object? videoDirect = _unset,
    bool? audioTranscoded,
    Object? error = _unset,
    bool? unsupported,
    Object? selectionSeriesId = _unset,
    bool? unauthorized,
    int? videoWidth,
    int? videoHeight,
    Object? overview = _unset,
    int? productionYear,
    List<MediaStream>? audioStreams,
    Object? selectedAudio = _unset,
    List<MediaStream>? subtitleStreams,
    Object? selectedSubtitle = _unset,
    Object? localSubtitlePath = _unset,
    Object? subtitleNotice = _unset,
    SubtitleStyle? subtitleStyle,
    TrackPrefs? trackPrefs,
    bool? hasPrevious,
    bool? hasNext,
    Object? previousEpisodeId = _unset,
    Object? nextEpisodeId = _unset,
    bool? completed,
    bool? canSkipIntro,
    bool? canSkipCredits,
    int? videoRotation,
    String? aspectMode,
    bool? locked,
    Object? sleepRemaining = _unset,
    Object? sleepDuration = _unset,
    PlaybackSettings? playbackSettings,
    DanmakuSettings? danmakuSettings,
    DanmakuStatus? danmakuStatus,
    List<DanmakuComment>? danmakuComments,
    Object? danmakuEpisodeLabel = _unset,
    bool? castDiscovering,
    List<DlnaDevice>? castDevices,
    Object? castingTo = _unset,
    Object? castError = _unset,
  }) {
    return PlayerState(
      itemName: itemName ?? this.itemName,
      loading: loading ?? this.loading,
      ready: ready ?? this.ready,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffering: buffering ?? this.buffering,
      playing: playing ?? this.playing,
      rate: rate ?? this.rate,
      resumedFrom: identical(resumedFrom, _unset)
          ? this.resumedFrom
          : resumedFrom as Duration?,
      videoDirect: identical(videoDirect, _unset)
          ? this.videoDirect
          : videoDirect as bool?,
      audioTranscoded: audioTranscoded ?? this.audioTranscoded,
      error: identical(error, _unset) ? this.error : error as String?,
      unsupported: unsupported ?? this.unsupported,
      selectionSeriesId: identical(selectionSeriesId, _unset)
          ? this.selectionSeriesId
          : selectionSeriesId as String?,
      unauthorized: unauthorized ?? this.unauthorized,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      overview: identical(overview, _unset)
          ? this.overview
          : overview as String?,
      productionYear: productionYear ?? this.productionYear,
      audioStreams: audioStreams ?? this.audioStreams,
      selectedAudio: identical(selectedAudio, _unset)
          ? this.selectedAudio
          : selectedAudio as int?,
      subtitleStreams: subtitleStreams ?? this.subtitleStreams,
      selectedSubtitle: identical(selectedSubtitle, _unset)
          ? this.selectedSubtitle
          : selectedSubtitle as int?,
      localSubtitlePath: identical(localSubtitlePath, _unset)
          ? this.localSubtitlePath
          : localSubtitlePath as String?,
      subtitleNotice: identical(subtitleNotice, _unset)
          ? this.subtitleNotice
          : subtitleNotice as String?,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      trackPrefs: trackPrefs ?? this.trackPrefs,
      hasPrevious: hasPrevious ?? this.hasPrevious,
      hasNext: hasNext ?? this.hasNext,
      previousEpisodeId: identical(previousEpisodeId, _unset)
          ? this.previousEpisodeId
          : previousEpisodeId as String?,
      nextEpisodeId: identical(nextEpisodeId, _unset)
          ? this.nextEpisodeId
          : nextEpisodeId as String?,
      completed: completed ?? this.completed,
      canSkipIntro: canSkipIntro ?? this.canSkipIntro,
      canSkipCredits: canSkipCredits ?? this.canSkipCredits,
      videoRotation: videoRotation ?? this.videoRotation,
      aspectMode: aspectMode ?? this.aspectMode,
      locked: locked ?? this.locked,
      sleepRemaining: identical(sleepRemaining, _unset)
          ? this.sleepRemaining
          : sleepRemaining as Duration?,
      sleepDuration: identical(sleepDuration, _unset)
          ? this.sleepDuration
          : sleepDuration as Duration?,
      playbackSettings: playbackSettings ?? this.playbackSettings,
      danmakuSettings: danmakuSettings ?? this.danmakuSettings,
      danmakuStatus: danmakuStatus ?? this.danmakuStatus,
      danmakuComments: danmakuComments ?? this.danmakuComments,
      danmakuEpisodeLabel: identical(danmakuEpisodeLabel, _unset)
          ? this.danmakuEpisodeLabel
          : danmakuEpisodeLabel as String?,
      castDiscovering: castDiscovering ?? this.castDiscovering,
      castDevices: castDevices ?? this.castDevices,
      castingTo: identical(castingTo, _unset)
          ? this.castingTo
          : castingTo as DlnaDevice?,
      castError: identical(castError, _unset)
          ? this.castError
          : castError as String?,
    );
  }
}

/// Drives one playback session: resume, negotiation, engine and reporting
/// (contract §3.4, §3.6, §10.9).
///
/// Engine and reporter are injected per instance because each playback owns
/// exactly one of them (libmpv instance / "already stopped" flag).
class PlayerController extends ChangeNotifier {
  PlayerController({
    required String itemId,
    required LibraryService library,
    required PlaybackService playback,
    required PlaybackEngine engine,
    required PlaybackReporter reporter,
    SubtitleService? subtitles,
    LocalSubtitlePicker? localSubtitlePicker,
    PipController? pip,
    DanmakuService? danmaku,
    DlnaCastService? cast,
    KeyValueStore? store,
    String? preferredSourceId,
    Directory? screenshotDirectory,
    this.pauseWhileCapturing = false,
    Duration probeDelay = const Duration(seconds: 3),
    Future<void> Function(Duration)? delay,
  }) : _itemId = itemId,
       _library = library,
       _playback = playback,
       _engine = engine,
       _reporter = reporter,
       _subtitles = subtitles,
       _localSubtitlePicker = localSubtitlePicker,
       _pip = pip,
       _danmaku = danmaku,
       _cast = cast,
       _store = store,
       _preferredSourceId = preferredSourceId,
       _screenshotDirectory = screenshotDirectory,
       _probeDelay = probeDelay,
       _delay = delay ?? Future<void>.delayed;

  /// Contract §10.9 d: resume only past this much playback.
  static const Duration _resumeThreshold = Duration(seconds: 10);

  /// The loaded item (null before `load()`), used by the portrait 选集 strip.
  MediaItem? get item => _item;

  /// App-wide subtitle rendering preferences (S4).
  static const String styleKey = SubtitleStyle.storageKey;

  /// App-wide track language preferences (S5).
  static const String trackPrefsKey = TrackPrefs.storageKey;

  /// App-wide engine preferences (S13 / S16). Shared with the settings page
  /// through [PlaybackSettings.storageKey] so both read and write one key.
  static const String playbackSettingsKey = PlaybackSettings.storageKey;

  /// App-wide danmaku preferences (S17).
  static const String danmakuSettingsKey = DanmakuSettings.storageKey;

  /// How long playback may stay stuck before an engine error line becomes the
  /// visible "播放失败" copy. mpv logs errors for trouble it recovers from
  /// (retried range requests, skipped frames), so the line alone proves
  /// nothing; a frozen position is the evidence.
  static const Duration _failureGrace = Duration(seconds: 2);

  /// The same window while the engine is filling its buffer. A network stall
  /// is expected to recover, so it only becomes copy once it looks permanent.
  static const Duration _bufferingFailureGrace = Duration(seconds: 20);

  /// Continuous play (P1): the last snapshot may stop a hair short of the
  /// runtime, so "reached the end" tolerates this much before the duration.
  static const Duration _completionEpsilon = Duration(milliseconds: 500);

  final String _itemId;
  final LibraryService _library;
  final PlaybackService _playback;
  final PlaybackEngine _engine;
  final PlaybackReporter _reporter;
  final SubtitleService? _subtitles;

  /// Local file picker (添加本地字幕); null only in harnesses that never pick.
  final LocalSubtitlePicker? _localSubtitlePicker;

  /// Android picture-in-picture (S18); null only in harnesses that never
  /// enter PIP.
  final PipController? _pip;

  /// DandanPlay match + comments (S17); null only in harnesses that never
  /// load danmaku.
  final DanmakuService? _danmaku;

  /// DLNA discovery + cast control (S19); null only in harnesses that never
  /// cast.
  final DlnaCastService? _cast;
  final KeyValueStore? _store;

  /// Version picked on the detail page (S7); null keeps the server default.
  final String? _preferredSourceId;

  /// Where screenshots are written (S16); null falls back to the system temp
  /// directory. Injected so tests never touch a real cache path.
  final Directory? _screenshotDirectory;

  /// S42: pause the picture while a screenshot is captured, then resume.
  final bool pauseWhileCapturing;

  final Duration _probeDelay;
  final Future<void> Function(Duration) _delay;

  PlayerState _state = const PlayerState();
  SubtitleStyle _style = const SubtitleStyle();
  TrackPrefs _trackPrefs = const TrackPrefs();
  PlaybackSettings _settings = const PlaybackSettings();
  DanmakuSettings _danmakuSettings = const DanmakuSettings();

  /// The loaded detail item (S17): enabling danmaku mid-session re-matches
  /// against it without a second library round-trip.
  MediaItem? _item;

  /// Intro/credits skip targets resolved from the item's chapters (S12).
  ChapterSkip _skip = const ChapterSkip();

  /// S23: a persisted gpu-next VO is applied once the first frame renders (wid
  /// valid), never at load before the Android surface is attached.
  bool _voApplied = false;

  /// Sleep timer (S16): a 1 s tick counts [_sleepLeft] down and pauses when it
  /// reaches zero. A countdown (not a wall-clock deadline) so fakeAsync tests
  /// can drive it without real time passing.
  Timer? _sleepTick;
  Duration _sleepLeft = Duration.zero;

  /// Explicit user picks made this session (S5): auto-match must never
  /// override them, including when preferences are re-applied live.
  bool _audioUserSelected = false;
  bool _subtitleUserSelected = false;
  PlaybackPlan? _plan;
  StreamSubscription<PlaybackSnapshot>? _ticks;
  Timer? _failureWatch;
  Duration? _failurePosition;
  bool _failureWaitedBuffer = false;
  bool _userPaused = false;

  /// Continuous play (P1): completion is announced once per item, even if the
  /// engine keeps emitting end-of-runtime snapshots afterwards.
  bool _completionNotified = false;
  Widget? _surface;
  Duration _lastTrustedPosition = Duration.zero;
  Future<void>? _stopFuture;
  bool _stopped = false;
  bool _disposed = false;

  PlayerState get state => _state;

  /// The version pinned for this session (S7). Episode navigation passes it
  /// on through `AppRoutes.playerFor(..., source:)` so the next episode keeps
  /// the same version (P1 continuous play).
  String? get preferredSourceId => _preferredSourceId;

  /// Continuous play (P1): the neighbor to play, or null when there is none.
  /// Navigation belongs to the page; the controller stays navigation-free and
  /// only exposes the ids computed from the season's `indexNumber` order.
  String? playPrevious() => _state.previousEpisodeId;

  String? playNext() => _state.nextEpisodeId;

  Duration get _reportPosition => _lastTrustedPosition;

  /// The engine owns the render widget (contract §10.9 b). Cached so the
  /// platform view is created once instead of on every rebuild.
  Widget get surface => _surface ??= _engine.createSurface();

  Future<void> load() async {
    if (_disposed || _stopped || _state.loading) return;

    _cancelFailureWatch();
    _failurePosition = null;
    _userPaused = false;
    _completionNotified = false;
    _skip = const ChapterSkip();
    _voApplied = false;
    _set(
      _state.copyWith(
        loading: true,
        error: null,
        unsupported: false,
        selectionSeriesId: null,
        unauthorized: false,
        completed: false,
        canSkipIntro: false,
        canSkipCredits: false,
        castDiscovering: false,
        castDevices: const <DlnaDevice>[],
        castingTo: null,
        castError: null,
        hasPrevious: false,
        hasNext: false,
        previousEpisodeId: null,
        nextEpisodeId: null,
      ),
    );

    _style = await _loadStyle();
    if (_disposed || _stopped) return;
    _trackPrefs = await _loadTrackPrefs();
    if (_disposed || _stopped) return;
    _settings = await _loadSettings();
    if (_disposed || _stopped) return;
    _danmakuSettings = await _loadDanmakuSettings();
    if (_disposed || _stopped) return;
    _set(
      _state.copyWith(
        subtitleStyle: _style,
        trackPrefs: _trackPrefs,
        playbackSettings: _settings,
        danmakuSettings: _danmakuSettings,
      ),
    );

    try {
      final item = await _library.item(_itemId);
      if (_disposed || _stopped) return;
      _item = item;
      _skip = resolveChapterSkip(
        item.chapters,
        isEpisode: item.type == 'Episode',
        duration: item.duration,
      );
      _set(
        _state.copyWith(
          itemName: item.name,
          productionYear: item.productionYear,
          duration: item.duration,
          overview: item.overview,
        ),
      );
      _updateSkipFlags(_state.position);

      // Continuous play (P1): the season list is fetched beside the
      // negotiation so a slow library never delays the start; a failure only
      // means no neighbors, never a broken playback.
      if (item.type == 'Episode' &&
          item.seriesId != null &&
          item.seasonId != null) {
        unawaited(_loadNeighbors(item));
      }

      // Picking an episode belongs to the series page, so stop before
      // negotiating: /PlaybackInfo on a series id has no playable source.
      if (item.type == 'Series') {
        _set(
          _state.copyWith(
            loading: false,
            unsupported: true,
            selectionSeriesId: item.id,
            error: '请选择分集后播放',
          ),
        );
        return;
      }

      // S17: danmaku auto-match runs beside playback setup when enabled; a
      // failure only surfaces a status line, never an error banner.
      if (_danmakuSettings.enabled) unawaited(_loadDanmaku(item));

      // Contract §10.9 d: > 10 s and not finished resumes, everything else
      // starts from zero.
      final userData = item.userData;
      final resume = !userData.played && userData.position > _resumeThreshold;
      final startAt = resume ? userData.position : Duration.zero;

      final plan = await _playback.resolve(
        _itemId,
        startAt: startAt,
        mediaSourceId: _preferredSourceId,
      );
      if (_disposed || _stopped) return;
      _plan = plan;

      await _ticks?.cancel();
      if (_disposed || _stopped) return;
      // Reset at open (including a genuine zero start); uncommanded zero
      // snapshots may be teardown noise. A completed ready-state seek below
      // explicitly accepts zero, so seeking to the beginning is not lost.
      _lastTrustedPosition = startAt;
      _ticks = _engine.state.listen(_onSnapshot);

      await _engine.open(plan);
      if (_disposed || _stopped) return;
      await _engine.setSubtitleStyle(_style);
      if (_disposed || _stopped) return;
      // S13 / S16: hardware decoding, volume ceiling and cache sizing are
      // engine properties, so they apply once the player is open.
      await _applyEngineSettings();
      if (_disposed || _stopped) return;
      _set(
        _state.copyWith(
          loading: false,
          ready: true,
          position: startAt,
          resumedFrom: resume ? startAt : null,
          // PlaybackInfo probes STRM sources; the detail response's stream
          // indices can be stale, so the menu follows the negotiated plan.
          subtitleStreams: plan.subtitles,
          audioStreams: plan.audios,
          selectedAudio: null,
        ),
      );

      // S5 auto-match: once the negotiated streams are known, a preferred
      // language picks its track; empty preferences keep the engine default.
      await _applyTrackPrefs();
      if (_disposed || _stopped) return;

      // Heartbeats and final reports share the teardown-safe position.
      await _reporter.started(plan, startAt, position: () => _reportPosition);

      unawaited(_confirmDirect(plan));
    } catch (error) {
      // Nothing may escape into the widget tree; §6 codes and anything else
      // both end up as mapped copy.
      _fail(error);
    }
  }

  /// Continuous play (P1): ordered neighbors of [item] within its season.
  /// Episodes sort by `indexNumber`; entries without one keep the server
  /// order at the end (`List.sort` is not stable, so ties fall back to the
  /// original position). An item missing from its season list has no
  /// neighbors rather than a guessed position.
  Future<void> _loadNeighbors(MediaItem item) async {
    try {
      final List<MediaItem> episodes = await _library.episodes(
        seriesId: item.seriesId!,
        seasonId: item.seasonId!,
      );
      if (_disposed || _stopped) return;
      final List<(int, MediaItem)> ordered = episodes.indexed.toList()
        ..sort(((int, MediaItem) a, (int, MediaItem) b) {
          final int? ai = a.$2.indexNumber;
          final int? bi = b.$2.indexNumber;
          if (ai != null && bi != null && ai != bi) return ai.compareTo(bi);
          if (ai == null && bi != null) return 1;
          if (ai != null && bi == null) return -1;
          return a.$1.compareTo(b.$1);
        });
      final int index = ordered.indexWhere(
        ((int, MediaItem) e) => e.$2.id == item.id,
      );
      if (index < 0) return;
      final String? previous = index > 0 ? ordered[index - 1].$2.id : null;
      final String? next = index < ordered.length - 1
          ? ordered[index + 1].$2.id
          : null;
      _set(
        _state.copyWith(
          hasPrevious: previous != null,
          hasNext: next != null,
          previousEpisodeId: previous,
          nextEpisodeId: next,
        ),
      );
    } catch (_) {
      // Neighbors are optional: a failed season fetch must not interrupt the
      // running playback or surface an error banner.
    }
  }

  Future<void> togglePlayPause() async {
    final plan = _plan;
    if (_disposed || _stopped || !_state.ready || plan == null) return;

    final wasPlaying = _state.playing;
    // The engine reporting `playing: false` also means "stopped by a dead
    // stream", so only this flag tells the failure check that the user asked
    // for the pause.
    _userPaused = wasPlaying;
    if (wasPlaying) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
    if (_disposed || _stopped) return;
    // Flipped eagerly so the button reacts; the engine stream stays
    // authoritative and overwrites this on the next snapshot.
    _set(_state.copyWith(playing: !wasPlaying));

    // Contract §10.9 c: pause / resume reports immediately, next to the
    // 10 s heartbeat.
    await _reporter.progress(plan, _reportPosition, paused: wasPlaying);
  }

  Future<void> seekTo(Duration position) async {
    final plan = _plan;
    if (_disposed || _stopped || !_state.ready || plan == null) return;

    await _engine.seekTo(position);
    if (_disposed || _stopped) return;
    _lastTrustedPosition = position;
    _set(_state.copyWith(position: position));
    _updateSkipFlags(position);

    // Contract §10.9 c: a finished seek reports immediately.
    await _reporter.progress(plan, _reportPosition, paused: !_state.playing);
  }

  /// S12: jump past the intro chapter to the start of the content. No-op when
  /// the item carried no usable intro marker.
  Future<void> skipIntro() async {
    final end = _skip.introEnd;
    if (_disposed || _stopped || end == null) return;
    await seekTo(end);
  }

  /// S12: jump to the runtime so the credits are skipped and completion (and
  /// thus auto-next) fires. No-op without a credits marker or a known runtime.
  Future<void> skipCredits() async {
    if (_disposed || _stopped || !_skip.hasCredits) return;
    final total = _state.duration;
    if (total <= Duration.zero) return;
    await seekTo(total);
  }

  /// Offers a skip only while the position sits inside its range; the intro
  /// button disappears once content starts, the credits button once it ends.
  void _updateSkipFlags(Duration position) {
    final intro =
        _skip.hasIntro &&
        position >= _skip.introStart! &&
        position < _skip.introEnd!;
    final credits = _skip.hasCredits && position >= _skip.creditsStart!;
    if (intro != _state.canSkipIntro || credits != _state.canSkipCredits) {
      _set(_state.copyWith(canSkipIntro: intro, canSkipCredits: credits));
    }
  }

  /// S19: scans the LAN for DLNA renderers. A failed scan is a picker line,
  /// never a playback error.
  Future<void> discoverCastDevices() async {
    final cast = _cast;
    if (_disposed || _stopped || cast == null) return;
    _set(_state.copyWith(castDiscovering: true, castError: null));
    try {
      final devices = await cast.discover();
      if (_disposed || _stopped) return;
      _set(_state.copyWith(castDiscovering: false, castDevices: devices));
    } catch (_) {
      if (_disposed || _stopped) return;
      _set(_state.copyWith(castDiscovering: false, castError: '未发现投屏设备'));
    }
  }

  /// S19: hands the current stream to [device] and pauses local playback so the
  /// audio is not doubled. The renderer fetches the URL itself, so it must carry
  /// `api_key` (header auth is invisible to it).
  Future<void> castTo(DlnaDevice device) async {
    final cast = _cast;
    final url = _castUrl;
    if (_disposed || _stopped || cast == null || url == null) return;
    try {
      await cast.cast(device, url, title: _castTitle);
      if (_disposed || _stopped) return;
      _set(_state.copyWith(castingTo: device, castError: null));
      if (_state.playing) await togglePlayPause();
    } catch (_) {
      if (_disposed || _stopped) return;
      _set(_state.copyWith(castError: '投屏失败，请重试'));
    }
  }

  /// S19: stops the renderer and clears the cast target. Local playback stays
  /// paused; the user resumes it explicitly.
  Future<void> stopCast() async {
    final cast = _cast;
    final device = _state.castingTo;
    if (_disposed || cast == null || device == null) return;
    try {
      await cast.stop(device);
    } catch (_) {
      // A renderer that already stopped or left the LAN must not block clearing
      // the local cast state.
    }
    if (_disposed || _stopped) return;
    _set(_state.copyWith(castingTo: null));
  }

  /// The negotiated URL with `api_key` guaranteed in the query; the logic
  /// lives on [PlaybackPlan.castUrl] so the detail page shares it (S38).
  String? get _castUrl => _plan?.castUrl;

  String get _castTitle => _item?.name ?? _state.itemName;

  /// [zeroToOne] is the slider value; [PlaybackEngine.setVolume] takes the
  /// player's own 0–100 scale, so the conversion lives here and nowhere else.
  /// Volume gain (S16) raises the ceiling above 100%, and the slider spans the
  /// full gained range so the boost is actually reachable.
  Future<void> setVolume(double zeroToOne) async {
    if (_disposed || _stopped) return;
    final level = zeroToOne.clamp(0.0, 1.0);
    await _engine.setVolume(level * _settings.volumeGainPercent);
  }

  /// Reserved subtitle band so controls never cover subtitles (Yamby parity).
  Future<void> setSubtitleBottomMargin(double pixels) =>
      _engine.setSubtitleBottomMargin(pixels);

  /// S78: portrait forces margins on so ASS dialogue follows the reserved band
  /// too; landscape hands the choice back to the 黑边 setting.
  Future<void> setSubtitleMarginsEnabled(bool enabled) =>
      _engine.setSubtitleMarginsEnabled(enabled);

  /// Playback speed (S2); the UI offers presets, the engine takes any rate.
  Future<void> setRate(double rate) async {
    if (_disposed || _stopped) return;
    await _engine.setRate(rate);
    if (_disposed || _stopped) return;
    _set(_state.copyWith(rate: rate));
  }

  /// Subtitle rendering preferences (S4): applied live and persisted for the
  /// next playback.
  Future<void> setSubtitleStyle(SubtitleStyle style) async {
    if (_disposed || _stopped) return;
    _style = style;
    _set(_state.copyWith(subtitleStyle: style));
    await _engine.setSubtitleStyle(style);
    final store = _store;
    if (store != null) {
      unawaited(store.write(styleKey, jsonEncode(style.toJson())));
    }
  }

  /// Live decoder/render diagnostics for the debug panel (播放详情).
  Future<PlaybackStats> readStats() => _engine.readStats();

  /// S16: set the video rotation to an explicit angle (0 / 90 / 180 / 270).
  /// Per session; the engine normalizes any other multiple of 90.
  Future<void> setVideoRotation(int degrees) async {
    if (_disposed || _stopped) return;
    final int normalized = ((degrees % 360) + 360) % 360;
    await _engine.setVideoRotation(normalized);
    if (_disposed || _stopped) return;
    _set(_state.copyWith(videoRotation: normalized));
  }

  /// S16: step the rotation by 90° (the rotate affordance).
  Future<void> rotateVideo() => setVideoRotation(_state.videoRotation + 90);

  /// S16: display aspect mode (default / 16:9 / 4:3 / 2.35:1 / fill).
  Future<void> setAspectMode(String mode) async {
    if (_disposed || _stopped) return;
    await _engine.setAspectMode(mode);
    if (_disposed || _stopped) return;
    _set(_state.copyWith(aspectMode: mode));
  }

  /// S13: flip hardware decoding, applied live and persisted for next time.
  Future<void> toggleHwdec() async {
    if (_disposed || _stopped) return;
    final bool enabled = !_settings.hwdecEnabled;
    _saveSettings(_settings.copyWith(hwdecEnabled: enabled));
    await _engine.setHwdecEnabled(enabled);
  }

  /// S16: volume gain ceiling in percent (100 = no gain). Applied live and
  /// persisted; the volume slider spans the gained range.
  Future<void> setVolumeGain(double percent) async {
    if (_disposed || _stopped) return;
    final double gain = percent.clamp(100.0, 1000.0);
    _saveSettings(_settings.copyWith(volumeGainPercent: gain));
    await _engine.setVolumeMax(gain);
  }

  /// S23: advanced video options (gpu-next renderer / deband / yuv420p).
  /// Applied live and persisted for the next playback; null fields keep the
  /// current value so each switch only touches its own flag. Anime4K is
  /// intentionally omitted: it needs external GLSL shader files.
  Future<void> setAdvancedVideo({
    bool? gpuNext,
    bool? deband,
    bool? yuv420,
  }) async {
    if (_disposed || _stopped) return;
    final PlaybackSettings next = _settings.copyWith(
      gpuNext: gpuNext,
      deband: deband,
      yuv420: yuv420,
    );
    _saveSettings(next);
    await _engine.setAdvancedVideo(
      gpuNext: next.gpuNext,
      deband: next.deband,
      yuv420: next.yuv420,
    );
  }

  /// S16: arm (or re-arm) the sleep timer; null cancels it. When it fires the
  /// player pauses and [PlayerState.sleepRemaining] clears.
  void setSleepTimer(Duration? duration) {
    if (_disposed || _stopped) return;
    _cancelSleepTick();
    if (duration == null || duration <= Duration.zero) {
      _set(_state.copyWith(sleepRemaining: null, sleepDuration: null));
      return;
    }
    _sleepLeft = duration;
    _set(_state.copyWith(sleepRemaining: duration, sleepDuration: duration));
    _sleepTick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _onSleepTick(),
    );
  }

  /// S16: cancel any armed sleep timer.
  void cancelSleepTimer() => setSleepTimer(null);

  /// S16: toggle the interface lock. While locked the page suppresses gestures
  /// and the control bar, leaving only the unlock affordance live.
  void toggleLock() {
    if (_disposed || _stopped) return;
    _set(_state.copyWith(locked: !_state.locked));
  }

  /// S16: capture the current frame (subtitles included) into the cache/temp
  /// directory and return the written path, or null on failure.
  Future<String?> takeScreenshot() async {
    if (_disposed || _stopped) return null;
    // S42: Yamby's 截图时暂停视频. The resume happens in `finally`, so a failed
    // capture still leaves playback running.
    final bool pauseFirst = pauseWhileCapturing && _state.playing;
    if (pauseFirst) {
      await togglePlayPause();
      if (_disposed || _stopped) return null;
    }
    try {
      final Directory dir = _screenshotDirectory ?? Directory.systemTemp;
      // Synchronous stat/mkdir: a screenshot is a rare, user-initiated action
      // and this keeps the path resolution free of real async I/O (which widget
      // tests cannot pump). The engine call below is the only await.
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final String name =
          'screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      final String path = '${dir.path}${Platform.pathSeparator}$name';
      return await _engine.takeScreenshot(path);
    } catch (_) {
      return null;
    } finally {
      if (pauseFirst && !_disposed && !_stopped) {
        await togglePlayPause();
      }
    }
  }

  /// S18: enter Android picture-in-picture. False when no PIP entry is wired
  /// or the platform refused; playback keeps running either way — the activity
  /// is not paused, so no engine or reporter handling is needed here.
  Future<bool> enterPip() async {
    if (_disposed || _stopped) return false;
    final PipController? pip = _pip;
    if (pip == null) return false;
    try {
      return await pip.enterPip();
    } catch (_) {
      return false;
    }
  }

  void _onSleepTick() {
    if (_disposed || _stopped) {
      _cancelSleepTick();
      return;
    }
    _sleepLeft -= const Duration(seconds: 1);
    if (_sleepLeft > Duration.zero) {
      _set(_state.copyWith(sleepRemaining: _sleepLeft));
      return;
    }
    _cancelSleepTick();
    _set(_state.copyWith(sleepRemaining: null, sleepDuration: null));
    unawaited(_pauseForSleep());
  }

  /// The sleep timer pausing is a user-style pause: it reports immediately and
  /// must not be mistaken for a dead stream by the failure watch.
  Future<void> _pauseForSleep() async {
    final plan = _plan;
    _userPaused = true;
    await _engine.pause();
    if (_disposed || _stopped) return;
    _set(_state.copyWith(playing: false));
    if (plan != null) {
      await _reporter.progress(plan, _reportPosition, paused: true);
    }
  }

  void _cancelSleepTick() {
    _sleepTick?.cancel();
    _sleepTick = null;
  }

  /// Applies the persisted engine preferences to the running player (S13/S16).
  Future<void> _applyEngineSettings() async {
    await _engine.setHwdecEnabled(_settings.hwdecEnabled);
    if (_disposed || _stopped) return;
    await _engine.setForceStereo(_settings.forceStereo);
    if (_disposed || _stopped) return;
    await _engine.setVolumeMax(_settings.volumeGainPercent);
    if (_disposed || _stopped) return;
    await _engine.setCacheConfig(
      cacheSecs: _settings.cacheSecs,
      demuxerMaxBytes: _settings.demuxerMaxBytes,
    );
    if (_disposed || _stopped) return;
    // S23: advanced video options are engine properties too. The VO switch is
    // deferred (applyVo:false): forcing it here, before media_kit attaches the
    // Android surface, aborts on libmpv's WinID assertion. media_kit selects
    // the default VO once wid is ready; a persisted gpu-next is applied on the
    // first rendered frame (see _onSnapshot).
    await _engine.setAdvancedVideo(
      gpuNext: _settings.gpuNext,
      deband: _settings.deband,
      yuv420: _settings.yuv420,
      applyVo: false,
    );
  }

  void _saveSettings(PlaybackSettings next) {
    _settings = next;
    _set(_state.copyWith(playbackSettings: next));
    final store = _store;
    if (store != null) {
      unawaited(store.write(playbackSettingsKey, jsonEncode(next.toJson())));
    }
  }

  Future<PlaybackSettings> _loadSettings() async {
    final store = _store;
    if (store == null) return _settings;
    final raw = await store.read(playbackSettingsKey);
    if (raw == null) return _settings;
    try {
      return PlaybackSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return _settings;
    }
  }

  /// S17: danmaku preferences, applied live and persisted for the next
  /// playback. Turning danmaku on (re)starts the match when nothing is loaded
  /// yet; turning it off only hides the overlay, the comments stay cached.
  Future<void> setDanmakuSettings(DanmakuSettings next) async {
    if (_disposed || _stopped) return;
    final bool wasEnabled = _danmakuSettings.enabled;
    _danmakuSettings = next;
    _set(_state.copyWith(danmakuSettings: next));
    final store = _store;
    if (store != null) {
      unawaited(store.write(danmakuSettingsKey, jsonEncode(next.toJson())));
    }
    final MediaItem? item = _item;
    if (next.enabled &&
        !wasEnabled &&
        item != null &&
        _state.danmakuComments.isEmpty &&
        _state.danmakuStatus != DanmakuStatus.loading) {
      unawaited(_loadDanmaku(item));
    }
  }

  /// S17: the 弹幕 switch in the player options sheet.
  Future<void> toggleDanmaku() => setDanmakuSettings(
    _danmakuSettings.copyWith(enabled: !_danmakuSettings.enabled),
  );

  Future<DanmakuSettings> _loadDanmakuSettings() async {
    final store = _store;
    if (store == null) return _danmakuSettings;
    final raw = await store.read(danmakuSettingsKey);
    if (raw == null) return _danmakuSettings;
    try {
      return DanmakuSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return _danmakuSettings;
    }
  }

  /// S17: match + fetch beside playback. The service contract never throws,
  /// but nothing may escape into the widget tree either way: a failure is the
  /// non-fatal [DanmakuStatus.error] status line, playback keeps running.

  /// S43: free-text anime search for the manual-match sheet; a transport
  /// failure is an empty result, never an exception in the UI.
  Future<List<DanmakuAnime>> searchDanmaku(String title) async {
    final DanmakuService? service = _danmaku;
    if (_disposed || service == null) return const <DanmakuAnime>[];
    try {
      return await service.search(title);
    } catch (_) {
      return const <DanmakuAnime>[];
    }
  }

  /// S43: remembers [episode] for the current item and shows its comments.
  Future<bool> applyDanmakuMatch(
    DanmakuAnime anime,
    DanmakuEpisode episode,
  ) async {
    final DanmakuService? service = _danmaku;
    final MediaItem? item = _item;
    if (_disposed || _stopped || service == null || item == null) return false;
    final DanmakuLoad load;
    try {
      load = await service.applyManual(item, anime, episode);
    } catch (_) {
      return false;
    }
    if (_disposed || _stopped) return false;
    _set(
      _state.copyWith(
        danmakuStatus: load.status,
        danmakuComments: load.comments,
        danmakuEpisodeLabel: load.episodeLabel,
      ),
    );
    return load.status == DanmakuStatus.matched;
  }

  /// S43: forgets the manual match and re-runs the automatic one.
  Future<void> clearDanmakuMatch() async {
    final DanmakuService? service = _danmaku;
    final MediaItem? item = _item;
    if (_disposed || _stopped || service == null || item == null) return;
    await service.clearManual(item.id);
    if (_disposed || _stopped) return;
    await _loadDanmaku(item);
  }

  /// True when the current item has a remembered manual match (S43).
  Future<bool> hasManualDanmakuMatch() async {
    final DanmakuService? service = _danmaku;
    final MediaItem? item = _item;
    if (service == null || item == null) return false;
    try {
      return await service.isManual(item);
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadDanmaku(MediaItem item) async {
    final DanmakuService? danmaku = _danmaku;
    if (danmaku == null) return;
    _set(_state.copyWith(danmakuStatus: DanmakuStatus.loading));
    try {
      final DanmakuLoad load = await danmaku.loadFor(item);
      if (_disposed || _stopped) return;
      _set(
        _state.copyWith(
          danmakuStatus: load.status,
          danmakuComments: load.comments,
          danmakuEpisodeLabel: load.episodeLabel,
        ),
      );
    } catch (_) {
      if (_disposed || _stopped) return;
      _set(
        _state.copyWith(
          danmakuStatus: DanmakuStatus.error,
          danmakuComments: const <DanmakuComment>[],
          danmakuEpisodeLabel: null,
        ),
      );
    }
  }

  Future<SubtitleStyle> _loadStyle() async {
    final store = _store;
    if (store == null) return _style;
    final raw = await store.read(styleKey);
    if (raw == null) return _style;
    try {
      return SubtitleStyle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return _style;
    }
  }

  /// Track language preferences (S5): persisted for the next playback and
  /// re-applied to the running session. Explicit picks made this session stay
  /// untouched; the new preference takes over on the next playback.
  Future<void> setTrackPrefs(TrackPrefs prefs) async {
    if (_disposed || _stopped) return;
    _trackPrefs = prefs;
    _set(_state.copyWith(trackPrefs: prefs));
    final store = _store;
    if (store != null) {
      unawaited(store.write(trackPrefsKey, jsonEncode(prefs.toJson())));
    }
    await _applyTrackPrefs();
  }

  Future<TrackPrefs> _loadTrackPrefs() async {
    final store = _store;
    if (store == null) return _trackPrefs;
    final raw = await store.read(trackPrefsKey);
    if (raw == null) return _trackPrefs;
    try {
      return TrackPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return _trackPrefs;
    }
  }

  /// Auto-match (S5): a non-empty preferred language selects the first
  /// matching stream, per kind. Empty preference, no match or an explicit
  /// user pick this session all leave the current track alone.
  Future<void> _applyTrackPrefs() async {
    if (!_audioUserSelected && _trackPrefs.audioLanguage.isNotEmpty) {
      final int index = _state.audioStreams.indexWhere(
        (MediaStream s) =>
            trackLanguageMatches(_trackPrefs.audioLanguage, s.language),
      );
      if (index >= 0 && index != _state.selectedAudio) {
        await _engine.selectAudioTrack(index);
        if (_disposed || _stopped) return;
        _set(_state.copyWith(selectedAudio: index));
      }
    }
    if (_disposed || _stopped) return;
    if (!_subtitleUserSelected && _trackPrefs.subtitleLanguage.isNotEmpty) {
      final int index = _state.subtitleStreams.indexWhere(
        (MediaStream s) =>
            trackLanguageMatches(_trackPrefs.subtitleLanguage, s.language),
      );
      if (index >= 0 && index != _state.selectedSubtitle) {
        // Same path as a user pick (external download included), but without
        // marking the choice as explicit.
        await _selectSubtitle(index);
      }
    }
  }

  /// Audio track selection (S5): index into [PlayerState.audioStreams] in
  /// server order; the engine maps it onto its own track list.
  Future<void> selectAudio(int index) async {
    if (_disposed || _stopped) return;
    final streams = _state.audioStreams;
    if (index < 0 || index >= streams.length) return;
    _audioUserSelected = true;
    await _engine.selectAudioTrack(index);
    if (_disposed || _stopped) return;
    _set(_state.copyWith(selectedAudio: index));
  }

  /// Subtitle selection (B6): null = off, embedded = mpv track by server order,
  /// external = download to cache then mount as a file. A download failure only
  /// surfaces a notice; the video keeps playing (contract §3.7).
  Future<void> selectSubtitle(int? index) async {
    if (_disposed || _stopped) return;
    // An explicit pick (including "off") outranks auto-match for this session.
    _subtitleUserSelected = true;
    await _selectSubtitle(index);
  }

  Future<void> _selectSubtitle(int? index) async {
    if (_disposed || _stopped) return;
    if (index == null) {
      await _engine.selectSubtitleTrack(null);
      if (_disposed || _stopped) return;
      _set(
        _state.copyWith(
          selectedSubtitle: null,
          localSubtitlePath: null,
          subtitleNotice: null,
        ),
      );
      return;
    }
    final streams = _state.subtitleStreams;
    if (index < 0 || index >= streams.length) return;
    final MediaStream stream = streams[index];

    if (!stream.isExternal) {
      await _engine.selectSubtitleTrack(index);
      if (_disposed || _stopped) return;
      _set(
        _state.copyWith(
          selectedSubtitle: index,
          localSubtitlePath: null,
          subtitleNotice: null,
        ),
      );
      return;
    }

    final SubtitleService? subtitles = _subtitles;
    final PlaybackPlan? plan = _plan;
    if (subtitles == null || plan == null) {
      _set(_state.copyWith(subtitleNotice: '外挂字幕不可用'));
      return;
    }
    try {
      final String path = await subtitles.externalFile(
        itemId: _itemId,
        mediaSourceId: plan.mediaSourceId,
        stream: stream,
      );
      if (_disposed || _stopped) return;
      await _engine.selectSubtitleTrack(null, externalPath: path);
      if (_disposed || _stopped) return;
      _set(
        _state.copyWith(
          selectedSubtitle: index,
          localSubtitlePath: null,
          subtitleNotice: null,
        ),
      );
    } on EmbyException {
      if (_disposed || _stopped) return;
      _set(_state.copyWith(subtitleNotice: '字幕加载失败'));
    }
  }

  /// Mounts a user-picked local subtitle file (添加本地字幕). The file is used
  /// directly — no download or copy through [SubtitleService] — and becomes
  /// the active selection until another track is picked. Cancel changes
  /// nothing; a picker or mount failure only surfaces the non-fatal notice.
  Future<void> addLocalSubtitle() async {
    if (_disposed || _stopped) return;
    final LocalSubtitlePicker? picker = _localSubtitlePicker;
    if (picker == null) {
      _set(_state.copyWith(subtitleNotice: '本地字幕不可用'));
      return;
    }
    final String? path;
    try {
      path = await picker.pick();
    } catch (_) {
      if (_disposed || _stopped) return;
      _set(_state.copyWith(subtitleNotice: '字幕加载失败'));
      return;
    }
    if (_disposed || _stopped || path == null) return;
    try {
      await _engine.selectSubtitleTrack(null, externalPath: path);
    } catch (_) {
      if (_disposed || _stopped) return;
      _set(_state.copyWith(subtitleNotice: '字幕加载失败'));
      return;
    }
    if (_disposed || _stopped) return;
    // An explicit pick outranks auto-match for this session (S5).
    _subtitleUserSelected = true;
    _set(
      _state.copyWith(
        selectedSubtitle: null,
        localSubtitlePath: path,
        subtitleNotice: null,
      ),
    );
  }

  /// Re-mounts the local file picked earlier this session, e.g. after an
  /// embedded track was tried. No-op when no local file is active.
  Future<void> selectLocalSubtitle() async {
    if (_disposed || _stopped) return;
    final String? path = _state.localSubtitlePath;
    if (path == null) return;
    _subtitleUserSelected = true;
    await _engine.selectSubtitleTrack(null, externalPath: path);
    if (_disposed || _stopped) return;
    _set(_state.copyWith(selectedSubtitle: null, subtitleNotice: null));
  }

  void _onSnapshot(PlaybackSnapshot snapshot) {
    if (_disposed || _stopped) return;
    // Captured on every snapshot, never throttled: stop() reports this value
    // and Android tears the surface down before the page can read it again.
    if (snapshot.position > Duration.zero) {
      _lastTrustedPosition = snapshot.position;
    }
    final previous = _state;
    final progressed = snapshot.position > previous.position;

    // A moved position proves the player survived whatever it logged, so a
    // banner left over from an earlier stall must not outlive the recovery.
    if (progressed) _dismissFailure();

    _set(
      _state.copyWith(
        position: snapshot.position,
        // The engine reports a zero duration until the demuxer read it; keep
        // the runtime from the detail response until then.
        duration: snapshot.duration > Duration.zero
            ? snapshot.duration
            : previous.duration,
        buffering: snapshot.buffering,
        playing: snapshot.playing,
        videoWidth: snapshot.videoWidth,
        videoHeight: snapshot.videoHeight,
      ),
    );
    _updateSkipFlags(snapshot.position);

    // S23: apply a persisted gpu-next once a frame has rendered (wid valid);
    // doing it at load before the surface attaches aborts on the WinID assert.
    if (!_voApplied && snapshot.videoWidth > 0) {
      _voApplied = true;
      if (_settings.gpuNext) {
        unawaited(
          _engine.setAdvancedVideo(
            gpuNext: true,
            deband: _settings.deband,
            yuv420: _settings.yuv420,
          ),
        );
      }
    }

    // Engine errors are opaque objects, so they never reach the UI as text;
    // the copy below is fixed (contract §6). The line is only a hint though:
    // mpv keeps playing after most of them, so a stall has to confirm it.
    if (snapshot.error != null) {
      _noteFailure();
    } else if (!progressed &&
        _failurePosition != null &&
        _failureWatch == null) {
      // A paused claim gets its window re-armed by the next snapshot, once
      // the player is expected to move again.
      _armFailureWatch();
    }

    _checkCompletion(snapshot, previous);
  }

  /// Continuous play (P1): reaching the end of the runtime while playing
  /// completes the item exactly once. Paused, buffering and not-yet-ready
  /// sessions never complete, and the engine dropping `playing` on the very
  /// last snapshot still counts because the previous one was playing. The
  /// page listens to [PlayerState.completed] and owns the navigation.
  void _checkCompletion(PlaybackSnapshot snapshot, PlayerState previous) {
    if (_completionNotified || !_state.ready || _userPaused) return;
    if (_state.buffering) return;
    final Duration total = _state.duration;
    if (total <= Duration.zero) return;
    if (_state.position < total - _completionEpsilon) return;
    if (!snapshot.playing && !previous.playing) return;
    _completionNotified = true;
    _set(_state.copyWith(completed: true));
  }

  /// Starts (or reuses) the claim that an engine error line broke playback.
  void _noteFailure() {
    // Claimed before `ready` too: a source that cannot be opened often only
    // shows up as an error line, and [_confirmFailure] waits for the load to
    // finish before it says anything.
    if (_failurePosition != null) return;
    _failurePosition = _lastTrustedPosition;
    _failureWaitedBuffer = false;
    _armFailureWatch();
  }

  void _armFailureWatch([Duration window = _failureGrace]) {
    _failureWatch?.cancel();
    _failureWatch = Timer(window, _confirmFailure);
  }

  void _cancelFailureWatch() {
    _failureWatch?.cancel();
    _failureWatch = null;
  }

  void _confirmFailure() {
    _failureWatch = null;
    final claim = _failurePosition;
    if (_disposed || _stopped || claim == null) return;

    // Frames arrived between the error line and this check: mpv recovered, so
    // the user must not be told playback failed.
    if (_lastTrustedPosition != claim) {
      if (_dismissFailure()) notifyListeners();
      return;
    }
    // Negotiation is still running, so there is nothing to say yet.
    if (_state.loading) {
      _armFailureWatch();
      return;
    }
    // The load path already owns the copy on screen.
    if (_state.error != null) {
      _failurePosition = null;
      return;
    }
    // The user asked for the pause; it waits for the resume snapshot instead
    // of polling.
    if (_userPaused) return;
    // Reaching the end of the runtime is not a failure either.
    final total = _state.duration;
    if (total > Duration.zero &&
        _state.position >= total - const Duration(seconds: 1)) {
      _failurePosition = null;
      return;
    }
    if (_state.buffering && !_failureWaitedBuffer) {
      // Filling the buffer is normal; only a buffer that never fills is a
      // failure, and that one gets the longer window.
      _failureWaitedBuffer = true;
      _armFailureWatch(_bufferingFailureGrace);
      return;
    }

    _failurePosition = null;
    _set(_state.copyWith(error: '播放失败，请重试'));
  }

  /// Drops the pending claim and any banner it produced; true when the screen
  /// actually showed one.
  bool _dismissFailure() {
    _cancelFailureWatch();
    _failurePosition = null;
    _failureWaitedBuffer = false;
    if (_state.error == null || !_state.ready) return false;
    _state = _state.copyWith(error: null);
    return true;
  }

  Future<void> _confirmDirect(PlaybackPlan plan) async {
    await _delay(_probeDelay);
    if (_disposed || _stopped) return;

    // Contract §10.9 f: /Sessions is the only source of the verdict, and it
    // stays null when the server did not say.
    final confirmed = await _playback.confirmDirect(plan);
    if (_disposed || _stopped) return;
    _plan = confirmed;
    _set(
      _state.copyWith(
        videoDirect: confirmed.videoDirect,
        audioTranscoded: confirmed.audioTranscoded,
      ),
    );
  }

  void _fail(Object error) {
    final unauthorized =
        error is EmbyException && error.code == AppErrorCode.unauthorized;
    _set(
      _state.copyWith(
        loading: false,
        ready: false,
        error: playerErrorMessage(error),
        unauthorized: unauthorized,
      ),
    );
  }

  void _set(PlayerState state) {
    if (_disposed || _stopped) return;
    _state = state;
    notifyListeners();
  }

  /// Repeated callers share the pending final report (contract §10.9 c).
  Future<void> stop() {
    if (_stopped) return _stopFuture ?? Future<void>.value();

    _cancelFailureWatch();
    _cancelSleepTick();
    _failurePosition = null;
    final plan = _plan;
    _stopFuture = plan == null
        ? Future<void>.value()
        : _reporter.stopped(plan, _reportPosition);
    _stopped = true;
    return _stopFuture!;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // Fallback for teardown without the page's awaited exit path.
    unawaited(stop());
    _cancelFailureWatch();
    _cancelSleepTick();
    unawaited(_ticks?.cancel());
    _ticks = null;
    unawaited(_engine.dispose());
    super.dispose();
  }
}

/// Maps a data-layer failure to playback copy (contract §6).
String playerErrorMessage(Object error) {
  final code = error is EmbyException ? error.code : null;
  return switch (code) {
    AppErrorCode.unauthorized => '登录已过期，请重新登录',
    AppErrorCode.forbidden => '没有播放该内容的权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.notFound => '内容不存在或已被移除',
    AppErrorCode.directPlayDenied => '服务器拒绝直连播放',
    AppErrorCode.playbackUnsupported => '这个片源无法播放',
    AppErrorCode.transcodeFailed => '服务器转码失败，请稍后重试',
    AppErrorCode.subtitleFailed => '字幕加载失败',
    _ => '播放失败，请重试',
  };
}
