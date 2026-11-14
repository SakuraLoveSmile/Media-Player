import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/danmaku/danmaku_settings.dart';
import '../../data/danmaku/models/danmaku_comment.dart';

/// Bullet-comment overlay (S17 弹幕, Yamby parity).
///
/// Sync approach: the page rebuilds this widget on every controller snapshot,
/// so [position] is the spawn clock — comments whose `time <= position` are
/// spawned through a single forward cursor into the time-sorted [comments].
/// Motion itself runs on one shared [Ticker] that accumulates wall time only
/// while [playing], so pausing freezes every comment mid-flight and resuming
/// continues it; a backward seek (or a forward jump past [_seekJump]) clears
/// the lanes and re-seeds the cursor at the new position instead of replaying
/// history. Scroll comments (mode 1/2/3) travel right→left across the box over
/// [scrollDuration] / speed; mode 5 pins top, mode 4 pins bottom above the
/// reserved subtitle band.
///
/// Settings honored: `enabled` (off renders nothing), `density` (fraction of
/// lanes → max concurrent comments), `opacity`, `speed` (duration multiplier)
/// and `fullArea` (top half vs the whole box). The whole layer ignores
/// pointers so player gestures pass straight through, and it sits above the
/// video surface but below the gesture layer, bars and subtitle band.
class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.comments,
    required this.position,
    required this.playing,
    required this.settings,
    this.scrollDuration = const Duration(seconds: 8),
    this.pinnedDuration = const Duration(seconds: 4),
    this.fontSize = 18,
  });

  /// Time-sorted comments of the matched episode (repository order).
  final List<DanmakuComment> comments;

  /// Current playback position; drives spawning and seek detection.
  final Duration position;

  /// Whether playback is running; paused freezes the lanes.
  final bool playing;

  final DanmakuSettings settings;

  /// Right→left travel time at speed 1.0.
  final Duration scrollDuration;

  /// How long a pinned (top/bottom) comment stays at speed 1.0.
  final Duration pinnedDuration;

  final double fontSize;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

/// One comment in flight: its spawn time on the shared clock, its lane and
/// its measured text width (so it fully exits before being pruned).
class _Run {
  _Run({
    required this.comment,
    required this.spawnClock,
    required this.lane,
    required this.width,
  });

  final DanmakuComment comment;
  final double spawnClock;
  final int lane;
  final double width;

  double progress(double clock, double duration) =>
      duration <= 0 ? 1.0 : ((clock - spawnClock) / duration).clamp(0.0, 1.0);
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  /// A forward position jump larger than this counts as a seek: engine
  /// snapshots arrive well under it even at 3x rate.
  static const Duration _seekJump = Duration(seconds: 5);

  /// Keep pinned-bottom comments clear of the player's reserved subtitle band
  /// (same ~8% the control bar stops above).
  static const double _subtitleBandFraction = 0.08;

  /// A scroll lane accepts its next comment once the previous one is halfway
  /// across — its tail has entered the box by then.
  static const double _laneReuseProgress = 0.5;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  /// Wall seconds accumulated while playing; the motion clock.
  double _clock = 0;
  final List<_Run> _runs = <_Run>[];

  /// Forward spawn cursor into [DanmakuOverlay.comments].
  int _cursor = 0;
  Duration _lastPosition = Duration.zero;
  bool _wasEnabled = false;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _lastPosition = widget.position;
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.comments, widget.comments)) {
      // A new episode (or a fresh load) is a new session.
      _runs.clear();
      _clock = 0;
      _cursor = _lowerBound(widget.position);
      _lastPosition = widget.position;
    }
    if (oldWidget.settings.density != widget.settings.density ||
        oldWidget.settings.fullArea != widget.settings.fullArea) {
      // Density / area apply live: drop the newest runs above the new cap.
      _applyCapacity();
    }
    _syncPosition();
    _updateTicker();
  }

  /// Prunes the newest runs when the density / area cap shrinks.
  void _applyCapacity() {
    if (_size.width <= 0 || _size.height <= 0) return;
    final int maxConcurrent = math.max(
      1,
      (_laneCount * widget.settings.density).round(),
    );
    while (_runs.length > maxConcurrent) {
      _runs.removeLast();
    }
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  double get _lineHeight => widget.fontSize * 1.6;

  double get _areaHeight =>
      widget.settings.fullArea ? _size.height : _size.height * 0.5;

  int get _laneCount => math.max(1, (_areaHeight / _lineHeight).floor());

  double _durationFor(DanmakuComment comment) {
    final Duration base = comment.isPinned
        ? widget.pinnedDuration
        : widget.scrollDuration;
    return base.inMicroseconds /
        Duration.microsecondsPerSecond /
        widget.settings.speed;
  }

  /// Spawn clock: advances only while playing, so a pause freezes the lanes.
  void _onTick(Duration elapsed) {
    final Duration delta = elapsed - _lastTick;
    _lastTick = elapsed;
    if (!widget.settings.enabled || !widget.playing) return;
    _clock += delta.inMicroseconds / Duration.microsecondsPerSecond;
    _runs.removeWhere(
      (_Run run) => run.progress(_clock, _durationFor(run.comment)) >= 1.0,
    );
    setState(() {});
  }

  void _updateTicker() {
    final Ticker? ticker = _ticker;
    if (ticker == null) return;
    final bool shouldRun =
        widget.settings.enabled && widget.playing && widget.comments.isNotEmpty;
    if (shouldRun && !ticker.isActive) {
      // Ticker.start() restarts elapsed at zero.
      _lastTick = Duration.zero;
      ticker.start();
    } else if (!shouldRun && ticker.isActive) {
      ticker.stop();
    }
  }

  /// Spawns every comment due at the current position; detects seeks and the
  /// off→on flip. Runs during build (LayoutBuilder) and on widget updates, so
  /// it must not call setState itself.
  void _syncPosition() {
    final Duration position = widget.position;
    if (!widget.settings.enabled) {
      _runs.clear();
      _wasEnabled = false;
      _lastPosition = position;
      return;
    }
    final bool seeked =
        position < _lastPosition || position - _lastPosition > _seekJump;
    if (!_wasEnabled || seeked) {
      // Just switched on, or the user seeked: start from the new position
      // instead of dumping every comment that already went by.
      _runs.clear();
      _clock = 0;
      _cursor = _lowerBound(position);
    }
    _wasEnabled = true;
    _lastPosition = position;
    while (_cursor < widget.comments.length &&
        widget.comments[_cursor].time <= position) {
      _spawn(widget.comments[_cursor]);
      _cursor++;
    }
  }

  /// First index whose time is >= [position] (comments are time-sorted).
  int _lowerBound(Duration position) {
    int lo = 0;
    int hi = widget.comments.length;
    while (lo < hi) {
      final int mid = (lo + hi) ~/ 2;
      if (widget.comments[mid].time < position) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _spawn(DanmakuComment comment) {
    if (_size.width <= 0 || _size.height <= 0) return;
    final int laneCount = _laneCount;
    // Density is the fraction of lanes allowed on screen at once.
    final int maxConcurrent = math.max(
      1,
      (laneCount * widget.settings.density).round(),
    );
    if (_runs.length >= maxConcurrent) return;

    final int lane;
    if (comment.mode == 5 || comment.mode == 4) {
      final int stacked = _runs
          .where((_Run run) => run.comment.mode == comment.mode)
          .length;
      // Pinned comments stack from their edge; a full stack drops the extra.
      if (stacked >= math.max(1, laneCount ~/ 2)) return;
      lane = stacked;
    } else {
      final int? free = _freeScrollLane(laneCount);
      if (free == null) return;
      lane = free;
    }
    _runs.add(
      _Run(
        comment: comment,
        spawnClock: _clock,
        lane: lane,
        width: _measure(comment),
      ),
    );
  }

  /// Scroll lanes live below the pinned-top stack; a lane is busy until its
  /// current comment is halfway across.
  int? _freeScrollLane(int laneCount) {
    final int topPinned = _runs
        .where((_Run run) => run.comment.mode == 5)
        .length;
    final Set<int> busy = <int>{};
    for (final _Run run in _runs) {
      if (run.comment.isPinned) continue;
      if (run.progress(_clock, _durationFor(run.comment)) <
          _laneReuseProgress) {
        busy.add(run.lane);
      }
    }
    for (int lane = topPinned; lane < laneCount; lane++) {
      if (!busy.contains(lane)) return lane;
    }
    return null;
  }

  TextStyle _styleFor(DanmakuComment comment) {
    return TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w600,
      color: Color(0xFF000000 | (comment.color & 0xFFFFFF)),
      // Dark halo keeps light comments legible on bright frames.
      shadows: const <Shadow>[
        Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(0.5, 0.5)),
      ],
    );
  }

  double _measure(DanmakuComment comment) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: comment.text, style: _styleFor(comment)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.enabled || widget.comments.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        _syncPosition();
        _updateTicker();
        return IgnorePointer(
          key: const Key('danmaku-overlay'),
          child: Opacity(
            opacity: widget.settings.opacity,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                for (final _Run run in _runs) _positioned(run),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _positioned(_Run run) {
    final double progress = run.progress(_clock, _durationFor(run.comment));
    final Widget text = Text(
      run.comment.text,
      key: Key('danmaku-comment-${run.comment.id}'),
      style: _styleFor(run.comment),
      maxLines: 1,
      softWrap: false,
    );
    if (run.comment.mode == 5) {
      return Positioned(
        top: run.lane * _lineHeight,
        left: 0,
        right: 0,
        child: Center(child: text),
      );
    }
    if (run.comment.mode == 4) {
      return Positioned(
        bottom: _size.height * _subtitleBandFraction + run.lane * _lineHeight,
        left: 0,
        right: 0,
        child: Center(child: text),
      );
    }
    // Right→left: starts fully off the right edge, exits fully off the left.
    final double x = _size.width - (_size.width + run.width) * progress;
    return Positioned(left: x, top: run.lane * _lineHeight, child: text);
  }
}
