import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glass_theme.dart';
import 'glass_tokens.dart';

/// A frosted "liquid glass" surface.
///
/// The material stacks the layers Apple describes for Liquid Glass:
/// a saturated backdrop blur, a tint gradient, a specular sheen along the top,
/// a hairline highlight border and a soft ambient shadow. Corners use a
/// continuous (squircle) curve instead of a circular arc.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = GlassRadii.card,
    this.blur,
    this.tintColor,
    this.tintOpacity,
    this.border = true,
    this.shadow = true,
    this.sheen = true,
    this.padding,
    this.margin,
    this.shape,
    this.brightness,
  });

  final Widget child;

  /// Corner radius in logical pixels. Use [GlassRadii.capsule] for pills.
  final double radius;

  /// Backdrop blur sigma; defaults to the palette value.
  final double? blur;

  /// Optional tint override (for example the system tint for a tinted glass).
  final Color? tintColor;

  /// Tint strength; defaults to the palette glass tint.
  final double? tintOpacity;

  final bool border;
  final bool shadow;
  final bool sheen;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Optional explicit shape, used for asymmetric corners (menus, sheets).
  final ShapeBorder? shape;

  /// Forces the palette when the surface must keep a mode regardless of theme.
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = brightness == null
        ? context.glass
        : GlassPalette.of(brightness!);
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final ShapeBorder resolvedShape = shape ??
        RoundedSuperellipseBorder(borderRadius: borderRadius);
    final double sigma = blur ?? palette.glassBlur;

    final GlassFace face = GlassFace.of(palette);
    final Color overlay = tintColor ?? Colors.transparent;

    Widget material = ClipPath(
      clipper: ShapeBorderClipper(
        shape: resolvedShape,
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ColorFilter.matrix(face.matrix),
          inner: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: face.whiteAlpha),
            gradient: tintColor == null
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      overlay.withValues(alpha: (tintOpacity ?? 0.34) + 0.06),
                      overlay.withValues(alpha: (tintOpacity ?? 0.34) - 0.06),
                    ],
                  ),
          ),
          child: Stack(
            children: <Widget>[
              if (sheen)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const <double>[0.0, 0.10, 1.0],
                          colors: <Color>[
                            palette.highlightTop,
                            palette.highlightTop.withValues(alpha: 0),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );

    if (border) {
      material = CustomPaint(
        foregroundPainter: _SquircleStrokePainter(
          shape: resolvedShape,
          topColor: palette.highlightTop,
          bottomColor: palette.highlightBottom,
          strokeWidth: 0.9,
        ),
        child: material,
      );
    }

    if (shadow) {
      material = CustomPaint(
        painter: _SquircleShadowPainter(
          shape: resolvedShape,
          color: palette.edgeShadow,
        ),
        child: material,
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: material);
    }
    return material;
  }
}

/// A selection "lens": the brighter, tinted glass used for the selected item in
/// navigation bars and segmented controls.
class GlassLens extends StatelessWidget {
  const GlassLens({
    super.key,
    required this.child,
    this.radius = GlassRadii.capsule,
    this.padding,
    this.tintColor,
    this.brightness,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? tintColor;
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette =
        brightness == null ? context.glass : GlassPalette.of(brightness!);
    return GlassSurface(
      radius: radius,
      brightness: brightness,
      tintColor: tintColor ?? palette.tint,
      tintOpacity: palette.isDark ? 0.20 : 0.14,
      padding: padding,
      child: child,
    );
  }
}

/// Full-screen wallpaper used behind the glass layers on the login and startup
/// screens. Rendered once, blurred once, and wrapped in a repaint boundary.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    this.child,
    this.brightness,
    this.intensity = 1,
  });

  final Widget? child;
  final Brightness? brightness;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette =
        brightness == null ? context.glass : GlassPalette.of(brightness!);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: palette.groupedBackground),
        RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 64, sigmaY: 64),
            child: CustomPaint(
              painter: _WallpaperPainter(
                brightness: palette.brightness,
                intensity: intensity,
              ),
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}

/// Hairline separator that keeps the iOS inset (leading aligned with text).
class GlassHairline extends StatelessWidget {
  const GlassHairline({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: SizedBox(
        height: 0.5,
        child: ColoredBox(color: context.glass.separator),
      ),
    );
  }
}

/// Face colour transform for a glass surface.
///
/// Flutter's [ui.ColorFilter.matrix] drops the translation column when it is
/// used as an [ui.ImageFilter] inside a backdrop filter (verified with a probe:
/// a +0.25 translation renders identically to +0). The black/white endpoints
/// are therefore folded into a white overlay instead: with face coefficients
/// `M`, black point `b` and white fill `f`, the composite
/// `(1 - f)·(M·c + b) + f` is reproduced by scaling `M` by
/// `(1 - f)/(1 - α)` and overlaying white at `α = (1 - f)·b + f`.
@immutable
class GlassFace {
  const GlassFace({required this.matrix, required this.whiteAlpha});

  final List<double> matrix;
  final double whiteAlpha;

  factory GlassFace.of(GlassPalette palette) {
    final List<double> source = palette.faceMatrix;
    final double fill = palette.faceFillAlpha;
    final double black = source[4];
    final double alpha = ((1 - fill) * black + fill).clamp(0.0, 1.0);
    final double scale = (1 - fill) / (1 - alpha);
    return GlassFace(
      matrix: <double>[
        source[0] * scale, source[1] * scale, source[2] * scale, 0, 0, //
        source[5] * scale, source[6] * scale, source[7] * scale, 0, 0, //
        source[10] * scale, source[11] * scale, source[12] * scale, 0, 0, //
        0, 0, 0, 1, 0, //
      ],
      whiteAlpha: alpha,
    );
  }
}

/// Squircle stroke used by every glass border.
class _SquircleStrokePainter extends CustomPainter {
  const _SquircleStrokePainter({
    required this.shape,
    required this.topColor,
    required this.bottomColor,
    required this.strokeWidth,
  });

  final ShapeBorder shape;
  final Color topColor;
  final Color bottomColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Path path = shape.getOuterPath(rect);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        <Color>[topColor, bottomColor],
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SquircleStrokePainter oldDelegate) =>
      oldDelegate.topColor != topColor ||
      oldDelegate.bottomColor != bottomColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.shape != shape;
}

/// Soft ambient shadow drawn from the squircle path.
class _SquircleShadowPainter extends CustomPainter {
  const _SquircleShadowPainter({required this.shape, required this.color});

  final ShapeBorder shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = shape.getOuterPath(Offset.zero & size);
    // transparentOccluder: keep the surface itself readable; only the shadow
    // outside the shape may be painted behind the backdrop filter.
    canvas.drawShadow(path, color, 5, true);
    canvas.drawShadow(path, color.withValues(alpha: color.a * 0.6), 14, true);
  }

  @override
  bool shouldRepaint(_SquircleShadowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shape != shape;
}

/// Colourful ambient wallpaper painted behind the glass.
class _WallpaperPainter extends CustomPainter {
  const _WallpaperPainter({required this.brightness, required this.intensity});

  final Brightness brightness;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final bool dark = brightness == Brightness.dark;
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = dark ? const Color(0xFF08080C) : const Color(0xFFE9E6F0),
    );

    final List<_Blob> blobs = dark
        ? const <_Blob>[
            _Blob(0.12, 0.10, 0.62, Color(0xFF5B3F8C)),
            _Blob(0.92, 0.18, 0.55, Color(0xFF1F4C7A)),
            _Blob(0.55, 0.62, 0.72, Color(0xFF2B2F63)),
            _Blob(0.88, 0.88, 0.5, Color(0xFF6E2E50)),
            _Blob(0.08, 0.82, 0.48, Color(0xFF17505A)),
          ]
        : const <_Blob>[
            _Blob(0.10, 0.12, 0.72, Color(0xFFFFD3A3)),
            _Blob(0.92, 0.16, 0.62, Color(0xFFC9DAFF)),
            _Blob(0.52, 0.55, 0.85, Color(0xFFF3D9FF)),
            _Blob(0.90, 0.90, 0.58, Color(0xFFFFC6D8)),
            _Blob(0.06, 0.86, 0.55, Color(0xFFC6F1E4)),
          ];

    for (final _Blob blob in blobs) {
      final Offset center = Offset(
        size.width * blob.dx,
        size.height * blob.dy,
      );
      final double radius = size.shortestSide * blob.radius;
      final Paint paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[
            blob.color.withValues(alpha: 0.9 * intensity),
            blob.color.withValues(alpha: 0.0),
          ],
        );
      canvas.drawCircle(center, radius, paint);
    }

    // Subtle top-down luminance so glass edges read well.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          <Color>[
            (dark ? Colors.black : Colors.white).withValues(alpha: 0.10),
            Colors.transparent,
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_WallpaperPainter oldDelegate) =>
      oldDelegate.brightness != brightness ||
      oldDelegate.intensity != intensity;
}

class _Blob {
  const _Blob(this.dx, this.dy, this.radius, this.color);

  final double dx;
  final double dy;
  final double radius;
  final Color color;
}
