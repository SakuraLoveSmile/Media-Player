import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/moviepilot_providers.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/moviepilot_exception.dart';
import '../../core/network/url_normalizer.dart';
import '../../data/moviepilot/models/moviepilot_config.dart';
import '../../ui/glass/glass_controls.dart';
import '../../ui/glass/glass_shell.dart';
import '../../ui/glass/glass_theme.dart';
import '../../ui/glass/glass_tokens.dart';

/// MoviePilot connection form (求片 plan S10).
///
/// Saves through [moviePilotSettingsProvider], which verifies the token before
/// persisting it. The dialog never logs or renders the token it holds, and the
/// field is obscured while typing.
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
  late final TextEditingController _token;
  bool _saving = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initial?.baseUrl ?? '');
    _token = TextEditingController(text: widget.initial?.apiToken ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;

    // `showGlassDialog` inserts a transparent Material for this, but the dialog
    // may also be opened by a route that does not, so it carries its own.
    return Material(
      type: MaterialType.transparency,
      child: GlassDialog(
        title: 'MoviePilot 连接',
        message: '填写 MoviePilot 地址与 API_TOKEN，用于搜索片源和跟踪求片进度。',
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
            const SizedBox(height: GlassSpacing.md),
            FeedbackCaptureMask(
              child: TextField(
                key: const Key('moviepilot-token'),
                controller: _token,
                enabled: !_saving,
                autocorrect: false,
                obscureText: _obscure,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_save()),
                decoration: InputDecoration(
                  labelText: 'API_TOKEN',
                  helperText: 'MoviePilot 设置 → 服务 → API_TOKEN',
                  suffixIcon: IconButton(
                    key: const Key('moviepilot-token-visibility'),
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
            if (_error != null) ...<Widget>[
              const SizedBox(height: GlassSpacing.md),
              Text(
                _error!,
                key: const Key('moviepilot-error'),
                style: GlassType.footnote.copyWith(color: palette.red),
              ),
            ],
            if (_notice != null) ...<Widget>[
              const SizedBox(height: GlassSpacing.md),
              Text(
                _notice!,
                key: const Key('moviepilot-notice'),
                style: GlassType.footnote.copyWith(color: palette.green),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          GlassButton(
            key: const Key('moviepilot-save'),
            label: '保存并测试',
            loading: _saving,
            onPressed: _saving ? null : () => unawaited(_save()),
          ),
          GlassButton(
            key: const Key('moviepilot-cancel'),
            label: '取消',
            variant: GlassButtonVariant.plain,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          if (widget.initial != null)
            GlassButton(
              key: const Key('moviepilot-clear'),
              label: '清除连接',
              variant: GlassButtonVariant.plain,
              onPressed: _saving ? null : () => unawaited(_clear()),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final config = MoviePilotConfig.fromInput(
      rawBaseUrl: _url.text,
      rawApiToken: _token.text,
    );
    if (config == null) {
      setState(() {
        _error = UrlNormalizer.normalize(_url.text) == null
            ? '地址无效，请填写 http:// 或 https:// 开头的地址'
            : 'API_TOKEN 不能为空';
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
          .save(config);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = '连接成功：${saved.baseUrl}';
      });
      // The saved state already updates the settings page; close on success so
      // the user is not left in a dialog that has done its job.
      Navigator.of(context).pop(saved);
    } on MoviePilotException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _describe(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '连接失败，请检查地址与网络';
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
      AppErrorCode.unauthorized => 'API_TOKEN 无效或权限不足，请检查后重试',
      AppErrorCode.notFound => '地址不正确：该路径下没有 MoviePilot 接口',
      AppErrorCode.networkUnreachable => '无法连接 MoviePilot，请检查地址与网络',
      AppErrorCode.tlsUntrusted => 'MoviePilot 证书不受信任',
      AppErrorCode.serverError => 'MoviePilot 返回异常，请稍后重试',
      _ => '连接失败，请检查地址与 API_TOKEN',
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
  await showGlassDialog<MoviePilotConfig>(
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
    final GlassPalette palette = context.glass;
    final config = ref.watch(moviePilotConfigProvider).value;
    final connecting = ref.watch(moviePilotSettingsProvider).isLoading;

    return ListTile(
      key: const Key('settings-moviepilot'),
      leading: Icon(Icons.cloud_outlined, color: palette.tint),
      title: const Text('MoviePilot 连接'),
      subtitle: Text(
        connecting
            ? '读取中…'
            : config == null
            ? '未连接：求片前需要填写地址与 API_TOKEN'
            : '已连接 ${config.baseUrl}',
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: palette.tertiaryLabel,
        size: 20,
      ),
      onTap: () => unawaited(showMoviePilotConfigDialog(context, ref)),
    );
  }
}
