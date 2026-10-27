import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_scaffold.dart';

/// Placeholder until F1 wires AuthRepository.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScaffold(
      title: '登录',
      body: Text('登录页占位'),
    );
  }
}
