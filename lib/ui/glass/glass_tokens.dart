import 'package:flutter/material.dart';

/// Design tokens for the Liquid Glass look.
///
/// The numbers come from Glasmio's iOS 27 reference implementation: the system
/// palette, grouped backgrounds, SF text styles, continuous corner radii and
/// the native glass recipe (5pt blur, face colour matrix, 0.53pt highlight
/// edge, 1.2% ambient shadow).
@immutable
class GlassPalette {
  const GlassPalette({
    required this.brightness,
    required this.groupedBackground,
    required this.elevatedBackground,
    required this.tertiaryGroupedBackground,
    required this.background,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.quaternaryLabel,
    required this.placeholder,
    required this.separator,
    required this.opaqueSeparator,
    required this.tint,
    required this.green,
    required this.orange,
    required this.red,
    required this.purple,
    required this.pink,
    required this.teal,
    required this.yellow,
    required this.indigo,
    required this.fill,
    required this.secondaryFill,
    required this.tertiaryFill,
    required this.quaternaryFill,
    required this.container,
    required this.subtleStroke,
    required this.faceMatrix,
    required this.glassBlur,
    required this.faceFillAlpha,
    required this.highlightTop,
    required this.highlightBottom,
    required this.edgeShadow,
    required this.innerShadow,
  });

  final Brightness brightness;

  // Backgrounds.
  final Color groupedBackground;
  final Color elevatedBackground;
  final Color tertiaryGroupedBackground;
  final Color background;

  // Label hierarchy.
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color quaternaryLabel;
  final Color placeholder;

  // Separators.
  final Color separator;
  final Color opaqueSeparator;

  // System tints.
  final Color tint;
  final Color green;
  final Color orange;
  final Color red;
  final Color purple;
  final Color pink;
  final Color teal;
  final Color yellow;
  final Color indigo;

  // Fills (segmented tracks, fields, pressed states).
  final Color fill;
  final Color secondaryFill;
  final Color tertiaryFill;
  final Color quaternaryFill;

  // Glass material.
  final Color container;
  final Color subtleStroke;
  final List<double> faceMatrix;
  final double glassBlur;
  final double faceFillAlpha;
  final Color highlightTop;
  final Color highlightBottom;
  final Color edgeShadow;
  final Color innerShadow;

  bool get isDark => brightness == Brightness.dark;

  /// Light appearance. Face matrix: sat 1.2, black 0.4, white 1.03, +20% white.
  static const GlassPalette light = GlassPalette(
    brightness: Brightness.light,
    groupedBackground: Color(0xFFF2F2F7),
    elevatedBackground: Color(0xFFFFFFFF),
    tertiaryGroupedBackground: Color(0xFFF2F2F7),
    background: Color(0xFFFFFFFF),
    label: Color(0xFF000000),
    secondaryLabel: Color(0x94000000),
    tertiaryLabel: Color(0x4D3C3C43),
    quaternaryLabel: Color(0x2E3C3C43),
    placeholder: Color(0x4D3C3C43),
    separator: Color(0xFFE6E6E6),
    opaqueSeparator: Color(0xFFC6C6C8),
    tint: Color(0xFF0088FF),
    green: Color(0xFF34C759),
    orange: Color(0xFFFF9500),
    red: Color(0xFFFF383C),
    purple: Color(0xFFAF52DE),
    pink: Color(0xFFFF2D55),
    teal: Color(0xFF5AC8FA),
    yellow: Color(0xFFFFCC00),
    indigo: Color(0xFF5856D6),
    fill: Color(0x1F767680),
    secondaryFill: Color(0x28787880),
    tertiaryFill: Color(0x14747480),
    quaternaryFill: Color(0x0F747480),
    container: Color(0xA3F8F8FA),
    subtleStroke: Color(0xA3FFFFFF),
    faceMatrix: <double>[
      1.078818, -0.407664, -0.041154, 0, 0.4, //
      -0.121182, 0.792336, -0.041154, 0, 0.4, //
      -0.121182, -0.407664, 1.158846, 0, 0.4, //
      0, 0, 0, 1, 0, //
    ],
    glassBlur: 5,
    faceFillAlpha: 0.2,
    highlightTop: Color(0x61FFFFFF),
    highlightBottom: Color(0x1AFFFFFF),
    edgeShadow: Color(0x05000000),
    innerShadow: Color(0x0F000000),
  );

  /// Dark appearance. Face matrix: sat 1.3, black 0.125, white 1.125.
  static const GlassPalette dark = GlassPalette(
    brightness: Brightness.dark,
    groupedBackground: Color(0xFF000000),
    elevatedBackground: Color(0xFF1C1C1E),
    tertiaryGroupedBackground: Color(0xFF2C2C2E),
    background: Color(0xFF000000),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0xB2EBEBF5),
    tertiaryLabel: Color(0x4DEBEBF5),
    quaternaryLabel: Color(0x2EEBEBF5),
    placeholder: Color(0x4DEBEBF5),
    separator: Color(0x2BFFFFFF),
    opaqueSeparator: Color(0xFF38383A),
    tint: Color(0xFF0091FF),
    green: Color(0xFF30D158),
    orange: Color(0xFFFF9F0A),
    red: Color(0xFFFF4245),
    purple: Color(0xFFBF5AF2),
    pink: Color(0xFFFF375F),
    teal: Color(0xFF64D2FF),
    yellow: Color(0xFFFFD60A),
    indigo: Color(0xFF5E5CE6),
    fill: Color(0x1FFFFFFF),
    secondaryFill: Color(0x52787880),
    tertiaryFill: Color(0x1FFFFFFF),
    quaternaryFill: Color(0x14747480),
    container: Color(0x8A1C1C1E),
    subtleStroke: Color(0x2BFFFFFF),
    faceMatrix: <double>[
      1.236220, -0.214560, -0.021660, 0, 0.125, //
      -0.063780, 1.085440, -0.021660, 0, 0.125, //
      -0.063780, -0.214560, 1.278340, 0, 0.125, //
      0, 0, 0, 1, 0, //
    ],
    glassBlur: 5,
    faceFillAlpha: 0,
    highlightTop: Color(0x38FFFFFF),
    highlightBottom: Color(0x14FFFFFF),
    edgeShadow: Color(0x05000000),
    innerShadow: Color(0x0F000000),
  );

  static GlassPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Continuous corner radii (GlasmioShapes).
abstract final class GlassRadii {
  static const double extraSmall = 8;
  static const double small = 16;
  static const double medium = 26;
  static const double large = 38;
  static const double extraLarge = 44;
  static const double capsule = 999;

  // Semantic aliases used by the app.
  static const double control = small;
  static const double field = small;
  static const double card = medium;
  static const double cardLarge = medium;
  static const double sheet = large;
  static const double alert = 34;
  static const double menu = 34;
}

/// Spacing steps: Glasmio uses compact 8 / regular 16 / section 32.
abstract final class GlassSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
}

/// Component geometry from the reference implementation.
abstract final class GlassMetrics {
  static const double controlHeight = 48;
  static const double buttonLarge = 50;
  static const double iconButton = 44;
  static const double listRow = 52;
  static const double listRowSubtitle = 68;
  static const double sectionTitle = 39;
  static const double toolbar = 54;
  static const double pageHorizontalPadding = 16;
  static const double alertWidth = 300;
}

/// Motion timings and curves modelled on UIKit spring behaviour.
abstract final class GlassMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 380);
  static const Duration header = Duration(milliseconds: 240);

  static const Curve emphasized = Cubic(0.25, 0.8, 0.25, 1);
  static const Curve standard = Cubic(0.4, 0.0, 0.2, 1);
  static const Curve decelerate = Cubic(0.0, 0.0, 0.2, 1);
  static const Curve press = Cubic(0.3, 0.0, 0.4, 1);
}

/// SF text styles: size / line height / tracking / weight.
abstract final class GlassType {
  static const TextStyle largeTitle = TextStyle(
    fontSize: 34,
    height: 41 / 34,
    letterSpacing: 0.40,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle title1 = TextStyle(
    fontSize: 28,
    height: 34 / 28,
    letterSpacing: 0.38,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle title2 = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    letterSpacing: -0.26,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle title3 = TextStyle(
    fontSize: 20,
    height: 25 / 20,
    letterSpacing: -0.45,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    letterSpacing: -0.43,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    letterSpacing: -0.43,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle callout = TextStyle(
    fontSize: 16,
    height: 21 / 16,
    letterSpacing: -0.31,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle subheadline = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    letterSpacing: -0.23,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle footnote = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    letterSpacing: -0.08,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle caption1 = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle caption2 = TextStyle(
    fontSize: 11,
    height: 13 / 11,
    letterSpacing: 0.06,
    fontWeight: FontWeight.w400,
  );

  /// Material role mapping documented by the reference implementation.
  static TextTheme textTheme(Color label) => TextTheme(
        displayLarge: largeTitle.copyWith(color: label),
        displayMedium: title1.copyWith(color: label),
        displaySmall: title2.copyWith(color: label),
        headlineLarge: largeTitle.copyWith(color: label),
        headlineMedium: title1.copyWith(color: label),
        headlineSmall: title2.copyWith(color: label),
        titleLarge: title3.copyWith(color: label),
        titleMedium: headline.copyWith(color: label),
        titleSmall: subheadline.copyWith(
          color: label,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: body.copyWith(color: label),
        bodyMedium: subheadline.copyWith(color: label),
        bodySmall: footnote.copyWith(color: label),
        labelLarge: body.copyWith(color: label, fontWeight: FontWeight.w600),
        labelMedium: caption1.copyWith(color: label),
        labelSmall: caption2.copyWith(color: label),
      );
}
