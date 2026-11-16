import 'package:flutter/material.dart';

import '../core/network/url_normalizer.dart';
import '../data/models/server_entry.dart';
import 'app_controls.dart';
import 'app_dialog.dart';
import 'server_card.dart';
import 'theme/app_tokens.dart';

/// Dialog helpers behind Yamby's per-server menu (S80): 显示名称, 编辑,
/// 自定义图标 and 添加备选地址. Each one returns the value to persist, or null
/// when the user backs out, so the caller owns every write.

/// 显示名称: rename a saved server.
Future<String?> showServerNameDialog(
  BuildContext context, {
  required String initial,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (BuildContext context) => _NameDialog(initial: initial),
  );
}

/// 自定义图标: pick the glyph shown on the server card.
Future<String?> showServerIconDialog(
  BuildContext context, {
  required String selected,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (BuildContext context) => _IconDialog(selected: selected),
  );
}

/// 编辑 / 添加备选地址: rewrite the name and the two addresses of a server.
///
/// Switching addresses does not touch the stored session, because the token
/// belongs to the server entry, not to one host name. [addressOnly] offers the
/// same fields without the display name (Yamby's 添加备选地址).
Future<ServerEntry?> showServerEditDialog(
  BuildContext context, {
  required ServerEntry entry,
  bool addressOnly = false,
}) {
  return showAppDialog<ServerEntry>(
    context: context,
    builder: (BuildContext context) =>
        _EditDialog(entry: entry, addressOnly: addressOnly),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_name.text.trim());

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: '显示名称',
      message: '只有这台设备上看到的名字，不影响服务器本身。',
      content: TextField(
        key: const Key('server-name-field'),
        controller: _name,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: '服务器名称',
          hintText: '例如 家里的 Emby',
        ),
      ),
      actions: <Widget>[
        AppButton(
          key: const Key('server-name-save'),
          label: '保存',
          onPressed: _submit,
        ),
        AppButton(
          key: const Key('server-name-cancel'),
          label: '取消',
          variant: AppButtonVariant.plain,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _IconDialog extends StatelessWidget {
  const _IconDialog({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return AppDialog(
      title: '自定义图标',
      message: '挑一个图标，方便在一列服务器里认出它。',
      content: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final String id in serverIconIds)
            InkWell(
              key: Key('server-icon-$id'),
              borderRadius: BorderRadius.circular(AppRadii.small),
              onTap: () => Navigator.of(context).pop(id),
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  color: id == selected
                      ? palette.primary.withValues(alpha: 0.16)
                      : palette.surfaceContainerHighest,
                  border: Border.all(
                    color: id == selected ? palette.primary : Colors.transparent,
                  ),
                ),
                child: Icon(
                  serverGlyphFor(id),
                  size: 26,
                  color: id == selected ? palette.primary : serverAccent,
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        AppButton(
          key: const Key('server-icon-cancel'),
          label: '取消',
          variant: AppButtonVariant.plain,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.entry, required this.addressOnly});

  final ServerEntry entry;
  final bool addressOnly;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.entry.name,
  );
  late final TextEditingController _lan = TextEditingController(
    text: UrlNormalizer.display(widget.entry.lanUrl ?? ''),
  );
  late final TextEditingController _wan = TextEditingController(
    text: UrlNormalizer.display(widget.entry.wanUrl ?? ''),
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _lan.dispose();
    _wan.dispose();
    super.dispose();
  }

  void _submit() {
    final String? lan = _address(_lan.text);
    if (lan == _invalid) {
      setState(() => _error = '局域网地址格式不正确，需要 http:// 或 https://');
      return;
    }
    final String? wan = _address(_wan.text);
    if (wan == _invalid) {
      setState(() => _error = '公网地址格式不正确，需要 https://');
      return;
    }
    if (lan == null && wan == null) {
      setState(() => _error = '请至少填写一个服务器地址');
      return;
    }
    final String name = widget.addressOnly
        ? widget.entry.name
        : _name.text.trim();
    Navigator.of(context).pop(
      widget.entry.copyWith(
        name: name,
        lanUrl: lan ?? '',
        wanUrl: wan ?? '',
      ),
    );
  }

  /// Marks a non-empty value that is not a usable address.
  static const String _invalid = '\u0000invalid';

  /// Empty stays null (meaning "clear this address"); unusable becomes
  /// [_invalid]; anything else is the canonical base URL.
  static String? _address(String raw) {
    if (raw.trim().isEmpty) return null;
    return UrlNormalizer.normalize(raw) ?? _invalid;
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.addressOnly ? '添加备选地址' : '编辑',
      message: widget.addressOnly
          ? '填上这台服务器的另一个地址，例如出差时用的公网地址。'
          : '修改后立即生效；已保存的登录状态会继续沿用。',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!widget.addressOnly) ...<Widget>[
            TextField(
              key: const Key('server-edit-name'),
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '显示名称',
                hintText: '留空则显示地址',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextField(
            key: const Key('server-edit-lan'),
            controller: _lan,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '局域网地址',
              hintText: 'http://192.168.1.10:8096',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('server-edit-wan'),
            controller: _wan,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '公网地址',
              hintText: 'https://media.example.com',
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              key: const Key('server-edit-error'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        AppButton(
          key: const Key('server-edit-save'),
          label: '保存',
          onPressed: _submit,
        ),
        AppButton(
          key: const Key('server-edit-cancel'),
          label: '取消',
          variant: AppButtonVariant.plain,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
