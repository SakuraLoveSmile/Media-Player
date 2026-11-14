import 'package:flutter/material.dart';

import '../../../core/errors/app_error.dart';
import '../../../data/moviepilot/models/mp_media_info.dart';
import '../../../ui/app_controls.dart';
import '../../../ui/theme/app_tokens.dart';

/// One `/media/search` hit (求片 plan S11).
///
/// Movies offer 求片 directly; series open the season picker first, so the card
/// shows the button label that matches what tapping it will do.
class SearchResultCard extends StatelessWidget {
  const SearchResultCard({
    super.key,
    required this.media,
    required this.onRequest,
    this.alreadyInLibrary = false,
    this.onPlay,
    this.busy = false,
  });

  final MpMediaInfo media;

  /// Called for a movie, or for a series after its season was chosen.
  final VoidCallback onRequest;

  /// True when MoviePilot already has the title, so the action is "去播放".
  final bool alreadyInLibrary;

  /// Plays the existing library item; only used with [alreadyInLibrary].
  final VoidCallback? onPlay;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final poster = media.posterUri;
    final subtitle = <String>[
      if (media.year.isNotEmpty) media.year,
      if (media.type != null) media.type!.wire,
      if (media.isSeries && media.numberOfSeasons > 0)
        '${media.numberOfSeasons} 季',
    ].join(' · ');

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Poster(uri: poster),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  media.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
                ],
                if (media.vote > 0) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppTag(
                        label: media.vote.toStringAsFixed(1),
                        dense: true,
                        color: Colors.orange,
                        icon: const Icon(Icons.star_rounded),
                      ),
                      if (media.isSeries) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        AppTag(
                          label: '剧集',
                          dense: true,
                          color: palette.secondary,
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: alreadyInLibrary
                      ? AppButton(
                          key: Key('search-play-${media.ref.mediaId}'),
                          label: '去播放',
                          variant: AppButtonVariant.tinted,
                          height: 36,
                          onPressed: onPlay,
                        )
                      : AppButton(
                          key: Key('search-request-${media.ref.mediaId}'),
                          label: media.isSeries ? '选择季' : '求片',
                          height: 36,
                          loading: busy,
                          onPressed: busy ? null : onRequest,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final Widget placeholder = ColoredBox(
      color: palette.surfaceContainerHighest,
      child: Icon(Icons.movie_outlined, color: palette.outline, size: 28),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.extraSmall),
      child: SizedBox(
        width: 68,
        height: 102,
        child: uri == null
            ? placeholder
            : Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

/// Copy for a failed search or subscribe action (求片 plan §6).
String requestFailureText(AppErrorCode code) {
  return switch (code) {
    AppErrorCode.unauthorized => '登录已失效，请在设置中重新登录',
    AppErrorCode.forbidden => '账号权限不足，无法操作',
    AppErrorCode.notConfigured => '尚未登录 MoviePilot',
    AppErrorCode.networkUnreachable => '无法连接 MoviePilot，请检查网络',
    AppErrorCode.notFound => 'MoviePilot 中找不到该条目',
    _ => '操作失败，请稍后重试',
  };
}
