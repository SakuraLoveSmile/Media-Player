import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

/// Button appearances mapped onto the Material button family.
enum AppButtonVariant {
  /// [FilledButton] — the single most important action.
  prominent,

  /// [FilledButton.tonal] — secondary actions.
  tinted,

  /// [OutlinedButton] — actions that sit on top of content.
  outlined,

  /// [TextButton] — dialogs and inline actions.
  plain,
}

/// A Material button with optional leading/trailing icons and a loading state.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.prominent,
    this.leading,
    this.trailing,
    this.loading = false,
    this.expand = false,
    this.height = AppMetrics.controlHeight,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final Widget? leading;
  final Widget? trailing;
  final bool loading;
  final bool expand;
  final double height;
  final String? semanticLabel;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color foreground = switch (variant) {
      AppButtonVariant.prominent => scheme.onPrimary,
      AppButtonVariant.tinted => scheme.onSecondaryContainer,
      AppButtonVariant.outlined => scheme.primary,
      AppButtonVariant.plain => scheme.primary,
    };

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          )
        else ...<Widget>[
          if (leading != null) ...<Widget>[
            IconTheme(
              data: IconThemeData(color: foreground, size: 18),
              child: leading!,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            IconTheme(
              data: IconThemeData(color: foreground, size: 18),
              child: trailing!,
            ),
          ],
        ],
      ],
    );

    final ButtonStyle style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(Size(0, height)),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      ),
    );

    final VoidCallback? handler = _enabled ? onPressed : null;
    Widget button = switch (variant) {
      AppButtonVariant.prominent => FilledButton(
        onPressed: handler,
        style: FilledButton.styleFrom().merge(style),
        child: content,
      ),
      AppButtonVariant.tinted => FilledButton.tonal(
        onPressed: handler,
        style: FilledButton.styleFrom().merge(style),
        child: content,
      ),
      AppButtonVariant.outlined => OutlinedButton(
        onPressed: handler,
        style: OutlinedButton.styleFrom().merge(style),
        child: content,
      ),
      AppButtonVariant.plain => TextButton(
        onPressed: handler,
        style: TextButton.styleFrom().merge(style),
        child: content,
      ),
    };

    if (semanticLabel != null) {
      button = Semantics(label: semanticLabel, button: true, child: button);
    }
    if (expand) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// A Material icon button used for toolbars and overlays.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 40,
    this.iconSize = 22,
    this.brightness,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    Widget button = IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: iconSize,
      icon: icon,
      style: IconButton.styleFrom(
        minimumSize: Size(size, size),
        fixedSize: Size(size, size),
      ),
    );
    if (brightness != null) {
      button = Theme(data: buildAppTheme(brightness!), child: button);
    }
    return button;
  }
}

/// A small tonal badge for status labels ("已看", "直连播放").
class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color? color;
  final Widget? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(dense ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            IconTheme(
              data: IconThemeData(size: dense ? 10 : 12, color: accent),
              child: icon!,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: (dense ? text.labelSmall : text.labelMedium)!.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A Material card container for grouped content.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = AppRadii.card,
    this.elevation = 1,
    this.margin,
    this.color,
    this.floating = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double elevation;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin ?? EdgeInsets.zero,
      elevation: floating ? 3 : elevation,
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
