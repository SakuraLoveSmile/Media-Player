import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/models/media_item.dart';
import '../../ui/app_bottom_nav.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_dialog.dart';
import '../../ui/app_page.dart';
import '../../ui/responsive.dart';
import '../../ui/app_loader.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/poster_card.dart';
import 'favorites_controller.dart';

/// Favorites browsing (S8): type tabs, a sort picker, paginated poster grid
/// and an empty state. Mirrors the search page shell.
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  final ScrollController _scroll = ScrollController();
  FavoritesController? _controller;
  bool _redirecting = false;
  String? _fatal;

  /// Immersive browsing (S39): hides the app bar; the exit button floats.
  bool _fullscreen = false;

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
      final controller = FavoritesController(services.library, services.posters)
        ..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '收藏加载失败，请稍后重试');
    }
  }

  void _onChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.state.unauthorized && !_redirecting) {
      _redirecting = true;
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

  /// S71: shuffle — open a random favorite from the loaded page.
  Future<void> _playRandom(FavoritesController controller) async {
    final MediaItem? item = controller.randomItem();
    if (item == null) return;
    await context.push(AppRoutes.playerFor(item.id));
    if (!mounted) return;
    await controller.load();
  }

  Future<void> _pickSort() async {
    final controller = _controller;
    if (controller == null) return;
    final (FavoritesSort, bool?)? picked =
        await showAppDialog<(FavoritesSort, bool?)>(
          context: context,
          builder: (BuildContext dialogContext) => AppDialog(
            title: '排序方式',
            // S70: the field list scrolls; 升序/降序 stay pinned below it.
            content: SizedBox(
              width: 320,
              height: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final FavoritesSort sort in FavoritesSort.values)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AppButton(
                              key: Key('favorites-sort-${sort.name}'),
                              label: sort.label,
                              expand: true,
                              variant: controller.state.sort == sort
                                  ? AppButtonVariant.tinted
                                  : AppButtonVariant.plain,
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop((sort, null)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppButton(
                          key: const Key('favorites-sort-asc'),
                          label: '升序',
                          expand: true,
                          variant: controller.state.sortDescending
                              ? AppButtonVariant.plain
                              : AppButtonVariant.tinted,
                          onPressed: () =>
                              Navigator.of(dialogContext)
                                  .pop((controller.state.sort, false)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppButton(
                          key: const Key('favorites-sort-desc'),
                          label: '降序',
                          expand: true,
                          variant: controller.state.sortDescending
                              ? AppButtonVariant.tinted
                              : AppButtonVariant.plain,
                          onPressed: () =>
                              Navigator.of(dialogContext)
                                  .pop((controller.state.sort, true)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              AppButton(
                label: '取消',
                variant: AppButtonVariant.plain,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
    if (picked == null || !mounted) return;
    controller.setSort(picked.$1, descending: picked.$2);
  }

  /// 筛选 dialog (S39): genre chips from `GET /Genres` plus a year field.
  Future<void> _pickFilter() async {
    final controller = _controller;
    if (controller == null) return;
    // Load the genre facets before opening the dialog: the dialog itself does
    // not listen to the controller, so a lazy load would leave it spinning.
    await controller.loadGenres();
    if (!mounted) return;
    String? genre = controller.state.genreFilter;
    int? year = controller.state.yearFilter;
    final TextEditingController yearText = TextEditingController(
      text: year == null ? '' : '$year',
    );
    final (String?, int?)? picked = await showAppDialog<(String?, int?)>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, void Function(VoidCallback) setState) {
          final List<String> genres = controller.state.genres;
          final bool loading = controller.state.facetsLoading;
          return AppDialog(
            title: '筛选',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '类型',
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      ChoiceChip(
                        key: const Key('favorites-genre-all'),
                        label: const Text('全部'),
                        selected: genre == null,
                        onSelected: (_) => setState(() => genre = null),
                      ),
                      for (final String name in genres)
                        ChoiceChip(
                          key: Key('favorites-genre-$name'),
                          label: Text(name),
                          selected: genre == name,
                          onSelected: (bool selected) =>
                              setState(() => genre = selected ? name : null),
                        ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  key: const Key('favorites-year'),
                  controller: yearText,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '年份',
                    hintText: '如 2024，留空不限',
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              AppButton(
                key: const Key('favorites-filter-clear'),
                label: '清除',
                variant: AppButtonVariant.plain,
                onPressed: () => Navigator.of(dialogContext).pop((null, null)),
              ),
              AppButton(
                key: const Key('favorites-filter-apply'),
                label: '应用',
                onPressed: () {
                  final int? parsed = int.tryParse(yearText.text.trim());
                  Navigator.of(dialogContext).pop((genre, parsed));
                },
              ),
            ],
          );
        },
      ),
    );
    yearText.dispose();
    if (picked == null || !mounted) return;
    controller.applyFilters(picked.$1, picked.$2);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final state = controller?.state;

    final Widget page = AppPage(
      title: '收藏',
      onBack: () => context.pop(),
      bottomNavigationBar: const AppBottomNav(
        current: AppNavDestination.favorites,
      ),

      child: _fatal != null
          ? _ErrorView(message: _fatal!, onRetry: _bootstrap)
          : controller == null || state == null
          ? const AppLoadingView()
          : Column(
              children: <Widget>[
                // Type tabs (S35), mirrored from Yamby's favorites page: each
                // chip carries its type icon.
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    children: <Widget>[
                      for (final (
                            FavoritesFilter filter,
                            String label,
                            IconData icon,
                          )
                          in <(FavoritesFilter, String, IconData)>[
                            (FavoritesFilter.all, '全部', Icons.apps),
                            (
                              FavoritesFilter.movies,
                              '电影',
                              Icons.movie_outlined,
                            ),
                            (FavoritesFilter.series, '剧集', Icons.tv),
                            (
                              FavoritesFilter.collections,
                              '合集',
                              Icons.collections_bookmark_outlined,
                            ),
                            (
                              FavoritesFilter.persons,
                              '演员',
                              Icons.person_outline,
                            ),
                          ])
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: Center(
                            child: ChoiceChip(
                              key: Key('favorites-filter-${filter.name}'),
                              avatar: Icon(
                                icon,
                                size: 16,
                                color: state.filter == filter
                                    ? Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                              ),
                              label: Text(label),
                              selected: state.filter == filter,
                              onSelected: (_) => controller.setFilter(filter),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Toolbar (S35): count, grid/list and the sort label.
                SizedBox(
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '${state.total} 项',
                          key: const Key('favorites-count'),
                          style: Theme.of(context).textTheme.labelMedium!
                              .copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const Spacer(),
                        // S71: Yamby's favorites row is 随机播放 → 视图 → 筛选 →
                        // 排序; 全屏 is ours and stays last.
                        AppIconButton(
                          key: const Key('favorites-random'),
                          tooltip: '随机播放',
                          icon: const Icon(Icons.shuffle_rounded),
                          onPressed: state.items.isEmpty
                              ? null
                              : () => _playRandom(controller),
                        ),
                        AppIconButton(
                          key: const Key('favorites-view-toggle'),
                          tooltip: state.viewMode == FavoritesViewMode.grid
                              ? '列表视图'
                              : '海报视图',
                          icon: Icon(
                            state.viewMode == FavoritesViewMode.grid
                                ? Icons.view_list_rounded
                                : Icons.grid_view_rounded,
                          ),
                          onPressed: controller.toggleViewMode,
                        ),
                        AppIconButton(
                          key: const Key('favorites-filter'),
                          tooltip: '筛选',
                          icon: const Icon(Icons.filter_list_rounded),
                          onPressed: () => unawaited(_pickFilter()),
                        ),
                        TextButton.icon(
                          key: const Key('favorites-sort'),
                          onPressed: () => unawaited(_pickSort()),
                          icon: const Icon(Icons.swap_vert, size: 16),
                          label: Text(
                            '${state.sort.label} ${state.sortDescending ? '↓' : '↑'}',
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        AppIconButton(
                          key: const Key('favorites-fullscreen'),
                          tooltip: '全屏浏览',
                          icon: const Icon(Icons.open_in_full),
                          onPressed: () => setState(() => _fullscreen = true),
                        ),
                      ],
                    ),
                  ),
                ),
                // 筛选 tags (S39): each active facet is removable in place.
                if (state.genreFilter != null || state.yearFilter != null)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      children: <Widget>[
                        if (state.genreFilter != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.sm,
                            ),
                            child: Center(
                              child: InputChip(
                                key: const Key('favorites-filter-genre-active'),
                                label: Text(state.genreFilter!),
                                onDeleted: () =>
                                    controller.setGenreFilter(null),
                              ),
                            ),
                          ),
                        if (state.yearFilter != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.sm,
                            ),
                            child: Center(
                              child: InputChip(
                                key: const Key('favorites-filter-year-active'),
                                label: Text('${state.yearFilter}'),
                                onDeleted: () => controller.setYearFilter(null),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (state.loading || state.loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                Expanded(child: _body(controller, state)),
              ],
            ),
    );
    if (!_fullscreen) return page;

    // 全屏浏览 (S39): the browsing surface without the app bar.
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _fatal != null
                  ? _ErrorView(message: _fatal!, onRetry: _bootstrap)
                  : controller == null || state == null
                  ? const AppLoadingView()
                  : Column(
                      children: <Widget>[
                        Expanded(child: _body(controller, state)),
                      ],
                    ),
            ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: AppIconButton(
                key: const Key('favorites-fullscreen-exit'),
                tooltip: '退出全屏',
                icon: const Icon(Icons.fullscreen_exit),
                onPressed: () => setState(() => _fullscreen = false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Type-aware navigation (S35): series/collection/person have their own
  /// pages; anything else opens the movie detail.
  void _openItem(MediaItem item) {
    if (item.id.isEmpty) return;
    switch (item.type) {
      case 'Series':
        context.push(AppRoutes.seriesFor(item.id));
      case 'BoxSet':
        context.push(AppRoutes.collectionFor(item.id, name: item.name));
      case 'Person':
        context.push(AppRoutes.personFor(item.id, name: item.name));
      default:
        context.push(AppRoutes.detailFor(item.id));
    }
  }

  Widget _body(FavoritesController controller, FavoritesState state) {
    if (state.error != null && state.items.isEmpty) {
      return _ErrorView(
        message: state.error!,
        onRetry: () => unawaited(controller.load()),
      );
    }
    if (state.items.isEmpty) {
      return state.loaded
          ? const _MessageView(
              message: '还没有收藏任何影片',
              icon: Icons.favorite_border,
            )
          : const AppLoadingView();
    }
    if (state.viewMode == FavoritesViewMode.list) {
      return ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        itemCount: state.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final MediaItem item = state.items[index];
          return _FavoriteRow(
            item: item,
            image: controller.posterImage(
              item.id,
              tag: item.imageTag,
              maxWidth: 160,
            ),
            onTap: () => _openItem(item),
          );
        },
      );
    }
    // S15: the favorites grid's column count follows the available width.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          gridDelegate: posterGridDelegate(constraints.maxWidth),
          itemCount: state.items.length,
          itemBuilder: (BuildContext context, int index) {
            final MediaItem item = state.items[index];
            return PosterCard(
              name: item.name,
              played: item.userData.played,
              rating: item.communityRating,
              unplayedCount: item.userData.unplayedItemCount,
              subtitle: item.yearLabel,
              image: controller.posterImage(
                item.id,
                tag: item.imageTag,
                maxWidth: 320,
              ),
              onTap: () => _openItem(item),
            );
          },
        );
      },
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: AppCard(
          radius: AppRadii.cardLarge,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 40, color: palette.outline),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
            ],
          ),
        ),
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
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: AppCard(
          radius: AppRadii.cardLarge,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.wifi_off_rounded,
                color: palette.onSurfaceVariant,
                size: 30,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge!
                    .copyWith(color: palette.onSurface),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: '重试',
                variant: AppButtonVariant.tinted,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact list row for the favorites list view (S35).
class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({
    required this.item,
    required this.image,
    required this.onTap,
  });

  final MediaItem item;
  final ImageProvider? image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return GestureDetector(
      key: Key('favorite-row-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: SizedBox(
              width: 56,
              height: 84,
              child: ColoredBox(
                color: palette.surfaceContainerHighest,
                child: image == null
                    ? Icon(Icons.movie_outlined, color: palette.outline)
                    : Image(
                        image: image!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.broken_image_outlined,
                          color: palette.outline,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    if (item.yearLabel != null) item.yearLabel!,
                    if (item.communityRating != null)
                      '★ ${item.communityRating!.toStringAsFixed(1)}',
                    if (item.userData.played) '已看',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelSmall!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
