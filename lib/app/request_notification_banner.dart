import 'package:flutter/material.dart';

import '../../data/moviepilot/progress/request_notification.dart';
import '../../ui/glass/glass_surface.dart';
import '../../ui/glass/glass_theme.dart';
import '../../ui/glass/glass_tokens.dart';

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
    final GlassPalette palette = context.glass;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        GlassSpacing.lg,
        GlassSpacing.lg,
        GlassSpacing.lg,
        0,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassSurface(
            radius: GlassRadii.card,
            padding: const EdgeInsets.fromLTRB(
              GlassSpacing.lg,
              GlassSpacing.md,
              GlassSpacing.sm,
              GlassSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.check_circle_outline, color: palette.green, size: 22),
                const SizedBox(width: GlassSpacing.md),
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
                        style: GlassType.subheadline.copyWith(
                          color: palette.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: GlassSpacing.xxs),
                      Text(
                        event.body,
                        key: const Key('request-banner-body'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GlassType.footnote.copyWith(
                          color: palette.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: GlassSpacing.sm),
                _BannerAction(
                  key: const Key('request-banner-open'),
                  label: '查看',
                  color: palette.tint,
                  onPressed: onTap,
                ),
                _BannerAction(
                  key: const Key('request-banner-dismiss'),
                  icon: Icons.close,
                  color: palette.tertiaryLabel,
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
            style: GlassType.footnote.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          );
    return Semantics(
      button: true,
      label: label ?? '关闭通知',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(GlassSpacing.sm),
          child: child,
        ),
      ),
    );
  }
}
