import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/hidden_libraries.dart';
import '../../app/providers.dart';
import '../../app/servers.dart';
import '../../core/router/app_routes.dart';
import '../../data/models/library_view.dart';
import '../../data/models/media_item.dart';
import '../../data/models/server_entry.dart';
import '../../ui/app_bottom_nav.dart';
import '../../ui/app_controls.dart';
import '../../ui/poster_card.dart';
import '../../ui/responsive.dart';
import '../../ui/nav_visibility.dart';
import '../../ui/app_loader.dart';
import '../../ui/theme/app_tokens.dart';
import 'home_controller.dart';

/// Home dashboard (P1/S28), laid out like Yamby's: a server header, the
/// recommended banner, the 媒体库 strip, 继续观看 and one poster row per
/// library, above the floating capsule navigation.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _scroll = ScrollController();
  HomeController? _controller;
  bool _redirecting = false;
  String? _fatal;

  @override
  void initState() {
    super.initState();
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
      // await it once so a hidden library never headlines the dashboard.
      Set<String> hidden = const <String>{};
      try {
        hidden = await ref.read(hiddenLibrariesControllerProvider.future);
      } catch (_) {
        // A broken preference hides nothing.
      }
      if (!mounted) return;
      final controller = HomeController(
        services.library,
        services.posters,
        hiddenViewIds: hidden,
      )..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '首页加载失败，请稍后重试');
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

  void _openItem(MediaItem item) {
    if (item.id.isEmpty) return;
    if (item.type == 'Series') {
      context.push(AppRoutes.seriesFor(item.id));
    } else {
      context.push(AppRoutes.detailFor(item.id));
    }
  }

  void _openLibrary(String viewId) {
    context.push(
      viewId.isEmpty ? AppRoutes.library : AppRoutes.libraryFor(viewId),
    );
  }

  /// Account avatar: switch between saved servers (Yamby's avatar dropdown).
  Future<void> _showServers() async {
    final String? activeId = ref
        .read(serversControllerProvider)
        .value
        ?.activeId;
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final AsyncValue<ServersState> async = ref.watch(
            serversControllerProvider,
          );
          final ServersState state = async.value ?? ServersState.empty;
          final ColorScheme palette = Theme.of(context).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      '服务器',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (state.servers.isEmpty)
                    ListTile(
                      key: const Key('home-servers-empty'),
                      leading: Icon(Icons.dns_outlined, color: palette.outline),
                      title: const Text('暂无保存的服务器'),
                    ),
                  for (final ServerEntry entry in state.servers)
                    ListTile(
                      key: Key('home-server-${entry.id}'),
                      leading: Icon(
                        entry.id == activeId
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: entry.id == activeId
                            ? palette.primary
                            : palette.outline,
                      ),
                      title: Text(
                        entry.name.isEmpty ? entry.addressLabel : entry.name,
                      ),
                      subtitle: Text(entry.addressLabel),
                      onTap: () => Navigator.of(sheetContext).pop(entry.id),
                    ),
                  ListTile(
                    key: const Key('home-server-add'),
                    leading: Icon(
                      Icons.add_circle_outline,
                      color: palette.primary,
                    ),
                    title: const Text('添加服务器'),
                    onTap: () => Navigator.of(sheetContext).pop('__add__'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == '__add__') {
      context.push(AppRoutes.loginAdd());
      return;
    }
    if (picked == activeId) return;
    final session = await ref
        .read(serversControllerProvider.notifier)
        .switchTo(picked);
    if (!mounted) return;
    context.go(session == null ? AppRoutes.loginFor(picked) : AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final HomeController? controller = _controller;
    final HomeState? state = controller?.state;

    return Scaffold(
      key: const Key('home-page'),
      extendBody: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _HomeHeader(
              serverName: state?.serverName ?? '',
              onAccount: () => unawaited(_showServers()),
              onSettings: () => context.push(AppRoutes.settings),
              onServers: () => context.push(AppRoutes.servers),
            ),
            Expanded(
              child: _fatal != null
                  ? _ErrorView(message: _fatal!, onRetry: _bootstrap)
                  : controller == null || state == null
                  ? const AppLoadingView()
                  : NavScrollReporter(child: _content(controller, state)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppNavDestination.home),
    );
  }

  Widget _content(HomeController controller, HomeState state) {
    // 通用 → 媒体库 (S32): hidden libraries disappear from the strip and rows.
    final Set<String> hidden =
        ref.watch(hiddenLibrariesControllerProvider).value ?? const <String>{};
    final List<LibraryView> views = state.views
        .where((LibraryView view) => !hidden.contains(view.id))
        .toList(growable: false);
    final List<HomeRow> rows = state.rows
        .where((HomeRow row) => !hidden.contains(row.view.id))
        .toList(growable: false);
    if (state.error != null && state.isEmpty) {
      return _ErrorView(
        message: state.error!,
        onRetry: () => unawaited(controller.load()),
      );
    }
    if (state.loaded && !state.loading && rows.isEmpty) {
      return _MessageView(
        message: state.rows.isEmpty
            ? '服务器没有可浏览的媒体库'
            : '媒体库已全部隐藏，可在设置 → 通用 → 媒体库中恢复',
      );
    }

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 120),
        children: <Widget>[
          if (state.banner.isNotEmpty)
            _BannerCarousel(
              items: state.banner,
              imageFor: (MediaItem item) =>
                  controller.backdropImage(item, maxWidth: 720) ??
                  controller.posterImage(
                    item.id,
                    tag: item.imageTag,
                    maxWidth: 640,
                  ),
              onTap: _openItem,
            ),
          if (views.isNotEmpty) ...<Widget>[
            const _SectionHeader(title: '媒体库'),
            _LibraryStrip(
              views: views,
              rows: rows,
              imageFor: (LibraryView view) =>
                  controller.viewImage(view, maxWidth: 480),
              onTap: (LibraryView view) => _openLibrary(view.id),
            ),
          ],
          const _SectionHeader(title: '继续观看'),
          if (state.resumable.isEmpty)
            const _EmptyHint(message: '没有正在观看的内容')
          else
            _ResumeRow(
              items: state.resumable,
              posterFor: (MediaItem item) => controller.posterImage(
                item.id,
                tag: item.imageTag,
                maxWidth: 320,
              ),
              backdropFor: (MediaItem item) =>
                  controller.backdropImage(item, maxWidth: 480),
              onTap: (MediaItem item) => item.id.isEmpty
                  ? null
                  : context.push(AppRoutes.playerFor(item.id)),
            ),
          for (final HomeRow row in rows)
            if (row.items.isNotEmpty)
              _LibraryRowSection(
                row: row,
                imageFor: (MediaItem item) => controller.posterImage(
                  item.id,
                  tag: item.imageTag,
                  maxWidth: 320,
                ),
                onTap: _openItem,
                onMore: () => _openLibrary(row.view.id),
              ),
        ],
      ),
    );
  }
}

/// Server avatar, server name, settings and the server-list action (Yamby's
/// home header).
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.serverName,
    required this.onAccount,
    required this.onSettings,
    required this.onServers,
  });

  final String serverName;
  final VoidCallback onAccount;
  final VoidCallback onSettings;
  final VoidCallback onServers;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const Key('home-account'),
            tooltip: '服务器',
            icon: const Icon(Icons.account_circle_outlined),
            iconSize: 28,
            onPressed: onAccount,
          ),
          Expanded(
            child: Text(
              serverName,
              key: const Key('home-server-name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const Key('home-settings'),
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: onSettings,
          ),
          IconButton(
            key: const Key('home-servers'),
            tooltip: '服务器列表',
            icon: Icon(
              Icons.play_arrow_rounded,
              color: palette.primary,
              size: 30,
            ),
            onPressed: onServers,
          ),
        ],
      ),
    );
  }
}

/// Recommended banner: a peeking carousel of wide artwork with a
/// rating · genres · year pill in the lower-right corner (Yamby's home).
class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel({
    required this.items,
    required this.imageFor,
    required this.onTap,
  });

  final List<MediaItem> items;
  final ImageProvider? Function(MediaItem item) imageFor;
  final ValueChanged<MediaItem> onTap;

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final PageController _page = PageController(viewportFraction: 0.87);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: homeBannerHeight(context),
      child: PageView.builder(
        controller: _page,
        itemCount: widget.items.length,
        itemBuilder: (BuildContext context, int index) {
          final MediaItem item = widget.items[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _BannerCard(
              item: item,
              image: widget.imageFor(item),
              onTap: () => widget.onTap(item),
            ),
          );
        },
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
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
    final List<String> genres = item.genres.take(2).toList(growable: false);
    final List<String> facts = <String>[
      if (item.communityRating != null)
        item.communityRating!.toStringAsFixed(1),
      if (genres.isNotEmpty) genres.join(' · '),
      if (item.productionYear != null) '${item.productionYear}',
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.cardLarge),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: palette.surfaceContainerHighest,
              child: image == null
                  ? Icon(Icons.movie_outlined, size: 40, color: palette.outline)
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
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
            if (facts.isNotEmpty)
              Positioned(
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(AppRadii.capsule),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (item.communityRating != null)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: Color(0xFFFFC94D),
                          ),
                        ),
                      Text(
                        facts.join('  |  '),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 媒体库 strip: one card per library — the library's own artwork and the
/// title count badge.
class _LibraryStrip extends StatelessWidget {
  const _LibraryStrip({
    required this.views,
    required this.rows,
    required this.imageFor,
    required this.onTap,
  });

  final List<LibraryView> views;
  final List<HomeRow> rows;
  final ImageProvider? Function(LibraryView view) imageFor;
  final ValueChanged<LibraryView> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: homeLibraryStripHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: views.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (BuildContext context, int index) {
          final LibraryView view = views[index];
          int count = view.itemCount ?? 0;
          if (count == 0) {
            for (final HomeRow row in rows) {
              if (row.view.id == view.id) count = row.total;
            }
          }
          return _LibraryCard(
            view: view,
            count: count,
            image: imageFor(view),
            onTap: () => onTap(view),
          );
        },
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.view,
    required this.count,
    required this.image,
    required this.onTap,
  });

  final LibraryView view;
  final int count;
  final ImageProvider? image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return GestureDetector(
      key: Key('home-library-${view.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: homeLibraryCardWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: homeLibraryCardWidth(context),
              height: homeLibraryCardHeight(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(
                      color: palette.surfaceContainerHighest,
                      child: image == null
                          ? const SizedBox.shrink()
                          : Image(
                              image: image!,
                              // The card already has the cover's own 16:9
                              // shape, so `cover` fills it exactly and the
                              // server's artwork is never cropped.
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                    ),
                    if (count > 0)
                      Positioned(
                        top: AppSpacing.xs,
                        right: AppSpacing.xs,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // The strip height is computed from this line's height, so the
            // name is never clipped by the card above it (S28).
            SizedBox(
              height: homeLibraryLabelHeight(context),
              child: Text(
                view.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: palette.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Continue-watching row: wide cards with the remaining time and a progress
/// bar, title and year underneath (Yamby's 继续观看).
class _ResumeRow extends StatelessWidget {
  const _ResumeRow({
    required this.items,
    required this.posterFor,
    required this.backdropFor,
    required this.onTap,
  });

  final List<MediaItem> items;
  final ImageProvider? Function(MediaItem item) posterFor;
  final ImageProvider? Function(MediaItem item) backdropFor;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: homeResumeRowHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (BuildContext context, int index) {
          final MediaItem item = items[index];
          return _ResumeCard(
            item: item,
            image: backdropFor(item) ?? posterFor(item),
            onTap: () => onTap(item),
          );
        },
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
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
    final int runTime = item.runTimeTicks;
    final int position = item.userData.positionTicks;
    final double fraction = runTime > 0
        ? (position / runTime).clamp(0.0, 1.0)
        : 0.0;
    final Duration remaining = item.duration - item.userData.position;
    return GestureDetector(
      key: Key('resume-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: homeResumeCardWidth(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              height: homeResumeImageHeight(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(
                      color: palette.surfaceContainerHighest,
                      child: image == null
                          ? Icon(
                              Icons.movie_outlined,
                              size: 30,
                              color: palette.outline,
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
                    Positioned(
                      left: AppSpacing.sm,
                      bottom: AppSpacing.sm + 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '剩余: ${_remainingLabel(remaining)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        key: Key('resume-progress-${item.id}'),
                        value: fraction,
                        minHeight: 3,
                        backgroundColor: Colors.black.withValues(alpha: 0.4),
                        color: palette.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              // S68: an episode's row is headed by its series, like Yamby.
              _resumeTitle(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            // S68: an episode shows `S1E2：标题` where a movie shows its year,
            // matching Yamby's 继续观看 card.
            if (_resumeSubtitle(item) != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _resumeSubtitle(item)!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryRowSection extends StatelessWidget {
  const _LibraryRowSection({
    required this.row,
    required this.imageFor,
    required this.onTap,
    required this.onMore,
  });

  final HomeRow row;
  final ImageProvider? Function(MediaItem item) imageFor;
  final ValueChanged<MediaItem> onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  row.view.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium!
                      .copyWith(color: palette.onSurface),
                ),
              ),
              GestureDetector(
                key: Key('home-more-${row.view.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: Text(
                  '更多',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: palette.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: homeRowHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: row.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (BuildContext context, int index) {
              final MediaItem item = row.items[index];
              return SizedBox(
                width: homeRowCardWidth(context),
                child: PosterCard(
                  name: item.name,
                  played: item.userData.played,
                  rating: item.communityRating,
                  unplayedCount: item.userData.unplayedItemCount,
                  centerTitle: true,
                  image: imageFor(item),
                  onTap: item.id.isEmpty ? null : () => onTap(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium!
            .copyWith(color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: AppCard(
        radius: AppRadii.cardLarge,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: palette.onSurfaceVariant),
        ),
      ),
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

/// `45分 6秒`, `24分`, `38秒` — Yamby's remaining-time wording.
String _remainingLabel(Duration value) {
  final Duration total = value.isNegative ? Duration.zero : value;
  final int hours = total.inHours;
  final int minutes = total.inMinutes.remainder(60);
  final int seconds = total.inSeconds.remainder(60);
  final StringBuffer buffer = StringBuffer();
  if (hours > 0) buffer.write('$hours时');
  if (minutes > 0) buffer.write('$minutes分 ');
  buffer.write('$seconds秒');
  return buffer.toString().trim();
}

/// S68: episodes are titled with their series, everything else with its name.
String _resumeTitle(MediaItem item) {
  if (item.type == 'Episode') {
    final String? series = item.seriesName;
    if (series != null && series.isNotEmpty) return series;
  }
  return item.name;
}

/// S68: `S1E2：标题` for episodes, the year for movies, nothing otherwise.
String? _resumeSubtitle(MediaItem item) {
  if (item.type == 'Episode') {
    final int? season = item.parentIndexNumber;
    final int? episode = item.indexNumber;
    final String number = <String>[
      if (season != null) 'S$season',
      if (episode != null) 'E$episode',
    ].join();
    if (number.isEmpty) return item.yearLabel;
    return item.name.isEmpty ? number : '$number：${item.name}';
  }
  return item.yearLabel;
}
