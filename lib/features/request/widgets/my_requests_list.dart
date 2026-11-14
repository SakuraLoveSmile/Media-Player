import 'package:flutter/material.dart';

import '../../../data/moviepilot/models/media_request.dart';
import '../../../ui/theme/app_tokens.dart';
import 'request_progress_card.dart';

/// The "我的求片" list (求片 plan S13).
///
/// Newest first, with the finished items kept in place: the page is a record of
/// what the user asked for, not only a queue.
class MyRequestsList extends StatelessWidget {
  const MyRequestsList({
    super.key,
    required this.requests,
    this.onSearchNow,
    this.onCancel,
    this.onPlay,
    this.busyIds = const <String>{},
  });

  final List<MediaRequest> requests;
  final void Function(MediaRequest request)? onSearchNow;
  final void Function(MediaRequest request)? onCancel;
  final void Function(MediaRequest request)? onPlay;
  final Set<String> busyIds;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    if (requests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Text(
          '还没有求片记录。搜索片名，点“求片”即可开始。',
          key: const Key('requests-empty'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: palette.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final request in requests)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: RequestProgressCard(
              request: request,
              busy: busyIds.contains(request.id),
              onSearchNow: onSearchNow == null
                  ? null
                  : () => onSearchNow!(request),
              onCancel: onCancel == null ? null : () => onCancel!(request),
              onPlay: onPlay == null ? null : () => onPlay!(request),
            ),
          ),
      ],
    );
  }
}

/// Section heading used inside the 求片 page body.
class RequestSectionHeader extends StatelessWidget {
  const RequestSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: palette.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
