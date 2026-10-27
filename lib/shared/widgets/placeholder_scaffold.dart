import 'package:flutter/material.dart';

/// Temporary shell used by the four placeholder routes.
///
/// Replaced by F1/F2/F3 screens; the app bar keeps the routes distinguishable
/// in widget tests and on a real device before the real UI exists.
class PlaceholderScaffold extends StatelessWidget {
  const PlaceholderScaffold({super.key, required this.title, this.body});

  final String title;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: body ?? const SizedBox.shrink()),
    );
  }
}
