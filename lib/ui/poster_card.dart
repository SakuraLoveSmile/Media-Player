import 'package:flutter/material.dart';

import 'app_controls.dart';
import 'theme/app_tokens.dart';

/// Poster grid card shared by the library, search, favorites and home rows:
/// a rounded poster with rating / unwatched badges and a title, built from
/// Material components.
///
/// The badges mirror Yamby (S28): the rating sits in the lower-right corner
/// and the unwatched-episode count in the upper-right; a played title keeps
/// its 已看 tag instead.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.name,
    this.played = false,
    required this.onTap,
    this.image,
    this.rating,
    this.unplayedCount = 0,
    this.subtitle,
    this.centerTitle = false,
  });

  final String name;
  final bool played;
  final ImageProvider? image;
  final VoidCallback? onTap;

  /// Community rating shown as the lower-right badge; null hides it.
  final double? rating;

  /// Unwatched episode count for a series poster (Yamby's blue count badge).
  final int unplayedCount;

  /// Optional second line (usually the production year or a year range).
  final String? subtitle;

  /// Home rows center the title under the poster, grids left-align it.
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final BorderRadius radius = BorderRadius.circular(AppRadii.card);

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Column(
        crossAxisAlignment: centerTitle
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: image == null
                        ? Icon(
                            Icons.movie_outlined,
                            size: 30,
                            color: scheme.outline,
                          )
                        : Image(
                            image: image!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              color: scheme.outline,
                            ),
                          ),
                  ),
                  if (unplayedCount > 0)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: _CountBadge(count: unplayedCount),
                    )
                  else if (played)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: AppTag(
                        label: '已看',
                        dense: true,
                        color: scheme.primary,
                      ),
                    ),
                  if (rating != null && rating! > 0)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: _RatingBadge(rating: rating!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name,
            maxLines: centerTitle ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            textAlign: centerTitle ? TextAlign.center : TextAlign.start,
            style: text.bodySmall!.copyWith(
              color: scheme.onSurface,
              fontWeight: centerTitle ? FontWeight.w600 : FontWeight.w500,
              height: 1.25,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: centerTitle ? TextAlign.center : TextAlign.start,
                style: text.labelSmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Translucent rating pill in the poster's lower-right corner.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: const BoxDecoration(
        color: Color(0xCC000000),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFC94D)),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Blue count badge for unwatched episodes, mirroring Yamby's series poster.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadii.capsule),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: scheme.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
