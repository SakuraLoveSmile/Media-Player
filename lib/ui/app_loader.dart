import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/appearance_settings.dart';
import 'theme/app_tokens.dart';

/// The app-wide loading animation (S66), mirroring Yamby's 自定义加载动画.
///
/// Four styles are drawn locally (no assets, no new dependencies): a morphing
/// blob (Yamby's default), pulsing dots, bouncing bars and a sweeping ring.
enum AppLoaderStyle {
  blob('气泡', 'appearance-loader-blob'),
  dots('三点', 'appearance-loader-dots'),
  bars('柱状', 'appearance-loader-bars'),
  ring('圆环', 'appearance-loader-ring');

  const AppLoaderStyle(this.label, this.keyName);

  final String label;
  final String keyName;

  static AppLoaderStyle fromName(String? name) {
    for (final AppLoaderStyle style in AppLoaderStyle.values) {
      if (style.name == name) return style;
    }
    return AppLoaderStyle.blob;
  }
}

/// A loading spinner that follows the 外观 → 加载动画 preference.
class AppLoader extends ConsumerWidget {
  const AppLoader({super.key, this.size = 36, this.color, this.previewStyle});

  final double size;
  final Color? color;

  /// Renders one specific style as a still frame (the 外观 picker). When set,
  /// the widget ignores the stored preference and never animates.
  final AppLoaderStyle? previewStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLoaderStyle style =
        previewStyle ??
        ref
            .watch(appearanceSettingsControllerProvider)
            .maybeWhen(
              data: (AppearanceSettings settings) =>
                  AppLoaderStyle.fromName(settings.loaderStyle),
              orElse: () => AppLoaderStyle.blob,
            );
    final Color tint = color ?? Theme.of(context).colorScheme.primary;
    final bool still = previewStyle != null;
    return SizedBox.square(
      key: const Key('app-loader'),
      dimension: size,
      child: still
          ? CustomPaint(painter: _painterFor(style, tint, size, 0.35))
          : switch (style) {
              AppLoaderStyle.blob => _BlobLoader(color: tint),
              AppLoaderStyle.dots => _DotsLoader(color: tint, size: size),
              AppLoaderStyle.bars => _BarsLoader(color: tint, size: size),
              AppLoaderStyle.ring => _RingLoader(color: tint, size: size),
            },
    );
  }
}

/// The page-level loading state (S79): the chosen [AppLoader] centred in the
/// page, faded in so it does not pop in while a page transition is still
/// running.
///
/// Every page that is waiting for its first payload should render this instead
/// of a bare [CircularProgressIndicator], so 外观 → 加载动画 applies everywhere
/// and the wait looks the same on every screen.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: '加载中',
        liveRegion: true,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AppMotion.fast,
          curve: AppMotion.decelerate,
          builder: (BuildContext context, double opacity, Widget? child) =>
              Opacity(opacity: opacity, child: child),
          child: AppLoader(size: size),
        ),
      ),
    );
  }
}

CustomPainter _painterFor(
  AppLoaderStyle style,
  Color tint,
  double size,
  double t,
) {
  return switch (style) {
    AppLoaderStyle.blob => _BlobPainter(t: t, color: tint),
    AppLoaderStyle.dots => _DotsPainter(t: t, color: tint, size: size),
    AppLoaderStyle.bars => _BarsPainter(t: t, color: tint, size: size),
    AppLoaderStyle.ring => _RingPainter(t: t, color: tint, size: size),
  };
}

/// Shared ticker that rebuilds a painter on every frame.
class _AnimatedPainter extends StatefulWidget {
  const _AnimatedPainter({required this.painter});

  final CustomPainter Function(double t) painter;

  @override
  State<_AnimatedPainter> createState() => _AnimatedPainterState();
}

class _AnimatedPainterState extends State<_AnimatedPainter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) =>
          CustomPaint(painter: widget.painter(_controller.value)),
    );
  }
}

/// Yamby's default: a soft blob that breathes and slowly morphs.
class _BlobLoader extends StatelessWidget {
  const _BlobLoader({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPainter(
      painter: (double t) => _BlobPainter(t: t, color: color),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double base = size.shortestSide * 0.3;
    final Paint paint = Paint()..color = color;
    final Path path = Path();
    const int segments = 60;
    for (int i = 0; i <= segments; i++) {
      final double angle = i / segments * math.pi * 2;
      final double wobble = 1 + 0.18 * math.sin(angle * 3 + t * math.pi * 2);
      final double radius = base * wobble;
      final Offset point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}

/// Three dots pulsing in sequence.
class _DotsLoader extends StatelessWidget {
  const _DotsLoader({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPainter(
      painter: (double t) => _DotsPainter(t: t, color: color, size: size),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.t, required this.color, required this.size});

  final double t;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final Paint paint = Paint()..color = color;
    final double radius = canvasSize.shortestSide * 0.09;
    final double spacing = canvasSize.shortestSide * 0.24;
    final double centerY = canvasSize.height / 2;
    final double startX = canvasSize.width / 2 - spacing;
    for (int i = 0; i < 3; i++) {
      final double phase = (t + i * 0.2) % 1.0;
      final double scale = 0.6 + 0.4 * math.sin(phase * math.pi).abs();
      canvas.drawCircle(
        Offset(startX + i * spacing, centerY),
        radius * scale,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.t != t;
}

/// Four bars bouncing out of phase.
class _BarsLoader extends StatelessWidget {
  const _BarsLoader({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPainter(
      painter: (double t) => _BarsPainter(t: t, color: color, size: size),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.t, required this.color, required this.size});

  final double t;
  final Color color;
  final double size;

  static const int bars = 4;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final Paint paint = Paint()..color = color;
    final double slot = canvasSize.width / bars;
    final double width = slot * 0.45;
    for (int i = 0; i < bars; i++) {
      final double phase = (t + i * 0.18) % 1.0;
      final double height =
          canvasSize.height * (0.25 + 0.75 * math.sin(phase * math.pi).abs());
      final double left = i * slot + (slot - width) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, canvasSize.height - height, width, height),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) => oldDelegate.t != t;
}

/// A sweeping arc.
class _RingLoader extends StatelessWidget {
  const _RingLoader({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPainter(
      painter: (double t) => _RingPainter(t: t, color: color, size: size),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.t, required this.color, required this.size});

  final double t;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final double stroke = canvasSize.shortestSide * 0.11;
    final Rect rect = Offset.zero & canvasSize;
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.22);
    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, track);
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect.deflate(stroke / 2),
      t * math.pi * 2,
      math.pi * 0.7,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.t != t;
}
