import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/models/media_item.dart';
import '../../ui/glass/glass_controls.dart';
import '../../ui/glass/glass_shell.dart';
import '../../ui/glass/glass_surface.dart';
import '../../ui/glass/glass_theme.dart';
import '../../ui/glass/glass_tokens.dart';
import 'library_controller.dart';

/// Library browsing: view switcher, poster grid, infinite scroll (contract §2),
/// restyled with a collapsing large title and continuous-corner posters.
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
      final controller = LibraryController(services.library, services.posters)
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

    return GlassPage(
      title: '媒体库',
      scrollController: _scroll,
      actions: <Widget>[
        GlassIconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: controller == null
              ? null
              : () => unawaited(controller.load(refresh: true)),
        ),
        GlassIconButton(
          key: const Key('library-request'),
          tooltip: '求片',
          icon: const Icon(Icons.add_task),
          onPressed: () => context.push(AppRoutes.request),
        ),
        GlassIconButton(
          key: const Key('library-settings'),
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(
          top: GlassHeaderMetrics.expandedHeight,
        ),
        child: _fatal != null
            ? _ErrorView(message: _fatal!, onRetry: _bootstrap)
            : controller == null || state == null
                ? const Center(child: CircularProgressIndicator())
                : _content(controller, state),
      ),
    );
  }

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
        if (state.views.length > 1)
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: GlassSpacing.lg,
                vertical: GlassSpacing.sm,
              ),
              itemCount: state.views.length,
              separatorBuilder: (_, _) => const SizedBox(width: GlassSpacing.sm),
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
        if (state.loading || state.loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: GlassSpacing.lg),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        Expanded(
          child: state.items.isEmpty
              ? (state.loaded
                  ? const _MessageView(message: '这个库还没有内容')
                  : const Center(child: CircularProgressIndicator()))
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                    GlassSpacing.lg,
                    GlassSpacing.md,
                    GlassSpacing.lg,
                    GlassSpacing.xxl,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 168,
                    mainAxisSpacing: GlassSpacing.xl,
                    crossAxisSpacing: GlassSpacing.md,
                    childAspectRatio: 0.56,
                  ),
                  itemCount: state.items.length,
                  itemBuilder: (BuildContext context, int index) {
                    final item = state.items[index];
                    return _PosterCard(
                      item: item,
                      image: controller.posterImage(
                        item.id,
                        tag: item.imageTag,
                        maxWidth: 320,
                      ),
                      onTap: () {
                        if (item.type == 'Series') {
                          context.push(AppRoutes.seriesFor(item.id));
                        } else {
                          context.push(AppRoutes.playerFor(item.id));
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PosterCard extends StatefulWidget {
  const _PosterCard({
    required this.item,
    required this.image,
    required this.onTap,
  });

  final MediaItem item;
  final ImageProvider? image;
  final VoidCallback onTap;

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    final ShapeBorder posterShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(GlassRadii.card),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.item.id.isEmpty ? null : widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: GlassMotion.fast,
        curve: GlassMotion.press,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: CustomPaint(
                foregroundPainter: _PosterRimPainter(palette: palette),
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: posterShape,
                    textDirection: TextDirection.ltr,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ColoredBox(
                        color: palette.fill,
                        child: widget.image == null
                            ? Icon(
                                Icons.movie_outlined,
                                size: 30,
                                color: palette.tertiaryLabel,
                              )
                            : Image(
                                image: widget.image!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.broken_image_outlined,
                                  color: palette.tertiaryLabel,
                                ),
                              ),
                      ),
                      if (widget.item.userData.played)
                        Positioned(
                          top: GlassSpacing.sm,
                          right: GlassSpacing.sm,
                          child: GlassTag(
                            label: '已看',
                            dense: true,
                            color: palette.tint,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: GlassSpacing.sm),
            Text(
              widget.item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GlassType.caption1.copyWith(
                color: palette.label,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hairline rim that keeps posters readable on the glass background.
class _PosterRimPainter extends CustomPainter {
  const _PosterRimPainter({required this.palette});

  final GlassPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(GlassRadii.card),
    ).getOuterPath(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = palette.label.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(_PosterRimPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GlassSpacing.xxxl),
        child: GlassSurface(
          radius: GlassRadii.cardLarge,
          padding: const EdgeInsets.all(GlassSpacing.xxl),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GlassType.body.copyWith(color: palette.secondaryLabel),
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
    final GlassPalette palette = context.glass;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GlassSpacing.xxxl),
        child: GlassSurface(
          radius: GlassRadii.cardLarge,
          padding: const EdgeInsets.all(GlassSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.wifi_off_rounded,
                color: palette.secondaryLabel,
                size: 30,
              ),
              const SizedBox(height: GlassSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GlassType.body.copyWith(color: palette.label),
              ),
              const SizedBox(height: GlassSpacing.xl),
              GlassButton(
                label: '重试',
                variant: GlassButtonVariant.tinted,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
