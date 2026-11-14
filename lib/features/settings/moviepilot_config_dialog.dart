import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/moviepilot_providers.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/moviepilot_exception.dart';
import '../../core/network/url_normalizer.dart';
import '../../data/moviepilot/models/moviepilot_config.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_dialog.dart';
import '../../ui/theme/app_tokens.dart';

/// MoviePilot sign-in form (求片 plan S10, account login in S16).
///
/// Saves through [moviePilotSettingsProvider], which trades the password for a
/// token and verifies it before persisting. The password never leaves this
/// widget: the dialog holds it in a controller, sends it once, and the store
/// keeps only the token. Neither the token nor the password is ever logged or
/// rendered.
class MoviePilotConfigDialog extends ConsumerStatefulWidget {
  const MoviePilotConfigDialog({super.key, this.initial});

  /// Existing connection to prefill; null when nothing is stored.
  final MoviePilotConfig? initial;

  @override
  ConsumerState<MoviePilotConfigDialog> createState() =>
      _MoviePilotConfigDialogState();
}

class _MoviePilotConfigDialogState
    extends ConsumerState<MoviePilotConfigDialog> {
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _otp;
  bool _saving = false;
  bool _obscure = true;
  bool _mfaRequired = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initial?.baseUrl ?? '');
    _username = TextEditingController(text: widget.initial?.username ?? '');
    _password = TextEditingController();
    _otp = TextEditingController();
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;

    // Keep a Material ancestor for routes that present this widget directly.
    return Material(
      type: MaterialType.transparency,
      child: AppDialog(
        title: 'MoviePilot 登录',
        message: '使用 MoviePilot 账号登录，用于搜索片源和跟踪求片进度。密码只用于换取登录令牌，不会保存。',
        maxWidth: 380,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FeedbackCaptureMask(
              child: TextField(
                key: const Key('moviepilot-url'),
                controller: _url,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '地址',
                  hintText: 'http://192.168.1.10:3002',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FeedbackCaptureMask(
              child: TextField(
                key: const Key('moviepilot-username'),
                controller: _username,
                enabled: !_saving,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  hintText: 'MoviePilot 登录用户名',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FeedbackCaptureMask(
              child: TextField(
                key: const Key('moviepilot-password'),
                controller: _password,
                enabled: !_saving,
                autocorrect: false,
                obscureText: _obscure,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_save()),
                decoration: InputDecoration(
                  labelText: '密码',
                  helperText: '仅用于换取登录令牌，不会保存',
                  suffixIcon: IconButton(
                    key: const Key('moviepilot-password-visibility'),
                    tooltip: _obscure ? '显示' : '隐藏',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),
            if (_mfaRequired) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FeedbackCaptureMask(
                child: TextField(
                  key: const Key('moviepilot-otp'),
                  controller: _otp,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_save()),
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    helperText: '该账号已开启二次验证，填写 6 位动态码',
                  ),
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                key: const Key('moviepilot-error'),
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: palette.error),
              ),
            ],
            if (_notice != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                _notice!,
                key: const Key('moviepilot-notice'),
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: Colors.green),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          AppButton(
            key: const Key('moviepilot-save'),
            label: _mfaRequired ? '验证并登录' : '登录并保存',
            loading: _saving,
            onPressed: _saving ? null : () => unawaited(_save()),
          ),
          AppButton(
            key: const Key('moviepilot-cancel'),
            label: '取消',
            variant: AppButtonVariant.plain,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          if (widget.initial != null)
            AppButton(
              key: const Key('moviepilot-clear'),
              label: '清除连接',
              variant: AppButtonVariant.plain,
              onPressed: _saving ? null : () => unawaited(_clear()),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final baseUrl = UrlNormalizer.normalize(_url.text);
    final username = _username.text.trim();
    final password = _password.text;
    final otp = _otp.text.trim();

    if (baseUrl == null) {
      setState(() {
        _error = '地址无效，请填写 http:// 或 https:// 开头的地址';
        _notice = null;
      });
      return;
    }
    if (username.isEmpty) {
      setState(() {
        _error = '用户名不能为空';
        _notice = null;
      });
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _error = '密码不能为空';
        _notice = null;
      });
      return;
    }
    if (_mfaRequired && otp.isEmpty) {
      setState(() {
        _error = '请输入二次验证码';
        _notice = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });

    try {
      final saved = await ref
          .read(moviePilotSettingsProvider.notifier)
          .login(
            baseUrl: baseUrl,
            username: username,
            password: password,
            otp: otp.isEmpty ? null : otp,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = '登录成功：${saved.username} @ ${saved.baseUrl}';
      });
      // The saved state already updates the settings page; close on success so
      // the user is not left in a dialog that has done its job.
      Navigator.of(context).pop(saved);
    } on MoviePilotException catch (error) {
      if (!mounted) return;
      if (error.code == AppErrorCode.unauthorized && error.mfaRequired) {
        // The password was accepted; the account just needs its one-time code.
        setState(() {
          _saving = false;
          _mfaRequired = true;
          _error = null;
          _notice = '该账号已开启二次验证，请输入验证码后重试。';
        });
        return;
      }
      setState(() {
        _saving = false;
        _error = _describe(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '登录失败，请检查地址、用户名与密码';
      });
    }
  }

  Future<void> _clear() async {
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    await ref.read(moviePilotSettingsProvider.notifier).clear();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _notice = '已清除连接';
    });
    Navigator.of(context).pop();
  }

  static String _describe(AppErrorCode code) {
    return switch (code) {
      AppErrorCode.unauthorized => '用户名或密码错误，或登录已失效',
      AppErrorCode.forbidden => '该账号没有使用 MoviePilot API 的权限',
      AppErrorCode.notFound => '地址不正确：该路径下没有 MoviePilot 接口',
      AppErrorCode.networkUnreachable => '无法连接 MoviePilot，请检查地址与网络',
      AppErrorCode.tlsUntrusted => 'MoviePilot 证书不受信任',
      AppErrorCode.serverError => 'MoviePilot 返回异常，请稍后重试',
      _ => '登录失败，请检查地址、用户名与密码',
    };
  }
}

/// Opens the dialog, prefilling whatever is stored.
Future<void> showMoviePilotConfigDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final config = await ref.read(moviePilotSettingsProvider.future);
  if (!context.mounted) return;
  await showAppDialog<MoviePilotConfig>(
    context: context,
    builder: (_) => MoviePilotConfigDialog(initial: config),
  );
  // Reading the saved value again keeps the subtitle correct even when the
  // dialog was dismissed with the system back.
  ref.invalidate(moviePilotSettingsProvider);
}

/// Settings row for the MoviePilot connection (求片 plan S10).
class MoviePilotSettingsTile extends ConsumerWidget {
  const MoviePilotSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final config = ref.watch(moviePilotConfigProvider).value;
    final connecting = ref.watch(moviePilotSettingsProvider).isLoading;

    return ListTile(
      key: const Key('settings-moviepilot'),
      leading: Icon(Icons.cloud_outlined, color: palette.primary),
      title: const Text('MoviePilot 连接'),
      subtitle: Text(
        connecting
            ? '读取中…'
            : config == null
            ? '未登录：求片前需要登录 MoviePilot 账号'
            : config.isExpired
            ? '登录已过期：请重新登录 ${config.username}'
            : '已登录 ${config.username}（${config.baseUrl}）',
      ),
      trailing: Icon(Icons.chevron_right, color: palette.outline, size: 20),
      onTap: () => unawaited(showMoviePilotConfigDialog(context, ref)),
    );
  }
}
