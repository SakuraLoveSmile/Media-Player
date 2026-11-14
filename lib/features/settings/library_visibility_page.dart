import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/hidden_libraries.dart';
import '../../app/providers.dart';
import '../../data/models/library_view.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';

/// 通用 → 媒体库 (S32): choose which libraries appear on the home strip and in
/// the library's view chips. The preference is local only; the server keeps
/// every library.
class LibraryVisibilityPage extends ConsumerStatefulWidget {
  const LibraryVisibilityPage({super.key});

  @override
  ConsumerState<LibraryVisibilityPage> createState() =>
      _LibraryVisibilityPageState();
}

class _LibraryVisibilityPageState extends ConsumerState<LibraryVisibilityPage> {
  Future<List<LibraryView>>? _views;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      setState(() => _views = services.library.views());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '媒体库加载失败，请稍后重试');
    }
  }

  Future<void> _toggle(String viewId, bool visible) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(hiddenLibrariesControllerProvider.notifier)
          .setHidden(viewId, !visible);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final Set<String> hidden =
        ref.watch(hiddenLibrariesControllerProvider).value ?? const <String>{};
    final Future<List<LibraryView>>? views = _views;
    return AppPage(
      title: '媒体库',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('library-visibility-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          AppSection(
            header: '显示的媒体库',
            footer: '关闭后该媒体库从首页与媒体库页隐藏，服务器内容不受影响',
            children: <Widget>[
              if (_error != null)
                ListTile(
                  leading: Icon(Icons.error_outline, color: palette.error),
                  title: Text(_error!),
                ),
              if (views == null && _error == null)
                const ListTile(
                  leading: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('加载中…'),
                ),
              if (views != null)
                FutureBuilder<List<LibraryView>>(
                  future: views,
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<List<LibraryView>> snapshot,
                      ) {
                        final List<LibraryView> items =
                            snapshot.data ?? const <LibraryView>[];
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const ListTile(title: Text('加载中…'));
                        }
                        if (items.isEmpty) {
                          return const ListTile(title: Text('服务器没有可浏览的媒体库'));
                        }
                        return Column(
                          children: <Widget>[
                            for (final LibraryView view in items)
                              SwitchListTile(
                                key: Key('visibility-${view.id}'),
                                secondary: Icon(
                                  hidden.contains(view.id)
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: hidden.contains(view.id)
                                      ? palette.outline
                                      : palette.primary,
                                ),
                                title: Text(view.name),
                                subtitle: Text(
                                  view.itemCount == null
                                      ? (hidden.contains(view.id)
                                            ? '已隐藏'
                                            : '显示中')
                                      : '${view.itemCount} 项',
                                ),
                                value: !hidden.contains(view.id),
                                onChanged: (bool value) =>
                                    unawaited(_toggle(view.id, value)),
                              ),
                          ],
                        );
                      },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
