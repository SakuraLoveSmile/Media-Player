import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/models/media_item.dart';
import 'library_controller.dart';

/// Library browsing: view switcher, poster grid, infinite scroll (contract §2).
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final ScrollController _scroll = ScrollController();
  LibraryController? _controller;
  bool _redirecting = false;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      final controller = LibraryController(services.library)
        ..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '媒体库加载失败，请稍后重试');
    }
  }

  void _onChanged() {
    final controller = _controller;
    if (controller == null) return;

    if (controller.state.unauthorized && !_redirecting) {
      _redirecting = true;
      // Session is already cleared by the repository; show the login screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.login);
      });
      return;
    }
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final controller = _controller;
    if (controller == null || !_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      unawaited(controller.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final state = controller?.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: controller == null
                ? null
                : () => unawaited(controller.load(refresh: true)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _fatal != null
          ? _ErrorView(message: _fatal!, onRetry: _bootstrap)
          : controller == null || state == null
              ? const Center(child: CircularProgressIndicator())
              : _content(context, controller, state),
    );
  }

  Widget _content(
    BuildContext context,
    LibraryController controller,
    LibraryState state,
  ) {
    // A failed first load has no views either; show the real reason first.
    if (state.error != null && state.items.isEmpty) {
      return _ErrorView(
        message: state.error!,
        onRetry: () => unawaited(controller.load(refresh: true)),
      );
    }

    if (state.loaded && !state.loading && state.views.isEmpty) {
      return const _MessageView(message: '服务器没有可浏览的媒体库');
    }

    return Column(
      children: <Widget>[
        if (state.views.length > 1)
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: state.views.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final view = state.views[index];
                return ChoiceChip(
                  label: Text(view.name),
                  selected: view.id == state.selectedView?.id,
                  onSelected: (_) => unawaited(controller.selectView(view)),
                );
              },
            ),
          ),
        if (state.loading || state.loadingMore)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: state.items.isEmpty
              ? (state.loaded
                  ? const _MessageView(message: '这个库还没有内容')
                  : const Center(child: CircularProgressIndicator()))
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.56,
                  ),
                  itemCount: state.items.length,
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return _PosterCard(
                      item: item,
                      imageUrl: controller.imageUrl(
                        item.id,
                        tag: item.imageTag,
                        maxWidth: 320,
                      ),
                      onTap: () => context.go(AppRoutes.playerFor(item.id)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.imageUrl,
    required this.onTap,
  });

  final MediaItem item;
  final Uri? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: imageUrl == null
                        ? const Icon(Icons.movie_outlined, size: 32)
                        : Image.network(
                            imageUrl.toString(),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                  ),
                  if (item.userData.played)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '已看',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
