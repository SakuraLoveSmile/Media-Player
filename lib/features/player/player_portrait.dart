import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/models/media_item.dart';
import '../../data/models/person.dart';
import '../../ui/app_controls.dart';
import '../../ui/theme/app_tokens.dart';
import 'player_controller.dart';

/// Yamby's played-progress blue, used by the wave progress bar and the
/// season-card progress lines (S78).
const Color kPlayerProgressPlayed = Color(0xFF57A8FF);

/// 「S1E2：标题」 for an episode, null for anything else (S75).
///
/// Lives here rather than in the page so the portrait chrome and its info sheet
/// share one rule without a second import of the page itself.
String? episodeSubtitleLabel(MediaItem? item) {
  if (item == null || item.type != 'Episode') return null;
  final int? season = item.parentIndexNumber;
  final int? episode = item.indexNumber;
  final String number = <String>[
    if (season != null) 'S$season',
    if (episode != null) 'E$episode',
  ].join();
  if (number.isEmpty) return null;
  return item.name.isEmpty ? number : '$number：${item.name}';
}

/// Emby still for an episode (S47 / S78).
///
/// Mirrors SeriesController.episodeImage — the series-level Thumb when the
/// episode carries no Primary of its own, otherwise the episode's own Primary —
/// but stays inside the player feature: features never import each other (the
/// layering guard). Null without a cache/tag so the caller draws its
/// placeholder.
ImageProvider? episodeStillImage({
  required LibraryService? library,
  required PosterCache? posters,
  required MediaItem? episode,
}) {
  if (library == null || posters == null || episode == null) return null;
  final String? thumbId = episode.parentThumbItemId;
  final String? thumbTag = episode.parentThumbTag;
  final bool hasThumb =
      thumbId != null &&
      thumbId.isNotEmpty &&
      thumbTag != null &&
      thumbTag.isNotEmpty;
  final Uri? url = hasThumb
      ? library.imageUrl(thumbId, tag: thumbTag, maxWidth: 480, type: 'Thumb')
      : library.imageUrl(episode.id, tag: episode.imageTag, maxWidth: 480);
  if (url == null) return null;
  return PosterImageProvider(
    cache: posters,
    itemId: hasThumb ? thumbId : episode.id,
    url: url,
    tag: hasThumb ? thumbTag : episode.imageTag,
    maxWidth: 480,
    variant: hasThumb ? 'episode-thumb' : '',
  );
}

/// Transparent series/movie title art for the portrait top bar (S78).
///
/// Episodes reach the series logo through ParentLogoItemId/ParentLogoImageTag;
/// movies carry their own ImageTags.Logo. Null without a cache/tag so the top
/// bar keeps its plain title text.
ImageProvider? playerLogoImage({
  required LibraryService? library,
  required PosterCache? posters,
  required MediaItem? item,
  int maxWidth = 320,
}) {
  if (library == null || posters == null || item == null) return null;
  final String? parentId = item.parentLogoItemId;
  final String? parentTag = item.parentLogoTag;
  if (parentId != null &&
      parentId.isNotEmpty &&
      parentTag != null &&
      parentTag.isNotEmpty) {
    final Uri? url = library.imageUrl(
      parentId,
      tag: parentTag,
      maxWidth: maxWidth,
      type: 'Logo',
    );
    if (url == null) return null;
    return PosterImageProvider(
      cache: posters,
      itemId: parentId,
      url: url,
      tag: parentTag,
      maxWidth: maxWidth,
      variant: 'logo',
    );
  }
  final String? ownTag = item.logoTag;
  if (ownTag == null || ownTag.isEmpty) return null;
  final Uri? url = library.imageUrl(
    item.id,
    tag: ownTag,
    maxWidth: maxWidth,
    type: 'Logo',
  );
  if (url == null) return null;
  return PosterImageProvider(
    cache: posters,
    itemId: item.id,
    url: url,
    tag: ownTag,
    maxWidth: maxWidth,
    variant: 'logo',
  );
}

/// 16:9 still with a neutral placeholder, shared by the next-up card and the
/// portrait info sheet.
class EpisodeStill extends StatelessWidget {
  const EpisodeStill({
    super.key,
    required this.image,
    this.radius = AppRadii.control,
  });

  final ImageProvider? image;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final Widget placeholder = ColoredBox(
      color: palette.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.movie_outlined, size: 20, color: palette.outline),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image == null
          ? placeholder
          : Image(
              image: image!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

/// Yamby-style wave progress (S78): the watched part is a blue wave, the rest a
/// grey line, and a white capsule marks the position. Replaces the Material
/// Slider in the portrait dock; the page keeps the seek/throttle policy.
class WaveProgressBar extends StatelessWidget {
  const WaveProgressBar({
    super.key,
    required this.position,
    required this.duration,
    this.onChangeStart,
    this.onChange,
    this.onChangeEnd,
    this.height = 28,
  });

  final Duration position;
  final Duration duration;

  /// Called when a drag starts, so the page can hold off auto-hide.
  final VoidCallback? onChangeStart;

  /// Called while dragging (the page throttles seek-on-drag with this).
  final ValueChanged<Duration>? onChange;

  /// Called on release / tap: one seek for the whole interaction.
  final ValueChanged<Duration>? onChangeEnd;

  final double height;

  double get _fraction {
    final int total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration _target(double dx, double width) {
    if (duration <= Duration.zero || width <= 0) return Duration.zero;
    final double fraction = (dx / width).clamp(0.0, 1.0);
    return Duration(milliseconds: (duration.inMilliseconds * fraction).round());
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = duration > Duration.zero && onChangeEnd != null;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled
              ? (TapUpDetails details) {
                  onChangeStart?.call();
                  onChangeEnd!(_target(details.localPosition.dx, width));
                }
              : null,
          onHorizontalDragStart: enabled
              ? (DragStartDetails details) {
                  onChangeStart?.call();
                  onChange?.call(_target(details.localPosition.dx, width));
                }
              : null,
          onHorizontalDragUpdate: enabled
              ? (DragUpdateDetails details) {
                  onChange?.call(_target(details.localPosition.dx, width));
                }
              : null,
          onHorizontalDragEnd: enabled
              ? (DragEndDetails details) {
                  onChangeEnd!(_target(details.localPosition.dx, width));
                }
              : null,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveProgressPainter(
                fraction: _fraction,
                playedColor: kPlayerProgressPlayed,
                remainColor: Colors.white.withValues(alpha: 0.32),
                thumbColor: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Non-interactive wave line: the watched progress over an episode still in the
/// info sheet's 集 strip (S78).
class WaveProgressLine extends StatelessWidget {
  const WaveProgressLine({
    super.key,
    required this.fraction,
    this.height = 12,
    this.playedColor = kPlayerProgressPlayed,
    this.remainColor = const Color(0x59FFFFFF),
    this.thumbColor = Colors.white,
  });

  final double fraction;
  final double height;
  final Color playedColor;
  final Color remainColor;
  final Color thumbColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveProgressPainter(
          fraction: fraction.clamp(0.0, 1.0),
          playedColor: playedColor,
          remainColor: remainColor,
          thumbColor: thumbColor,
        ),
      ),
    );
  }
}

class _WaveProgressPainter extends CustomPainter {
  const _WaveProgressPainter({
    required this.fraction,
    required this.playedColor,
    required this.remainColor,
    required this.thumbColor,
  });

  final double fraction;
  final Color playedColor;
  final Color remainColor;
  final Color thumbColor;

  // Tuned against Yamby's dock: a taller, longer wave than a plain sine at the
  // track's own scale (P1 visual parity).
  static const double _stroke = 3;
  static const double _amplitude = 5;
  static const double _wavelength = 36;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final double cy = size.height / 2;
    final double endX = size.width * fraction;
    final Paint remain = Paint()
      ..color = remainColor
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (endX < size.width) {
      canvas.drawLine(Offset(endX, cy), Offset(size.width, cy), remain);
    }
    if (endX > 0) {
      final Path wave = Path()..moveTo(0, cy);
      for (double x = 0; x <= endX; x += 1) {
        wave.lineTo(
          x,
          cy + math.sin((x / _wavelength) * 2 * math.pi) * _amplitude,
        );
      }
      canvas.drawPath(
        wave,
        Paint()
          ..color = playedColor
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    // White capsule marker, kept inside the track at both ends.
    final double thumbX = endX.clamp(2.0, math.max(2.0, size.width - 2.0));
    final double thumbHeight = math.min(size.height - 6, 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(thumbX, cy),
          width: 3,
          height: thumbHeight,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(_WaveProgressPainter old) =>
      old.fraction != fraction ||
      old.playedColor != playedColor ||
      old.remainColor != remainColor ||
      old.thumbColor != thumbColor;
}

/// Yamby's 接下来 floating card (S78): a still, the next episode label and its
/// progress line, shown over the video's bottom-right corner near the end.
class NextUpCard extends StatelessWidget {
  const NextUpCard({
    super.key,
    required this.image,
    required this.title,
    required this.fraction,
    required this.onTap,
  });

  final ImageProvider? image;
  final String title;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '接下来',
                        style: Theme.of(context).textTheme.labelMedium!
                            .copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: 79,
                  child: EpisodeStill(
                    image: image,
                    radius: AppRadii.extraSmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall!
                      .copyWith(color: Colors.white, height: 1.25),
                ),
                const SizedBox(height: 6),
                WaveProgressLine(
                  fraction: fraction,
                  height: 10,
                  remainColor: Colors.white.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Portrait info sheet (S78, Yamby parity): the playing episode's still and
/// metadata, the season's 集 strip with the current episode's wave progress,
/// then the cast row when the detail response carried People.
class PortraitInfoSheet extends StatelessWidget {
  const PortraitInfoSheet({
    super.key,
    required this.controller,
    required this.episode,
    this.series,
    required this.people,
    required this.seasonEpisodes,
    required this.library,
    required this.posters,
    required this.onEpisodeSelected,
  });

  final PlayerController controller;

  /// Item shown in the sheet: the season-list entry when available (it carries
  /// the parent Thumb), else the playing item itself.
  final MediaItem episode;

  /// Series detail behind the episode. Episodes usually carry no
  /// CommunityRating / PremiereDate, so the header falls back to the series'
  /// values — Yamby shows the series rating on this panel.
  final MediaItem? series;

  /// Cast from the detail response (People); the row is hidden when empty.
  final List<Person> people;

  final List<MediaItem> seasonEpisodes;
  final LibraryService? library;
  final PosterCache? posters;
  final ValueChanged<MediaItem> onEpisodeSelected;

  ImageProvider? _stillFor(MediaItem item) =>
      episodeStillImage(library: library, posters: posters, episode: item);

  ImageProvider? _personImage(Person person) {
    final LibraryService? library = this.library;
    final PosterCache? posters = this.posters;
    final String? id = person.id;
    if (library == null || posters == null || id == null || id.isEmpty) {
      return null;
    }
    final Uri? url = library.imageUrl(id, tag: person.imageTag, maxWidth: 160);
    if (url == null) return null;
    return PosterImageProvider(
      cache: posters,
      itemId: id,
      url: url,
      tag: person.imageTag,
      maxWidth: 160,
      variant: 'person-avatar',
    );
  }

  /// 「2004/06/04」: the episode's premiere, else the series', else the year.
  static String? _dateLabel(MediaItem item, MediaItem? series) {
    final DateTime? date = item.premiereAt ?? series?.premiereAt;
    if (date != null) {
      final String month = date.month.toString().padLeft(2, '0');
      final String day = date.day.toString().padLeft(2, '0');
      return '${date.year}/$month/$day';
    }
    return item.productionYear?.toString() ??
        series?.productionYear?.toString();
  }

  /// Episode rating when the server set one, else the playing item's, else the
  /// series' (Emby rates series; Yamby shows ★7.0 on the episode panel too).
  double? _rating() =>
      episode.communityRating ??
      controller.item?.communityRating ??
      series?.communityRating;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final PlayerState state = controller.state;
    final String? seriesName = episode.seriesName;
    final String mainTitle = (seriesName != null && seriesName.isNotEmpty)
        ? seriesName
        : episode.name;
    final String? episodeLabel = episodeSubtitleLabel(episode);
    final String? dateLabel = _dateLabel(episode, series);
    final double? rating = _rating();
    final String? overview = (episode.overview?.trim().isNotEmpty ?? false)
        ? episode.overview
        : state.overview;
    final List<Person> actors = <Person>[
      for (final Person person in people)
        if (person.type == null || person.type == 'Actor') person,
    ];
    // Yamby's 集 cards are about half the screen wide; height follows 16:9.
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double cardWidth = (screenWidth * 0.48).clamp(140.0, 240.0);
    final double cardImageHeight = cardWidth * 9 / 16;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: AppCard(
        color: palette.surfaceContainerLow,
        radius: AppRadii.sheet,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                key: const Key('player-info-handle'),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 132,
                  height: 74,
                  child: EpisodeStill(image: _stillFor(episode)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        mainTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium!.copyWith(
                          color: palette.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (episodeLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            episodeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall!.copyWith(
                              color: palette.onSurface,
                            ),
                          ),
                        ),
                      if (dateLabel != null || rating != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          // Wrap rather than Row: the sheet column is narrow on
                          // phones, so a long date plus rating wraps instead of
                          // overflowing.
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              if (dateLabel != null)
                                Text(
                                  dateLabel,
                                  style: text.labelMedium!.copyWith(
                                    color: palette.onSurfaceVariant,
                                    fontFeatures: const <FontFeature>[
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              if (rating != null)
                                Row(
                                  key: const Key('player-info-rating'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: palette.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      rating.toStringAsFixed(1),
                                      style: text.labelMedium!.copyWith(
                                        color: palette.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      if (overview != null && overview.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            overview,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall!.copyWith(
                              color: palette.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('player-info-close'),
                  tooltip: '收起',
                  color: palette.onSurfaceVariant,
                  iconSize: 22,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
            // Only the lower section scrolls: the header stays outside any
            // scrollable, so dragging it down dismisses the sheet like Yamby.
            Flexible(
              child: SingleChildScrollView(
                key: const Key('player-info-sheet'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (seasonEpisodes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        '集',
                        style: text.titleSmall!.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        height: cardImageHeight + 24,
                        child: ListView.separated(
                          key: const Key('player-info-episodes'),
                          scrollDirection: Axis.horizontal,
                          itemCount: seasonEpisodes.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: AppSpacing.sm),
                          itemBuilder: (BuildContext context, int index) {
                            final MediaItem item = seasonEpisodes[index];
                            final bool current = item.id == episode.id;
                            final double fraction;
                            if (current) {
                              fraction = state.duration > Duration.zero
                                  ? state.position.inMilliseconds /
                                        state.duration.inMilliseconds
                                  : 0;
                            } else {
                              fraction = item.runTimeTicks <= 0
                                  ? 0
                                  : item.userData.positionTicks /
                                        item.runTimeTicks;
                            }
                            return InkWell(
                              key: Key('player-episode-${item.id}'),
                              borderRadius: BorderRadius.circular(
                                AppRadii.control,
                              ),
                              onTap: () => onEpisodeSelected(item),
                              child: SizedBox(
                                width: cardWidth,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Container(
                                      height: cardImageHeight,
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
                                          EpisodeStill(image: _stillFor(item)),
                                          if (fraction > 0)
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: WaveProgressLine(
                                                fraction: fraction,
                                                height: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      episodeSubtitleLabel(item) ?? item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.labelSmall!.copyWith(
                                        color: current
                                            ? palette.primary
                                            : palette.onSurfaceVariant,
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
                    if (actors.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        '演员',
                        style: text.titleSmall!.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          key: const Key('player-info-people'),
                          scrollDirection: Axis.horizontal,
                          itemCount: actors.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: AppSpacing.md),
                          itemBuilder: (BuildContext context, int index) {
                            final Person person = actors[index];
                            final ImageProvider? image = _personImage(person);
                            final Widget placeholder = ColoredBox(
                              color: palette.surfaceContainerHighest,
                              child: Icon(
                                Icons.person,
                                color: palette.outline,
                                size: 24,
                              ),
                            );
                            return SizedBox(
                              width: 64,
                              child: Column(
                                children: <Widget>[
                                  ClipOval(
                                    child: SizedBox(
                                      width: 56,
                                      height: 56,
                                      child: image == null
                                          ? placeholder
                                          : Image(
                                              image: image,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  placeholder,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    person.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.labelSmall!.copyWith(
                                      color: palette.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
