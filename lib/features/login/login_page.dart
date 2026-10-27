import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/router/app_routes.dart';
import 'login_form.dart';

/// Dual-address login (contract §1.2, §1.4, §6).
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
    final theme = Theme.of(context);
    final error = _error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Media Player',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '连接你的 Emby 服务器',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    key: const Key('login-lan-url'),
                    controller: _lanUrl,
                    enabled: !_submitting,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '局域网地址',
                      hintText: 'http://192.168.1.10:8096',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
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
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('login-username'),
                    controller: _username,
                    enabled: !_submitting,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('login-password'),
                    controller: _password,
                    enabled: !_submitting,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            error,
                            key: const Key('login-error'),
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                          if (_details.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _details.join(' · '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('login-submit'),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '地址与凭据只保存在本机',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
