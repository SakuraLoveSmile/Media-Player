import 'package:flutter/material.dart';

import '../../../data/moviepilot/models/media_request.dart';
import '../../../ui/glass/glass_controls.dart';
import '../../../ui/glass/glass_theme.dart';
import '../../../ui/glass/glass_tokens.dart';

/// The 求片 page for one request (求片 plan S13).
///
/// Renders whatever the derivation produced: a staged download shows a
/// determined bar with speed and ETA, searching and organizing show an
/// indeterminate bar, and a finished item offers a way into playback.
class RequestProgressCard extends StatelessWidget {
  const RequestProgressCard({
    super.key,
    required this.request,
    this.onSearchNow,
    this.onCancel,
    this.onPlay,
    this.busy = false,
  });

  final MediaRequest request;
  final VoidCallback? onSearchNow;
  final VoidCallback? onCancel;
  final VoidCallback? onPlay;

  /// An action for this card is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;

    return GlassCard(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _header(palette)),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: GlassSpacing.md),
          RequestStageChain(stage: request.stage),
          const SizedBox(height: GlassSpacing.md),
          _progress(context, palette),
          if (request.message.isNotEmpty) ...<Widget>[
            const SizedBox(height: GlassSpacing.sm),
            Text(
              request.message,
              key: Key('request-message-${request.id}'),
              style: GlassType.footnote.copyWith(
                color: request.stage == RequestStage.noResource
                    ? palette.orange
                    : palette.secondaryLabel,
              ),
            ),
          ],
          const SizedBox(height: GlassSpacing.md),
          _actions(palette),
        ],
      ),
    );
  }

  Widget _header(GlassPalette palette) {
    final season = request.seasonLabel;
    final subtitle = <String>[
      if (request.year.isNotEmpty) request.year,
      if (season.isNotEmpty) season,
      if (request.isSeries) '电视剧' else '电影',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          request.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GlassType.body.copyWith(
            color: palette.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GlassType.caption1.copyWith(color: palette.secondaryLabel),
          ),
        ],
      ],
    );
  }

  Widget _progress(BuildContext context, GlassPalette palette) {
    switch (request.stage) {
      case RequestStage.downloading:
        final progress = request.progressPercent;
        final hasValue = progress != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(GlassRadii.capsule),
              child: LinearProgressIndicator(
                key: Key('request-bar-${request.id}'),
                value: hasValue ? progress.clamp(0.0, 1.0) : null,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: GlassSpacing.sm),
            Row(
              children: <Widget>[
                if (hasValue)
                  Text(
                    '${request.percentDisplay}%',
                    key: Key('request-percent-${request.id}'),
                    style: GlassType.footnote.copyWith(
                      color: palette.tint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const Spacer(),
                if (request.downloadSpeed.isNotEmpty)
                  Text(
                    request.downloadSpeed,
                    style: GlassType.caption1.copyWith(
                      color: palette.secondaryLabel,
                    ),
                  ),
                if (request.eta.isNotEmpty) ...<Widget>[
                  const SizedBox(width: GlassSpacing.sm),
                  Text(
                    '剩余 ${request.eta}',
                    style: GlassType.caption1.copyWith(
                      color: palette.tertiaryLabel,
                    ),
                  ),
                ],
              ],
            ),
            if (request.isSeries && request.totalEpisodes > 0) ...<Widget>[
              const SizedBox(height: GlassSpacing.xs),
              Text(
                '已完成 ${request.completedEpisodes}/${request.totalEpisodes} 集',
                key: Key('request-episodes-${request.id}'),
                style: GlassType.caption1.copyWith(
                  color: palette.secondaryLabel,
                ),
              ),
            ],
            if (request.activeTaskCount > 1) ...<Widget>[
              const SizedBox(height: GlassSpacing.xs),
              Text(
                '${request.activeTaskCount} 个任务并行下载',
                style: GlassType.caption2.copyWith(
                  color: palette.tertiaryLabel,
                ),
              ),
            ],
          ],
        );
      case RequestStage.organizing:
        return ClipRRect(
          borderRadius: BorderRadius.circular(GlassRadii.capsule),
          child: LinearProgressIndicator(
            key: Key('request-bar-${request.id}'),
            minHeight: 6,
          ),
        );
      case RequestStage.inLibrary:
        return _Badge(
          key: Key('request-library-${request.id}'),
          label: '已入库',
          color: palette.green,
          icon: Icons.check_circle_outline,
        );
      case RequestStage.noResource:
        return _Badge(
          key: Key('request-no-resource-${request.id}'),
          label: '暂无资源',
          color: palette.orange,
          icon: Icons.search_off,
        );
      case RequestStage.paused:
        return _Badge(
          key: Key('request-paused-${request.id}'),
          label: '已暂停',
          color: palette.tertiaryLabel,
          icon: Icons.pause_circle_outline,
        );
      case RequestStage.cancelled:
        return _Badge(
          key: Key('request-cancelled-${request.id}'),
          label: '已取消',
          color: palette.tertiaryLabel,
          icon: Icons.cancel_outlined,
        );
      case RequestStage.submitted:
      case RequestStage.searching:
      case RequestStage.organizedPendingLibrary:
        return ClipRRect(
          borderRadius: BorderRadius.circular(GlassRadii.capsule),
          child: LinearProgressIndicator(
            key: Key('request-bar-${request.id}'),
            minHeight: 6,
          ),
        );
    }
  }

  Widget _actions(GlassPalette palette) {
    final actions = <Widget>[];

    if (request.stage == RequestStage.inLibrary && request.embyItemId != null) {
      actions.add(
        GlassButton(
          key: Key('request-play-${request.id}'),
          label: request.isSeries ? '去媒体库查看' : '去播放',
          variant: GlassButtonVariant.tinted,
          height: 36,
          onPressed: onPlay,
        ),
      );
    } else if (request.stage != RequestStage.cancelled) {
      if (onSearchNow != null && request.subscribeId != null) {
        actions.add(
          GlassButton(
            key: Key('request-search-now-${request.id}'),
            label: '立即搜索',
            variant: GlassButtonVariant.glass,
            height: 36,
            onPressed: busy ? null : onSearchNow,
          ),
        );
      }
      if (onCancel != null) {
        actions.add(
          GlassButton(
            key: Key('request-cancel-${request.id}'),
            label: '取消求片',
            variant: GlassButtonVariant.plain,
            height: 36,
            onPressed: busy ? null : onCancel,
          ),
        );
      }
    }

    if (actions.isEmpty) {
      return Text(
        '求片完成',
        style: GlassType.caption1.copyWith(color: palette.green),
      );
    }

    return Wrap(
      spacing: GlassSpacing.sm,
      runSpacing: GlassSpacing.sm,
      alignment: WrapAlignment.end,
      children: actions,
    );
  }
}

/// The stage chain: 已提交 → 搜索 → 下载 → 整理 → 入库.
class RequestStageChain extends StatelessWidget {
  const RequestStageChain({super.key, required this.stage});

  final RequestStage stage;

  /// Labels for the chain, in order.
  static const List<String> labels = <String>['已提交', '搜索', '下载', '整理', '入库'];

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    final index = stage.chainIndex;

    return Row(
      children: <Widget>[
        for (int i = 0; i < labels.length; i++) ...<Widget>[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: GlassSpacing.xs),
                color: i <= index
                    ? palette.tint.withValues(alpha: 0.6)
                    : palette.separator,
              ),
            ),
          GlassTag(
            label: labels[i],
            dense: true,
            color: i <= index ? palette.tint : palette.tertiaryLabel,
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GlassTag(
        label: label,
        color: color,
        icon: Icon(icon),
      ),
    );
  }
}
