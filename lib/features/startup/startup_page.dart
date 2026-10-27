import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/app_routes.dart';
import '../../shared/widgets/placeholder_scaffold.dart';

/// Placeholder until B3-6 replaces it with the session gate.
class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderScaffold(
      title: AppConfig.appName,
      body: FilledButton(
        onPressed: () => context.go(AppRoutes.login),
        child: const Text('继续'),
      ),
    );
  }
}
