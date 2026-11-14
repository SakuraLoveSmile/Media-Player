import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/appearance_settings.dart';
import 'theme/app_tokens.dart';

/// Fades and slides a grid/list cell in on its first appearance (S67), the
/// effect behind 外观 → 启用列表动画. Cells beyond [maxIndex] render直接, so a
/// long page never animates everything at once.
class ListEntrance extends ConsumerStatefulWidget {
  const ListEntrance({
    super.key,
    required this.index,
    required this.child,
    this.maxIndex = 12,
  });

  final int index;
  final Widget child;
  final int maxIndex;

  @override
  ConsumerState<ListEntrance> createState() => _ListEntranceState();
}

class _ListEntranceState extends ConsumerState<ListEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = ref
        .watch(appearanceSettingsControllerProvider)
        .maybeWhen(
          data: (AppearanceSettings settings) => settings.listAnimation,
          orElse: () => true,
        );
    if (!enabled || widget.index >= widget.maxIndex) return widget.child;
    // Stagger the first cells so the grid ripples in instead of popping.
    final double delay = (widget.index % 6) * 0.08;
    final CurvedAnimation curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.clamp(0.0, 0.6),
        (delay + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (BuildContext context, Widget? child) {
        final double t = curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
