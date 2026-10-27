import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_scaffold.dart';

/// Placeholder until F3 wires PlaybackEngine.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return PlaceholderScaffold(
      title: '播放',
      body: Text('条目 $itemId'),
    );
  }
}
