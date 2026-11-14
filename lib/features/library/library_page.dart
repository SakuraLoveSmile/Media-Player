import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/hidden_libraries.dart';
import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/router/app_routes.dart';
import '../../data/library/library_service.dart';
import '../../data/models/library_view.dart';
import '../../data/models/media_item.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_dialog.dart';
import '../../ui/app_page.dart';
import '../../ui/responsive.dart';
import '../../ui/app_loader.dart';
import '../../ui/list_entrance.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/poster_card.dart';
import 'library_controller.dart';

/// Library browsing: view switcher, poster grid, infinite scroll (contract §2),
/// restyled with a collapsing large title and continuous-corner posters.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({
    super.key,
    this.initialViewId,
    this.initialGenre,
    this.initialStudioId,
    this.initialStudioName,
  });

  /// Library opened from a home 媒体库 / 更多 card (S28); null browses the
  /// first view.
  final String? initialViewId;

  /// Genre seeded from a detail page chip (S46); null opens unfiltered.
  final String? initialGenre;

  /// Studio seeded from a detail page 工作室 link (S60).
  final String? initialStudioId;
  final String? initialStudioName;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final ScrollController _scroll = ScrollController();
  LibraryController? _controller;
  LibraryService? _library;
  bool _redirecting = false;
  String? _fatal;

  /// Master-detail selection (S15): only meaningful on wide surfaces, where
  /// tapping a poster selects it for the preview pane instead of navigating.
  String? _selectedId;

  /// Immersive browsing (S31): hides the app bar while the grid keeps its own
  /// toolbar; the exit button stays floating on top.
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
      // S32: the hidden-library list may still be resolving on a cold start;
      // await it once so the first page never flashes hidden libraries.
      Set<String> hidden = const <String>{};
      try {
        hidden = await ref.read(hiddenLibrariesControllerProvider.future);
      } catch (_) {
        // A broken preference hides nothing.
      }
      if (!mounted) return;
      final controller = LibraryController(
        services.library,
        services.posters,
        preferredViewId: widget.initialViewId,
        preferredGenre: widget.initialGenre,
        preferredStudioId: widget.initialStudioId,
        preferredStudioName: widget.initialStudioName,
        hiddenViewIds: hidden,
      )..addListener(_onChanged);
      _library = services.library;
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
    // A reload that no longer contains the selected item (tab/view switch,
    // refresh) drops the preview selection instead of showing a stale pane.
    final selected = _selectedId;
    if (selected != null &&
        !controller.state.items.any((item) => item.id == selected)) {
      _selectedId = null;
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

    final Widget page = AppPage(
      title: _titleFor(state),
      actions: <Widget>[
        AppIconButton(
          key: const Key('library-search'),
          tooltip: '搜索',
          icon: const Icon(Icons.search),
          onPressed: () => context.push(AppRoutes.search),
        ),
        AppIconButton(
          key: const Key('library-favorites'),
          tooltip: '收藏',
          icon: const Icon(Icons.favorite_border),
          onPressed: () => context.push(AppRoutes.favorites),
        ),
        AppIconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: controller == null
              ? null
              : () => unawaited(controller.load(refresh: true)),
        ),
        AppIconButton(
          key: const Key('library-request'),
          tooltip: '求片',
          icon: const Icon(Icons.add_task),
          onPressed: () => context.push(AppRoutes.request),
        ),
        AppIconButton(
          key: const Key('library-settings'),
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ],
      child: _fatal != null
          ? _ErrorView(message: _fatal!, onRetry: _bootstrap)
          : controller == null || state == null
          ? const AppLoadingView()
          : _content(controller, state),
    );
    if (!_fullscreen) return page;

    // 全屏浏览 (S31, Yamby's expand action): the same browsing surface without
    // the app bar, with a floating exit button.
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _fatal != null
                  ? _ErrorView(message: _fatal!, onRetry: _bootstrap)
                  : controller == null || state == null
                  ? const AppLoadingView()
                  : _content(controller, state),
            ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: AppIconButton(
                key: const Key('library-fullscreen-exit'),
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

  /// App-bar title: the browsing library's own name on view-scoped tabs
  /// (Yamby shows the library name), a generic label for the global tabs.
  String _titleFor(LibraryState? state) {
    if (state == null) return '媒体库';
    final LibraryView? view = state.selectedView;
    final bool scoped =
        state.tab == LibraryTab.all ||
        state.tab == LibraryTab.type ||
        state.tab == LibraryTab.tag;
    return scoped && view != null && view.name.isNotEmpty ? view.name : '媒体库';
  }

  Future<void> _pickSort() async {
    final controller = _controller;
    if (controller == null) return;
    final LibraryState state = controller.state;
    final (LibrarySort, bool?)? picked =
        await showAppDialog<(LibrarySort, bool?)>(
          context: context,
          builder: (BuildContext dialogContext) => AppDialog(
            title: '排序方式',
            // S70: ten sort fields need a scrollable body; 升序/降序 stay at
            // the bottom so they are always reachable.
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
                        for (final LibrarySort sort in LibrarySort.values)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AppButton(
                              key: Key('library-sort-${sort.name}'),
                              label: sort.label,
                              expand: true,
                              variant: state.sort == sort
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
                          key: const Key('library-sort-asc'),
                          label: '升序',
                          expand: true,
                          variant: state.sortDescending
                              ? AppButtonVariant.plain
                              : AppButtonVariant.tinted,
                          onPressed: () =>
                              Navigator.of(dialogContext)
                                  .pop((state.sort, false)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppButton(
                          key: const Key('library-sort-desc'),
                          label: '降序',
                          expand: true,
                          variant: state.sortDescending
                              ? AppButtonVariant.tinted
                              : AppButtonVariant.plain,
                          onPressed: () =>
                              Navigator.of(dialogContext)
                                  .pop((state.sort, true)),
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

  /// 全部 筛选 (S10): genre chips from `genres()` plus a year field, applied
  /// through `items(genre:, year:)`. Popping null keeps the current filters.
  Future<void> _pickFilter() async {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.loadGenres());
    final ({String? genre, int? year})? picked =
        await showAppDialog<({String? genre, int? year})>(
          context: context,
          builder: (BuildContext dialogContext) =>
              _FilterDialog(controller: controller),
        );
    if (picked == null || !mounted) return;
    controller.applyFilters(picked.genre, picked.year);
  }

  void _playRandom(LibraryController controller) {
    final MediaItem? item = controller.randomItem();
    if (item == null) return;
    _openItem(item);
  }

  void _openItem(MediaItem item) {
    if (item.type == 'Series') {
      context.push(AppRoutes.seriesFor(item.id));
    } else {
      // S10: a BoxSet collection poster opens the detail page; a dedicated
      // collection-children browse route is out of this slice's scope.
      context.push(AppRoutes.detailFor(item.id));
    }
  }

  /// S15: on wide surfaces a tap selects the item for the persistent preview
  /// pane; below the breakpoint it keeps navigating straight to the item.
  void _selectOrOpen(MediaItem item) {
    if (isWide(context)) {
      setState(() => _selectedId = item.id);
      return;
    }
    _openItem(item);
  }

  String _emptyMessage(LibraryTab tab) => switch (tab) {
    LibraryTab.all => '这个库还没有内容',
    LibraryTab.resume => '没有正在观看的内容',
    LibraryTab.favorites => '还没有收藏任何影片',
    LibraryTab.collections => '还没有任何合集',
    LibraryTab.type => '这个分类下还没有内容',
    LibraryTab.tag => '没有匹配的内容',
    LibraryTab.upcoming => '暂无即将上映的内容',
  };

  Widget _content(LibraryController controller, LibraryState state) {
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
        // Sub-tabs, ordered like Yamby: 全部 / 继续播放 / 合集 / 类型 / 标签 / 收藏.
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            children: <Widget>[
              for (final (LibraryTab tab, String label)
                  in <(LibraryTab, String)>[
                    // S69: Yamby's order — 即将上映 sits right after 继续播放.
                    (LibraryTab.all, '全部'),
                    (LibraryTab.resume, '继续播放'),
                    (LibraryTab.upcoming, '即将上映'),
                    (LibraryTab.collections, '合集'),
                    (LibraryTab.type, '类型'),
                    (LibraryTab.tag, '标签'),
                    (LibraryTab.favorites, '收藏'),
                  ])
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Center(
                    child: ChoiceChip(
                      key: Key('library-tab-${tab.name}'),
                      label: Text(label),
                      selected: state.tab == tab,
                      onSelected: (_) => controller.selectTab(tab),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Toolbar (S31, Yamby's row): count, fullscreen, filter, view switch,
        // shuffle and the sort label.
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Text(
                  '${state.total} 项',
                  key: const Key('library-count'),
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  key: const Key('library-fullscreen'),
                  tooltip: '全屏浏览',
                  icon: const Icon(Icons.open_in_full),
                  onPressed: () => setState(() => _fullscreen = true),
                ),
                if (state.tab == LibraryTab.all)
                  AppIconButton(
                    key: const Key('library-filter'),
                    tooltip: '筛选',
                    icon: const Icon(Icons.filter_list_rounded),
                    onPressed: _pickFilter,
                  ),
                AppIconButton(
                  key: const Key('library-view-toggle'),
                  tooltip: state.viewMode == LibraryViewMode.grid
                      ? '列表视图'
                      : '海报视图',
                  icon: Icon(
                    state.viewMode == LibraryViewMode.grid
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                  ),
                  onPressed: controller.toggleViewMode,
                ),
                AppIconButton(
                  key: const Key('library-random'),
                  tooltip: '随机播放',
                  icon: const Icon(Icons.shuffle_rounded),
                  onPressed: state.items.isEmpty
                      ? null
                      : () => _playRandom(controller),
                ),
                // S45: the upcoming tab always sorts by premiere date, so the
                // sort control becomes a static label there.
                if (state.tab == LibraryTab.upcoming)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs),
                    child: Text(
                      '上映日期 ↑',
                      key: const Key('library-sort-upcoming'),
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    key: const Key('library-sort'),
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
              ],
            ),
          ),
        ),
        // Library views scope 全部 / 类型 / 标签; 继续 / 收藏 / 合集 are global.
        if ((state.tab == LibraryTab.all ||
                state.tab == LibraryTab.type ||
                state.tab == LibraryTab.tag) &&
            state.views.length > 1)
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              itemCount: state.views.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (BuildContext context, int index) {
                final view = state.views[index];
                return Center(
                  child: ChoiceChip(
                    label: Text(view.name),
                    selected: view.id == state.selectedView?.id,
                    onSelected: (_) => unawaited(controller.selectView(view)),
                  ),
                );
              },
            ),
          ),
        // 类型 tab: secondary Movie/Series chooser (S10).
        if (state.tab == LibraryTab.type)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              children: <Widget>[
                for (final LibraryTypeFilter filter in LibraryTypeFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Center(
                      child: ChoiceChip(
                        key: Key('library-type-${filter.name}'),
                        label: Text(filter.label),
                        selected: state.typeFilter == filter,
                        onSelected: (_) => controller.setTypeFilter(filter),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // 标签 tab: server tag chips; selecting one filters by Tag (S10).
        if (state.tab == LibraryTab.tag)
          SizedBox(
            height: 52,
            child: state.tags.isNotEmpty
                ? ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: Center(
                          child: ChoiceChip(
                            key: const Key('library-tag-all'),
                            label: const Text('全部'),
                            selected: state.selectedTag == null,
                            onSelected: (_) => controller.selectTag(null),
                          ),
                        ),
                      ),
                      for (final String tag in state.tags)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: Center(
                            child: ChoiceChip(
                              key: Key('library-tag-$tag'),
                              label: Text(tag),
                              selected: state.selectedTag == tag,
                              onSelected: (bool selected) =>
                                  controller.selectTag(selected ? tag : null),
                            ),
                          ),
                        ),
                    ],
                  )
                : state.facetsLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : state.facetsError != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            state.facetsError!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        AppButton(
                          key: const Key('library-tags-retry'),
                          label: '重试',
                          variant: AppButtonVariant.plain,
                          onPressed: () =>
                              unawaited(controller.loadTags(refresh: true)),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        // Active 全部 filters, each removable in place (S10).
        if (state.tab == LibraryTab.all && state.hasFilters)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              children: <Widget>[
                if (state.genreFilter != null)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Center(
                      child: InputChip(
                        key: const Key('library-filter-genre-active'),
                        label: Text(state.genreFilter!),
                        onDeleted: () => controller.setGenreFilter(null),
                      ),
                    ),
                  ),
                if (state.yearFilter != null)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Center(
                      child: InputChip(
                        key: const Key('library-filter-year-active'),
                        label: Text('${state.yearFilter}'),
                        onDeleted: () => controller.setYearFilter(null),
                      ),
                    ),
                  ),
                if (state.studioFilterId != null ||
                    state.studioFilterName != null)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Center(
                      child: InputChip(
                        key: const Key('library-filter-studio-active'),
                        label: Text(
                          '工作室: ${state.studioFilterName ?? state.studioFilterId ?? ''}',
                        ),
                        onDeleted: controller.clearStudioFilter,
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
        Expanded(child: _itemsBody(controller, state)),
      ],
    );
  }

  Widget _itemsBody(LibraryController controller, LibraryState state) {
    if (state.items.isEmpty) {
      return state.loaded
          ? _MessageView(message: _emptyMessage(state.tab))
          : const AppLoadingView();
    }

    final Widget body;
    if (state.viewMode == LibraryViewMode.list) {
      body = ListView.separated(
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
          final item = state.items[index];
          return _SelectionRing(
            selected: isWide(context) && item.id == _selectedId,
            child: _LibraryListRow(
              item: item,
              image: controller.posterImage(
                item.id,
                tag: item.imageTag,
                maxWidth: 160,
              ),
              onTap: item.id.isEmpty ? null : () => _selectOrOpen(item),
            ),
          );
        },
      );
    } else {
      // S15: the column count follows the pane's own width, so the grid also
      // adapts when the master-detail preview takes a slice of the surface.
      body = LayoutBuilder(
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
              final item = state.items[index];
              return ListEntrance(
                index: index,
                child: _SelectionRing(
                  selected: isWide(context) && item.id == _selectedId,
                  child: PosterCard(
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
                    onTap: item.id.isEmpty ? null : () => _selectOrOpen(item),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    if (!isWide(context)) return body;

    // S15 master-detail: the grid keeps paging on the left while a persistent
    // preview pane shows the selected item on the right.
    final LibraryService? library = _library;
    return Row(
      children: <Widget>[
        Expanded(child: body),
        SizedBox(
          width: AppBreakpoints.previewPaneWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              0,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            child: library == null
                ? const SizedBox.shrink()
                : _LibraryPreviewPane(
                    itemId: _selectedId,
                    service: library,
                    imageFor: (MediaItem item) => controller.posterImage(
                      item.id,
                      tag: item.imageTag,
                      maxWidth: 480,
                    ),
                    onPlay: (MediaItem item) =>
                        context.push(AppRoutes.playerFor(item.id)),
                    onDetails: _openItem,
                  ),
          ),
        ),
      ],
    );
  }
}

/// A primary-coloured ring around the selected poster/row in the wide
/// master-detail layout (S15); invisible otherwise.
class _SelectionRing extends StatelessWidget {
  const _SelectionRing({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: child,
    );
  }
}

/// Persistent preview pane of the wide library layout (S15). Fetches the full
/// item through [LibraryService.item] (a lightweight reuse of the detail
/// data, without importing the detail feature) and offers 播放 / 详情 actions
/// that navigate; tapping posters only changes the selection.
class _LibraryPreviewPane extends StatefulWidget {
  const _LibraryPreviewPane({
    required this.itemId,
    required this.service,
    required this.imageFor,
    required this.onPlay,
    required this.onDetails,
  });

  final String? itemId;
  final LibraryService service;
  final ImageProvider? Function(MediaItem item) imageFor;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onDetails;

  @override
  State<_LibraryPreviewPane> createState() => _LibraryPreviewPaneState();
}

class _LibraryPreviewPaneState extends State<_LibraryPreviewPane> {
  MediaItem? _item;
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_LibraryPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId) unawaited(_load());
  }

  /// A generation counter discards answers for selections the user already
  /// left, mirroring the library controller's paging contract.
  Future<void> _load() async {
    final String? id = widget.itemId;
    final int seq = ++_seq;
    if (id == null || id.isEmpty) {
      setState(() {
        _item = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _item = null;
      _loading = true;
      _error = null;
    });
    try {
      final MediaItem item = await widget.service.item(id);
      if (!mounted || seq != _seq) return;
      setState(() {
        _item = item;
        _loading = false;
      });
    } on EmbyException catch (error) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = error.code == AppErrorCode.unauthorized
            ? '登录已过期，请重新登录'
            : '详情加载失败，请稍后重试';
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = '详情加载失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final MediaItem? item = _item;

    final Widget content;
    if (widget.itemId == null) {
      content = Center(
        key: const Key('library-preview-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.movie_outlined, size: 40, color: palette.outline),
            const SizedBox(height: AppSpacing.md),
            Text(
              '选择海报查看详情',
              style: text.bodyMedium!.copyWith(color: palette.onSurfaceVariant),
            ),
          ],
        ),
      );
    } else if (_loading) {
      content = const AppLoadingView();
    } else if (_error != null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: text.bodyMedium!.copyWith(color: palette.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('library-preview-retry'),
              label: '重试',
              variant: AppButtonVariant.tinted,
              onPressed: () => unawaited(_load()),
            ),
          ],
        ),
      );
    } else if (item == null) {
      content = const SizedBox.shrink();
    } else {
      // Series / BoxSet containers cannot be played directly; 详情 opens
      // their own page instead.
      final bool playable = item.type != 'Series' && item.type != 'BoxSet';
      final ImageProvider? poster = widget.imageFor(item);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.card),
              child: SizedBox(
                height: 220,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ColoredBox(
                    color: palette.surfaceContainerHighest,
                    child: poster == null
                        ? Icon(
                            Icons.movie_outlined,
                            size: 30,
                            color: palette.outline,
                          )
                        : Image(
                            image: poster,
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
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            item.name,
            key: const Key('library-preview-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge!.copyWith(color: palette.onSurface),
          ),
          if (item.tagline != null && item.tagline!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              item.tagline!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall!.copyWith(color: palette.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              if (item.communityRating != null)
                AppTag(
                  label: item.communityRating!.toStringAsFixed(1),
                  icon: const Icon(Icons.star),
                  color: Colors.orange,
                ),
              if (item.productionYear != null)
                AppTag(label: '${item.productionYear}'),
              if (item.runTimeTicks > 0)
                AppTag(label: _previewRuntime(item.duration)),
              for (final String genre in item.genres) AppTag(label: genre),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                item.overview?.trim().isNotEmpty == true
                    ? item.overview!
                    : '暂无简介',
                style: text.bodyMedium!.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  key: const Key('library-preview-play'),
                  label: '播放',
                  leading: const Icon(Icons.play_arrow),
                  onPressed: playable ? () => widget.onPlay(item) : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  key: const Key('library-preview-details'),
                  label: '详情',
                  variant: AppButtonVariant.tinted,
                  leading: const Icon(Icons.info_outline),
                  onPressed: () => widget.onDetails(item),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return AppCard(
      key: const Key('library-preview-pane'),
      radius: AppRadii.cardLarge,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: content,
    );
  }
}

String _previewRuntime(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return minutes > 0 ? '$hours小时$minutes分' : '$hours小时';
  }
  return '$minutes分钟';
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: AppCard(
          radius: AppRadii.cardLarge,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge!
                .copyWith(color: palette.onSurfaceVariant),
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

/// Compact list row (P1 view switch): small poster, name, year and the watched
/// tag, on the same Material surface as the rest of the page.
class _LibraryListRow extends StatelessWidget {
  const _LibraryListRow({
    required this.item,
    required this.image,
    required this.onTap,
  });

  final MediaItem item;
  final ImageProvider? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return GestureDetector(
      key: Key('library-row-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AppCard(
        radius: AppRadii.card,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 48,
              height: 72,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.extraSmall),
                child: ColoredBox(
                  color: palette.surfaceContainerHighest,
                  child: image == null
                      ? Center(
                          child: Icon(
                            Icons.movie_outlined,
                            size: 22,
                            color: palette.outline,
                          ),
                        )
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
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      color: palette.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.productionYear != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${item.productionYear}',
                      style: Theme.of(context).textTheme.bodySmall!
                          .copyWith(color: palette.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (item.userData.played) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              AppTag(label: '已看', dense: true, color: palette.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 筛选 dialog body (S10): genre chips streamed from the controller plus a
/// year field. Pops a `({genre, year})` record on 应用 / 清除筛选, null on
/// 取消, so the page applies both facets in a single reload.
class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.controller});

  final LibraryController controller;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late String? _genre = widget.controller.state.genreFilter;
  late final TextEditingController _year = TextEditingController(
    text: widget.controller.state.yearFilter?.toString() ?? '',
  );

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  void _apply() {
    final String text = _year.text.trim();
    Navigator.of(context).pop((
      genre: _genre,
      // A blank or unparseable year clears the facet instead of guessing.
      year: text.isEmpty ? null : int.tryParse(text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return AppDialog(
      title: '筛选',
      content: AnimatedBuilder(
        animation: widget.controller,
        builder: (BuildContext context, _) {
          final LibraryState state = widget.controller.state;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '类型',
                style: text.titleSmall!.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 120,
                child: state.genres.isEmpty
                    ? state.facetsLoading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Center(
                              child: state.facetsError != null
                                  ? AppButton(
                                      key: const Key(
                                        'library-filter-genres-retry',
                                      ),
                                      label: '类型加载失败，点击重试',
                                      variant: AppButtonVariant.plain,
                                      onPressed: () => unawaited(
                                        widget.controller.loadGenres(
                                          refresh: true,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      '没有可用的类型',
                                      style: text.bodyMedium!.copyWith(
                                        color: palette.onSurfaceVariant,
                                      ),
                                    ),
                            )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: <Widget>[
                            ChoiceChip(
                              key: const Key('library-filter-genre-any'),
                              label: const Text('不限'),
                              selected: _genre == null,
                              onSelected: (_) => setState(() => _genre = null),
                            ),
                            for (final String genre in state.genres)
                              ChoiceChip(
                                key: Key('library-filter-genre-$genre'),
                                label: Text(genre),
                                selected: _genre == genre,
                                onSelected: (bool selected) => setState(
                                  () => _genre = selected ? genre : null,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('library-filter-year'),
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '年份',
                  hintText: '例如 2024',
                ),
              ),
            ],
          );
        },
      ),
      actions: <Widget>[
        AppButton(
          key: const Key('library-filter-apply'),
          label: '应用',
          variant: AppButtonVariant.tinted,
          onPressed: _apply,
        ),
        AppButton(
          key: const Key('library-filter-clear'),
          label: '清除筛选',
          variant: AppButtonVariant.plain,
          onPressed: () => Navigator.of(context).pop((genre: null, year: null)),
        ),
        AppButton(
          label: '取消',
          variant: AppButtonVariant.plain,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
