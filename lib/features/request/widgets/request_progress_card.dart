import 'package:flutter/material.dart';

import '../../../data/moviepilot/models/media_request.dart';
import '../../../ui/app_controls.dart';
import '../../../ui/theme/app_tokens.dart';

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
    final ColorScheme palette = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _header(context, palette)),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RequestStageChain(stage: request.stage),
          const SizedBox(height: AppSpacing.md),
          _status(context, palette),
          _progress(context, palette),
          const SizedBox(height: AppSpacing.md),
          _actions(context, palette),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme palette) {
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
          style: Theme.of(context).textTheme.bodyLarge!
              .copyWith(color: palette.onSurface, fontWeight: FontWeight.w600),
        ),
        if (subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.labelMedium!
                .copyWith(color: palette.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  /// The one sentence describing the phase, and the only place it is written.
  Widget _status(BuildContext context, ColorScheme palette) {
    final String text;
    final Color color;
    switch (request.stage) {
      case RequestStage.inLibrary:
        text = request.message.isEmpty ? '已入库，可以播放' : request.message;
        color = Colors.green;
      case RequestStage.noResource:
        text = request.message.isEmpty ? '暂未找到资源，持续订阅中' : request.message;
        color = Colors.orange;
      case RequestStage.paused:
        text = request.message.isEmpty ? '已在 MoviePilot 中暂停' : request.message;
        color = palette.outline;
      case RequestStage.cancelled:
        text = request.message.isEmpty ? '已取消求片' : request.message;
        color = palette.outline;
      case RequestStage.submitted:
        text = request.message.isEmpty
            ? '已提交，等待 MoviePilot 搜索'
            : request.message;
        color = palette.onSurfaceVariant;
      case RequestStage.searching:
        text = request.message.isEmpty ? '正在搜索资源' : request.message;
        color = palette.primary;
      case RequestStage.downloading:
        text = request.message.isEmpty ? '正在下载' : request.message;
        color = palette.primary;
      case RequestStage.organizing:
        text = request.message.isEmpty ? '正在整理文件到媒体库' : request.message;
        color = palette.primary;
      case RequestStage.organizedPendingLibrary:
        text = request.message.isEmpty ? '整理完成，等待 Emby 入库' : request.message;
        color = palette.primary;
    }
    return Text(
      text,
      key: Key('request-status-${request.id}'),
      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: color),
    );
  }

  /// Numbers and badges instead of a progress bar.
  ///
  /// A bar was misleading here: MoviePilot reports a phase, not a fraction, so
  /// an indeterminate bar sat at some arbitrary fill and looked like stalled
  /// progress. The sentence describing the phase lives in the message line
  /// below; this method only adds what that cannot express — the download
  /// numbers, or a badge for a stage that is not progress at all.
  Widget _progress(BuildContext context, ColorScheme palette) {
    switch (request.stage) {
      case RequestStage.downloading:
        final progress = request.progressPercent;
        final details = <String>[
          if (progress != null) '${request.percentDisplay}%',
          if (request.downloadSpeed.isNotEmpty) request.downloadSpeed,
          if (request.eta.isNotEmpty) '剩余 ${request.eta}',
        ];
        final episodes = request.isSeries && request.totalEpisodes > 0
            ? '已完成 ${request.completedEpisodes}/${request.totalEpisodes} 集'
            : null;
        final tasks = request.activeTaskCount > 1
            ? '${request.activeTaskCount} 个任务并行'
            : null;
        final below = <String>[
          if (details.isNotEmpty) details.join(' · '),
          ?episodes,
          ?tasks,
        ];
        if (below.isEmpty) return const SizedBox.shrink();
        return Text(
          below.join('\n'),
          key: Key('request-detail-${request.id}'),
          style: Theme.of(context).textTheme.labelMedium!
              .copyWith(color: palette.onSurfaceVariant),
        );
      case RequestStage.inLibrary:
        return _Badge(
          key: Key('request-library-${request.id}'),
          label: '已入库',
          color: Colors.green,
          icon: Icons.check_circle_outline,
        );
      case RequestStage.noResource:
        return _Badge(
          key: Key('request-no-resource-${request.id}'),
          label: '暂无资源',
          color: Colors.orange,
          icon: Icons.search_off,
        );
      case RequestStage.paused:
        return _Badge(
          key: Key('request-paused-${request.id}'),
          label: '已暂停',
          color: palette.outline,
          icon: Icons.pause_circle_outline,
        );
      case RequestStage.cancelled:
        return _Badge(
          key: Key('request-cancelled-${request.id}'),
          label: '已取消',
          color: palette.outline,
          icon: Icons.cancel_outlined,
        );
      case RequestStage.submitted:
      case RequestStage.searching:
      case RequestStage.organizing:
      case RequestStage.organizedPendingLibrary:
        // The message line already states the phase.
        return const SizedBox.shrink();
    }
  }

  Widget _actions(BuildContext context, ColorScheme palette) {
    final actions = <Widget>[];

    if (request.stage == RequestStage.inLibrary && request.embyItemId != null) {
      actions.add(
        AppButton(
          key: Key('request-play-${request.id}'),
          label: request.isSeries ? '去媒体库查看' : '去播放',
          variant: AppButtonVariant.tinted,
          height: 36,
          onPressed: onPlay,
        ),
      );
    } else if (request.stage != RequestStage.cancelled) {
      if (onSearchNow != null && request.subscribeId != null) {
        actions.add(
          AppButton(
            key: Key('request-search-now-${request.id}'),
            label: '立即搜索',
            variant: AppButtonVariant.outlined,
            height: 36,
            onPressed: busy ? null : onSearchNow,
          ),
        );
      }
      if (onCancel != null) {
        actions.add(
          AppButton(
            key: Key('request-cancel-${request.id}'),
            label: '取消求片',
            variant: AppButtonVariant.plain,
            height: 36,
            onPressed: busy ? null : onCancel,
          ),
        );
      }
    }

    if (actions.isEmpty) {
      return Text(
        '求片完成',
        style: Theme.of(context).textTheme.labelMedium!
            .copyWith(color: Colors.green),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
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
    final ColorScheme palette = Theme.of(context).colorScheme;
    final index = stage.chainIndex;

    return Row(
      children: <Widget>[
        for (int i = 0; i < labels.length; i++) ...<Widget>[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                color: i <= index
                    ? palette.primary.withValues(alpha: 0.6)
                    : palette.outlineVariant,
              ),
            ),
          AppTag(
            label: labels[i],
            dense: true,
            color: i <= index ? palette.primary : palette.outline,
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
      child: AppTag(label: label, color: color, icon: Icon(icon)),
    );
  }
}
