import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/library/poster_cache.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_dialog.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';

/// 通用 → 图片缓存 (S32): shows how much artwork is cached on disk and lets the
/// user drop it. Scoped to the poster cache only — subtitles and backups have
/// their own lifecycles.
class CacheSettingsPage extends ConsumerStatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  ConsumerState<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends ConsumerState<CacheSettingsPage> {
  PosterCache? _cache;
  Future<int>? _size;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = await ref.read(bootstrapProvider.future);
    if (!mounted) return;
    setState(() {
      _cache = services.posters;
      _size = services.posters.sizeBytes();
    });
  }

  Future<void> _clear() async {
    final PosterCache? cache = _cache;
    if (cache == null || _clearing) return;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppDialog(
        title: '清除图片缓存',
        content: Text(
          '删除本机已下载的海报与剧照，下次浏览会重新下载。',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
        actions: <Widget>[
          AppButton(
            label: '取消',
            variant: AppButtonVariant.plain,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            key: const Key('cache-clear-confirm'),
            label: '清除',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await cache.clear();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('图片缓存已清除')));
      setState(() => _size = cache.sizeBytes());
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('清除失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final Future<int>? size = _size;
    return AppPage(
      title: '图片缓存',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('cache-settings-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          AppSection(
            header: '本机缓存',
            children: <Widget>[
              ListTile(
                leading: Icon(
                  Icons.photo_library_outlined,
                  color: palette.primary,
                ),
                title: const Text('海报与剧照'),
                subtitle: size == null
                    ? const Text('计算中…')
                    : FutureBuilder<int>(
                        future: size,
                        builder: (BuildContext context, snapshot) {
                          final int? bytes = snapshot.data;
                          return Text(
                            bytes == null
                                ? '计算中…'
                                : '已缓存 ${_formatBytes(bytes)}',
                            key: const Key('cache-size'),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    key: const Key('cache-clear'),
                    label: '清除缓存',
                    variant: AppButtonVariant.tinted,
                    leading: const Icon(Icons.delete_outline),
                    onPressed: _clearing || _cache == null ? null : _clear,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const double mb = 1024 * 1024;
  const double gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}
