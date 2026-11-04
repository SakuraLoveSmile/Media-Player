import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'glass_theme.dart';
import 'glass_tokens.dart';

/// Button appearances used across the app.
enum GlassButtonVariant {
  /// Filled with the system tint, for the single most important action.
  prominent,

  /// Tinted translucent fill, for secondary actions.
  tinted,

  /// Frosted glass capsule, for actions that sit on top of content.
  glass,

  /// Text-only, for dialogs and inline actions.
  plain,
}

/// Press animation shared by the glass controls: a small scale down with a
/// quick spring back.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.enabled});

  final Widget child;
  final bool enabled;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: GlassMotion.fast,
        curve: GlassMotion.press,
        child: widget.child,
      ),
    );
  }
}

/// Capsule button following the iOS 26 control geometry.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = GlassButtonVariant.prominent,
    this.leading,
    this.trailing,
    this.loading = false,
    this.expand = false,
    this.height = 50,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final GlassButtonVariant variant;
  final Widget? leading;
  final Widget? trailing;
  final bool loading;
  final bool expand;
  final double height;
  final String? semanticLabel;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    final Color tint = palette.tint;

    final (Color foreground, Color background) = switch (variant) {
      GlassButtonVariant.prominent => (Colors.white, tint),
      GlassButtonVariant.tinted => (tint, tint.withValues(alpha: 0.16)),
      GlassButtonVariant.glass => (palette.label, Colors.transparent),
      GlassButtonVariant.plain => (tint, Colors.transparent),
    };

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (leading != null) ...<Widget>[
          IconTheme(
            data: IconThemeData(color: foreground, size: 19),
            child: leading!,
          ),
          const SizedBox(width: GlassSpacing.sm),
        ],
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          )
        else
          Text(
            label,
            style: GlassType.body.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              fontSize: 16.5,
            ),
          ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: GlassSpacing.sm),
          IconTheme(
            data: IconThemeData(color: foreground, size: 19),
            child: trailing!,
          ),
        ],
      ],
    );

    Widget button = Opacity(
      opacity: _enabled ? 1 : 0.4,
      child: _PressScale(
        enabled: _enabled,
        child: SizedBox(
          height: height,
          child: variant == GlassButtonVariant.glass
              ? GlassSurface(
                  radius: GlassRadii.capsule,
                  padding: const EdgeInsets.symmetric(
                    horizontal: GlassSpacing.xl,
                  ),
                  child: Center(widthFactor: 1, child: content),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(GlassRadii.capsule),
                    border: variant == GlassButtonVariant.plain
                        ? null
                        : Border.all(
                            color: variant == GlassButtonVariant.prominent
                                ? Colors.white.withValues(alpha: 0.22)
                                : tint.withValues(alpha: 0.1),
                          ),
                    gradient: variant == GlassButtonVariant.prominent
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color.lerp(tint, Colors.white, 0.16)!,
                              tint,
                            ],
                          )
                        : null,
                    boxShadow: variant == GlassButtonVariant.prominent
                        ? <BoxShadow>[
                            BoxShadow(
                              color: tint.withValues(alpha: 0.28),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GlassSpacing.xl,
                    ),
                    child: Center(widthFactor: 1, child: content),
                  ),
                ),
        ),
      ),
    );

    if (expand) {
      button = SizedBox(width: double.infinity, child: button);
    } else {
      button = IntrinsicWidth(child: button);
    }

    return Semantics(
      button: true,
      enabled: _enabled,
      label: semanticLabel ?? label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _enabled ? onPressed : null,
        child: button,
      ),
    );
  }
}

/// Circular frosted glass icon button, used for toolbars and overlays.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 42,
    this.iconSize = 19,
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
    final GlassPalette palette =
        brightness == null ? context.glass : GlassPalette.of(brightness!);
    final bool enabled = onPressed != null;
    final Widget button = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: _PressScale(
        enabled: enabled,
        child: GlassSurface(
          radius: GlassRadii.capsule,
          brightness: brightness,
          blur: 18,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: size,
            height: size,
            child: IconTheme(
              data: IconThemeData(color: palette.label, size: iconSize),
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );

    final Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onPressed : null,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: button,
      ),
    );

    if (tooltip == null) return result;
    return Tooltip(message: tooltip!, child: result);
  }
}

/// Small frosted capsule used for status labels ("已看", "直连播放").
class GlassTag extends StatelessWidget {
  const GlassTag({
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
    final GlassPalette palette = context.glass;
    final Color accent = color ?? palette.label;
    return GlassSurface(
      radius: GlassRadii.capsule,
      blur: 14,
      tintColor: accent,
      tintOpacity: 0.2,
      border: false,
      shadow: false,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? GlassSpacing.sm : GlassSpacing.md,
        vertical: dense ? 2 : GlassSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            IconTheme(
              data: IconThemeData(
                size: dense ? 10 : 12,
                color: accent,
              ),
              child: icon!,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: (dense ? GlassType.caption2 : GlassType.caption1).copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grouped inset card: the standard container for settings sections, with an
/// optional glass material when it floats above content.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = GlassRadii.cardLarge,
    this.floating = false,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool floating;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    if (floating) {
      return GlassSurface(
        radius: radius,
        padding: padding,
        margin: margin,
        child: child,
      );
    }
    final GlassPalette palette = context.glass;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: palette.elevatedBackground,
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}
