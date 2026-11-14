import 'package:flutter/material.dart';

import 'app_controls.dart';
import 'nav_visibility.dart';
import 'theme/app_tokens.dart';

/// A Material page shell: [Scaffold] with an [AppBar] and an optional bottom
/// navigation bar. Replaces the iOS-style collapsing large-title shell.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.onBack,
    this.padding = EdgeInsets.zero,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final EdgeInsetsGeometry padding;
  final Widget? bottomNavigationBar;

  /// S55: Yamby's servers page puts 添加 in a floating button.
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The bottom navigation is a floating capsule (S28); let content scroll
      // underneath instead of reserving an opaque band.
      extendBody: bottomNavigationBar != null,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
        leading: onBack == null
            ? null
            : IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
        automaticallyImplyLeading: onBack != null,
      ),
      // S63: pages report their scroll direction so the capsule nav can hide.
      body: NavScrollReporter(
        child: SafeArea(
          top: false,
          child: Padding(padding: padding, child: child),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// A full-screen Material canvas for pages without an app bar.
class AppCanvas extends StatelessWidget {
  const AppCanvas({super.key, required this.child, this.safeArea = true});

  final Widget child;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: safeArea ? SafeArea(child: child) : child);
  }
}

/// A Material grouped section: an optional header, a card of rows separated by
/// dividers and an optional footer.
class AppSection extends StatelessWidget {
  const AppSection({
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final List<Widget> rows = <Widget>[];
    for (int index = 0; index < children.length; index++) {
      if (index > 0) {
        rows.add(const Divider(height: 1, indent: AppSpacing.lg));
      }
      rows.add(children[index]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              header!,
              style: text.titleSmall!.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AppCard(
            floating: floating,
            child: Column(children: rows),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              footer!,
              style: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
