import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glass_controls.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';
import 'glass_tokens.dart';

/// Fixed geometry shared by pages that use the collapsing large title.
abstract final class GlassHeaderMetrics {
  static const double barHeight = 52;
  static const double expandedHeight = 110;
}

/// Scroll-driven page shell with a collapsing large title.
///
/// While the content is at the top the title is drawn large and left aligned,
/// like UIKit's large titles. As soon as it scrolls, a frosted navigation bar
/// fades in and the same title crossfades into a compact, centered capsule.
class GlassPage extends StatefulWidget {
  const GlassPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.onBack,
    this.scrollController,
    this.wallpaper = false,
    this.padding = EdgeInsets.zero,
    this.bottomOverlay,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final ScrollController? scrollController;
  final bool wallpaper;
  final EdgeInsetsGeometry padding;
  final Widget? bottomOverlay;

  @override
  State<GlassPage> createState() => _GlassPageState();
}

class _GlassPageState extends State<GlassPage> {
  ScrollController? _ownController;
  ScrollController get _controller => widget.scrollController ?? _ownController!;

  double _progress = 0;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController == null) {
      _ownController = ScrollController();
    }
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(GlassPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      _ownController?.dispose();
      _ownController = widget.scrollController == null ? ScrollController() : null;
      _controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _ownController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final double next = (_controller.offset / 34).clamp(0.0, 1.0);
    if ((next - _progress).abs() < 0.01) return;
    setState(() => _progress = next);
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    return Scaffold(
      backgroundColor: palette.groupedBackground,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (widget.wallpaper)
            const AmbientBackdrop()
          else
            ColoredBox(color: palette.groupedBackground),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
          if (widget.bottomOverlay != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(top: false, child: widget.bottomOverlay!),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _GlassNavigationBar(
              title: widget.title,
              progress: _progress,
              actions: widget.actions,
              onBack: widget.onBack,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassNavigationBar extends StatelessWidget {
  const _GlassNavigationBar({
    required this.title,
    required this.progress,
    required this.actions,
    required this.onBack,
  });

  final String title;
  final double progress;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    // Past this point the large title has faded out, so the capsule takes
    // over; keeping the swap at one threshold keeps exactly one title widget
    // in the tree.
    final bool compact = progress >= 0.6;

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: GlassHeaderMetrics.expandedHeight,
        child: Stack(
          children: <Widget>[
            // Frosted bar that fades in once the content scrolls under it.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: progress,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: Container(
                        height: GlassHeaderMetrics.barHeight,
                        decoration: BoxDecoration(
                          color: palette.container,
                          border: Border(
                            bottom: BorderSide(
                              color: palette.separator,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Large title. Only one of the two title widgets is mounted at a
            // time: they carry the same string, and two live copies would make
            // every `find.text(<page title>)` ambiguous for tests and screen
            // readers while the page is scrolled.
            if (!compact)
              Positioned(
                left: GlassSpacing.xl,
                right: GlassSpacing.xl,
                top: GlassHeaderMetrics.barHeight + GlassSpacing.xs,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1 - progress * 1.6).clamp(0.0, 1.0),
                    child: Transform.scale(
                      alignment: Alignment.centerLeft,
                      scale: 1 - 0.08 * progress,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GlassType.largeTitle.copyWith(
                          color: palette.label,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Compact, centered capsule title.
            if (compact)
              Positioned.fill(
                top: 0,
                bottom: GlassHeaderMetrics.expandedHeight -
                    GlassHeaderMetrics.barHeight,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: progress,
                    child: Center(
                      child: GlassSurface(
                        radius: GlassRadii.capsule,
                        blur: 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: GlassSpacing.lg,
                          vertical: GlassSpacing.xs,
                        ),
                        child: Text(
                          title,
                          maxLines: 1,
                          style: GlassType.headline.copyWith(
                            color: palette.label,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Leading back affordance.
            if (onBack != null)
              Positioned(
                left: GlassSpacing.sm,
                top: 5,
                child: GlassIconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '返回',
                  onPressed: onBack,
                ),
              ),
            // Trailing actions.
            if (actions.isNotEmpty)
              Positioned(
                right: GlassSpacing.sm,
                top: 5,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int index = 0; index < actions.length; index++) ...<Widget>[
                      if (index > 0) const SizedBox(width: GlassSpacing.sm),
                      actions[index],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Simple full-screen canvas for pages without scrolling content.
class GlassCanvas extends StatelessWidget {
  const GlassCanvas({
    super.key,
    required this.child,
    this.wallpaper = true,
    this.safeArea = true,
  });

  final Widget child;
  final bool wallpaper;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    final Widget content = safeArea ? SafeArea(child: child) : child;
    if (!wallpaper) {
      return ColoredBox(color: palette.groupedBackground, child: content);
    }
    return AmbientBackdrop(child: content);
  }
}

/// iOS inset-grouped section card.
class GlassSection extends StatelessWidget {
  const GlassSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.floating = false,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    final List<Widget> rows = <Widget>[];
    for (int index = 0; index < children.length; index++) {
      if (index > 0) {
        rows.add(const GlassHairline(indent: GlassSpacing.lg));
      }
      rows.add(children[index]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GlassSpacing.xl,
              GlassSpacing.xl,
              GlassSpacing.xl,
              GlassSpacing.sm,
            ),
            child: Text(
              header!,
              style: GlassType.footnote.copyWith(
                color: palette.secondaryLabel,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GlassSpacing.lg),
          child: floating
              ? GlassSurface(
                  radius: GlassRadii.cardLarge,
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(GlassRadii.cardLarge),
                    child: Column(children: rows),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(GlassRadii.cardLarge),
                  child: Material(
                    color: palette.elevatedBackground,
                    child: Column(children: rows),
                  ),
                ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GlassSpacing.xl,
              GlassSpacing.sm,
              GlassSpacing.xl,
              0,
            ),
            child: Text(
              footer!,
              style: GlassType.footnote.copyWith(
                color: palette.secondaryLabel,
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens a frosted alert-style dialog with the blurred barrier iOS uses.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String barrierLabel = 'dismiss',
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.16),
    transitionDuration: GlassMotion.base,
    pageBuilder: (BuildContext dialogContext, _, _) {
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const SizedBox.expand(),
            ),
          ),
          Center(child: builder(dialogContext)),
        ],
      );
    },
    transitionBuilder: (_, Animation<double> animation, _, Widget child) {
      final CurvedAnimation curved = CurvedAnimation(
        parent: animation,
        curve: GlassMotion.emphasized,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Frosted alert card used by the update prompt and the settings pickers.
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    this.title,
    this.message,
    required this.actions,
    this.content,
    this.maxWidth = 320,
  });

  final String? title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    return Padding(
      padding: const EdgeInsets.all(GlassSpacing.xxl),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GlassSurface(
          radius: GlassRadii.alert,
          blur: 30,
          padding: const EdgeInsets.fromLTRB(
            GlassSpacing.xl,
            GlassSpacing.xl,
            GlassSpacing.xl,
            GlassSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (title != null)
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: GlassType.headline.copyWith(color: palette.label),
                ),
              if (message != null) ...<Widget>[
                const SizedBox(height: GlassSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: GlassType.footnote.copyWith(
                    color: palette.secondaryLabel,
                  ),
                ),
              ],
              if (content != null) ...<Widget>[
                const SizedBox(height: GlassSpacing.lg),
                content!,
              ],
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(height: GlassSpacing.xl),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int index = 0; index < actions.length; index++) ...<Widget>[
                      if (index > 0) const SizedBox(height: GlassSpacing.sm),
                      actions[index],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
