import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/models/media_item.dart';
import '../../ui/app_bottom_nav.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_page.dart';
import '../../ui/responsive.dart';
import '../../ui/app_loader.dart';
import '../../ui/list_entrance.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/poster_card.dart';
import 'search_controller.dart';

/// Library-wide title search (S6): debounced query, type chips, poster grid
/// and recent terms when the field is empty.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _text = TextEditingController();
  LibrarySearchController? _controller;
  bool _redirecting = false;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _text.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      final controller = LibrarySearchController(
        services.library,
        services.posters,
        store: services.store,
      )..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.loadHistory();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '搜索初始化失败，请稍后重试');
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

  void _applyTerm(String term) {
    _text.text = term;
    _controller?.setQuery(term);
    _controller?.submit();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final state = controller?.state;

    return AppPage(
      title: '搜索',
      onBack: () => context.pop(),
      bottomNavigationBar: const AppBottomNav(
        current: AppNavDestination.search,
      ),
      child: _fatal != null
          ? _MessageView(message: _fatal!)
          : controller == null || state == null
          ? const AppLoadingView()
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  child: AppCard(
                    radius: AppRadii.capsule,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: TextField(
                      key: const Key('search-field'),
                      controller: _text,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: '搜索电影 / 剧集 / 合集 / 演员',
                        border: InputBorder.none,
                        icon: Icon(Icons.search),
                      ),
                      onChanged: controller.setQuery,
                      onSubmitted: (_) => controller.submit(),
                    ),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    children: <Widget>[
                      for (final (SearchFilter filter, String label)
                          in <(SearchFilter, String)>[
                            (SearchFilter.all, '全部'),
                            (SearchFilter.movies, '电影'),
                            (SearchFilter.series, '剧集'),
                            (SearchFilter.collections, '合集'),
                            (SearchFilter.persons, '演员'),
                          ])
                        Builder(
                          builder: (BuildContext context) {
                            final bool selected = filter == SearchFilter.all
                                ? state.filters.contains(SearchFilter.all)
                                : state.filters.contains(filter);
                            return Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.sm,
                              ),
                              child: Center(
                                child: FilterChip(
                                  key: Key('search-filter-${filter.name}'),
                                  label: Text(label),
                                  // S72: Yamby marks a picked type with ✓ and leaves
                                  // the others outlined.
                                  showCheckmark: true,
                                  side: selected
                                      ? BorderSide.none
                                      : BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                  selected: selected,
                                  onSelected: (_) =>
                                      controller.toggleFilter(filter),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                Expanded(child: _body(controller, state)),
              ],
            ),
    );
  }

  /// S61: one section per result type, in Yamby's order.
  static List<SearchGroup> _groupResults(List<MediaItem> results) {
    const List<(String, String)> order = <(String, String)>[
      ('Movie', '电影'),
      ('Series', '剧集'),
      ('BoxSet', '合集'),
      ('Person', '演员'),
    ];
    final List<SearchGroup> groups = <SearchGroup>[];
    for (final (String type, String label) in order) {
      final List<MediaItem> items = results
          .where((MediaItem item) => item.type == type)
          .toList(growable: false);
      if (items.isNotEmpty) {
        groups.add(SearchGroup(type: type, label: label, items: items));
      }
    }
    // Unknown types (albums, videos, …) still render, under one header.
    final List<MediaItem> other = results
        .where(
          (MediaItem item) =>
              !order.any(((String, String) entry) => entry.$1 == item.type),
        )
        .toList(growable: false);
    if (other.isNotEmpty) {
      groups.add(SearchGroup(type: 'Other', label: '其他', items: other));
    }
    return groups;
  }

  /// Routes one result to the page that owns its type.
  void _openItem(MediaItem item) {
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

  Widget _body(LibrarySearchController controller, SearchState state) {
    if (state.error != null) {
      return _ErrorView(message: state.error!, onRetry: controller.submit);
    }
    if (state.query.trim().isEmpty) {
      return _HistoryView(
        history: state.history,
        onPick: _applyTerm,
        onRemove: (String term) => unawaited(controller.removeHistory(term)),
        onClear: () => unawaited(controller.clearHistory()),
      );
    }
    if (state.loading && state.results.isEmpty) {
      return const AppLoadingView();
    }
    if (state.loaded && state.results.isEmpty) {
      return _MessageView(message: '没有找到「${state.query.trim()}」');
    }
    // S61: Yamby groups results by type; a single-type search keeps the plain
    // grid so nothing gains a pointless header.
    final List<SearchGroup> groups = _groupResults(state.results);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final SliverGridDelegate delegate = posterGridDelegate(
          constraints.maxWidth,
        );
        Widget card(MediaItem item, int index) => ListEntrance(
          index: index,
          child: PosterCard(
            name: item.name,
            played: item.userData.played,
            image: controller.posterImage(
              item.id,
              tag: item.imageTag,
              maxWidth: 320,
            ),
            onTap: item.id.isEmpty ? null : () => _openItem(item),
          ),
        );
        if (groups.length > 1) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              0,
              AppSpacing.md,
              0,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              for (final SearchGroup group in groups) ...<Widget>[
                Padding(
                  key: Key('search-group-${group.type}'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    group.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: delegate,
                  itemCount: group.items.length,
                  itemBuilder: (BuildContext context, int index) =>
                      card(group.items[index], index),
                ),
              ],
            ],
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          gridDelegate: delegate,
          itemCount: state.results.length,
          itemBuilder: (BuildContext context, int index) =>
              card(state.results[index], index),
        );
      },
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({
    required this.history,
    required this.onPick,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> history;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                history.isEmpty ? '输入名称搜索电影 / 剧集' : '最近搜索',
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
            ),
            if (history.isNotEmpty)
              TextButton(
                key: const Key('search-history-clear'),
                onPressed: onClear,
                child: const Text('清除全部'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // S52: two-column rounded entries, like Yamby's history view.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double tileWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final String term in history)
                  SizedBox(
                    width: tileWidth,
                    child: AppCard(
                      key: Key('search-history-$term'),
                      radius: AppRadii.control,
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.search,
                            size: 18,
                            color: palette.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: InkWell(
                              onTap: () => onPick(term),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  term,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            key: Key('search-history-remove-$term'),
                            tooltip: '移除',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onRemove(term),
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: palette.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
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

/// One type section of the search results (S61).
class SearchGroup {
  const SearchGroup({
    required this.type,
    required this.label,
    required this.items,
  });

  final String type;
  final String label;
  final List<MediaItem> items;
}
