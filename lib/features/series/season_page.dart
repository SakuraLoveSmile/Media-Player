import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/auth/auth_service.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/media_item.dart';
import '../../ui/app_bottom_nav.dart';
import '../../ui/app_loader.dart';
import '../../ui/nav_visibility.dart';
import '../../ui/responsive.dart';
import '../../ui/theme/app_tokens.dart';
import 'season_controller.dart';
import 'series_widgets.dart';

/// One season's episode list (S78), opened from the series page's 季 row and
/// laid out like Yamby's: the series backdrop with the floating bar, the year
/// metadata, the resume row, then 第 N 季 and the episode cards.
class SeasonPage extends ConsumerStatefulWidget {
  const SeasonPage({super.key, required this.seriesId, required this.seasonId});

  final String seriesId;
  final String seasonId;

  @override
  ConsumerState<SeasonPage> createState() => _SeasonPageState();
}

class _SeasonPageState extends ConsumerState<SeasonPage> {
  final ScrollController _scroll = ScrollController();
  SeasonController? _controller;
  AuthService? _auth;
  StreamSubscription<AuthSession?>? _session;
  bool _redirecting = false;
  bool _leaving = false;
  bool _openingPlayer = false;
  bool _barOpaque = false;
  String? _fatal;

  /// The player replaces itself with the next episode, which never completes
  /// the push future (S78 device fix): the busy state is unlocked by a timer
  /// and the page polls for becoming current again to refresh the episodes.
  Timer? _busyUnlock;
  Timer? _playbackWatch;
  bool _returnHandled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Re-show the capsule navigation; a scrolled series page would otherwise
    // leave it hidden when this page is pushed on top (S78 device fix).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(navVisibleProvider.notifier).set(true);
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _busyUnlock?.cancel();
    _playbackWatch?.cancel();
    _scroll.removeListener(_onScroll);
    unawaited(_session?.cancel());
    _controller?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_controller != null) return;
    setState(() => _fatal = null);
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted || _leaving) return;
      if (widget.seriesId.isEmpty || widget.seasonId.isEmpty) {
        setState(() => _fatal = '季信息缺失，请返回剧集页重试');
        return;
      }
      _auth = services.auth;
      _session = services.auth.session.listen((session) {
        if (session == null) _toLogin();
      });
      if (services.auth.current == null) {
        _toLogin();
        return;
      }
      final controller = SeasonController(
        seriesId: widget.seriesId,
        seasonId: widget.seasonId,
        library: services.library,
        posters: services.posters,
      )..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
    } catch (_) {
      if (!mounted || _leaving) return;
      setState(() => _fatal = '剧集加载失败，请稍后重试');
    }
  }

  void _toLogin() {
    if (!mounted || _redirecting || _leaving) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(AppRoutes.login);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onChanged() {
    if (_controller?.state.unauthorized ?? false) {
      _toLogin();
      return;
    }
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!mounted || !_scroll.hasClients) return;
    final bool next = _scroll.offset > _heroHeight(context) - 120;
    if (next != _barOpaque) setState(() => _barOpaque = next);
  }

  /// Yamby's season hero matches the series hero at about 1.05x the width.
  double _heroHeight(BuildContext context) =>
      isWide(context) ? 460 : MediaQuery.sizeOf(context).width * 1.05;

  void _leave() {
    if (_leaving || _redirecting) return;
    _leaving = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.seriesFor(widget.seriesId));
    }
  }

  Future<void> _play(MediaItem episode) async {
    if (!mounted || _openingPlayer || _redirecting || _leaving) return;
    final session = _auth?.current;
    if (session == null) {
      _toLogin();
      return;
    }
    setState(() => _openingPlayer = true);
    _returnHandled = false;
    // The player swaps itself for the next episode, so its push future may
    // never complete; never leave the row stuck in its busy state.
    _busyUnlock = Timer(const Duration(seconds: 1), () {
      if (mounted && _openingPlayer) setState(() => _openingPlayer = false);
    });
    _watchForReturn(session);
    try {
      await context.push<void>(AppRoutes.playerFor(episode.id));
      await _onPlaybackReturn(session);
    } finally {
      _busyUnlock?.cancel();
      _busyUnlock = null;
      _playbackWatch?.cancel();
      _playbackWatch = null;
      if (mounted) setState(() => _openingPlayer = false);
    }
  }

  /// Watches the route becoming current again, so the episode list refreshes
  /// even when the player replaced its own route (S78 device fix).
  void _watchForReturn(AuthSession session) {
    _playbackWatch?.cancel();
    bool covered = false;
    _playbackWatch = Timer.periodic(const Duration(milliseconds: 700), (
      Timer timer,
    ) {
      if (!mounted) {
        timer.cancel();
        _playbackWatch = null;
        return;
      }
      final bool current = ModalRoute.of(context)?.isCurrent ?? true;
      if (!current) {
        covered = true;
        return;
      }
      if (!covered) return;
      timer.cancel();
      _playbackWatch = null;
      if (_openingPlayer && mounted) {
        setState(() => _openingPlayer = false);
      }
      if (mounted) ref.read(navVisibleProvider.notifier).set(true);
      unawaited(_onPlaybackReturn(session));
    });
  }

  Future<void> _onPlaybackReturn(AuthSession session) async {
    if (_returnHandled || !mounted) return;
    if (_leaving || _redirecting) {
      _returnHandled = true;
      return;
    }
    if (!identical(_auth?.current, session)) {
      _returnHandled = true;
      return;
    }
    // A route replacement can complete the push future while the player is
    // still on top; only refresh once this page is visible again.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _returnHandled = true;
    _playbackWatch?.cancel();
    _playbackWatch = null;
    await _controller?.refreshEpisodes();
  }

  Future<void> _openEpisodePicker(SeasonState state) async {
    final MediaItem? season = state.season;
    await showSeriesEpisodePicker(
      context: context,
      title: season == null ? '选集' : '选集 · ${seasonLabel(season)}',
      episodes: state.episodes,
      labelOf: (MediaItem episode) =>
          episodeLabel(episode, seasonNumber: season?.indexNumber),
      subtitleOf: (MediaItem episode) => episode.runTimeTicks > 0
          ? durationLabel(episode.duration)
          : '这一集暂无时长信息',
      imageOf: (MediaItem episode) => _controller?.episodeImage(episode),
      onSelected: (MediaItem episode) => unawaited(_play(episode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SeasonState? state = _controller?.state;
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          _leaving = true;
        } else {
          _leave();
        }
      },
      child: Scaffold(
        key: const Key('season-page'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        extendBody: true,
        body: _fatal != null
            ? _errorBody(
                message: _fatal!,
                onRetry: _bootstrap,
                backKey: const Key('season-back'),
              )
            : state == null || (state.season == null && state.loading)
            ? const AppLoadingView()
            : state.season == null
            ? _errorBody(
                message: state.error ?? '剧集加载失败，请稍后重试',
                onRetry: () => _controller!.load(),
                backKey: const Key('season-back'),
              )
            : NavScrollReporter(child: _content(state)),
        bottomNavigationBar: const AppBottomNav(
          current: AppNavDestination.home,
        ),
      ),
    );
  }

  /// Error state with a retry and a visible way back (S78).
  Widget _errorBody({
    required String message,
    required Future<void> Function() onRetry,
    required Key backKey,
  }) {
    return Stack(
      children: <Widget>[
        SafeArea(
          child: _ErrorView(message: message, onRetry: onRetry),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: SeriesBackButton(key: backKey, onPressed: _leave),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(SeasonState state) {
    final List<Widget> children = <Widget>[
      _hero(state),
      SizedBox(
        height: 2,
        child: state.episodesLoading
            ? const LinearProgressIndicator(
                key: Key('season-episodes-loading'),
                minHeight: 2,
              )
            : null,
      ),
      ..._playBlock(state),
      ..._episodeList(state),
      const SizedBox(height: 96),
    ];
    final Widget list = ListView(
      key: const Key('season-scroll'),
      controller: _scroll,
      padding: EdgeInsets.zero,
      children: children,
    );
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: isWide(context)
              ? Center(
                  child: ConstrainedBox(
                    key: const Key('season-wide-content'),
                    constraints: const BoxConstraints(
                      maxWidth: AppBreakpoints.detailMaxWidth,
                    ),
                    child: list,
                  ),
                )
              : list,
        ),
        Positioned(top: 0, left: 0, right: 0, child: _topBar(state)),
      ],
    );
  }

  Widget _topBar(SeasonState state) {
    final Widget bar = SeriesTopBar(
      keyPrefix: 'season',
      title: state.series?.name ?? '季',
      opaque: _barOpaque,
      played: state.watched,
      favorite: state.season?.userData.isFavorite ?? false,
      busy: state.playedBusy || state.favoriteBusy,
      onBack: _leave,
      onWatched: () => unawaited(_controller!.togglePlayed()),
      onFavorite: () => unawaited(_controller!.toggleFavorite()),
      onRefresh: () => unawaited(_controller!.refresh()),
      onTogglePlayed: () => unawaited(_controller!.togglePlayed()),
    );
    if (!isWide(context)) return bar;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppBreakpoints.detailMaxWidth,
        ),
        child: bar,
      ),
    );
  }

  Widget _hero(SeasonState state) {
    final MediaItem? series = state.series;
    final ColorScheme palette = Theme.of(context).colorScheme;
    final SeasonController controller = _controller!;
    final ImageProvider? art = series == null
        ? controller.posterImage(
            state.season!.id,
            tag: state.season!.imageTag,
            maxWidth: 780,
          )
        : controller.backdropImage(series, maxWidth: 1200) ??
              controller.posterImage(
                series.id,
                tag: series.imageTag,
                maxWidth: 780,
              );
    // Yamby shows only the year here; the episode count lives on the series
    // page's season-card badge (S78).
    final String meta =
        '${series?.productionYear ?? state.season?.productionYear ?? ''}';
    return SizedBox(
      key: const Key('season-hero'),
      height: _heroHeight(context),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            color: palette.surfaceContainerHighest,
            child: art == null
                ? Icon(Icons.movie_outlined, size: 40, color: palette.outline)
                : Image(
                    image: art,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: <double>[0, 0.32],
                colors: <Color>[Color(0x66000000), Color(0x00000000)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: <double>[0, 0.45, 1],
                colors: <Color>[
                  Color(0x00000000),
                  Color(0x59000000),
                  Color(0xE6000000),
                ],
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.md,
            child: Text(
              meta,
              key: const Key('season-meta'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// The resume row (S78): the season's play target with its progress fill and
  /// the 选集 chevron.
  List<Widget> _playBlock(SeasonState state) {
    final MediaItem? target = state.playTarget;
    final List<Widget> rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          0,
        ),
        child: state.episodes.isEmpty && !state.episodesLoading
            ? Text(
                state.episodesError == null ? '这一季暂无分集' : '分集加载失败',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : Row(
                children: <Widget>[
                  SizedBox(
                    width: seriesPlayButtonWidth(context),
                    child: SeriesPlayButton(
                      key: const Key('season-play'),
                      label: _playLabel(state, target),
                      progress: target == null ? 0 : _progress(target),
                      onPressed: _openingPlayer || target == null
                          ? null
                          : () => unawaited(_play(target)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SeriesPickerButton(
                    key: const Key('season-episodes'),
                    onPressed: _openingPlayer || state.episodes.isEmpty
                        ? null
                        : () => unawaited(_openEpisodePicker(state)),
                  ),
                ],
              ),
      ),
    ];
    if (state.episodesError != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: _InlineError(
            key: const Key('season-episodes-error'),
            message: state.episodesError!,
            onRetry: () => unawaited(_controller!.refreshEpisodes()),
            retryKey: const Key('season-episodes-retry'),
          ),
        ),
      );
    }
    if (state.writeError != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Text(
            state.writeError!,
            key: const Key('season-write-error'),
            style: Theme.of(context).textTheme.labelMedium!
                .copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    return rows;
  }

  String _playLabel(SeasonState state, MediaItem? target) {
    if (state.watched) return '已播放';
    if (target == null) return '播放';
    final bool resumable =
        !target.userData.played && target.userData.positionTicks > 0;
    if (!resumable) return '播放';
    final Duration remaining = target.duration - target.userData.position;
    return '继续 (剩余: ${durationLabel(remaining.isNegative ? Duration.zero : remaining)})';
  }

  /// 第 N 季 plus the episode cards (S78).
  List<Widget> _episodeList(SeasonState state) {
    if (state.episodes.isEmpty) return const <Widget>[];
    final MediaItem? season = state.season;
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xxxl,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        child: Text(
          season == null ? '第 N 季' : seasonLabel(season),
          key: const Key('season-heading'),
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      for (final (int index, MediaItem episode) in state.episodes.indexed)
        _EpisodeCard(
          key: Key('season-episode-${episode.id}'),
          episode: episode,
          number: episode.indexNumber ?? index + 1,
          image: _controller!.episodeImage(episode),
          onTap: _openingPlayer ? null : () => unawaited(_play(episode)),
        ),
    ];
  }
}

/// Episode progress as a 0..1 fraction; 0 for finished or unmeasured episodes.
double _progress(MediaItem episode) {
  if (episode.userData.played || episode.runTimeTicks <= 0) return 0;
  return (episode.userData.positionTicks / episode.runTimeTicks).clamp(
    0.0,
    1.0,
  );
}

/// One episode card: still on the left (16:9, ~48% of the screen), 1.标题 and
/// the duration on the right, the 2-line overview underneath (S78).
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    super.key,
    required this.episode,
    required this.number,
    required this.image,
    required this.onTap,
  });

  final MediaItem episode;
  final int number;
  final ImageProvider? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final double progress = _progress(episode);
    final String? overview = episode.overview;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double wanted = isWide(context)
                ? 280
                : MediaQuery.sizeOf(context).width * 0.48;
            final double imageWidth = wanted.clamp(
              120.0,
              constraints.maxWidth - 140,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      child: SizedBox(
                        width: imageWidth,
                        height: imageWidth * 9 / 16,
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            image == null
                                ? ColoredBox(
                                    color: palette.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.movie_outlined,
                                      size: 22,
                                      color: palette.outline,
                                    ),
                                  )
                                : Image(
                                    image: image!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color: palette.surfaceContainerHighest,
                                    ),
                                  ),
                            if (episode.userData.played)
                              Positioned(
                                top: AppSpacing.xs,
                                right: AppSpacing.xs,
                                child: Container(
                                  key: Key(
                                    'season-episode-played-${episode.id}',
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.42),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            if (progress > 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: LinearProgressIndicator(
                                  key: Key(
                                    'season-episode-progress-${episode.id}',
                                  ),
                                  value: progress,
                                  minHeight: 3,
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                          ],
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
                            '$number.${episode.name}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall!
                                .copyWith(
                                  color: palette.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          if (episode.runTimeTicks > 0) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              durationLabel(episode.duration),
                              style: Theme.of(context).textTheme.bodySmall!
                                  .copyWith(color: palette.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (overview != null && overview.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: palette.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Inline, retryable error above the content (S78).
class _InlineError extends StatelessWidget {
  const _InlineError({
    super.key,
    required this.message,
    required this.onRetry,
    required this.retryKey,
  });

  final String message;
  final VoidCallback onRetry;
  final Key retryKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.labelMedium!
                .copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
        TextButton(key: retryKey, onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

/// Full-page error with a manual retry (S78).
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              key: const Key('season-retry'),
              onPressed: () => unawaited(onRetry()),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
