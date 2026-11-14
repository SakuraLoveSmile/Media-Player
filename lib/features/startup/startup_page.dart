import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/router/app_routes.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';

/// Session gate: restore the stored session, then route to library or login
/// (contract §10.5).
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
      context.go(session == null ? AppRoutes.login : AppRoutes.home);
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
    final String? error = _error;
    final ColorScheme palette = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: palette.surface,
      body: AppCanvas(
        child: Center(
          child: AppCard(
            radius: 34,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxxl,
              vertical: AppSpacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        palette.primary.withValues(alpha: 0.95),
                        palette.secondary.withValues(alpha: 0.9),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  AppConfig.appName,
                  style: Theme.of(context).textTheme.titleLarge!
                      .copyWith(color: palette.onSurface),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (error == null)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else ...<Widget>[
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: '重试',
                    variant: AppButtonVariant.tinted,
                    onPressed: _boot,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
