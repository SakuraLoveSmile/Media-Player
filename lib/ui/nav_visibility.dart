import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the floating capsule navigation is currently on screen (S63).
///
/// Pages report scroll direction through [NavScrollReporter]; the capsule
/// slides out on a downward scroll and comes back on the first upward one.
class NavVisibility extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool visible) {
    if (state == visible) return;
    state = visible;
  }
}

final NotifierProvider<NavVisibility, bool> navVisibleProvider =
    NotifierProvider<NavVisibility, bool>(NavVisibility.new);

/// Watches a page's scroll notifications and keeps [navVisibleProvider] in
/// sync. Only the page's own (non-nested) scroll is considered, so a nested
/// horizontal strip never hides the bar.
class NavScrollReporter extends ConsumerStatefulWidget {
  const NavScrollReporter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NavScrollReporter> createState() => _NavScrollReporterState();
}

class _NavScrollReporterState extends ConsumerState<NavScrollReporter> {
  double _lastOffset = 0;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        // depth 0 is the page's own scrollable, not a nested horizontal list.
        if (notification.depth != 0) return false;
        if (notification is ScrollUpdateNotification &&
            notification.metrics.axis == Axis.vertical) {
          final double offset = notification.metrics.pixels;
          final double delta = offset - _lastOffset;
          _lastOffset = offset;
          final bool atTop = offset <= 8;
          if (atTop) {
            _set(true);
          } else if (delta > 6) {
            _set(false);
          } else if (delta < -6) {
            _set(true);
          }
        }
        return false;
      },
      child: widget.child,
    );
  }

  void _set(bool visible) => ref.read(navVisibleProvider.notifier).set(visible);
}
