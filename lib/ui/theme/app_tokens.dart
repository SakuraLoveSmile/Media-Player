import 'package:flutter/material.dart';

/// Neutral layout tokens for the Material design system.
///
/// These are design-system-agnostic geometry helpers (an 4/8-based spacing
/// scale, Material 3 corner radii and Material motion curves). They carry no
/// platform-specific styling; colours and typography come from the Material
/// [ColorScheme] and [TextTheme] built in `app_theme.dart`.
abstract final class AppSpacing {
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

/// Material 3 corner radii (circular arcs, not continuous corners).
abstract final class AppRadii {
  static const double extraSmall = 8;
  static const double small = 12;
  static const double medium = 16;
  static const double large = 28;
  static const double extraLarge = 28;
  static const double capsule = 999;

  // Semantic aliases used across the app.
  static const double control = small;
  static const double field = small;
  static const double card = medium;
  static const double cardLarge = medium;
  static const double sheet = large;
  static const double alert = large;
  static const double menu = small;
}

/// Component geometry.
abstract final class AppMetrics {
  static const double controlHeight = 48;
  static const double buttonLarge = 48;
  static const double iconButton = 44;
  static const double listRow = 56;
  static const double listRowSubtitle = 72;
  static const double toolbar = 56;
  static const double pageHorizontalPadding = 16;
}

/// Material motion durations and curves.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);
  static const Duration header = Duration(milliseconds: 240);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve standard = Curves.fastOutSlowIn;
  static const Curve decelerate = Curves.decelerate;
  static const Curve press = Curves.easeOut;

  /// Page-to-page cross-fade (S79). A push is a touch longer than a pop so
  /// arriving feels deliberate while going back stays immediate; 320ms was
  /// picked on device, where a pure fade reads shorter than the 300ms zoom it
  /// replaced because nothing moves.
  static const Duration pageIn = Duration(milliseconds: 320);
  static const Duration pageOut = Duration(milliseconds: 260);

  /// The incoming page becomes visible quickly and then settles softly.
  static const Curve pageInCurve = Curves.easeOutCubic;

  /// The leaving page dissolves smoothly all the way through a pop.
  static const Curve pageOutCurve = Curves.easeInOutCubic;
}
