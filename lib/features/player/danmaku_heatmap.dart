import 'package:flutter/material.dart';

import '../../data/danmaku/models/danmaku_comment.dart';

/// Danmaku density strip drawn above the seek bar (S44): one bucket per slice
/// of the runtime, height by comment count. Yamby shows a similar heatmap so
/// the viewer can see where the discussion is.
class DanmakuHeatmap extends StatelessWidget {
  const DanmakuHeatmap({
    super.key,
    required this.comments,
    required this.duration,
    this.height = 6,
    this.color,
  });

  final List<DanmakuComment> comments;
  final Duration duration;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color base = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: CustomPaint(
          painter: _HeatPainter(
            comments: comments,
            duration: duration,
            color: base,
          ),
        ),
      ),
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter({
    required this.comments,
    required this.duration,
    required this.color,
  });

  final List<DanmakuComment> comments;
  final Duration duration;
  final Color color;

  /// Buckets across the runtime: enough resolution for a phone-width bar
  /// without allocating one entry per comment.
  static const int buckets = 120;

  @override
  void paint(Canvas canvas, Size size) {
    final int totalMs = duration.inMilliseconds;
    if (totalMs <= 0 || size.width <= 0) return;
    final List<int> counts = List<int>.filled(buckets, 0);
    for (final DanmakuComment comment in comments) {
      final int index = (comment.time.inMilliseconds / totalMs * buckets)
          .floor();
      if (index < 0 || index >= buckets) continue;
      counts[index]++;
    }
    int max = 0;
    for (final int count in counts) {
      if (count > max) max = count;
    }
    if (max == 0) return;

    final Paint paint = Paint();
    final double bucketWidth = size.width / buckets;
    for (int index = 0; index < buckets; index++) {
      final int count = counts[index];
      if (count == 0) continue;
      final double strength = count / max;
      paint.color = color.withValues(alpha: 0.12 + 0.78 * strength);
      final double barHeight = size.height * (0.25 + 0.75 * strength);
      canvas.drawRect(
        Rect.fromLTWH(
          index * bucketWidth,
          size.height - barHeight,
          bucketWidth,
          barHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HeatPainter oldDelegate) =>
      oldDelegate.comments != comments ||
      oldDelegate.duration != duration ||
      oldDelegate.color != color;
}
