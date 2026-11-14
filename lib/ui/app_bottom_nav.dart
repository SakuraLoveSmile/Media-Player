import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/appearance_settings.dart';
import '../core/router/app_routes.dart';
import 'nav_visibility.dart';
import 'theme/app_tokens.dart';

/// The three peer destinations of the bottom navigation bar (P1).
enum AppNavDestination { home, search, favorites }

/// The floating capsule navigation (S28), mirroring Yamby's three-icon pill:
/// 首页 / 搜索 / 收藏, no labels, the current destination inside a filled
/// circle. Lives in `lib/ui/` so any feature can mount it as an [AppPage]
/// `bottomNavigationBar` without importing another feature.
class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({super.key, required this.current});

  final AppNavDestination current;

  static const Map<
    AppNavDestination,
    ({IconData icon, String label, String route})
  >
  _destinations =
      <AppNavDestination, ({IconData icon, String label, String route})>{
        AppNavDestination.home: (
          icon: Icons.home_outlined,
          label: '首页',
          route: AppRoutes.home,
        ),
        AppNavDestination.search: (
          icon: Icons.search,
          label: '搜索',
          route: AppRoutes.search,
        ),
        AppNavDestination.favorites: (
          icon: Icons.star_border_rounded,
          label: '收藏',
          route: AppRoutes.favorites,
        ),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // S62: Yamby's 外观 page switches the capsule off for a standard bar.
    final bool floating = ref
        .watch(appearanceSettingsControllerProvider)
        .maybeWhen(
          data: (AppearanceSettings settings) => settings.floatingNav,
          orElse: () => true,
        );
    if (!floating) return _standardBar(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const List<AppNavDestination> values = AppNavDestination.values;
    // S63: 自动隐藏悬浮导航栏 — slide away while scrolling down.
    final bool autoHide = ref
        .watch(appearanceSettingsControllerProvider)
        .maybeWhen(
          data: (AppearanceSettings settings) => settings.autoHideNav,
          orElse: () => true,
        );
    final bool visible = !autoHide || ref.watch(navVisibleProvider);
    return AnimatedSlide(
      key: const Key('nav-capsule-slide'),
      offset: visible ? Offset.zero : const Offset(0, 1.6),
      duration: AppMotion.base,
      curve: AppMotion.emphasized,
      child: IgnorePointer(
        ignoring: !visible,
        child: _capsule(context, scheme, values),
      ),
    );
  }

  Widget _capsule(
    BuildContext context,
    ColorScheme scheme,
    List<AppNavDestination> values,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Center(
        heightFactor: 1,
        child: Material(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
          elevation: 6,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(AppRadii.capsule),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final AppNavDestination destination in values)
                  _NavPill(
                    key: Key('nav-${destination.name}'),
                    icon: _destinations[destination]!.icon,
                    label: _destinations[destination]!.label,
                    selected: destination == current,
                    onTap: () {
                      if (destination == current) return;
                      context.push(_destinations[destination]!.route);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Material bottom bar with the same three destinations and labels.
  Widget _standardBar(BuildContext context) {
    return NavigationBar(
      key: const Key('nav-standard-bar'),
      selectedIndex: AppNavDestination.values.indexOf(current),
      onDestinationSelected: (int index) {
        final AppNavDestination destination = AppNavDestination.values[index];
        if (destination == current) return;
        context.push(_destinations[destination]!.route);
      },
      destinations: <Widget>[
        for (final AppNavDestination destination in AppNavDestination.values)
          NavigationDestination(
            key: Key('nav-standard-${destination.name}'),
            icon: Icon(_destinations[destination]!.icon),
            label: _destinations[destination]!.label,
          ),
      ],
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 52,
          height: 44,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.85)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 23,
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
