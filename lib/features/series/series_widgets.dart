import 'package:flutter/material.dart';

import '../../data/models/media_item.dart';
import '../../ui/responsive.dart';
import '../../ui/theme/app_tokens.dart';

/// `S1E2` / `E2` for an episode (S78). The season number comes from the
/// episode itself when the server sends it, otherwise from the season the page
/// loaded, so a season page can label rows without another request.
String episodeCode(MediaItem episode, {int? seasonNumber, int? episodeNumber}) {
  final int? season = episode.parentIndexNumber ?? seasonNumber;
  final int number = episode.indexNumber ?? episodeNumber ?? 1;
  return season == null ? 'E$number' : 'S${season}E$number';
}

/// `S1E2：标题`, or just the code for an unnamed episode.
String episodeLabel(
  MediaItem episode, {
  int? seasonNumber,
  int? episodeNumber,
}) {
  final String code = episodeCode(
    episode,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );
  return episode.name.isEmpty ? code : '$code：${episode.name}';
}

/// Yamby's duration copy: `4分19秒`, `1小时2分3秒` (S78).
String durationLabel(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  final int seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '$hours小时$minutes分$seconds秒';
  if (minutes > 0) return '$minutes分$seconds秒';
  return '$seconds秒';
}

/// Yamby's season label: 第 1 季, the server name for specials (S78).
String seasonLabel(MediaItem season) {
  final int? number = season.indexNumber;
  if (number != null && number > 0) return '第 $number 季';
  if (season.name.trim().isNotEmpty) return season.name;
  return number == null ? '特别篇' : '第 $number 季';
}

/// Width of Yamby's resume button: about 58% of the screen, capped at the
/// centred content width on wide surfaces (S78).
double seriesPlayButtonWidth(BuildContext context) {
  if (isWide(context)) return AppBreakpoints.detailMaxWidth * 0.58;
  return MediaQuery.sizeOf(context).width * 0.58;
}

/// The floating action bar over a full-bleed hero (S78): round back button,
/// the item title once the hero has scrolled away, watched/favorite toggles and
/// the overflow menu (刷新 / 标记已看).
class SeriesTopBar extends StatelessWidget {
  const SeriesTopBar({
    super.key,
    required this.title,
    required this.opaque,
    required this.played,
    required this.favorite,
    required this.busy,
    required this.onBack,
    required this.onWatched,
    required this.onFavorite,
    required this.onRefresh,
    required this.onTogglePlayed,
    this.keyPrefix = 'series',
  });

  final String title;

  /// True once the hero has scrolled behind the bar: the bar turns black and
  /// the title fades in.
  final bool opaque;
  final bool played;
  final bool favorite;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onWatched;
  final VoidCallback onFavorite;
  final VoidCallback onRefresh;
  final VoidCallback onTogglePlayed;

  /// Keys are namespaced so the series and season pages can both be tested.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.paddingOf(context).top;
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      color: opaque ? Colors.black : Colors.transparent,
      padding: EdgeInsets.only(top: topPadding, left: 4, right: 4),
      height: topPadding + 56,
      child: Row(
        children: <Widget>[
          _BarAction(
            key: Key('$keyPrefix-back'),
            tooltip: '返回',
            onPressed: onBack,
            child: const Icon(Icons.arrow_back, shadows: _barIconShadows),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AnimatedOpacity(
              key: Key('$keyPrefix-title'),
              opacity: opaque ? 1 : 0,
              duration: AppMotion.fast,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium!
                    .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          _BarAction(
            key: Key('$keyPrefix-watched'),
            tooltip: played ? '标记未看' : '标记已看',
            onPressed: busy ? null : onWatched,
            child: Icon(
              played ? Icons.check_circle : Icons.check_circle_outline,
              color: played ? Colors.greenAccent : Colors.white,
              shadows: _barIconShadows,
            ),
          ),
          _BarAction(
            key: Key('$keyPrefix-favorite'),
            tooltip: favorite ? '取消收藏' : '收藏',
            onPressed: busy ? null : onFavorite,
            // Yamby's unfavorited state is a heart with a small plus (S78).
            child: favorite
                ? const Icon(Icons.favorite, color: Colors.pinkAccent)
                : const _FavoriteAddIcon(),
          ),
          PopupMenuButton<String>(
            key: Key('$keyPrefix-overflow'),
            tooltip: '更多',
            icon: const Icon(
              Icons.more_vert,
              color: Colors.white,
              shadows: _barIconShadows,
            ),
            onSelected: (String value) {
              if (value == 'refresh') onRefresh();
              if (value == 'played') onTogglePlayed();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                key: Key('$keyPrefix-menu-refresh'),
                value: 'refresh',
                child: const Text('刷新'),
              ),
              PopupMenuItem<String>(
                key: Key('$keyPrefix-menu-played'),
                value: 'played',
                child: Text(played ? '标记未看' : '标记已看'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The floating back button drawn over an error state, so a failed load can
/// still be left (S78).
class SeriesBackButton extends StatelessWidget {
  const SeriesBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _BarAction(
    tooltip: '返回',
    onPressed: onPressed,
    child: Icon(
      Icons.arrow_back,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

/// Shadow that keeps a white icon readable over bright artwork (S78).
const List<Shadow> _barIconShadows = <Shadow>[
  Shadow(color: Colors.black54, blurRadius: 8),
];

/// Yamby's top-bar action: a plain white icon with a 48dp touch target and no
/// circular background (S78).
class _BarAction extends StatelessWidget {
  const _BarAction({
    super.key,
    required this.tooltip,
    required this.child,
    this.onPressed,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: IconTheme.merge(
            data: const IconThemeData(size: 24, color: Colors.white),
            child: Center(
              child: enabled ? child : Opacity(opacity: 0.4, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Unfavorited heart with the small plus Yamby draws on its top-right (S78).
class _FavoriteAddIcon extends StatelessWidget {
  const _FavoriteAddIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Align(
            alignment: Alignment.center,
            child: Icon(
              Icons.favorite_border,
              size: 23,
              shadows: _barIconShadows,
            ),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: Icon(Icons.add, size: 12, shadows: _barIconShadows),
          ),
        ],
      ),
    );
  }
}

/// Yamby's resume row (S78): a dark neutral button whose watched portion is
/// filled light blue, with white copy on top. The played fraction is visible
/// before resting, and the button is 56dp tall like the reference client.
class SeriesPlayButton extends StatelessWidget {
  const SeriesPlayButton({
    super.key,
    required this.label,
    required this.progress,
    required this.onPressed,
  });

  /// Dark neutral button fill (~#3A3A3A in Yamby), used in both app themes.
  static const Color surface = Color(0xFF3A3A3A);

  /// Light blue watched-portion fill (~#8AB4F8 in Yamby).
  static const Color progressFill = Color(0xFF8AB4F8);

  final String label;
  final double progress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color foreground = enabled ? Colors.white : Colors.white54;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Material(
        color: enabled ? surface : surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (progress > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: const ColoredBox(color: progressFill),
                  ),
                ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.play_arrow_rounded, color: foreground, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The light-blue square chevron beside the play button; it opens the 选集
/// sheet (S78). 54x56 with a dark icon, like Yamby.
class SeriesPickerButton extends StatelessWidget {
  const SeriesPickerButton({super.key, required this.onPressed});

  /// Dark glyph on the light-blue square, matching the reference client.
  static const Color iconColor = Color(0xFF1B1B1F);

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return SizedBox(
      width: 54,
      height: 56,
      child: Material(
        color: enabled
            ? SeriesPlayButton.progressFill
            : SeriesPlayButton.progressFill.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Icon(
            Icons.keyboard_arrow_down,
            color: enabled ? iconColor : iconColor.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// A section title (`继续观看`, `季`, ...), with the optional ‹ # › paging
/// controls Yamby puts on the right of the 继续观看 row (S78).
class SeriesSectionHeader extends StatelessWidget {
  const SeriesSectionHeader(
    this.text, {
    super.key,
    this.onPrevious,
    this.onNext,
    this.onSeasons,
    this.keyPrefix = 'series',
  });

  final String text;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSeasons;
  final String keyPrefix;

  bool get _paged => onPrevious != null || onNext != null || onSeasons != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_paged)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: palette.outlineVariant),
                borderRadius: BorderRadius.circular(AppRadii.capsule),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _PagerButton(
                    key: Key('$keyPrefix-prev'),
                    tooltip: '向左翻页',
                    icon: Icons.chevron_left,
                    onPressed: onPrevious,
                  ),
                  _PagerButton(
                    key: Key('$keyPrefix-hash'),
                    tooltip: '选集',
                    icon: Icons.tag,
                    onPressed: onSeasons,
                  ),
                  _PagerButton(
                    key: Key('$keyPrefix-next'),
                    tooltip: '向右翻页',
                    icon: Icons.chevron_right,
                    onPressed: onNext,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Icon(
            icon,
            size: 18,
            color: onPressed == null
                ? palette.onSurfaceVariant.withValues(alpha: 0.4)
                : palette.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The 选集 bottom sheet: the current season's episodes, tap to play (S78).
Future<void> showSeriesEpisodePicker({
  required BuildContext context,
  required String title,
  required List<MediaItem> episodes,
  required String Function(MediaItem episode) labelOf,
  required String Function(MediaItem episode) subtitleOf,
  required ImageProvider? Function(MediaItem episode) imageOf,
  required void Function(MediaItem episode) onSelected,
}) {
  final ColorScheme palette = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                title,
                key: const Key('episode-picker-title'),
                style: Theme.of(context).textTheme.titleMedium!
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: episodes.isEmpty
                  ? const Center(child: Text('这一季暂无分集'))
                  : ListView.builder(
                      key: const Key('episode-picker-list'),
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      itemCount: episodes.length,
                      itemBuilder: (BuildContext context, int index) {
                        final MediaItem episode = episodes[index];
                        final ImageProvider? image = imageOf(episode);
                        return InkWell(
                          key: Key('episode-pick-${episode.id}'),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            onSelected(episode);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.sm,
                            ),
                            child: Row(
                              children: <Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.control,
                                  ),
                                  child: SizedBox(
                                    width: 96,
                                    height: 54,
                                    child: image == null
                                        ? ColoredBox(
                                            color:
                                                palette.surfaceContainerHighest,
                                            child: Icon(
                                              Icons.movie_outlined,
                                              size: 20,
                                              color: palette.outline,
                                            ),
                                          )
                                        : Image(
                                            image: image,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                ColoredBox(
                                                  color: palette
                                                      .surfaceContainerHighest,
                                                ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        labelOf(episode),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                      Text(
                                        subtitleOf(episode),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall!
                                            .copyWith(
                                              color: palette.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  episode.userData.played
                                      ? Icons.check_circle
                                      : Icons.play_arrow,
                                  size: 20,
                                  color: episode.userData.played
                                      ? Colors.greenAccent
                                      : palette.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
