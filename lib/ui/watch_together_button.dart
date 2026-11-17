import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_routes.dart';

/// Shared navigation entry; room state and configuration live in the feature.
class WatchTogetherButton extends StatelessWidget {
  const WatchTogetherButton({
    super.key,
    this.itemId,
    this.sourceId,
    this.compact = false,
  });
  final String? itemId;
  final String? sourceId;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    void open() => context.push(
      AppRoutes.watchTogetherFor(itemId: itemId, sourceId: sourceId),
    );
    return compact
        ? IconButton(
            tooltip: '一起看',
            icon: const Icon(Icons.groups_outlined),
            onPressed: open,
          )
        : TextButton.icon(
            onPressed: open,
            icon: const Icon(Icons.groups_outlined),
            label: const Text('一起看'),
          );
  }
}
