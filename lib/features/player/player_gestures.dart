import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/device/brightness.dart';
import '../../ui/theme/app_tokens.dart';
import 'playback_time.dart';

/// Keep this much clear of the system gesture edges (back / home) so player
/// drags never fight the OS (S1).
const double kPlayerGestureEdgeMargin = 16;

/// A full-height vertical swipe spans the whole 0..1 range; up increases.
double verticalLevelDelta(double dy, double height) =>
    height <= 0 ? 0 : -dy / height;

/// A full-width horizontal swipe spans at most 90 s (the whole item if shorter).
Duration seekSpan(Duration duration) => duration < const Duration(seconds: 90)
    ? duration
    : const Duration(seconds: 90);

Duration horizontalSeekDelta(double dx, double width, Duration span) =>
    width <= 0
    ? Duration.zero
    : Duration(milliseconds: (dx / width * span.inMilliseconds).round());

Duration clampDuration(Duration value, Duration max) =>
    value < Duration.zero ? Duration.zero : (value > max ? max : value);

/// Holding the picture plays it faster without touching the chosen speed: the
/// temporary rate never drops below this floor (S82).
const double kPlayerHoldMinRate = 2.0;

/// Temporary rate for a held picture: `max(base, kPlayerHoldMinRate)`, so
/// holding from 1.25x speeds up while an already-fast 3.0x is never slowed.
double holdRateFor(double baseRate) =>
    baseRate < kPlayerHoldMinRate ? kPlayerHoldMinRate : baseRate;

enum _GestureKind { brightness, volume, seek }

/// Drag layer over the video surface: left-half vertical = brightness,
/// right-half vertical = volume, horizontal = seek preview (applied on release)
/// and — when the page offers it — a held picture plays faster (S82).
///
/// Lives below the top / control bars in the player Stack so their sliders and
/// buttons keep their own input. Levels update live while dragging; only the
/// seek is deferred to release so one gesture reports one seek (contract §10.9 c).
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    super.key,
    required this.volume,
    required this.onVolume,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.brightness,
    this.onTap,
    this.onHoldStart,
    this.onHoldEnd,
    this.holdRate,
  });

  final double volume;
  final ValueChanged<double> onVolume;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final BrightnessService brightness;

  /// A plain tap (no drag) toggles the player controls; drags stay gestures.
  final VoidCallback? onTap;

  /// S82: press-and-hold boosts playback. Without [onHoldStart] the layer keeps
  /// the long-press recognizer out of the gesture arena, so callers that do not
  /// offer the shortcut keep exactly the old tap / drag behaviour.
  final VoidCallback? onHoldStart;

  /// Fired on release and on cancellation, so the page can restore the rate.
  final VoidCallback? onHoldEnd;

  /// Temporary rate shown in the central capsule while held. Null falls back to
  /// [kPlayerHoldMinRate] for the label.
  final double? holdRate;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  _GestureKind? _kind;
  Size _size = Size.zero;
  double _level = 0;
  double _brightnessLevel = 0.5;
  Duration _seekTarget = Duration.zero;

  /// True from the long-press start until release / cancel: the capsule is up
  /// and the page holds the temporary rate.
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBrightness());
  }

  Future<void> _loadBrightness() async {
    final double value = await widget.brightness.current();
    if (mounted) setState(() => _brightnessLevel = value);
  }

  /// Whether the page offers the press-and-hold boost. Without it the
  /// long-press callbacks stay null, so the recognizer never enters the arena
  /// and tap / drag arbitration is untouched.
  bool get _holds => widget.onHoldStart != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPlayerGestureEdgeMargin,
        0,
        kPlayerGestureEdgeMargin,
        kPlayerGestureEdgeMargin,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            key: const Key('player-gesture-area'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _verticalStart,
            onVerticalDragUpdate: _verticalUpdate,
            onVerticalDragEnd: _end,
            onHorizontalDragStart: _horizontalStart,
            onHorizontalDragUpdate: _horizontalUpdate,
            onHorizontalDragEnd: _horizontalEnd,
            onTap: widget.onTap,
            onLongPressStart: _holds ? _holdStart : null,
            onLongPressEnd: _holds ? _holdEnd : null,
            onLongPressCancel: _holds ? _holdCancel : null,
            child: _kind == null && !_holding
                ? const SizedBox.expand()
                : Center(child: _indicator()),
          );
        },
      ),
    );
  }

  void _verticalStart(DragStartDetails details) {
    // A drag that takes over from a hold gives the rate back first, so the
    // boost can never outlive the finger that asked for it.
    _releaseHold();
    final bool left = details.localPosition.dx < _size.width / 2;
    setState(() {
      _kind = left ? _GestureKind.brightness : _GestureKind.volume;
      _level = left ? _brightnessLevel : widget.volume;
    });
  }

  void _verticalUpdate(DragUpdateDetails details) {
    final _GestureKind? kind = _kind;
    if (kind != _GestureKind.brightness && kind != _GestureKind.volume) return;
    final double next =
        (_level + verticalLevelDelta(details.delta.dy, _size.height)).clamp(
          0.0,
          1.0,
        );
    setState(() => _level = next);
    if (kind == _GestureKind.brightness) {
      _brightnessLevel = next;
      unawaited(widget.brightness.set(next));
    } else {
      widget.onVolume(next);
    }
  }

  void _horizontalStart(DragStartDetails details) {
    _releaseHold();
    setState(() {
      _kind = _GestureKind.seek;
      _seekTarget = widget.position;
    });
  }

  void _horizontalUpdate(DragUpdateDetails details) {
    if (_kind != _GestureKind.seek) return;
    final Duration span = seekSpan(widget.duration);
    setState(() {
      _seekTarget = clampDuration(
        _seekTarget + horizontalSeekDelta(details.delta.dx, _size.width, span),
        widget.duration,
      );
    });
  }

  void _horizontalEnd(DragEndDetails details) {
    if (_kind == _GestureKind.seek) widget.onSeek(_seekTarget);
    _end();
  }

  void _end([DragEndDetails? details]) {
    setState(() => _kind = null);
  }

  void _holdStart(LongPressStartDetails details) {
    // One start per press: a repeated callback must not stack boosts.
    if (_holding) return;
    setState(() => _holding = true);
    widget.onHoldStart?.call();
  }

  void _holdEnd(LongPressEndDetails details) => _releaseHold();

  /// A cancelled hold (pointer cancel, another winner) restores exactly like a
  /// release; leaving the rate boosted would strand the user at the fast rate.
  void _holdCancel() => _releaseHold();

  @override
  void dispose() {
    // The layer disappears mid-hold when the player locks, rotates or closes;
    // hand the rate back instead of stranding the boost. No setState here —
    // the element is already going away.
    if (_holding) {
      _holding = false;
      widget.onHoldEnd?.call();
    }
    super.dispose();
  }

  void _releaseHold() {
    if (!_holding) return;
    setState(() => _holding = false);
    widget.onHoldEnd?.call();
  }

  Widget _indicator() {
    final (IconData icon, String label) = switch (_kind) {
      _GestureKind.brightness => (
        Icons.brightness_6,
        '亮度 ${(_level * 100).round()}%',
      ),
      _GestureKind.volume => (
        _level == 0 ? Icons.volume_off : Icons.volume_up,
        '音量 ${(_level * 100).round()}%',
      ),
      _GestureKind.seek => (
        Icons.fast_forward,
        '${formatPlaybackTime(_seekTarget)} / ${formatPlaybackTime(widget.duration)}',
      ),
      null => (
        Icons.fast_forward_rounded,
        '${widget.holdRate ?? kPlayerHoldMinRate}x 加速中',
      ),
    };
    return Material(
      // Always dark: the indicator sits over video and must stay legible even
      // when the app theme is light.
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(AppRadii.capsule),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
