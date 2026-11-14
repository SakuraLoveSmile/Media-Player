import 'package:flutter/material.dart';

import '../../data/moviepilot/progress/request_notification.dart';
import '../ui/app_controls.dart';
import '../ui/theme/app_tokens.dart';

/// In-app banner for a finished 求片.
///
/// Shown above the router subtree by the app shell, so it reaches every page —
/// including the player, where the user is most likely to be when a request
/// finishes. Tapping opens 我的求片; the banner auto-dismisses otherwise.
class RequestNotificationBanner extends StatelessWidget {
  const RequestNotificationBanner({
    super.key,
    required this.event,
    required this.onTap,
    required this.onDismiss,
  });

  final RequestNotification event;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppCard(
            radius: AppRadii.card,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.check_circle_outline, color: Colors.green, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        event.title,
                        key: const Key('request-banner-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: palette.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        event.body,
                        key: const Key('request-banner-body'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall!
                            .copyWith(color: palette.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _BannerAction(
                  key: const Key('request-banner-open'),
                  label: '查看',
                  color: palette.primary,
                  onPressed: onTap,
                ),
                _BannerAction(
                  key: const Key('request-banner-dismiss'),
                  icon: Icons.close,
                  color: palette.outline,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact text/icon button that does not need a Material ancestor of its own:
/// the banner is mounted above the router, where the nearest `Material` comes
/// from the app's theme and would otherwise tint the ink.
class _BannerAction extends StatelessWidget {
  const _BannerAction({
    super.key,
    this.label,
    this.icon,
    required this.color,
    required this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = icon != null
        ? Icon(icon, size: 18, color: color)
        : Text(
            label!,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: color, fontWeight: FontWeight.w600),
          );
    return Semantics(
      button: true,
      label: label ?? '关闭通知',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: child,
        ),
      ),
    );
  }
}
