import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/router/app_routes.dart';
import '../../data/auth/server_session_service.dart';
import '../../data/models/server_entry.dart';
import '../../data/models/server_profile.dart';
import '../../ui/app_controls.dart';
import '../../ui/theme/app_tokens.dart';
import 'login_form.dart';

/// Dual-address login (contract §1.2, §1.4, §6), presented as a Material card.
///
/// S20: the form can target a saved server ([serverId]) or create a brand-new
/// one ([addMode]); on success the entry is written to the server directory and
/// the session is stored under that server's id. With neither, it behaves as the
/// original single-server login against the active (`default`) server.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.serverId, this.addMode = false});

  /// Existing saved server to log in to; null for the active/default server.
  final String? serverId;

  /// When true, a new directory entry is created on success.
  final bool addMode;

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

  /// Server id this login targets; resolved from the route/directory on init.
  String _targetServerId = defaultServerId;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveTargetAndPrefill());
  }

  @override
  void dispose() {
    _lanUrl.dispose();
    _wanUrl.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _resolveTargetAndPrefill() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      final directory = services.servers;
      final String target;
      if (widget.addMode) {
        target = const Uuid().v4();
      } else if (widget.serverId != null && widget.serverId!.isNotEmpty) {
        target = widget.serverId!;
      } else {
        target = await directory?.activeId() ?? defaultServerId;
      }
      if (!mounted) return;
      _targetServerId = target;

      final ServerEntry? entry = await directory?.find(target);
      String? lan = entry?.lanUrl;
      String? wan = entry?.wanUrl;
      if (entry == null) {
        // No saved entry (default login or a fresh add): prefill the last used
        // addresses, exactly as the single-server flow did.
        final profile = await services.auth.lastProfile();
        lan ??= profile?.lanUrl;
        wan ??= profile?.wanUrl;
      }
      if (!mounted) return;
      setState(() {
        if (_lanUrl.text.isEmpty && lan != null) _lanUrl.text = lan;
        if (_wanUrl.text.isEmpty && wan != null) _wanUrl.text = wan;
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
          final auth = services.auth;
          final target = _targetServerId;
          // Point the repository at the target server so the session is stored
          // under its id (no-op for fakes that only support a single session).
          // `AuthService` is an interface class, so cast rather than promote.
          if (auth is ServerSessionService) {
            (auth as ServerSessionService).useServer(target);
          }
          await auth.login(
            username: username,
            password: password,
            profile: profile,
          );
          // Save the (non-secret) entry into the directory and make it active.
          final directory = services.servers;
          if (directory != null) {
            final stored = await auth.lastProfile();
            await directory.upsert(
              ServerEntry(
                id: target,
                name: _entryName(stored, profile),
                lanUrl: stored?.lanUrl ?? profile.lanUrl,
                wanUrl: stored?.wanUrl ?? profile.wanUrl,
              ),
            );
            await directory.setActive(target);
          }
          if (!mounted) return;
          context.go(AppRoutes.home);
        } on EmbyException catch (error) {
          if (!mounted) return;
          setState(() {
            _error = loginErrorMessage(error.code);
            _details = error.failures
                .map(
                  (failure) =>
                      '${failure.kind.name}: ${_endpointReason(failure.code)}',
                )
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

  /// A friendly default name for a newly saved entry: the stored server name if
  /// present, else the address host, else a generic label. Users can rename it
  /// later; the directory never stores credentials.
  static String _entryName(ServerProfile? stored, ServerProfile form) {
    final name = stored?.name ?? '';
    if (name.isNotEmpty) return name;
    final url = stored?.lanUrl ?? stored?.wanUrl ?? form.lanUrl ?? form.wanUrl;
    if (url != null) {
      final host = Uri.tryParse(url)?.host;
      if (host != null && host.isNotEmpty) return host;
    }
    return '服务器';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final String? error = _error;

    return Scaffold(
      backgroundColor: palette.surface,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          SafeArea(
            child: Stack(
              children: <Widget>[
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.lg,
                  child: AppIconButton(
                    key: const Key('login-settings'),
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push(AppRoutes.settings),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                      vertical: AppSpacing.xxxl,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: AppCard(
                        radius: 34,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xxl,
                          AppSpacing.xxxl,
                          AppSpacing.xxl,
                          AppSpacing.xxl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _Header(palette: palette),
                            const SizedBox(height: AppSpacing.xxl),
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
                            const SizedBox(height: AppSpacing.md),
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
                            const SizedBox(height: AppSpacing.lg),
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
                            const SizedBox(height: AppSpacing.md),
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
                              const SizedBox(height: AppSpacing.lg),
                              _ErrorPanel(
                                message: error,
                                details: _details,
                                palette: palette,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xxl),
                            AppButton(
                              key: const Key('login-submit'),
                              label: '登录',
                              expand: true,
                              loading: _submitting,
                              onPressed: _submitting ? null : _submit,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              '地址与凭据只保存在本机',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelMedium!
                                  .copyWith(color: palette.onSurfaceVariant),
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

  final ColorScheme palette;

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
                palette.primary.withValues(alpha: 0.95),
                palette.secondary.withValues(alpha: 0.9),
              ],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.primary.withValues(alpha: 0.35),
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
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Media Player',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium!
              .copyWith(color: palette.onSurface, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '连接你的 Emby 服务器',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: palette.onSurfaceVariant),
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
  final ColorScheme palette;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: AppRadii.control,
      elevation: 0,
      color: palette.error.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, color: palette.error, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  key: const Key('login-error'),
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: palette.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs, left: 24),
              child: Text(
                details.join(' · '),
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: palette.error.withValues(alpha: 0.8)),
              ),
            ),
        ],
      ),
    );
  }
}
