import 'package:flutter/material.dart';

import 'theme/app_tokens.dart';

/// Tablet / wide-screen breakpoints (S15). Browse pages adapt their poster
/// grids at [compact]/[medium]/[expanded]; the library gains a persistent
/// master-detail preview pane at [medium] and the detail page switches to a
/// constrained two-column layout there.
abstract final class AppBreakpoints {
  /// Phone landscape / small tablet boundary: 3 → 4 poster columns.
  static const double compact = 600;

  /// Tablet boundary: 4 → 5 poster columns, library master-detail pane and
  /// the wide detail layout turn on at this width.
  static const double medium = 900;

  /// Large tablet / desktop boundary: 5 → 6 poster columns.
  static const double expanded = 1200;

  /// Width of the library's persistent preview pane on wide surfaces.
  static const double previewPaneWidth = 360;

  /// Reading-width cap of the detail page content on wide surfaces.
  static const double detailMaxWidth = 1000;
}

/// Poster card aspect ratio (width / height) shared by every browse grid and
/// the home poster rows, so cards keep the same shape at any column count.
const double posterAspectRatio = 0.56;

/// True on tablet / wide surfaces (>= [AppBreakpoints.medium]).
bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= AppBreakpoints.medium;

/// Poster-grid column count for an available width (S15):
/// <600 → 3, <900 → 4, <1200 → 5, else 6.
int posterGridColumns(double availableWidth) {
  if (availableWidth < AppBreakpoints.compact) return 3;
  if (availableWidth < AppBreakpoints.medium) return 4;
  if (availableWidth < AppBreakpoints.expanded) return 5;
  return 6;
}

/// The shared poster-grid delegate: a fixed responsive column count with the
/// design-system spacing and the common poster aspect ratio.
SliverGridDelegate posterGridDelegate(double availableWidth) {
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: posterGridColumns(availableWidth),
    mainAxisSpacing: AppSpacing.xl,
    crossAxisSpacing: AppSpacing.md,
    childAspectRatio: posterAspectRatio,
  );
}

/// Home poster-row card width; rows scale up on wide surfaces (S15).
double homeRowCardWidth(BuildContext context) => isWide(context) ? 180 : 130;

/// Home poster-row height: the poster keeps the grid aspect ratio and the
/// centred title sits under it (S28).
double homeRowHeight(BuildContext context) =>
    homeRowCardWidth(context) / posterAspectRatio + 28;

/// Media library covers are the server's own artwork and Emby reports them
/// as 16:9 (PrimaryImageAspectRatio 1.7778 on 4.10, measured on the views of
/// this server). The card keeps that ratio so the strip shows the whole
/// cover instead of cropping its sides.
const double libraryCoverAspectRatio = 16 / 9;

/// 媒体库 strip card width / height (S28): Yamby's wide library card.
double homeLibraryCardWidth(BuildContext context) =>
    isWide(context) ? 240 : 170;
double homeLibraryCardHeight(BuildContext context) =>
    homeLibraryCardWidth(context) / libraryCoverAspectRatio;

/// Height of the library name line under the card. Derived from the label's
/// own line height and the user's text scale, so a larger font setting makes
/// the strip taller instead of clipping the name (S28).
double homeLibraryLabelHeight(BuildContext context) {
  final TextStyle? style = Theme.of(context).textTheme.labelMedium;
  final double fontSize = style?.fontSize ?? 12;
  final double lineHeight = fontSize * (style?.height ?? 1.33);
  return MediaQuery.textScalerOf(context).scale(lineHeight);
}

/// Strip height: the cover, the gap under it and the library name (S28).
double homeLibraryStripHeight(BuildContext context) =>
    homeLibraryCardHeight(context) +
    AppSpacing.sm +
    homeLibraryLabelHeight(context) +
    AppSpacing.xs;

/// Continue-watching card width: two cards peek per screen like Yamby.
double homeResumeCardWidth(BuildContext context) {
  final double width = MediaQuery.sizeOf(context).width;
  final double cardWidth = (width - AppSpacing.lg * 2 - AppSpacing.md) / 2;
  return cardWidth.clamp(150.0, 280.0);
}

/// Continue-watching artwork height (16:9 like the server's backdrop).
double homeResumeImageHeight(BuildContext context) =>
    homeResumeCardWidth(context) * 9 / 16;

/// Continue-watching row height: the artwork plus title and year lines.
double homeResumeRowHeight(BuildContext context) =>
    homeResumeImageHeight(context) + 46;

/// Recommended banner height (wide artwork), taller on wide surfaces (S15).
double homeBannerHeight(BuildContext context) {
  final double width = MediaQuery.sizeOf(context).width;
  return isWide(context) ? 260 : (width - AppSpacing.lg * 2) / 2.15;
}
