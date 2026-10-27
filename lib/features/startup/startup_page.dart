import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/router/app_routes.dart';
import '../../shared/widgets/placeholder_scaffold.dart';

/// Session gate: restore the stored session, then route to library or login
/// (contract §10.5). Replaced by the real splash in F1.
class StartupPage extends ConsumerStatefulWidget {
  const StartupPage({super.key});

  @override
  ConsumerState<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends ConsumerState<StartupPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    if (_error != null) setState(() => _error = null);

    try {
      final services = await ref.read(bootstrapProvider.future);
      final session = await services.auth.restore();
      if (!mounted) return;
      context.go(session == null ? AppRoutes.login : AppRoutes.library);
    } on EmbyException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '启动失败，请稍后重试');
    }
  }

  String _messageFor(AppErrorCode code) {
    return switch (code) {
      AppErrorCode.tlsUntrusted => '服务器证书不受信任',
      AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
      _ => '启动失败，请稍后重试',
    };
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return PlaceholderScaffold(
      title: AppConfig.appName,
      body: error == null
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(error),
                const SizedBox(height: 12),
                FilledButton(onPressed: _boot, child: const Text('重试')),
              ],
            ),
    );
  }
}
