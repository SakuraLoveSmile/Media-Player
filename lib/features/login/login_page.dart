import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/router/app_routes.dart';
import '../../ui/glass/glass_controls.dart';
import '../../ui/glass/glass_surface.dart';
import '../../ui/glass/glass_theme.dart';
import '../../ui/glass/glass_tokens.dart';
import 'login_form.dart';

/// Dual-address login (contract §1.2, §1.4, §6), presented as a floating glass
/// panel over the ambient wallpaper.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _lanUrl = TextEditingController();
  final TextEditingController _wanUrl = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _submitting = false;
  String? _error;
  List<String> _details = const <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_prefillAddresses());
  }

  @override
  void dispose() {
    _lanUrl.dispose();
    _wanUrl.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _prefillAddresses() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      final profile = await services.auth.lastProfile();
      if (!mounted || profile == null) return;
      setState(() {
        if (_lanUrl.text.isEmpty && profile.lanUrl != null) {
          _lanUrl.text = profile.lanUrl!;
        }
        if (_wanUrl.text.isEmpty && profile.wanUrl != null) {
          _wanUrl.text = profile.wanUrl!;
        }
      });
    } catch (_) {
      // Prefill is a convenience; a failure must not block manual entry.
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final result = validateLoginForm(
      lanUrl: _lanUrl.text,
      wanUrl: _wanUrl.text,
      username: _username.text,
      password: _password.text,
    );

    switch (result) {
      case LoginFormInvalid(:final message):
        setState(() {
          _error = message;
          _details = const <String>[];
        });
        return;
      case LoginFormValid(:final profile, :final username, :final password):
        setState(() {
          _submitting = true;
          _error = null;
          _details = const <String>[];
        });
        try {
          final services = await ref.read(bootstrapProvider.future);
          await services.auth.login(
            username: username,
            password: password,
            profile: profile,
          );
          if (!mounted) return;
          context.go(AppRoutes.library);
        } on EmbyException catch (error) {
          if (!mounted) return;
          setState(() {
            _error = loginErrorMessage(error.code);
            _details = error.failures
                .map((failure) =>
                    '${failure.kind.name}: ${_endpointReason(failure.code)}')
                .toList(growable: false);
          });
        } catch (_) {
          if (!mounted) return;
          setState(() => _error = '登录失败，请稍后重试');
        } finally {
          if (mounted) setState(() => _submitting = false);
        }
    }
  }

  static String _endpointReason(Object code) {
    final name = code.toString().split('.').last;
    return switch (name) {
      'networkUnreachable' => '无法连接',
      'tlsUntrusted' => '证书不可信',
      'serverMismatch' => '不是同一台服务器',
      'serverError' => '响应异常',
      _ => name,
    };
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    final String? error = _error;

    return Scaffold(
      backgroundColor: palette.groupedBackground,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const AmbientBackdrop(),
          SafeArea(
            child: Stack(
              children: <Widget>[
                Positioned(
                  top: GlassSpacing.xs,
                  right: GlassSpacing.lg,
                  child: GlassIconButton(
                    key: const Key('login-settings'),
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push(AppRoutes.settings),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GlassSpacing.xxl,
                      vertical: GlassSpacing.xxxl,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: GlassSurface(
                        radius: 34,
                        blur: 32,
                        padding: const EdgeInsets.fromLTRB(
                          GlassSpacing.xxl,
                          GlassSpacing.xxxl,
                          GlassSpacing.xxl,
                          GlassSpacing.xxl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _Header(palette: palette),
                            const SizedBox(height: GlassSpacing.xxl),
                            FeedbackCaptureMask(
                              child: TextField(
                                key: const Key('login-lan-url'),
                                controller: _lanUrl,
                                enabled: !_submitting,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '局域网地址',
                                  hintText: 'http://192.168.1.10:8096',
                                ),
                              ),
                            ),
                            const SizedBox(height: GlassSpacing.md),
                            FeedbackCaptureMask(
                              child: TextField(
                                key: const Key('login-wan-url'),
                                controller: _wanUrl,
                                enabled: !_submitting,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '公网地址（可选）',
                                  hintText: 'https://emby.example.com',
                                  helperText: '留空则只使用局域网',
                                ),
                              ),
                            ),
                            const SizedBox(height: GlassSpacing.lg),
                            FeedbackCaptureMask(
                              child: TextField(
                                key: const Key('login-username'),
                                controller: _username,
                                enabled: !_submitting,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '用户名',
                                ),
                              ),
                            ),
                            const SizedBox(height: GlassSpacing.md),
                            TextField(
                              key: const Key('login-password'),
                              controller: _password,
                              enabled: !_submitting,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: '密码',
                              ),
                            ),
                            if (error != null) ...<Widget>[
                              const SizedBox(height: GlassSpacing.lg),
                              _ErrorPanel(
                                message: error,
                                details: _details,
                                palette: palette,
                              ),
                            ],
                            const SizedBox(height: GlassSpacing.xxl),
                            GlassButton(
                              key: const Key('login-submit'),
                              label: '登录',
                              expand: true,
                              loading: _submitting,
                              onPressed: _submitting ? null : _submit,
                            ),
                            const SizedBox(height: GlassSpacing.md),
                            Text(
                              '地址与凭据只保存在本机',
                              textAlign: TextAlign.center,
                              style: GlassType.caption1.copyWith(
                                color: palette.secondaryLabel,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.palette});

  final GlassPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                palette.tint.withValues(alpha: 0.95),
                palette.indigo.withValues(alpha: 0.9),
              ],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.tint.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
        const SizedBox(height: GlassSpacing.lg),
        Text(
          'Media Player',
          textAlign: TextAlign.center,
          style: GlassType.title1.copyWith(
            color: palette.label,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: GlassSpacing.xs),
        Text(
          '连接你的 Emby 服务器',
          textAlign: TextAlign.center,
          style: GlassType.footnote.copyWith(color: palette.secondaryLabel),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.details,
    required this.palette,
  });

  final String message;
  final List<String> details;
  final GlassPalette palette;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: GlassRadii.control,
      blur: 16,
      tintColor: palette.red,
      tintOpacity: 0.16,
      shadow: false,
      padding: const EdgeInsets.all(GlassSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                color: palette.red,
                size: 16,
              ),
              const SizedBox(width: GlassSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  key: const Key('login-error'),
                  style: GlassType.footnote.copyWith(
                    color: palette.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: GlassSpacing.xs,
                left: 24,
              ),
              child: Text(
                details.join(' · '),
                style: GlassType.caption1.copyWith(
                  color: palette.red.withValues(alpha: 0.8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
