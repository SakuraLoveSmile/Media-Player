import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/screenshot_settings.dart';
import '../../core/device/brightness.dart';
import '../../core/device/screen_orientation.dart';
import '../../core/router/app_routes.dart';
import '../../data/cast/dlna_device.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/danmaku/danmaku_repository.dart';
import '../../data/danmaku/models/danmaku_anime.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_stream.dart';
import '../../data/playback/playback_engine.dart';
import '../../data/playback/playback_settings.dart';
import '../../data/playback/track_prefs.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loader.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_tokens.dart';
import 'danmaku_heatmap.dart';
import 'danmaku_overlay.dart';
import 'player_controller.dart';
import 'player_gestures.dart';
import 'player_portrait.dart';
import 'playback_time.dart';

/// Playback screen: engine surface plus the §5 control set.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.itemId,
    this.preferredSourceId,
    this.initialPortrait = false,
    this.initialAudioIndex,
    this.initialSubtitleIndex,
  });

  final String itemId;

  /// Version picked on the detail page (S7); null keeps the server default.
  final String? preferredSourceId;

  /// S78: open in 竖屏播放. Continuous play (上一集/下一集, sheet 选集, 自动连播)
  /// forwards the current mode through the route, so a fresh player page does
  /// not fall back to the default landscape pin mid-session.
  final bool initialPortrait;

  /// Track indices picked in the detail page's 当前轨道 rows (S37); applied
  /// once the plan is negotiated, after the automatic language match.
  final int? initialAudioIndex;
  final int? initialSubtitleIndex;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  PlayerController? _controller;
  bool _redirecting = false;
  bool _leaving = false;
  String? _fatal;
  double _volume = 1;

  /// S53: current season's episodes, used by the S78 portrait info sheet
  /// (集 strip and 接下来 card) and to resolve richer episode stills.
  List<MediaItem> _seasonEpisodes = const <MediaItem>[];

  /// S78 rev: parks the below-video 选集 strip on the playing episode.
  final ScrollController _stripScroll = ScrollController();
  bool _stripPinned = false;

  /// S78: series detail behind the playing episode, used by the info sheet's
  /// rating/date fallback (episodes usually carry no CommunityRating).
  MediaItem? _seriesItem;

  /// S78: episode stills for the portrait info sheet and 接下来 card. Filled
  /// from the bootstrapped services; null until then (placeholders render).
  LibraryService? _library;
  PosterCache? _posters;
  final BrightnessService _brightness = ScreenBrightnessService();

  /// S77: playback orientation. The player starts in landscape by default and
  /// in portrait when the route says so (S78 continuous play), and the control
  /// in both layouts switches modes, pinning the device to the chosen one so
  /// rotating the phone cannot flip it back.
  PlaybackOrientation _orientation = PlaybackOrientation.landscape;
  late final ScreenOrientationService _orientationService;

  /// Controls auto-hide so they never sit over the subtitle band; a tap on the
  /// video brings them back (Yamby parity).
  static const Duration _controlsHideDelay = Duration(seconds: 3);
  /// S79: starts hidden - a freshly opened player shows only the loader until
  /// the first frame is live (or the user taps).
  bool _controlsVisible = false;

  /// S79: true until the first live frame. Opening never pops the chrome open;
  /// only a tap does. Mid-session stalls keep the chrome's own behaviour.
  bool _opening = true;

  /// The chrome was already cleared for this opening, so a later tap that
  /// brings it back is not undone by the next state notification.
  bool _openingChromeCleared = false;
  Timer? _hideTimer;

  /// Yamby keeps landscape subtitles near the bottom edge: ~5% above the
  /// screen bottom.
  static const double _subtitleMarginFraction = 0.05;

  /// S78: portrait subtitles sit inside the video box but must clear the dock
  /// title row that floats on the box's bottom edge, so the band is much
  /// higher than landscape's — 15% of the box, with a fixed floor that covers
  /// the title row on short cinematic boxes.
  static const double _portraitSubtitleMarginFraction = 0.15;
  static const double _portraitSubtitleMinMargin = 44;
  double? _subMargin;

  /// S78: whether mpv may move ASS dialogue with the reserved band. Portrait
  /// forces it on (the band must clear the dock title row); landscape leaves
  /// it to the 黑边 setting.
  bool? _subMarginMode;

  /// S26: tallest the portrait video box may grow, as a fraction of the
  /// available height. Very tall sources (e.g. 9:16) would otherwise push the
  /// whole info/control region off screen; the box keeps its aspect ratio and
  /// centers horizontally instead.
  static const double _portraitVideoMaxHeightFraction = 0.6;

  /// Slider value while the thumb is held, in milliseconds: seeking only
  /// happens when the drag ends (contract §10.9 c reports one seek, not one
  /// per frame).
  double? _dragMillis;

  /// Throttle for S33 seek-on-drag (one seek every ~200 ms while dragging).
  DateTime? _lastDragSeek;

  @override
  void initState() {
    super.initState();
    _orientationService = ref.read(playerOrientationServiceProvider);
    // S78: continuous play re-opens the player with the mode it was in; a
    // direct entry keeps S77's 默认横屏播放. Pinning happens synchronously on
    // open so the very first frame is already the right layout, not a flash.
    _orientation = widget.initialPortrait
        ? PlaybackOrientation.portrait
        : PlaybackOrientation.landscape;
    unawaited(_orientationService.lock(_orientation));
    unawaited(_bootstrap());
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Continuous play (P1): go_router keys the player page by route pattern,
    // so replacing one episode with another reuses this State instead of
    // running initState again. A new item (or pinned version) is a new
    // session: rebuild the controller, and clear the exit latch so the fresh
    // episode can navigate and leave again.
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.preferredSourceId != widget.preferredSourceId) {
      _leaving = false;
      _dragMillis = null;
      // A fresh episode opens like a fresh player: chrome out of the way until
      // the picture is live (S79).
      _opening = true;
      _openingChromeCleared = false;
      _controlsVisible = false;
      _scheduleHide();
      // S78: the new route carries its own pin; adopt it if it differs (a
      // same-mode replacement keeps the current lock untouched).
      final PlaybackOrientation wanted = widget.initialPortrait
          ? PlaybackOrientation.portrait
          : PlaybackOrientation.landscape;
      if (wanted != _orientation) {
        _orientation = wanted;
        unawaited(_orientationService.lock(wanted));
      }
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    // Also covers exits that bypass _leave; an earlier stop is idempotent.
    unawaited(_brightness.reset());
    // S77: hand the screen back to the device so the pages underneath (and the
    // next player visit, which starts from the default) follow it again.
    unawaited(_orientationService.restore());
    _hideTimer?.cancel();
    _stripScroll.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsHideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  /// S79: while the stream is opening the chrome stays out of the way - the
  /// loader and the speed readout are all the user needs. No gesture layer is
  /// mounted yet, so the video area itself takes the tap that brings the
  /// chrome back (and hides it again).
  void _toggleOpeningChrome() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = !_controlsVisible);
  }

  // A modal sheet covers the controls while it is open; bring them back when
  // it closes so the quick menus are immediately usable again.
  void _restoreControlsAfterSheet() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  /// S77: switches 竖屏播放 ↔ 横屏播放 and pins the screen to the chosen mode.
  void _toggleOrientation() {
    final PlaybackOrientation next =
        _orientation == PlaybackOrientation.landscape
        ? PlaybackOrientation.portrait
        : PlaybackOrientation.landscape;
    setState(() {
      _orientation = next;
      // The landscape overlay hides itself after a while; entering that mode
      // brings it back so the switch visibly lands on the full-screen player.
      if (next == PlaybackOrientation.landscape) _controlsVisible = true;
    });
    unawaited(_orientationService.lock(next));
    _scheduleHide();
  }

  /// Hidden controls must not swallow taps or cover the subtitles.
  Widget _fade(Widget child) => IgnorePointer(
    ignoring: !_controlsVisible,
    child: AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: child,
    ),
  );

  /// Applies the reserved subtitle margin once per value: landscape derives it
  /// from the screen height, portrait (S26) from the video box height, so the
  /// band always hugs the bottom edge of whatever the surface actually is.
  void _syncSubtitleMargin(PlayerController controller, double margin) {
    if (_subMargin == margin) return;
    _subMargin = margin;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(controller.setSubtitleBottomMargin(margin));
    });
  }

  /// S78: portrait turns subtitle margins on so both text and ASS dialogue sit
  /// above the dock title row; landscape restores the user's 黑边 choice.
  void _syncSubtitleMarginsMode(PlayerController controller, bool enabled) {
    if (_subMarginMode == enabled) return;
    _subMarginMode = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(controller.setSubtitleMarginsEnabled(enabled));
    });
  }

  /// S78 portrait (Yamby parity): the video box pinned to the top in its own
  /// aspect box, a control layer covering that box which auto-hides like the
  /// landscape chrome, and a two-row dock hanging off the video's bottom edge.
  /// The old below-video overview, 选集 strip and volume slider moved into the
  /// title sheet, the 更多 sheet and the gestures; landscape is untouched.
  Widget _portraitBody(PlayerController controller, PlayerState state) {
    final double aspect = (state.videoWidth > 0 && state.videoHeight > 0)
        ? state.videoWidth / state.videoHeight
        : 16 / 9;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxHeight =
            constraints.maxHeight * _portraitVideoMaxHeightFraction;
        final double naturalHeight = constraints.maxWidth / aspect;
        final double boxHeight = naturalHeight < maxHeight
            ? naturalHeight
            : maxHeight;
        final double portraitMargin =
            _portraitSubtitleMarginFraction * boxHeight;
        _syncSubtitleMargin(
          controller,
          portraitMargin < _portraitSubtitleMinMargin
              ? _portraitSubtitleMinMargin
              : portraitMargin,
        );
        // ASS dialogue otherwise ignores the band and lands on the title row.
        _syncSubtitleMarginsMode(controller, true);
        final bool chrome = !state.locked;
        final Widget? nextUp = chrome
            ? _portraitNextUp(controller, state)
            : null;
        // Width the aspect box actually occupies: a tall source centers a
        // narrower box, and the title row must not reserve room for the
        // next-up card when that would leave it no text space.
        final double boxWidth = naturalHeight < maxHeight
            ? constraints.maxWidth
            : maxHeight * aspect;
        return Column(
          key: const Key('player-portrait'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Align keeps the box's width loose inside the stretched Column so
            // very tall sources still cap at the max height and center instead
            // of being forced full-width.
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      controller.surface,
                      // S17: danmaku sits above the video but below the chrome.
                      DanmakuOverlay(
                        comments: state.danmakuComments,
                        position: state.position,
                        playing: state.playing,
                        settings: state.danmakuSettings,
                      ),
                      if (state.ready && !state.locked)
                        PlayerGestureLayer(
                          volume: _volume,
                          onVolume: (double next) {
                            setState(() => _volume = next);
                            unawaited(controller.setVolume(next));
                          },
                          position: state.position,
                          duration: state.duration,
                          onSeek: (Duration target) =>
                              unawaited(controller.seekTo(target)),
                          brightness: _brightness,
                          onTap: _toggleControls,
                        ),
                      // S79: the configured loader covers 开播, with the live
                      // network speed underneath it; buffering keeps a smaller
                      // copy without the readout.
                      if (state.loading || state.buffering)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              AppLoader(size: state.loading ? 44 : 32),
                              const SizedBox(height: AppSpacing.sm),
                              _OpeningSpeed(controller: controller),
                            ],
                          ),
                        ),
                      // S79: the chrome is hidden while opening; this layer is
                      // what lets a tap bring it back.
                      if (_opening && !state.locked)
                        Positioned.fill(
                          child: GestureDetector(
                            key: const Key('player-opening-tap'),
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleOpeningChrome,
                          ),
                        ),
                      // Notices stay outside the auto-hide layer: a failed
                      // subtitle download must not go unmentioned.
                      Positioned(
                        left: 52,
                        right: AppSpacing.sm,
                        top: 46,
                        child: _portraitNotices(state),
                      ),
                      if (chrome)
                        Positioned.fill(
                          child: _fade(
                            _portraitOverlay(
                              controller,
                              state,
                              reserveRight: nextUp != null && boxWidth > 320,
                            ),
                          ),
                        ),
                      // Stacked after the chrome so the card wins the taps it
                      // covers, exactly like Yamby's overlapping 接下来 card.
                      if (nextUp != null)
                        Positioned(
                          right: AppSpacing.sm,
                          bottom: AppSpacing.sm,
                          child: nextUp,
                        ),
                      if (state.locked)
                        Positioned(
                          top: AppSpacing.xs,
                          left: AppSpacing.sm,
                          child: _unlockControl(controller),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // S12 skip prompts keep their own strip under the video: the box
            // is too short for floating pills in portrait, and this keeps them
            // tappable and independent of the auto-hide timer.
            _portraitSkipBar(controller, state),
            if (chrome) _fade(_portraitDock(controller, state)),
            // S78 rev: keep the episode information visible under the player.
            // Yamby hides it inside the title sheet, but that leaves the page
            // looking empty once the chrome fades out; viewers still expect
            // the title, overview and 选集 strip on screen.
            Expanded(child: _portraitInfoPanel(controller, state)),
          ],
        );
      },
    );
  }

  /// The full-video control layer: top row, centre transport, screenshot/lock
  /// column, speed column and the dock's title row on the video's bottom edge.
  Widget _portraitOverlay(
    PlayerController controller,
    PlayerState state, {
    required bool reserveRight,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Align(
          alignment: Alignment.topCenter,
          child: _portraitTopBar(controller, state),
        ),
        Align(
          alignment: Alignment.center,
          child: _portraitTransport(controller, state),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: _portraitSideButtons(controller),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: _portraitRateColumn(controller, state),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: _portraitTitleRow(
            controller,
            state,
            reserveRight: reserveRight,
          ),
        ),
      ],
    );
  }

  /// Round back button, one-line title and the round quick-action group; S77's
  /// 横屏播放 entry stays at the far right. A tall source can make the video box
  /// narrower than the six-entry group: the title is then dropped and the group
  /// scales down instead of overflowing.
  Widget _portraitTopBar(PlayerController controller, PlayerState state) {
    final MediaItem? item = controller.item;
    final String title = item?.seriesName?.isNotEmpty ?? false
        ? item!.seriesName!
        : state.itemName;
    // S78: Yamby draws the series logo art here instead of the plain title when
    // the server exposes one; the text stays as the fallback.
    final ImageProvider? logo = playerLogoImage(
      library: _library,
      posters: _posters,
      item: item,
    );
    final Widget titleText = Text(
      title,
      key: const Key('player-portrait-title-text'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall!
          .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
    );
    final Widget titleWidget = logo == null
        ? titleText
        : ConstrainedBox(
            key: const Key('player-portrait-logo'),
            constraints: const BoxConstraints(maxWidth: 118, maxHeight: 26),
            child: Image(
              image: logo,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, _, _) => titleText,
            ),
          );
    final List<Widget> buttons = _portraitTopActions(controller, state);
    const double gap = AppSpacing.xxs;
    const double button = 34;
    const double actionsWidth = 6 * button + 5 * gap;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        // Symmetric with the left edge so the trailing 横屏播放 button is not
        // flush against the screen edge (S78 visual parity).
        AppSpacing.sm,
        0,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double titleSpace =
              constraints.maxWidth - 36 - AppSpacing.sm - actionsWidth;
          final Widget actions = titleSpace >= 40
              ? SizedBox(
                  width: actionsWidth,
                  child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
                )
              : Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: buttons,
                    ),
                  ),
                );
          return Row(
            children: <Widget>[
              _CircleIcon(
                dense: true,
                key: const Key('player-back'),
                tooltip: '返回媒体库',
                icon: Icons.arrow_back,
                size: 36,
                iconSize: 20,
                onPressed: _leave,
              ),
              const SizedBox(width: AppSpacing.sm),
              if (titleSpace >= 40)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // heightFactor keeps the bar one control row tall; without
                    // it the Align would claim the whole video box height and
                    // drag every round action into the middle of the video.
                    heightFactor: 1,
                    child: titleWidget,
                  ),
                ),
              actions,
            ],
          );
        },
      ),
    );
  }

  /// The portrait top bar's round entries in Yamby's order (截图 / 画面比例 /
  /// 投屏 / 字幕 / 更多) with S77's 横屏播放 toggle kept last.
  List<Widget> _portraitTopActions(
    PlayerController controller,
    PlayerState state,
  ) {
    return <Widget>[
      _CircleIcon(
        dense: true,
        key: const Key('player-top-screenshot'),
        icon: Icons.photo_camera_outlined,
        size: 34,
        iconSize: 18,
        onPressed: () => unawaited(_quickScreenshot(controller)),
      ),
      const SizedBox(width: AppSpacing.xxs),
      PopupMenuButton<String>(
        key: const Key('player-quick-aspect'),
        tooltip: '画面比例',
        padding: EdgeInsets.zero,
        initialValue: state.aspectMode,
        onSelected: (String mode) => unawaited(controller.setAspectMode(mode)),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          for (final (String mode, String label) in _quickAspects)
            PopupMenuItem<String>(value: mode, child: Text(label)),
        ],
        child: _portraitSlot(
          const Icon(Icons.aspect_ratio, color: Colors.white, size: 18),
        ),
      ),
      const SizedBox(width: AppSpacing.xxs),
      _CircleIcon(
        dense: true,
        key: const Key('player-quick-cast'),
        icon: Icons.cast,
        size: 34,
        iconSize: 18,
        onPressed: () => _quickCast(controller),
      ),
      const SizedBox(width: AppSpacing.xxs),
      _subtitleControl(
        controller,
        state,
        key: const Key('player-top-subtitle'),
        compact: true,
      ),
      const SizedBox(width: AppSpacing.xxs),
      _CircleIcon(
        dense: true,
        key: const Key('player-options-menu'),
        icon: Icons.more_vert,
        size: 34,
        iconSize: 18,
        onPressed: () => _openOptionsSheet(controller),
      ),
      // S77: the mode toggle stays the last (extra) entry of the group.
      const SizedBox(width: AppSpacing.xxs),
      _CircleIcon(
        dense: true,
        key: const Key('player-orientation-toggle'),
        tooltip: '横屏播放',
        icon: Icons.stay_current_landscape,
        size: 34,
        iconSize: 18,
        onPressed: _toggleOrientation,
      ),
    ];
  }

  /// One 34 px circular slot for the portrait top row / popup children.
  Widget _portraitSlot(Widget child) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  /// Left column: screenshot and lock (Yamby's quick column).
  Widget _portraitSideButtons(PlayerController controller) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _CircleIcon(
          dense: true,
          key: const Key('player-quick-screenshot'),
          icon: Icons.photo_camera_outlined,
          size: 36,
          iconSize: 20,
          onPressed: () => unawaited(_quickScreenshot(controller)),
        ),
        const SizedBox(height: AppSpacing.md),
        _CircleIcon(
          dense: true,
          key: const Key('player-quick-lock'),
          icon: Icons.lock_outline,
          size: 36,
          iconSize: 20,
          onPressed: () {
            controller.toggleLock();
            setState(() => _controlsVisible = true);
            _scheduleHide();
          },
        ),
      ],
    );
  }

  /// Right column: − / rate / + speed stepper, vertical like Yamby.
  Widget _portraitRateColumn(PlayerController controller, PlayerState state) {
    final int index = _ratePresets.indexOf(state.rate);
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadii.capsule),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            key: const Key('player-rate-down'),
            tooltip: '减速',
            color: Colors.white.withValues(alpha: 0.9),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: index > 0
                ? () => unawaited(controller.setRate(_ratePresets[index - 1]))
                : null,
            icon: const Icon(Icons.remove),
          ),
          PopupMenuButton<double>(
            key: const Key('player-rate-menu'),
            initialValue: state.rate,
            tooltip: '播放速度',
            padding: EdgeInsets.zero,
            onSelected: (double rate) => unawaited(controller.setRate(rate)),
            itemBuilder: (BuildContext context) => _ratePresets
                .map(
                  (double rate) => PopupMenuItem<double>(
                    value: rate,
                    child: Text('${rate}x'),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                '${state.rate}x',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('player-rate-up'),
            tooltip: '加速',
            color: Colors.white.withValues(alpha: 0.9),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: index >= 0 && index < _ratePresets.length - 1
                ? () => unawaited(controller.setRate(_ratePresets[index + 1]))
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  /// Centre transport: ±10 s flanking play / pause.
  Widget _portraitTransport(PlayerController controller, PlayerState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppIconButton(
          key: const Key('player-seek-back-10'),
          tooltip: '后退 10 秒',
          size: 44,
          iconSize: 28,
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
          onPressed: () {
            final Duration target =
                state.position - const Duration(seconds: 10);
            unawaited(
              controller.seekTo(target.isNegative ? Duration.zero : target),
            );
            _scheduleHide();
          },
        ),
        const SizedBox(width: AppSpacing.md),
        AppIconButton(
          key: const Key('player-play-toggle'),
          tooltip: state.playing ? '暂停' : '播放',
          size: 56,
          iconSize: 40,
          icon: Icon(
            state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
          ),
          onPressed: () {
            _scheduleHide();
            unawaited(controller.togglePlayPause());
          },
        ),
        const SizedBox(width: AppSpacing.md),
        AppIconButton(
          key: const Key('player-seek-forward-10'),
          tooltip: '前进 10 秒',
          size: 44,
          iconSize: 28,
          icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
          onPressed: () {
            final Duration target =
                state.position + const Duration(seconds: 10);
            final Duration clamped =
                state.duration > Duration.zero && target > state.duration
                ? state.duration
                : target;
            unawaited(controller.seekTo(clamped));
            _scheduleHide();
          },
        ),
      ],
    );
  }

  /// Dock row 1, half-floating on the video's bottom edge: previous / next
  /// episode and the tappable title that opens the info sheet.
  Widget _portraitTitleRow(
    PlayerController controller,
    PlayerState state, {
    required bool reserveRight,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        reserveRight ? 168 : AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          _CircleIcon(
            dense: true,
            key: const Key('player-prev-episode'),
            tooltip: '上一集',
            icon: Icons.skip_previous_rounded,
            size: 36,
            iconSize: 20,
            onPressed: state.hasPrevious
                ? () {
                    final String? id = controller.playPrevious();
                    if (id != null) unawaited(_goToEpisode(id));
                  }
                : null,
          ),
          const SizedBox(width: AppSpacing.xs),
          _CircleIcon(
            dense: true,
            key: const Key('player-next-episode'),
            tooltip: '下一集',
            icon: Icons.skip_next_rounded,
            size: 36,
            iconSize: 20,
            onPressed: state.hasNext
                ? () {
                    final String? id = controller.playNext();
                    if (id != null) unawaited(_goToEpisode(id));
                  }
                : null,
          ),
          const Spacer(),
          // The episode title now lives in the below-video info region, so the
          // dock keeps only a details entry: a long title here would sit on top
          // of the subtitle band at the video's bottom edge.
          IconButton(
            key: const Key('player-dock-title'),
            tooltip: '播放详情',
            color: Colors.white.withValues(alpha: 0.85),
            iconSize: 20,
            onPressed: () => _openInfoSheet(controller),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }

  /// Dock row 2, on black below the video: clock, wave progress and the audio
  /// / subtitle entries.
  Widget _portraitDock(PlayerController controller, PlayerState state) {
    final Duration total = state.duration;
    final Duration shown = _dragMillis == null
        ? state.position
        : Duration(milliseconds: _dragMillis!.round());
    final bool seekable = total > Duration.zero;
    return Container(
      key: const Key('player-portrait-dock'),
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Text(
            '${formatPlaybackTime(shown)} / ${formatPlaybackTime(total)}',
            key: const Key('player-portrait-time'),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: WaveProgressBar(
              key: const Key('player-progress'),
              position: shown,
              duration: total,
              onChangeStart: () => _hideTimer?.cancel(),
              onChange: seekable
                  ? (Duration target) {
                      setState(
                        () => _dragMillis = target.inMilliseconds.toDouble(),
                      );
                      _scheduleHide();
                      // S33: Yamby's 拖拽进度条时快速跳转, throttled like the
                      // landscape slider so one drag reports a handful of seeks.
                      if (state.playbackSettings.seekOnDrag) {
                        final DateTime now = DateTime.now();
                        final DateTime? last = _lastDragSeek;
                        if (last == null ||
                            now.difference(last) >=
                                const Duration(milliseconds: 200)) {
                          _lastDragSeek = now;
                          unawaited(controller.seekTo(target));
                        }
                      }
                    }
                  : null,
              onChangeEnd: seekable
                  ? (Duration target) {
                      setState(() => _dragMillis = null);
                      _scheduleHide();
                      unawaited(controller.seekTo(target));
                    }
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _trackControl(controller),
          _subtitleControl(controller, state),
        ],
      ),
    );
  }

  /// Below-video information region (S78 rev): series title, episode label,
  /// overview and a 选集 strip, all outside the auto-hide chrome so they stay
  /// readable while the controls fade. The info button opens the full detail
  /// sheet (rating / 集 / 演员) that Yamby keeps there.
  Widget _portraitInfoPanel(PlayerController controller, PlayerState state) {
    final MediaItem? item = controller.item;
    final String title = item?.seriesName?.isNotEmpty ?? false
        ? item!.seriesName!
        : state.itemName;
    final String? episode = episodeSubtitleLabel(item);
    final String? rawOverview = state.overview ?? item?.overview;
    final String? overview = (rawOverview == null || rawOverview.trim().isEmpty)
        ? null
        : rawOverview;
    final bool hasEpisodes = _seasonEpisodes.isNotEmpty;
    _maybePinStrip(item);
    final ColorScheme palette = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return ColoredBox(
      key: const Key('player-portrait-info'),
      color: Colors.black,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      key: const Key('player-portrait-info-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (episode != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          episode,
                          key: const Key('player-portrait-info-episode'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium!.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('player-portrait-details'),
                tooltip: '播放详情',
                color: Colors.white.withValues(alpha: 0.75),
                iconSize: 22,
                onPressed: () => _openInfoSheet(controller),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          if (overview != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                overview,
                key: const Key('player-portrait-overview'),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium!.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
            ),
          if (hasEpisodes) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Text(
                  '选集',
                  style: text.titleSmall!.copyWith(color: Colors.white),
                ),
                const Spacer(),
                Text(
                  '共 ${_seasonEpisodes.length} 集',
                  style: text.labelSmall!.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 118,
              child: ListView.separated(
                key: const Key('player-portrait-episodes'),
                controller: _stripScroll,
                scrollDirection: Axis.horizontal,
                itemCount: _seasonEpisodes.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final MediaItem candidate = _seasonEpisodes[index];
                  final bool current = item != null && candidate.id == item.id;
                  final double fraction = current
                      ? (state.duration > Duration.zero
                            ? state.position.inMilliseconds /
                                  state.duration.inMilliseconds
                            : 0)
                      : (candidate.runTimeTicks <= 0
                            ? 0
                            : candidate.userData.positionTicks /
                                  candidate.runTimeTicks);
                  return InkWell(
                    key: Key('player-strip-${candidate.id}'),
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    onTap: current
                        ? null
                        : () => unawaited(_goToEpisode(candidate.id)),
                    child: SizedBox(
                      width: 156,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            height: 88,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadii.control,
                              ),
                              border: current
                                  ? Border.all(
                                      color: palette.primary,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                EpisodeStill(image: _episodeStill(candidate)),
                                if (fraction > 0)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: WaveProgressLine(
                                      fraction: fraction.clamp(0.0, 1.0),
                                      height: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            episodeSubtitleLabel(candidate) ?? candidate.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelSmall!.copyWith(
                              color: current
                                  ? palette.primary
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// S12 skip prompts in their own strip under the video (portrait): the video
  /// box is too short for floating pills, and this keeps them tappable while
  /// the chrome is hidden. A source without chapter markers renders nothing.
  Widget _portraitSkipBar(PlayerController controller, PlayerState state) {
    if (!state.ready ||
        state.locked ||
        (!state.canSkipIntro && !state.canSkipCredits)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm, top: AppSpacing.xs),
      child: Align(
        alignment: Alignment.centerRight,
        child: _skipButtons(controller, state),
      ),
    );
  }

  /// Resume hint and subtitle notice shown over the video while it plays.
  Widget _portraitNotices(PlayerState state) {
    final Duration? resumedFrom = state.resumedFrom;
    final String? notice = state.subtitleNotice;
    if (resumedFrom == null && notice == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (resumedFrom != null)
          _Banner(
            key: const Key('player-resume-hint'),
            message: '已从 ${formatPlaybackTime(resumedFrom)} 继续播放',
          ),
        if (notice != null)
          Padding(
            padding: EdgeInsets.only(
              top: resumedFrom == null ? 0 : AppSpacing.xs,
            ),
            child: _Banner(
              key: const Key('player-subtitle-notice'),
              message: notice,
            ),
          ),
      ],
    );
  }

  /// S78: the 接下来 floating card — only while the current episode has a next
  /// episode and less than 30 s of runtime remain, then gone again as soon as
  /// the position leaves that window.
  Widget? _portraitNextUp(PlayerController controller, PlayerState state) {
    if (!state.ready || state.locked || !state.hasNext) return null;
    final Duration total = state.duration;
    if (total <= Duration.zero) return null;
    final Duration remaining = total - state.position;
    if (remaining <= Duration.zero ||
        remaining >= const Duration(seconds: 30)) {
      return null;
    }
    final String? nextId = state.nextEpisodeId;
    MediaItem? next;
    for (final MediaItem candidate in _seasonEpisodes) {
      if (candidate.id == nextId) {
        next = candidate;
        break;
      }
    }
    final String title;
    if (next != null) {
      title = episodeSubtitleLabel(next) ?? next.name;
    } else {
      // No cached entry: derive the number from the playing episode instead of
      // inventing a title.
      final MediaItem? item = controller.item;
      final int? season = item?.parentIndexNumber;
      final int? number = item?.indexNumber;
      title = season != null && number != null
          ? 'S${season}E${number + 1}'
          : '下一集';
    }
    final double fraction =
        (state.position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return NextUpCard(
      key: const Key('player-next-up'),
      image: next == null ? null : _episodeStill(next),
      title: title,
      fraction: fraction,
      onTap: () {
        final String? id = controller.playNext();
        if (id != null) unawaited(_goToEpisode(id));
      },
    );
  }

  /// Episode still through the shared poster cache (S47/S78).
  ImageProvider? _episodeStill(MediaItem? item) =>
      episodeStillImage(library: _library, posters: _posters, episode: item);

  /// S78: tapping the dock title opens the dark info sheet (still, metadata,
  /// 集 strip, cast). Switching episodes replaces the player route like the
  /// landscape 选集 did.
  void _openInfoSheet(PlayerController controller) {
    final MediaItem? current = controller.item;
    if (current == null) return;
    MediaItem episode = current;
    for (final MediaItem candidate in _seasonEpisodes) {
      if (candidate.id == current.id) {
        episode = candidate;
        break;
      }
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: PortraitInfoSheet(
          controller: controller,
          episode: episode,
          series: _seriesItem,
          people: current.people,
          seasonEpisodes: _seasonEpisodes,
          library: _library,
          posters: _posters,
          onEpisodeSelected: (MediaItem selected) {
            Navigator.of(sheetContext).pop();
            unawaited(_goToEpisode(selected.id));
          },
        ),
      ),
    ).whenComplete(_restoreControlsAfterSheet);
  }

  static const List<double> _ratePresets = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0,
  ];

  /// Track picker (S5): audio + subtitle lists and language preferences in
  /// one bottom sheet; the subtitle quick menu stays as it was.
  Widget _trackControl(PlayerController controller) {
    return IconButton(
      key: const Key('player-track-menu'),
      tooltip: '音轨与字幕',
      color: Colors.white.withValues(alpha: 0.75),
      iconSize: 20,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(),
      onPressed: () => _openTrackSheet(controller),
      icon: const Icon(Icons.audiotrack),
    );
  }

  /// Live decoder/render diagnostics (播放详情) for debugging.
  Widget _statsControl(PlayerController controller) {
    return IconButton(
      key: const Key('player-stats-menu'),
      tooltip: '播放详情',
      color: Colors.white.withValues(alpha: 0.75),
      iconSize: 20,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(),
      onPressed: () => _openStatsSheet(controller),
      icon: const Icon(Icons.analytics_outlined),
    );
  }

  /// S16 lock: the only live control while the interface is locked.
  Widget _unlockControl(PlayerController controller) {
    return IconButton(
      key: const Key('player-unlock'),
      tooltip: '解锁',
      color: Colors.white,
      iconSize: 22,
      onPressed: () {
        controller.toggleLock();
        // Bring the controls back immediately rather than waiting for a tap.
        setState(() => _controlsVisible = true);
        _scheduleHide();
      },
      icon: const Icon(Icons.lock_open),
    );
  }

  /// Subtitle picker (B6): off plus one entry per server stream; external
  /// files are downloaded by the controller before mounting. Local files
  /// (添加本地字幕) mount directly and show as "filename（本地）".
  Widget _subtitleControl(
    PlayerController controller,
    PlayerState state, {
    Key key = const Key('player-subtitle-menu'),
    bool compact = false,
  }) {
    // PopupMenuButton drops null results, so "off" uses a sentinel value;
    // -2 opens the style sheet, -4 picks a local file, -5 re-mounts it.
    final String? localPath = state.localSubtitlePath;
    return PopupMenuButton<int>(
      key: key,
      initialValue: localPath != null ? -5 : (state.selectedSubtitle ?? -1),
      tooltip: '字幕',
      enabled: true,
      onSelected: (int index) {
        if (index == -2) {
          _openSubtitleStyle(controller);
          return;
        }
        if (index == -4) {
          unawaited(controller.addLocalSubtitle());
          return;
        }
        if (index == -5) {
          unawaited(controller.selectLocalSubtitle());
          return;
        }
        unawaited(controller.selectSubtitle(index < 0 ? null : index));
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
        if (state.subtitleStreams.isEmpty)
          const PopupMenuItem<int>(
            value: -3,
            enabled: false,
            child: Text('无字幕'),
          )
        else
          const PopupMenuItem<int>(value: -1, child: Text('关闭')),
        for (int i = 0; i < state.subtitleStreams.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(_subtitleLabel(state.subtitleStreams[i], i)),
          ),
        if (localPath != null)
          PopupMenuItem<int>(
            value: -5,
            child: Text(_localSubtitleLabel(localPath)),
          ),
        const PopupMenuItem<int>(value: -4, child: Text('添加本地字幕…')),
        const PopupMenuItem<int>(value: -2, child: Text('字幕样式…')),
      ],
      // S78: the portrait top row is a round 34 px slot like its Yamby
      // counterparts; landscape keeps the bare icon.
      child: compact
          ? Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                state.selectedSubtitle != null || localPath != null
                    ? Icons.subtitles
                    : Icons.subtitles_outlined,
                color: Colors.white.withValues(alpha: 0.9),
                size: 18,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                state.selectedSubtitle != null || localPath != null
                    ? Icons.subtitles
                    : Icons.subtitles_outlined,
                color: Colors.white.withValues(alpha: 0.75),
                size: 20,
              ),
            ),
    );
  }

  /// Filename of a mounted local subtitle, marked like the external suffix.
  static String _localSubtitleLabel(String path) {
    final String name = path.split(RegExp(r'[\\/]')).last;
    return '$name（本地）';
  }

  static String _subtitleLabel(MediaStream stream, int index) {
    final String? title = stream.displayTitle;
    final String label;
    if (title != null && title.isNotEmpty) {
      label = title;
    } else {
      final String? language = stream.language;
      label = (language != null && language.isNotEmpty)
          ? language
          : '字幕 ${index + 1}';
    }
    // Server titles can collide between embedded and external tracks; the
    // suffix keeps the download-backed choice identifiable (Yamby parity).
    return stream.isExternal ? '$label（外挂）' : label;
  }

  /// Non-fatal subtitle copy; a download failure must not interrupt video.
  Widget _subtitleNotice(PlayerState state) {
    final String? notice = state.subtitleNotice;
    if (notice == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.lg, top: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _Banner(
          key: const Key('player-subtitle-notice'),
          message: notice,
        ),
      ),
    );
  }

  void _openSubtitleStyle(PlayerController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: _SubtitleStyleSheet(controller: controller),
      ),
    ).whenComplete(_restoreControlsAfterSheet);
  }

  void _openTrackSheet(PlayerController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: _TrackStyleSheet(controller: controller),
      ),
    ).whenComplete(_restoreControlsAfterSheet);
  }

  void _openStatsSheet(PlayerController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: _StatsSheet(controller: controller),
      ),
    ).whenComplete(_restoreControlsAfterSheet);
  }

  void _openOptionsSheet(PlayerController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: _OptionsSheet(
          controller: controller,
          onDanmakuManualMatch: () {
            Navigator.of(context).pop();
            unawaited(_openDanmakuMatchSheet(controller));
          },
          // S78: 媒体信息 has no separate portrait button any more; the 更多
          // sheet keeps the entry reachable there (landscape also has its own).
          onStats: () {
            Navigator.of(context).pop();
            _openStatsSheet(controller);
          },
        ),
      ),
    ).whenComplete(_restoreControlsAfterSheet);
  }

  /// S43: manual danmaku match sheet. Owned by the page because it needs the
  /// ScaffoldMessenger after the sheet closes.
  Future<void> _openDanmakuMatchSheet(PlayerController controller) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: _DanmakuMatchSheet(controller: controller),
      ),
    );
    _restoreControlsAfterSheet();
  }

  /// Fetches the playing episode's season for the portrait info sheet and the
  /// 接下来 card (S53 / S78), and the series detail for the sheet header's
  /// CommunityRating (episodes usually carry none; Yamby shows the series'
  /// rating). Failures only hide that data, playback is unaffected.
  Future<void> _loadSeasonEpisodes(
    PlayerController controller,
    LibraryService library,
  ) async {
    final MediaItem? item = controller.item;
    final String? seriesId = item?.seriesId;
    final String? seasonId = item?.seasonId;
    if (item == null ||
        item.type != 'Episode' ||
        seriesId == null ||
        seasonId == null) {
      return;
    }
    // Fired beside the episode list so opening the sheet never waits on it.
    final Future<MediaItem?> series = _loadSeriesInfo(library, seriesId);
    try {
      final List<MediaItem> episodes = await library.episodes(
        seriesId: seriesId,
        seasonId: seasonId,
      );
      if (!mounted || controller != _controller) return;
      setState(() => _seasonEpisodes = episodes);
    } catch (_) {
      // The 集 strip simply stays hidden.
    }
    final MediaItem? seriesItem = await series;
    if (!mounted || controller != _controller || seriesItem == null) return;
    setState(() => _seriesItem = seriesItem);
  }

  /// S78 rev: park the below-video 选集 strip on the playing episode the first
  /// time it lays out, so a late episode is not stranded off-screen. Runs from
  /// the portrait build because the season may load while landscape is active.
  void _maybePinStrip(MediaItem? current) {
    if (_stripPinned || current == null || _seasonEpisodes.isEmpty) return;
    final int index = _seasonEpisodes.indexWhere(
      (MediaItem episode) => episode.id == current.id,
    );
    if (index <= 0) {
      _stripPinned = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stripScroll.hasClients) return;
      _stripPinned = true;
      final double target = (index * (156 + AppSpacing.sm)).clamp(
        0.0,
        _stripScroll.position.maxScrollExtent,
      );
      _stripScroll.jumpTo(target);
    });
  }

  /// Series detail for the sheet's rating/date fallback (S78). Optional: a
  /// server that refuses the extra request keeps the episode-only header.
  Future<MediaItem?> _loadSeriesInfo(
    LibraryService library,
    String seriesId,
  ) async {
    try {
      return await library.item(seriesId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _bootstrap() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      // S78: portrait stills resolve through the same poster cache the library
      // pages use, so sheet and 接下来 art never re-download a second copy.
      _library = services.library;
      _posters = services.posters;
      // The preference provider may still be resolving on a cold start; await
      // it once so the first capture already honours the setting.
      bool pauseWhileCapturing = false;
      try {
        pauseWhileCapturing = await ref
            .read(screenshotSettingsControllerProvider.future)
            .then((settings) => settings.pauseWhileCapturing);
      } catch (_) {
        // A broken preference keeps the default.
      }
      if (!mounted) return;
      final controller = PlayerController(
        itemId: widget.itemId,
        library: services.library,
        playback: services.playback,
        engine: services.createEngine(),
        reporter: services.createReporter(),
        subtitles: services.subtitles,
        localSubtitlePicker: services.localSubtitlePicker,
        pip: services.pip,
        danmaku: services.danmaku,
        cast: services.cast,
        store: services.store,
        preferredSourceId: widget.preferredSourceId,
        screenshotDirectory: services.screenshotDirectory,
        pauseWhileCapturing: pauseWhileCapturing,
      )..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
      // S37: track picks from the detail page win over the automatic language
      // match; unknown indices are ignored so a stale pick cannot fail a start.
      if (!mounted) return;
      await _applyInitialTracks(controller);
      // S53: the portrait 选集 strip needs the season's episodes; a failure
      // only hides the strip, playback is unaffected.
      await _loadSeasonEpisodes(controller, services.library);
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '播放初始化失败，请稍后重试');
    }
  }

  /// Applies the detail page's 当前轨道 picks once the plan is negotiated.
  ///
  /// The detail page stores *server* stream indices; the controller's
  /// `selectAudio` / `selectSubtitle` take positions in the negotiated track
  /// lists, so the index is translated here. Unknown indices are ignored.
  Future<void> _applyInitialTracks(PlayerController controller) async {
    final int? audio = widget.initialAudioIndex;
    if (audio != null) {
      final int position = controller.state.audioStreams.indexWhere(
        (stream) => stream.index == audio,
      );
      if (position >= 0) await controller.selectAudio(position);
    }
    final int? subtitle = widget.initialSubtitleIndex;
    if (subtitle != null && subtitle < 0) {
      // The detail page's 关闭 choice.
      await controller.selectSubtitle(null);
    } else if (subtitle != null) {
      final int position = controller.state.subtitleStreams.indexWhere(
        (stream) => stream.index == subtitle,
      );
      if (position >= 0) await controller.selectSubtitle(position);
    }
  }

  /// Retrying re-negotiates the session, so it rebuilds the controller instead
  /// of calling `load()` again: the reporter latches "already stopped" after
  /// its final report, so a reused one would either leave the previous
  /// `PlaySessionId` without `Sessions/Playing/Stopped` (contract §3.6) or
  /// silence the new session. Disposing first sends that `Stopped` and frees
  /// the engine exactly once (contract §10.9 c).
  Future<void> _reload() async {
    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_onChanged);
      // Detached before disposing so `State.dispose()` cannot reach this
      // instance again.
      _controller = null;
      previous.dispose();
    }
    if (!mounted) return;
    // A fresh engine has never seen the reserved subtitle margin; drop the
    // cache so the next build re-applies it (retry and continuous play).
    _subMargin = null;
    _subMarginMode = null;
    // The season/series cache belongs to the previous item.
    _seasonEpisodes = const <MediaItem>[];
    _seriesItem = null;
    setState(() => _fatal = null);
    await _bootstrap();
  }

  void _onChanged() {
    final controller = _controller;
    if (controller == null) return;

    if (controller.state.unauthorized && !_redirecting) {
      _redirecting = true;
      // Session is already cleared by the repository; show the login screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.login);
      });
      return;
    }
    // Continuous play (P1): a completed episode advances to its neighbor.
    // `_goToEpisode` latches `_leaving` synchronously, so the repeated
    // notifications of a latched `completed` flag cannot re-trigger it.
    final PlayerState state = controller.state;
    if (state.completed &&
        state.hasNext &&
        state.playbackSettings.autoPlayNext &&
        !_leaving &&
        !_redirecting) {
      final String? next = controller.playNext();
      if (next != null) unawaited(_goToEpisode(next));
    }
    // S79: while a loader owns the screen (opening or buffering) the chrome
    // stays out of the way; once the picture is live the usual "show briefly,
    // then auto-hide" behaviour takes over again. `ready` alone is too early:
    // it flips when the engine is open, before the first frame is decoded.
    if (_opening && state.ready && !state.buffering) {
      // First live frame: the opening is over. The chrome appears briefly (the
      // usual 3 s auto-hide) so the user lands on a normal player; during the
      // opening itself only the loader and the speed readout show.
      _opening = false;
      _controlsVisible = true;
      _scheduleHide();
    } else if (_opening && !_openingChromeCleared) {
      _openingChromeCleared = true;
      _hideTimer?.cancel();
      _controlsVisible = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    if (_leaving || _redirecting) return;
    _leaving = true;
    // Report before pop to avoid Video teardown zeroing the position first.
    await _controller?.stop();
    if (!mounted || _redirecting) return;
    if (context.canPop()) {
      context.pop();
    } else {
      // The library entered through `go`, so there is nothing to pop back to.
      context.go(AppRoutes.library);
    }
  }

  /// A series id has no playable source: stop reporting first, then hand the
  /// route over to the episode picker.
  Future<void> _selectEpisodes(String seriesId) async {
    if (_leaving || _redirecting) return;
    _leaving = true;
    await _controller?.stop();
    if (!mounted || _redirecting) return;
    context.pushReplacement(AppRoutes.seriesFor(seriesId));
  }

  /// Continuous play (P1): hand the route over to a neighbor episode. The
  /// replacement keeps the back stack from growing one player per episode,
  /// and the pinned version (S7) rides along so the next episode negotiates
  /// the same source. Track language preferences are persisted app-wide, so
  /// the fresh controller auto-matches them again; explicit per-session picks
  /// intentionally do not carry over (each episode is a new session).
  Future<void> _goToEpisode(String itemId) async {
    if (_leaving || _redirecting) return;
    _leaving = true;
    // Report before the replacement so the final position survives teardown.
    await _controller?.stop();
    if (!mounted || _redirecting) return;
    // S78: carry the current mode so the replacement page does not flip back
    // to the S77 landscape default mid-session.
    context.pushReplacement(
      AppRoutes.playerFor(
        itemId,
        source: widget.preferredSourceId,
        portrait: _orientation == PlaybackOrientation.portrait,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop is false so the system back and the in-page button share one
      // exit path; leaving unmounts the page, which disposes the controller.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Theme(
        // Player overlays sit on video: keep them dark with light bars
        // and text so they stay legible under a light app theme.
        data: buildAppTheme(Brightness.dark),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    final fatal = _fatal;
    if (fatal != null) {
      return _NoticeView(message: fatal, onBack: _leave, onRetry: _reload);
    }

    final controller = _controller;
    final state = controller?.state;
    if (controller == null || state == null) {
      // S79: opening a video waits on the app's own 加载动画 (外观 → 加载动画),
      // not a bare Material spinner.
      return const AppLoadingView();
    }

    if (state.unsupported) {
      final seriesId = state.selectionSeriesId;
      return _NoticeView(
        message: state.error ?? '这个条目暂不支持播放',
        onBack: _leave,
        onSelectEpisodes: seriesId == null
            ? null
            : () => unawaited(_selectEpisodes(seriesId)),
      );
    }
    final error = state.error;
    if (error != null && !state.ready) {
      return _NoticeView(message: error, onBack: _leave, onRetry: _reload);
    }

    // S77: the playback mode decides the layout, not the device: the player
    // pins the screen to the chosen orientation, so rotating the phone cannot
    // silently swap the layout out from under the user.
    final bool portrait = _orientation == PlaybackOrientation.portrait;
    if (portrait) return _portraitBody(controller, state);

    // Landscape keeps the full-screen surface and the screen-bottom band.
    _syncSubtitleMargin(
      controller,
      _subtitleMarginFraction * MediaQuery.sizeOf(context).height,
    );
    _syncSubtitleMarginsMode(controller, state.subtitleStyle.useMargins);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // §10.9 b: the engine owns the render widget; the page only places it.
        // Built unconditionally (like portrait): the Android surface must be
        // attached before mpv initializes its video output. Gating on `ready`
        // (set only after open() returns) let a fast-opening source init the VO
        // with no WinID, which aborts on assertion-enabled libmpv builds.
        controller.surface,
        // S17: danmaku above the video, below gestures / bars / subtitles.
        if (state.ready)
          Positioned.fill(
            child: DanmakuOverlay(
              comments: state.danmakuComments,
              position: state.position,
              playing: state.playing,
              settings: state.danmakuSettings,
            ),
          ),
        if (state.ready && !state.locked)
          Positioned.fill(
            child: PlayerGestureLayer(
              volume: _volume,
              onVolume: (double next) {
                setState(() => _volume = next);
                unawaited(controller.setVolume(next));
              },
              position: state.position,
              duration: state.duration,
              onSeek: (Duration target) => unawaited(controller.seekTo(target)),
              brightness: _brightness,
              onTap: _toggleControls,
            ),
          ),
        // S79: see the portrait layout - loader + speed while opening, a
        // smaller loader alone while buffering.
        if (state.loading || state.buffering)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppLoader(size: state.loading ? 44 : 32),
                const SizedBox(height: AppSpacing.sm),
                _OpeningSpeed(controller: controller),
              ],
            ),
          ),
        // S79: a tap on the video brings the hidden chrome back while opening.
        if (_opening && !state.locked)
          Positioned.fill(
            child: GestureDetector(
              key: const Key('player-opening-tap'),
              behavior: HitTestBehavior.opaque,
              onTap: _toggleOpeningChrome,
            ),
          ),
        if (error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 160,
            child: _Banner(message: error, emphasis: true),
          ),
        if (!state.locked)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _fade(
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _landscapeTopBar(controller, state),
                  if (state.resumedFrom != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.lg,
                        top: AppSpacing.sm,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Banner(
                          key: const Key('player-resume-hint'),
                          message:
                              '已从 ${formatPlaybackTime(state.resumedFrom!)} 继续播放',
                        ),
                      ),
                    ),
                  _subtitleNotice(state),
                ],
              ),
            ),
          ),
        if (state.ready && !state.locked) ...<Widget>[
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: _fade(_landscapeLeftRail(controller)),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: _fade(_landscapeRightRail(controller, state)),
          ),
          Positioned.fill(child: _fade(_landscapeTransport(controller, state))),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _fade(_landscapeBottomBar(controller, state)),
          ),
        ],
        // S16 lock: gestures and bars are suppressed; only unlock stays live.
        if (state.locked)
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            child: _unlockControl(controller),
          ),
        // S12: skip prompts float above the bar and stay put when it hides.
        if (state.ready && !state.locked)
          Positioned(
            right: AppSpacing.md,
            bottom: 140,
            child: _skipButtons(controller, state),
          ),
      ],
    );
  }

  Widget _skipButtons(PlayerController controller, PlayerState state) {
    final buttons = <Widget>[
      if (state.canSkipIntro)
        _SkipButton(
          key: const Key('player-skip-intro'),
          icon: Icons.fast_forward,
          label: '跳过片头',
          onPressed: () => unawaited(controller.skipIntro()),
        ),
      if (state.canSkipCredits)
        _SkipButton(
          key: const Key('player-skip-credits'),
          icon: Icons.skip_next,
          label: '跳过片尾',
          onPressed: () => unawaited(controller.skipCredits()),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < buttons.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          buttons[i],
        ],
      ],
    );
  }

  static const List<(String, String)> _quickAspects = <(String, String)>[
    ('default', '默认'),
    ('16:9', '16:9'),
    ('4:3', '4:3'),
    ('2.35:1', '2.35:1'),
    ('fill', '填充'),
  ];

  SliderThemeData _playerSliderTheme() => SliderTheme.of(context).copyWith(
    activeTrackColor: Colors.white.withValues(alpha: 0.92),
    inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
    thumbColor: Colors.white,
    overlayColor: Colors.white.withValues(alpha: 0.12),
    trackHeight: 4.5,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
  );

  /// Seek slider shared by the landscape bar and the portrait info region.
  Widget _progressSlider(PlayerController controller, PlayerState state) {
    final Duration total = state.duration;
    final double max = total > Duration.zero
        ? total.inMilliseconds.toDouble()
        : 1.0;
    final double value =
        (_dragMillis ?? state.position.inMilliseconds.toDouble()).clamp(
          0.0,
          max,
        );
    final Duration shown = _dragMillis == null
        ? state.position
        : Duration(milliseconds: _dragMillis!.round());
    final Widget slider = SliderTheme(
      data: _playerSliderTheme(),
      child: Slider(
        key: const Key('player-progress'),
        value: value,
        max: max,
        label: formatPlaybackTime(shown),
        onChanged: total > Duration.zero
            ? (double next) {
                setState(() => _dragMillis = next);
                _scheduleHide();
                // S33: Yamby's 拖拽进度条时快速跳转 — the picture follows the
                // thumb, throttled so a drag still reports a handful of seeks
                // rather than one per frame.
                if (state.playbackSettings.seekOnDrag) {
                  final DateTime now = DateTime.now();
                  final DateTime? last = _lastDragSeek;
                  if (last == null ||
                      now.difference(last) >=
                          const Duration(milliseconds: 200)) {
                    _lastDragSeek = now;
                    unawaited(
                      controller.seekTo(Duration(milliseconds: next.round())),
                    );
                  }
                }
              }
            : null,
        onChangeEnd: total > Duration.zero
            ? (double next) {
                setState(() => _dragMillis = null);
                _scheduleHide();
                unawaited(
                  controller.seekTo(Duration(milliseconds: next.round())),
                );
              }
            : null,
      ),
    );
    // S44: danmaku density heatmap above the bar, only while comments are on.
    final bool showHeatmap =
        state.danmakuSettings.enabled && state.danmakuComments.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showHeatmap) ...<Widget>[
          DanmakuHeatmap(
            key: const Key('danmaku-heatmap'),
            comments: state.danmakuComments,
            duration: total,
            height: 6,
            color: Colors.white,
          ),
          const SizedBox(height: 2),
        ],
        slider,
      ],
    );
  }

  /// Volume slider shared by the landscape bar and the portrait info region.
  Widget _volumeControl(PlayerController controller) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          _volume == 0 ? Icons.volume_off : Icons.volume_up,
          color: Colors.white.withValues(alpha: 0.75),
          size: 18,
        ),
        SizedBox(
          width: 116,
          child: SliderTheme(
            data: _playerSliderTheme(),
            child: Slider(
              key: const Key('player-volume'),
              value: _volume,
              label: '音量 ${(_volume * 100).round()}%',
              onChanged: (double next) {
                setState(() => _volume = next);
                _scheduleHide();
                unawaited(controller.setVolume(next));
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Screenshot from the landscape rail; reports on the player's own
  /// ScaffoldMessenger since no sheet is open.
  Future<void> _quickScreenshot(PlayerController controller) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? path = await controller.takeScreenshot();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(path == null ? '截图失败' : '截图已保存：$path')),
    );
  }

  /// DLNA renderer picker from the landscape header (same sheet as 播放选项).
  void _quickCast(PlayerController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: _CastSheet(controller: controller),
      ),
    ).whenComplete(_restoreControlsAfterSheet);
  }

  /// Landscape header (Yamby parity): translucent gradient, round back button,
  /// the title with the direct-play verdict underneath and the quick actions.
  Widget _landscapeTopBar(PlayerController controller, PlayerState state) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xxl,
      ),
      child: Row(
        children: <Widget>[
          _CircleIcon(
            key: const Key('player-back'),
            icon: Icons.arrow_back,
            onPressed: _leave,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  // S75: the landscape bar follows the same rule as portrait.
                  controller.item?.seriesName?.isNotEmpty ?? false
                      ? controller.item!.seriesName!
                      : state.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (episodeSubtitleLabel(controller.item) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      episodeSubtitleLabel(controller.item)!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                if (state.ready)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _DirectStatus(
                      videoDirect: state.videoDirect,
                      audioTranscoded: state.audioTranscoded,
                    ),
                  ),
              ],
            ),
          ),
          // S77: 竖屏播放 — the landscape pin keeps the app sideways, so this
          // is the only way back to the portrait player.
          _CircleIcon(
            key: const Key('player-orientation-toggle'),
            tooltip: '竖屏播放',
            icon: Icons.stay_current_portrait,
            onPressed: _toggleOrientation,
          ),
          // S48: Yamby's top row starts with the capture shortcut.
          _CircleIcon(
            key: const Key('player-top-screenshot'),
            icon: Icons.photo_camera_outlined,
            onPressed: () => unawaited(_quickScreenshot(controller)),
          ),
          PopupMenuButton<String>(
            key: const Key('player-quick-aspect'),
            tooltip: '画面比例',
            initialValue: state.aspectMode,
            onSelected: (String mode) =>
                unawaited(controller.setAspectMode(mode)),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              for (final (String mode, String label) in _quickAspects)
                PopupMenuItem<String>(value: mode, child: Text(label)),
            ],
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.aspect_ratio, color: Colors.white, size: 22),
            ),
          ),
          _CircleIcon(
            key: const Key('player-quick-cast'),
            icon: Icons.cast,
            onPressed: () => _quickCast(controller),
          ),
          // S48: and a subtitle-list entry, matching Yamby's top bar.
          _subtitleControl(
            controller,
            state,
            key: const Key('player-top-subtitle'),
          ),
          _CircleIcon(
            key: const Key('player-options-menu'),
            icon: Icons.more_vert,
            onPressed: () => _openOptionsSheet(controller),
          ),
        ],
      ),
    );
  }

  /// Left rail: screenshot and lock (Yamby's landscape quick column).
  Widget _landscapeLeftRail(PlayerController controller) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _CircleIcon(
              key: const Key('player-quick-screenshot'),
              icon: Icons.photo_camera_outlined,
              onPressed: () => unawaited(_quickScreenshot(controller)),
            ),
            const SizedBox(height: AppSpacing.md),
            _CircleIcon(
              key: const Key('player-quick-lock'),
              icon: Icons.lock_outline,
              onPressed: () {
                controller.toggleLock();
                setState(() => _controlsVisible = true);
                _scheduleHide();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Right rail: playback speed − / value / + (vertical like Yamby).
  Widget _landscapeRightRail(PlayerController controller, PlayerState state) {
    final int index = _ratePresets.indexOf(state.rate);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppRadii.capsule),
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                key: const Key('player-rate-down'),
                tooltip: '减速',
                color: Colors.white.withValues(alpha: 0.9),
                iconSize: 20,
                onPressed: index > 0
                    ? () =>
                          unawaited(controller.setRate(_ratePresets[index - 1]))
                    : null,
                icon: const Icon(Icons.remove),
              ),
              PopupMenuButton<double>(
                key: const Key('player-rate-menu'),
                initialValue: state.rate,
                tooltip: '播放速度',
                onSelected: (double rate) =>
                    unawaited(controller.setRate(rate)),
                itemBuilder: (BuildContext context) => _ratePresets
                    .map(
                      (double rate) => PopupMenuItem<double>(
                        value: rate,
                        child: Text('${rate}x'),
                      ),
                    )
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    '${state.rate}x',
                    style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('player-rate-up'),
                tooltip: '加速',
                color: Colors.white.withValues(alpha: 0.9),
                iconSize: 20,
                onPressed: index >= 0 && index < _ratePresets.length - 1
                    ? () =>
                          unawaited(controller.setRate(_ratePresets[index + 1]))
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Centre transport: previous / play-pause / next.
  Widget _landscapeTransport(PlayerController controller, PlayerState state) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Yamby's centre transport is ±10 s; episode switching lives in the
          // bottom bar (S40).
          AppIconButton(
            key: const Key('player-seek-back-10'),
            tooltip: '后退 10 秒',
            size: 56,
            iconSize: 34,
            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
            onPressed: () {
              final Duration target =
                  state.position - const Duration(seconds: 10);
              unawaited(
                controller.seekTo(target.isNegative ? Duration.zero : target),
              );
              _scheduleHide();
            },
          ),
          const SizedBox(width: AppSpacing.xl),
          AppIconButton(
            key: const Key('player-play-toggle'),
            tooltip: state.playing ? '暂停' : '播放',
            size: 72,
            iconSize: 54,
            icon: Icon(
              state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              _scheduleHide();
              unawaited(controller.togglePlayPause());
            },
          ),
          const SizedBox(width: AppSpacing.xl),
          AppIconButton(
            key: const Key('player-seek-forward-10'),
            tooltip: '前进 10 秒',
            size: 56,
            iconSize: 34,
            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
            onPressed: () {
              final Duration target =
                  state.position + const Duration(seconds: 10);
              final Duration clamped =
                  state.duration > Duration.zero && target > state.duration
                  ? state.duration
                  : target;
              unawaited(controller.seekTo(clamped));
              _scheduleHide();
            },
          ),
        ],
      ),
    );
  }

  /// Bottom bar (Yamby parity): title + track/subtitle/stats entries above a
  /// full-width seek bar, with the clock and volume underneath.
  Widget _landscapeBottomBar(PlayerController controller, PlayerState state) {
    final Duration total = state.duration;
    final Duration shown = _dragMillis == null
        ? state.position
        : Duration(milliseconds: _dragMillis!.round());
    // S75: an episode shows `S1E4：标题` (no year prefix), a movie keeps
    // Yamby's `(年份) 标题`.
    final String? episode = episodeSubtitleLabel(controller.item);
    final String title =
        episode ??
        (state.productionYear == null
            ? state.itemName
            : '(${state.productionYear}) ${state.itemName}');
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Color(0xE6000000), Color(0x00000000)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Yamby's bottom row: episode switching + title at the left, the
          // track pickers at the right (S40).
          Row(
            children: <Widget>[
              _episodeButton(
                key: const Key('player-prev-episode'),
                tooltip: '上一集',
                icon: Icons.skip_previous_rounded,
                enabled: state.hasPrevious,
                onPressed: () {
                  final String? id = controller.playPrevious();
                  if (id != null) unawaited(_goToEpisode(id));
                },
              ),
              _episodeButton(
                key: const Key('player-next-episode'),
                tooltip: '下一集',
                icon: Icons.skip_next_rounded,
                enabled: state.hasNext,
                onPressed: () {
                  final String? id = controller.playNext();
                  if (id != null) unawaited(_goToEpisode(id));
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall!
                      .copyWith(color: Colors.white),
                ),
              ),
              _trackControl(controller),
              _subtitleControl(controller, state),
              _statsControl(controller),
            ],
          ),
          // Clock left of the full-width seek bar, like Yamby.
          Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(
                  '${formatPlaybackTime(shown)} / ${formatPlaybackTime(total)}',
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              Expanded(child: _progressSlider(controller, state)),
            ],
          ),
          Row(children: <Widget>[const Spacer(), _volumeControl(controller)]),
        ],
      ),
    );
  }

  /// Continuous play (P1): neighbor navigation flanks the play toggle. The
  /// button stays visible but disabled when there is no such neighbor, so
  /// movies and season edges keep a stable control layout.
  Widget _episodeButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return AppIconButton(
      key: key,
      tooltip: tooltip,
      size: 34,
      iconSize: 18,
      icon: Icon(icon),
      onPressed: enabled ? onPressed : null,
    );
  }
}

/// Direct-play verdict from §10.9 f: `null` is "unconfirmed", never "direct".
class _DirectStatus extends StatelessWidget {
  const _DirectStatus({
    required this.videoDirect,
    required this.audioTranscoded,
  });

  final bool? videoDirect;
  final bool audioTranscoded;

  @override
  Widget build(BuildContext context) {
    final (String message, bool emphasis) = switch (videoDirect) {
      false => ('服务器正在转码，未直连', true),
      true => (audioTranscoded ? '直连播放（音频转码）' : '直连播放', false),
      null => ('直连状态未确认', false),
    };

    return _Banner(
      key: const Key('player-direct-status'),
      message: message,
      emphasis: emphasis,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.message, this.emphasis = false});

  final String message;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return AppCard(
      color: emphasis
          ? palette.error.withValues(alpha: 0.45)
          : Colors.black.withValues(alpha: 0.55),
      radius: AppRadii.capsule,
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
          color: emphasis ? const Color(0xFFFFD9D6) : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Colors.black.withValues(alpha: 0.6),
      radius: AppRadii.capsule,
      elevation: 0,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.capsule),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeView extends StatelessWidget {
  const _NoticeView({
    required this.message,
    required this.onBack,
    this.onRetry,
    this.onSelectEpisodes,
  });

  final String message;
  final VoidCallback onBack;
  final Future<void> Function()? onRetry;
  final VoidCallback? onSelectEpisodes;

  @override
  Widget build(BuildContext context) {
    final Future<void> Function()? retry = onRetry;
    final ColorScheme palette = Theme.of(context).colorScheme;

    return Center(
      key: const Key('player-error'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: AppCard(
          color: palette.surfaceContainerLow,
          radius: AppRadii.cardLarge,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                color: palette.onSurfaceVariant,
                size: 28,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge!
                    .copyWith(color: palette.onSurface),
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  AppButton(
                    key: const Key('player-back'),
                    label: '返回',
                    variant: AppButtonVariant.outlined,
                    onPressed: onBack,
                  ),
                  if (onSelectEpisodes != null)
                    AppButton(
                      key: const Key('player-select-episodes'),
                      label: '选择分集',
                      onPressed: onSelectEpisodes,
                    ),
                  if (retry != null)
                    AppButton(label: '重试', onPressed: () => unawaited(retry())),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtitle rendering preferences (S4): live engine passthrough, persisted by
/// the controller for the next playback.
class _SubtitleStyleSheet extends StatelessWidget {
  const _SubtitleStyleSheet({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final SubtitleStyle style = controller.state.subtitleStyle;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: AppCard(
            color: palette.surfaceContainerLow,
            radius: AppRadii.sheet,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: ListView(
              key: const Key('subtitle-style-sheet'),
              shrinkWrap: true,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '字幕样式',
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(color: palette.onSurface),
                      ),
                    ),
                    IconButton(
                      key: const Key('subtitle-style-close'),
                      tooltip: '关闭',
                      color: palette.onSurface,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '字体',
                  style: Theme.of(context).textTheme.labelMedium!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final (String family, String label, String key)
                        in <(String, String, String)>[
                          ('', '默认', 'subtitle-font-default'),
                          ('sans-serif', '无衬线', 'subtitle-font-sans'),
                          ('serif', '衬线', 'subtitle-font-serif'),
                          ('monospace', '等宽', 'subtitle-font-mono'),
                        ])
                      ChoiceChip(
                        key: Key(key),
                        label: Text(label),
                        selected: style.font == family,
                        onSelected: (_) => unawaited(
                          controller.setSubtitleStyle(
                            style.copyWith(font: family),
                          ),
                        ),
                      ),
                  ],
                ),
                _slider(
                  context,
                  label: '字号',
                  value: '${(style.scale * 100).round()}%',
                  child: Slider(
                    key: const Key('subtitle-scale'),
                    min: 0.5,
                    max: 2,
                    divisions: 30,
                    value: style.scale,
                    label: '${(style.scale * 100).round()}%',
                    onChanged: (double v) => unawaited(
                      controller.setSubtitleStyle(style.copyWith(scale: v)),
                    ),
                  ),
                ),
                _slider(
                  context,
                  label: '延迟',
                  value:
                      '${(style.delay.inMilliseconds / 1000).toStringAsFixed(1)}s',
                  child: Slider(
                    key: const Key('subtitle-delay'),
                    min: -5,
                    max: 5,
                    divisions: 100,
                    value: style.delay.inMilliseconds / 1000,
                    label:
                        '${(style.delay.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    onChanged: (double v) => unawaited(
                      controller.setSubtitleStyle(
                        style.copyWith(
                          delay: Duration(milliseconds: (v * 1000).round()),
                        ),
                      ),
                    ),
                  ),
                ),
                _slider(
                  context,
                  label: '描边',
                  value: style.borderSize.toStringAsFixed(1),
                  child: Slider(
                    key: const Key('subtitle-border'),
                    min: 0,
                    max: 5,
                    divisions: 10,
                    value: style.borderSize,
                    label: style.borderSize.toStringAsFixed(1),
                    onChanged: (double v) => unawaited(
                      controller.setSubtitleStyle(
                        style.copyWith(borderSize: v),
                      ),
                    ),
                  ),
                ),
                _slider(
                  context,
                  label: '阴影',
                  value: style.shadowOffset.toStringAsFixed(1),
                  child: Slider(
                    key: const Key('subtitle-shadow'),
                    min: 0,
                    max: 5,
                    divisions: 10,
                    value: style.shadowOffset,
                    label: style.shadowOffset.toStringAsFixed(1),
                    onChanged: (double v) => unawaited(
                      controller.setSubtitleStyle(
                        style.copyWith(shadowOffset: v),
                      ),
                    ),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const Key('subtitle-ass-override'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '覆盖 ASS 样式',
                      style: Theme.of(context).textTheme.bodyLarge!
                          .copyWith(color: palette.onSurface),
                    ),
                    subtitle: Text(
                      '关闭时保留脚本样式，仅字号生效',
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: palette.onSurfaceVariant),
                    ),
                    value: style.overrideAss,
                    onChanged: (bool v) => unawaited(
                      controller.setSubtitleStyle(
                        style.copyWith(overrideAss: v),
                      ),
                    ),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const Key('subtitle-ass-margins'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'ASS 黑边',
                      style: Theme.of(context).textTheme.bodyLarge!
                          .copyWith(color: palette.onSurface),
                    ),
                    subtitle: Text(
                      '将字幕放入画面黑边，不遮挡视频',
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: palette.onSurfaceVariant),
                    ),
                    value: style.useMargins,
                    onChanged: (bool v) => unawaited(
                      controller.setSubtitleStyle(
                        style.copyWith(useMargins: v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    key: const Key('subtitle-style-reset'),
                    label: '恢复默认',
                    variant: AppButtonVariant.tinted,
                    onPressed: () => unawaited(
                      controller.setSubtitleStyle(const SubtitleStyle()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required String value,
    required Widget child,
  }) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: palette.onSurface,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white.withValues(alpha: 0.92),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.12),
              trackHeight: 4.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// In-playback track selection (S5): audio and subtitle lists with the
/// current pick checked, plus the language preferences that drive auto-match.
/// Styling mirrors [_SubtitleStyleSheet]; the controller persists the prefs.
class _TrackStyleSheet extends StatelessWidget {
  const _TrackStyleSheet({required this.controller});

  final PlayerController controller;

  /// Preference options; the empty code means auto (engine default).
  static const List<(String, String)> _languages = <(String, String)>[
    ('', '自动'),
    ('chi', '中文'),
    ('eng', '英语'),
    ('jpn', '日语'),
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final PlayerState state = controller.state;
        final TrackPrefs prefs = state.trackPrefs;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: AppCard(
            color: palette.surfaceContainerLow,
            radius: AppRadii.sheet,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: ListView(
              key: const Key('track-sheet'),
              shrinkWrap: true,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '音轨与字幕',
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(color: palette.onSurface),
                      ),
                    ),
                    IconButton(
                      key: const Key('track-sheet-close'),
                      tooltip: '关闭',
                      color: palette.onSurface,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _sectionTitle(context, '音轨'),
                if (state.audioStreams.isEmpty)
                  _emptyHint(context, '无音轨')
                else
                  for (int i = 0; i < state.audioStreams.length; i++)
                    _trackRow(
                      context,
                      key: Key('track-audio-$i'),
                      label: _audioLabel(state.audioStreams[i], i),
                      selected: state.selectedAudio == i,
                      onTap: () => unawaited(controller.selectAudio(i)),
                    ),
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, '字幕'),
                _trackRow(
                  context,
                  key: const Key('track-subtitle-off'),
                  label: '关闭',
                  selected:
                      state.selectedSubtitle == null &&
                      state.localSubtitlePath == null,
                  onTap: () => unawaited(controller.selectSubtitle(null)),
                ),
                if (state.localSubtitlePath != null)
                  _trackRow(
                    context,
                    key: const Key('track-subtitle-local'),
                    label: _PlayerPageState._localSubtitleLabel(
                      state.localSubtitlePath!,
                    ),
                    selected: true,
                    onTap: () => unawaited(controller.selectLocalSubtitle()),
                  ),
                if (state.subtitleStreams.isEmpty)
                  _emptyHint(context, '无字幕')
                else
                  for (int i = 0; i < state.subtitleStreams.length; i++)
                    _trackRow(
                      context,
                      key: Key('track-subtitle-$i'),
                      label: _PlayerPageState._subtitleLabel(
                        state.subtitleStreams[i],
                        i,
                      ),
                      selected: state.selectedSubtitle == i,
                      onTap: () => unawaited(controller.selectSubtitle(i)),
                    ),
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, '语言偏好'),
                Text(
                  '开始播放时自动选择匹配语言的轨道',
                  style: Theme.of(context).textTheme.labelMedium!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.sm),
                _prefRow(
                  context,
                  label: '音轨',
                  keyPrefix: 'track-pref-audio',
                  selected: prefs.audioLanguage,
                  onSelected: (String code) => unawaited(
                    controller.setTrackPrefs(
                      prefs.copyWith(audioLanguage: code),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _prefRow(
                  context,
                  label: '字幕',
                  keyPrefix: 'track-pref-subtitle',
                  selected: prefs.subtitleLanguage,
                  onSelected: (String code) => unawaited(
                    controller.setTrackPrefs(
                      prefs.copyWith(subtitleLanguage: code),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium!
          .copyWith(color: palette.onSurfaceVariant),
    );
  }

  Widget _emptyHint(BuildContext context, String text) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge!
            .copyWith(color: palette.outline),
      ),
    );
  }

  Widget _trackRow(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge!
              .copyWith(color: palette.onSurface),
        ),
        trailing: selected ? Icon(Icons.check, color: palette.primary) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _prefRow(
    BuildContext context, {
    required String label,
    required String keyPrefix,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium!
              .copyWith(color: palette.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final (String code, String name) in _languages)
              ChoiceChip(
                key: Key('$keyPrefix-${code.isEmpty ? 'auto' : code}'),
                label: Text(name),
                selected: selected == code,
                onSelected: (_) => onSelected(code),
              ),
          ],
        ),
      ],
    );
  }

  static String _audioLabel(MediaStream stream, int index) {
    final String? title = stream.displayTitle;
    if (title != null && title.isNotEmpty) return title;
    final String? language = stream.language;
    return (language != null && language.isNotEmpty)
        ? language
        : '音轨 ${index + 1}';
  }
}

/// Player misc options (S16 / S13 / S23 / S18): rotation, aspect, hardware
/// decode, advanced video (gpu-next / deband / yuv420p), volume gain, sleep
/// timer, screenshot, Android picture-in-picture and lock in one forced-dark
/// sheet. Styling mirrors [_TrackStyleSheet]; the controller owns state and
/// persistence.
class _OptionsSheet extends StatelessWidget {
  const _OptionsSheet({
    required this.controller,
    this.onDanmakuManualMatch,
    this.onStats,
  });

  final PlayerController controller;

  /// S43: opens the manual danmaku match sheet (owned by the page, which has
  /// the ScaffoldMessenger and the modal plumbing).
  final VoidCallback? onDanmakuManualMatch;

  /// S78: 播放详情 (媒体信息) entry, used by the portrait layout where the
  /// stats button no longer has a dedicated spot.
  final VoidCallback? onStats;

  static const List<int> _rotations = <int>[0, 90, 180, 270];
  static const List<(String, String, String)> _aspects =
      <(String, String, String)>[
        ('default', '默认', 'player-aspect-default'),
        ('16:9', '16:9', 'player-aspect-169'),
        ('4:3', '4:3', 'player-aspect-43'),
        ('2.35:1', '2.35:1', 'player-aspect-235'),
        ('fill', '填充', 'player-aspect-fill'),
      ];
  static const List<double> _gains = <double>[100, 150, 200];
  static const List<int> _sleepMinutes = <int>[15, 30, 60, 90];

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final PlayerState state = controller.state;
        final PlaybackSettings settings = state.playbackSettings;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: AppCard(
            color: palette.surfaceContainerLow,
            radius: AppRadii.sheet,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: ListView(
              key: const Key('player-options-sheet'),
              shrinkWrap: true,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '播放选项',
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(color: palette.onSurface),
                      ),
                    ),
                    if (onStats != null)
                      IconButton(
                        key: const Key('player-stats-entry'),
                        tooltip: '播放详情',
                        color: palette.onSurfaceVariant,
                        onPressed: onStats,
                        icon: const Icon(Icons.analytics_outlined),
                      ),
                    IconButton(
                      key: const Key('player-options-close'),
                      tooltip: '关闭',
                      color: palette.onSurface,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _sectionTitle(context, '旋转'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final int degrees in _rotations)
                      ChoiceChip(
                        key: Key('player-rotate-$degrees'),
                        label: Text('$degrees°'),
                        selected: state.videoRotation == degrees,
                        onSelected: (_) =>
                            unawaited(controller.setVideoRotation(degrees)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, '画面比例'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final (String mode, String label, String key)
                        in _aspects)
                      ChoiceChip(
                        key: Key(key),
                        label: Text(label),
                        selected: state.aspectMode == mode,
                        onSelected: (_) =>
                            unawaited(controller.setAspectMode(mode)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const Key('player-hwdec-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '硬件解码',
                      style: Theme.of(context).textTheme.bodyLarge!
                          .copyWith(color: palette.onSurface),
                    ),
                    subtitle: Text(
                      '关闭后使用软件解码',
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: palette.onSurfaceVariant),
                    ),
                    value: settings.hwdecEnabled,
                    onChanged: (_) => unawaited(controller.toggleHwdec()),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, '音量增益'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final double gain in _gains)
                      ChoiceChip(
                        key: Key('player-gain-${gain.round()}'),
                        label: Text('${gain.round()}%'),
                        selected: settings.volumeGainPercent == gain,
                        onSelected: (_) =>
                            unawaited(controller.setVolumeGain(gain)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, '定时关闭'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    ChoiceChip(
                      key: const Key('player-sleep-off'),
                      label: const Text('关'),
                      selected: state.sleepDuration == null,
                      onSelected: (_) => controller.cancelSleepTimer(),
                    ),
                    for (final int minutes in _sleepMinutes)
                      ChoiceChip(
                        key: Key('player-sleep-$minutes'),
                        label: Text('$minutes 分'),
                        selected:
                            state.sleepDuration == Duration(minutes: minutes),
                        onSelected: (_) => controller.setSleepTimer(
                          Duration(minutes: minutes),
                        ),
                      ),
                  ],
                ),
                if (state.sleepRemaining != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      '剩余 ${formatPlaybackTime(state.sleepRemaining!)}',
                      key: const Key('player-sleep-remaining'),
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: palette.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    key: const Key('player-screenshot'),
                    label: '截图',
                    variant: AppButtonVariant.tinted,
                    leading: const Icon(Icons.photo_camera),
                    onPressed: () => unawaited(_screenshot(context)),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    key: const Key('player-cast'),
                    label: '投屏',
                    variant: AppButtonVariant.tinted,
                    leading: const Icon(Icons.cast),
                    onPressed: () => _openCast(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const Key('player-lock-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '锁定界面',
                      style: Theme.of(context).textTheme.bodyLarge!
                          .copyWith(color: palette.onSurface),
                    ),
                    subtitle: Text(
                      '锁定后禁用手势与控制栏',
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: palette.onSurfaceVariant),
                    ),
                    value: state.locked,
                    onChanged: (_) => controller.toggleLock(),
                  ),
                ),
                // S18: picture-in-picture is an Android-only affordance; the
                // other platforms have no entry (and a no-op controller). It
                // sits below the lock row so it never shifts the lock switch's
                // scroll-into-view position.
                if (!kIsWeb &&
                    defaultTargetPlatform ==
                        TargetPlatform.android) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: const Key('player-pip'),
                      label: '画中画',
                      variant: AppButtonVariant.tinted,
                      leading: const Icon(Icons.picture_in_picture_alt),
                      onPressed: () => unawaited(_enterPip(context)),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, '高级'),
                const SizedBox(height: AppSpacing.sm),
                _advancedSwitch(
                  context,
                  key: const Key('adv-gpu-next'),
                  title: 'GPU-Next 渲染',
                  subtitle: '使用 gpu-next 视频输出，关闭恢复默认',
                  value: settings.gpuNext,
                  onChanged: (bool value) =>
                      unawaited(controller.setAdvancedVideo(gpuNext: value)),
                ),
                _advancedSwitch(
                  context,
                  key: const Key('adv-deband'),
                  title: '去色带',
                  subtitle: '减少色彩断层，略微增加性能开销',
                  value: settings.deband,
                  onChanged: (bool value) =>
                      unawaited(controller.setAdvancedVideo(deband: value)),
                ),
                _advancedSwitch(
                  context,
                  key: const Key('adv-yuv420'),
                  title: '强制 YUV420P',
                  subtitle: '画面输出异常时的兼容性选项',
                  value: settings.yuv420,
                  onChanged: (bool value) =>
                      unawaited(controller.setAdvancedVideo(yuv420: value)),
                ),
                // S17: danmaku (DandanPlay). The match status is a plain line
                // here — a failure never becomes an error banner.
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, '弹幕'),
                const SizedBox(height: AppSpacing.sm),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const Key('danmaku-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '弹幕',
                      style: Theme.of(context).textTheme.bodyLarge!
                          .copyWith(color: palette.onSurface),
                    ),
                    subtitle: Text(
                      '来自 DandanPlay 的弹幕评论',
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: palette.onSurfaceVariant),
                    ),
                    value: state.danmakuSettings.enabled,
                    onChanged: (_) => unawaited(controller.toggleDanmaku()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    _danmakuStatusText(state),
                    key: const Key('danmaku-status'),
                    style: Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
                ),
                if (onDanmakuManualMatch != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        key: const Key('danmaku-manual-match'),
                        label: '手动匹配',
                        variant: AppButtonVariant.tinted,
                        leading: const Icon(Icons.manage_search),
                        onPressed: onDanmakuManualMatch,
                      ),
                    ),
                  ),
                _danmakuSlider(
                  context,
                  label: '密度',
                  value: '${(state.danmakuSettings.density * 100).round()}%',
                  child: Slider(
                    key: const Key('danmaku-density'),
                    min: 0.1,
                    max: 1,
                    divisions: 9,
                    value: state.danmakuSettings.density,
                    label: '${(state.danmakuSettings.density * 100).round()}%',
                    onChanged: (double v) => unawaited(
                      controller.setDanmakuSettings(
                        state.danmakuSettings.copyWith(density: v),
                      ),
                    ),
                  ),
                ),
                _danmakuSlider(
                  context,
                  label: '不透明度',
                  value: '${(state.danmakuSettings.opacity * 100).round()}%',
                  child: Slider(
                    key: const Key('danmaku-opacity'),
                    min: 0.1,
                    max: 1,
                    divisions: 9,
                    value: state.danmakuSettings.opacity,
                    label: '${(state.danmakuSettings.opacity * 100).round()}%',
                    onChanged: (double v) => unawaited(
                      controller.setDanmakuSettings(
                        state.danmakuSettings.copyWith(opacity: v),
                      ),
                    ),
                  ),
                ),
                _danmakuSlider(
                  context,
                  label: '速度',
                  value: '${state.danmakuSettings.speed}x',
                  child: Slider(
                    key: const Key('danmaku-speed'),
                    min: 0.5,
                    max: 2,
                    divisions: 6,
                    value: state.danmakuSettings.speed,
                    label: '${state.danmakuSettings.speed}x',
                    onChanged: (double v) => unawaited(
                      controller.setDanmakuSettings(
                        state.danmakuSettings.copyWith(speed: v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    ChoiceChip(
                      key: const Key('danmaku-area-half'),
                      label: const Text('上半屏'),
                      selected: !state.danmakuSettings.fullArea,
                      onSelected: (_) => unawaited(
                        controller.setDanmakuSettings(
                          state.danmakuSettings.copyWith(fullArea: false),
                        ),
                      ),
                    ),
                    ChoiceChip(
                      key: const Key('danmaku-area-full'),
                      label: const Text('全屏'),
                      selected: state.danmakuSettings.fullArea,
                      onSelected: (_) => unawaited(
                        controller.setDanmakuSettings(
                          state.danmakuSettings.copyWith(fullArea: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// S17: the non-fatal match status line beside the 弹幕 toggle.
  static String _danmakuStatusText(PlayerState state) {
    if (!state.danmakuSettings.enabled) return '开启后自动匹配弹幕';
    return switch (state.danmakuStatus) {
      DanmakuStatus.idle => '开启后自动匹配弹幕',
      DanmakuStatus.loading => '弹幕匹配中…',
      DanmakuStatus.matched =>
        '已匹配：${state.danmakuEpisodeLabel ?? ''}'
            '（${state.danmakuComments.length} 条）',
      DanmakuStatus.noMatch => '未匹配到弹幕',
      DanmakuStatus.error => '弹幕加载失败，不影响播放',
    };
  }

  /// S17: one danmaku slider, styled like the subtitle-style sliders.
  Widget _danmakuSlider(
    BuildContext context, {
    required String label,
    required String value,
    required Widget child,
  }) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: palette.onSurface,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white.withValues(alpha: 0.92),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.12),
              trackHeight: 4.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  /// Captures a frame, closes the sheet, then reports the saved path (or the
  /// failure) on the player's own ScaffoldMessenger so it is not hidden behind
  /// the sheet.
  Future<void> _screenshot(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final String? path = await controller.takeScreenshot();
    if (!context.mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(path == null ? '截图失败' : '截图已保存：$path')),
    );
  }

  /// S18: closes the sheet first so the PIP window shows the video, then asks
  /// the activity to enter picture-in-picture. Playback keeps running; a
  /// refusal only surfaces a non-fatal SnackBar on the player's own
  /// ScaffoldMessenger (same path as [_screenshot]).
  Future<void> _enterPip(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    final bool entered = await controller.enterPip();
    if (!entered) {
      messenger.showSnackBar(const SnackBar(content: Text('进入画中画失败')));
    }
  }

  /// S19: opens the DLNA renderer picker over the options sheet. Discovery
  /// starts when the picker mounts; casting pauses local playback.
  void _openCast(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: _CastSheet(controller: controller),
      ),
    );
  }

  /// S23: one advanced-video switch, styled like the hwdec / lock rows.
  Widget _advancedSwitch(
    BuildContext context, {
    required Key key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge!
              .copyWith(color: palette.onSurface),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.labelMedium!
              .copyWith(color: palette.onSurfaceVariant),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium!
          .copyWith(color: palette.onSurfaceVariant),
    );
  }
}

/// Live decoder/render diagnostics (播放详情). Polls the engine once a second
/// while open so frame rate / real-time bitrate track playback; placeholders
/// until mpv reports a property.
class _StatsSheet extends StatefulWidget {
  const _StatsSheet({required this.controller});

  final PlayerController controller;

  @override
  State<_StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<_StatsSheet> {
  Timer? _timer;
  PlaybackStats _stats = const PlaybackStats();

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final PlaybackStats stats = await widget.controller.readStats();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final PlaybackStats s = _stats;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: AppCard(
        color: palette.surfaceContainerLow,
        radius: AppRadii.sheet,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '播放详情',
                  style: Theme.of(context).textTheme.titleLarge!
                      .copyWith(color: palette.onSurface),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('player-stats-close'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: palette.onSurfaceVariant),
                ),
              ],
            ),
            Flexible(
              child: ListView(
                key: const Key('player-stats-sheet'),
                shrinkWrap: true,
                children: <Widget>[
                  _row('分辨率', s.width > 0 ? '${s.width}×${s.height}' : '—'),
                  _row('视频编码', s.videoCodec ?? '—'),
                  _row('音频编码', s.audioCodec ?? '—'),
                  _row('容器帧率', _fps(s.containerFps)),
                  _row('实时帧率', _fps(s.estimatedFps)),
                  _row('视频比特率', _bitrate(s.videoBitrate)),
                  _row('音频比特率', _bitrate(s.audioBitrate)),
                  _row('网络速度', formatByteRate(s.cacheSpeed)),
                  _row(
                    '缓存时长',
                    s.cacheSeconds == null
                        ? '—'
                        : '${s.cacheSeconds!.toStringAsFixed(1)} s',
                  ),
                  _row('解码丢帧', '${s.decoderDroppedFrames ?? 0}'),
                  _row('输出丢帧', '${s.voDroppedFrames ?? 0}'),
                  _row('硬解', (s.hwdec ?? '').isEmpty ? '关' : s.hwdec!),
                  _row('视频输出', s.vo ?? '—'),
                  _row('音频输出', s.ao ?? '—'),
                  _row(
                    '采样率',
                    s.audioSampleRate == null ? '—' : '${s.audioSampleRate} Hz',
                  ),
                  _row('声道', s.audioChannels ?? '—'),
                  _row(
                    '倍速',
                    s.speed == null ? '—' : '${s.speed!.toStringAsFixed(2)}×',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: palette.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: palette.onSurface,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fps(double? fps) =>
      (fps == null || fps <= 0) ? '—' : '${fps.toStringAsFixed(3)} fps';

  static String _bitrate(int? bps) {
    if (bps == null || bps <= 0) return '—';
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(2)} Mbps';
    return '${(bps / 1000).toStringAsFixed(0)} kbps';
  }

}

/// Formats a network rate reported in bytes per second (mpv `cache-speed`).
String formatByteRate(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(2)} MB/s';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB/s';
  return '$bytes B/s';
}

/// S79: the live network speed under the opening loader.
///
/// Reads mpv's `cache-speed` twice a second while the stream is being opened,
/// so a slow start reads as "loading at 300 KB/s" instead of looking stuck.
/// The readout keeps the last sample between polls and falls back to
/// 正在连接… until the engine reports one.
class _OpeningSpeed extends StatefulWidget {
  const _OpeningSpeed({required this.controller});

  final PlayerController controller;

  @override
  State<_OpeningSpeed> createState() => _OpeningSpeedState();
}

class _OpeningSpeedState extends State<_OpeningSpeed> {
  Timer? _timer;
  int? _bytesPerSecond;

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
    _timer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _poll() async {
    int? speed;
    try {
      speed = (await widget.controller.readStats()).cacheSpeed;
    } catch (_) {
      // A missing stats channel must never disturb playback.
      return;
    }
    if (!mounted || speed == _bytesPerSecond) return;
    setState(() => _bytesPerSecond = speed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String rate = formatByteRate(_bytesPerSecond);
    return Text(
      rate == '—' ? '正在连接…' : rate,
      key: const Key('player-opening-speed'),
      style: Theme.of(context).textTheme.labelMedium!.copyWith(
        color: Colors.white.withValues(alpha: 0.72),
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

/// S19: DLNA renderer picker. Discovery runs on mount; the list rebuilds from
/// the controller so a scan, a cast and a stop all reflect without a reopen.
class _CastSheet extends StatefulWidget {
  const _CastSheet({required this.controller});

  final PlayerController controller;

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  @override
  void initState() {
    super.initState();
    // Deferred so the scan's first state change never notifies listeners while
    // the sheet route is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.discoverCastDevices());
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: AppCard(
        color: palette.surfaceContainerLow,
        radius: AppRadii.sheet,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (BuildContext context, _) {
            final PlayerState state = widget.controller.state;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '投屏',
                      style: Theme.of(context).textTheme.titleLarge!
                          .copyWith(color: palette.onSurface),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('player-cast-refresh'),
                      tooltip: '重新搜索',
                      onPressed: () =>
                          unawaited(widget.controller.discoverCastDevices()),
                      icon: Icon(
                        Icons.refresh,
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      key: const Key('player-cast-close'),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: palette.onSurfaceVariant),
                    ),
                  ],
                ),
                Flexible(
                  child: ListView(
                    key: const Key('player-cast-sheet'),
                    shrinkWrap: true,
                    children: <Widget>[
                      if (state.castingTo != null) ...<Widget>[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.cast_connected,
                            color: palette.primary,
                          ),
                          title: Text(
                            '正在投屏到 ${state.castingTo!.name}',
                            style: Theme.of(context).textTheme.bodyLarge!
                                .copyWith(color: palette.onSurface),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppButton(
                            key: const Key('player-cast-stop'),
                            label: '停止投屏',
                            variant: AppButtonVariant.tinted,
                            leading: const Icon(Icons.stop_circle_outlined),
                            onPressed: () =>
                                unawaited(widget.controller.stopCast()),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      if (state.castDiscovering)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (state.castDevices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          child: Text(
                            state.castError ?? '未发现投屏设备',
                            key: const Key('player-cast-empty'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(color: palette.onSurfaceVariant),
                          ),
                        )
                      else
                        for (final DlnaDevice device in state.castDevices)
                          ListTile(
                            key: Key('player-cast-device-${device.id}'),
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.cast,
                              color: palette.onSurfaceVariant,
                            ),
                            title: Text(
                              device.name,
                              style: Theme.of(context).textTheme.bodyLarge!
                                  .copyWith(color: palette.onSurface),
                            ),
                            subtitle: Text(
                              device.address,
                              style: Theme.of(context).textTheme.labelMedium!
                                  .copyWith(color: palette.onSurfaceVariant),
                            ),
                            onTap: () =>
                                unawaited(widget.controller.castTo(device)),
                          ),
                      if (state.castError != null &&
                          state.castDevices.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            state.castError!,
                            style: Theme.of(context).textTheme.labelMedium!
                                .copyWith(color: palette.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A circular translucent icon button drawn over the video (Yamby's player
/// chrome).
class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 42,
    this.iconSize = 22,
    this.dense = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Diameter of the round background; the portrait overlay uses the compact
  /// 34/36 px variants to fit its six-entry top row (S78).
  final double size;
  final double iconSize;

  /// Drops the 48 px Material tap-target padding so the widget lays out at
  /// exactly [size]. The portrait chrome needs that to fit its narrow video
  /// box; landscape keeps the padded target.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      // The compact portrait variants own their exact 34/36 px slot; the
      // landscape chrome keeps Material's default inner padding.
      padding: dense ? EdgeInsets.zero : null,
      icon: Icon(icon, color: Colors.white, size: iconSize),
      style:
          IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.35),
            minimumSize: Size(size, size),
            fixedSize: Size(size, size),
          ).copyWith(
            tapTargetSize: dense ? MaterialTapTargetSize.shrinkWrap : null,
          ),
    );
  }
}

/// Manual danmaku matching (S43): search DandanPlay and remember the chosen
/// episode per Emby item.
class _DanmakuMatchSheet extends StatefulWidget {
  const _DanmakuMatchSheet({required this.controller});

  final PlayerController controller;

  @override
  State<_DanmakuMatchSheet> createState() => _DanmakuMatchSheetState();
}

class _DanmakuMatchSheetState extends State<_DanmakuMatchSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.state.itemName,
  );
  bool _searching = false;
  bool? _manual;
  String? _error;
  List<DanmakuAnime>? _results;

  @override
  void initState() {
    super.initState();
    unawaited(_loadManual());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadManual() async {
    final bool manual = await widget.controller.hasManualDanmakuMatch();
    if (!mounted) return;
    setState(() => _manual = manual);
  }

  Future<void> _search() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    final List<DanmakuAnime> results = await widget.controller.searchDanmaku(
      _text.text,
    );
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
      if (results.isEmpty) _error = '没有找到匹配的剧集';
    });
  }

  Future<void> _apply(DanmakuAnime anime, DanmakuEpisode episode) async {
    final bool ok = await widget.controller.applyDanmakuMatch(anime, episode);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = '匹配失败，请稍后重试');
    }
  }

  Future<void> _clear() async {
    await widget.controller.clearDanmakuMatch();
    if (!mounted) return;
    setState(() {
      _manual = false;
      _results = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return AppCard(
      key: const Key('danmaku-match-sheet'),
      color: palette.surfaceContainerLow,
      radius: AppRadii.sheet,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '弹幕匹配',
                    style: Theme.of(context).textTheme.titleMedium!
                        .copyWith(color: palette.onSurface),
                  ),
                ),
                IconButton(
                  key: const Key('danmaku-match-close'),
                  tooltip: '关闭',
                  color: palette.onSurface,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('danmaku-match-search'),
                    controller: _text,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: '输入番剧名称',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_search()),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  key: const Key('danmaku-match-go'),
                  label: '搜索',
                  onPressed: _searching ? null : () => unawaited(_search()),
                ),
              ],
            ),
            if (_manual == true)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '当前已使用手动匹配',
                        style: Theme.of(context).textTheme.labelMedium!
                            .copyWith(color: palette.primary),
                      ),
                    ),
                    TextButton(
                      key: const Key('danmaku-match-clear'),
                      onPressed: () => unawaited(_clear()),
                      child: const Text('清除'),
                    ),
                  ],
                ),
              ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _error!,
                  key: const Key('danmaku-match-error'),
                  style: Theme.of(context).textTheme.labelMedium!
                      .copyWith(color: palette.error),
                ),
              ),
            if (_results != null && _results!.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results!.length,
                  itemBuilder: (BuildContext context, int index) {
                    final DanmakuAnime anime = _results![index];
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            anime.title,
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(
                                  color: palette.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: <Widget>[
                              for (final DanmakuEpisode episode
                                  in anime.episodes)
                                ActionChip(
                                  key: Key(
                                    'danmaku-match-episode-${episode.id}',
                                  ),
                                  label: Text(episode.title),
                                  onPressed: () =>
                                      unawaited(_apply(anime, episode)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
