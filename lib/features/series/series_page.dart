import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/auth/auth_service.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/media_item.dart';
import '../../data/models/person.dart';
import '../../ui/app_bottom_nav.dart';
import '../../ui/app_loader.dart';
import '../../ui/nav_visibility.dart';
import '../../ui/poster_card.dart';
import '../../ui/responsive.dart';
import '../../ui/theme/app_tokens.dart';
import 'series_controller.dart';
import 'series_widgets.dart';

/// Series detail (S78), laid out like Yamby's: a full-bleed backdrop with the
/// floating action bar on top, the rating/season pills and genre chips on the
/// hero's gradient, the resume row, the overview, 继续观看, 季, 演员, 艺术图,
/// 工作室, 外部链接 and 推荐.
class SeriesPage extends ConsumerStatefulWidget {
  const SeriesPage({super.key, required this.seriesId, this.urlOpener});

  final String seriesId;

  /// Injectable external-link launcher (widget tests); production keeps
  /// url_launcher.
  final Future<bool> Function(Uri url)? urlOpener;

  @override
  ConsumerState<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends ConsumerState<SeriesPage> {
  final ScrollController _scroll = ScrollController();
  final ScrollController _continueScroll = ScrollController();
  SeriesController? _controller;
  AuthService? _auth;
  StreamSubscription<AuthSession?>? _session;
  bool _redirecting = false;
  bool _leaving = false;
  bool _openingPlayer = false;
  bool _barOpaque = false;
  String? _fatal;

  /// The player replaces itself with the next episode, which never completes
  /// the push future (S78 device fix): the busy state is unlocked by a timer
  /// and the page polls for becoming current again to refresh the resume data.
  Timer? _busyUnlock;
  Timer? _playbackWatch;
  bool _returnHandled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // A page entered after a scrolled page must show the capsule navigation
    // again instead of inheriting its hidden state (S78 device fix).
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
    _continueScroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_controller != null) return;
    setState(() => _fatal = null);
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted || _leaving) return;
      _auth = services.auth;
      _session = services.auth.session.listen((session) {
        if (session == null) _toLogin();
      });
      if (services.auth.current == null) {
        _toLogin();
        return;
      }
      final controller = SeriesController(
        seriesId: widget.seriesId,
        library: services.library,
        posters: services.posters,
        urlOpener: widget.urlOpener,
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
    // Session stream events can arrive while no frame is scheduled (for
    // example, while a paused player covers this page).
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onChanged() {
    if (_controller?.state.unauthorized ?? false) {
      _toLogin();
      return;
    }
    if (mounted) setState(() {});
  }

  /// The floating bar turns opaque once the hero has scrolled behind it.
  void _onScroll() {
    if (!mounted || !_scroll.hasClients) return;
    final bool next = _scroll.offset > _heroHeight(context) - 120;
    if (next != _barOpaque) setState(() => _barOpaque = next);
  }

  /// Yamby's series hero is about 1.05x the screen width (S78).
  double _heroHeight(BuildContext context) =>
      isWide(context) ? 460 : MediaQuery.sizeOf(context).width * 1.05;

  void _leave() {
    if (_leaving || _redirecting) return;
    _leaving = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.library);
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

  /// Watches the route becoming current again, so the resume data refreshes
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

  Future<void> _openEpisodePicker(SeriesState state) async {
    final MediaItem? season = state.selectedSeason;
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

  void _openSeason(MediaItem season) {
    if (_openingPlayer) return;
    unawaited(
      context.push<void>(
        AppRoutes.seasonFor(season.id, seriesId: widget.seriesId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SeriesState? state = _controller?.state;
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
        key: const Key('series-page'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        // The capsule navigation floats over the content, like the home page.
        extendBody: true,
        body: _fatal != null
            ? _errorBody(
                message: _fatal!,
                onRetry: _bootstrap,
                backKey: const Key('series-back'),
              )
            : state == null || (state.series == null && state.loading)
            ? const AppLoadingView()
            : state.series == null
            ? _errorBody(
                message: state.error ?? '剧集加载失败，请稍后重试',
                onRetry: () => _controller!.load(),
                backKey: const Key('series-back'),
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

  Widget _content(SeriesState state) {
    final List<Widget> children = <Widget>[
      _hero(state),
      // A thin loading bar keeps the old rows on screen while the next season
      // request is in flight.
      SizedBox(
        height: 2,
        child: state.episodesLoading
            ? const LinearProgressIndicator(
                key: Key('series-episodes-loading'),
                minHeight: 2,
              )
            : null,
      ),
      ..._playBlock(state),
      ..._overview(state),
      ..._writeError(state),
      if (state.continueWatchingEpisodes.isNotEmpty)
        ..._continueWatching(state),
      if (state.seasons.isNotEmpty) ..._seasons(state),
      if (state.series != null && state.series!.people.isNotEmpty)
        ..._cast(state),
      if (state.series != null && state.series!.backdropTags.length > 1)
        ..._artwork(state),
      if (state.series != null && state.series!.studios.isNotEmpty)
        ..._studios(state),
      if (state.series != null && state.series!.externalUrls.isNotEmpty)
        ..._externalLinks(state),
      if (state.similar.isNotEmpty) ..._similar(state),
      const SizedBox(height: 96),
    ];
    final Widget list = ListView(
      key: const Key('series-scroll'),
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
                    key: const Key('series-wide-content'),
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

  Widget _topBar(SeriesState state) {
    final MediaItem? series = state.series;
    final Widget bar = SeriesTopBar(
      title: series?.name ?? '剧集',
      opaque: _barOpaque,
      played: series?.userData.played ?? false,
      favorite: series?.userData.isFavorite ?? false,
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

  Widget _hero(SeriesState state) {
    final MediaItem series = state.series!;
    final ColorScheme palette = Theme.of(context).colorScheme;
    final SeriesController controller = _controller!;
    final ImageProvider? art =
        controller.backdropImage(series, maxWidth: 1200) ??
        controller.posterImage(series.id, tag: series.imageTag, maxWidth: 780);
    // Yamby mixes the metadata styles (S78): the rating is a light-blue star
    // with white digits, the official rating and the season count are
    // light-blue outlined pills, and the year range is plain white text.
    final List<Widget> metadata = <Widget>[
      if (series.communityRating != null)
        Row(
          key: const Key('series-rating'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.star_rounded, size: 18, color: palette.primary),
            const SizedBox(width: 3),
            Text(
              series.communityRating!.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      if ((series.officialRating ?? '').isNotEmpty)
        _HeroPill(
          key: const Key('series-official-rating'),
          borderColor: palette.primary,
          child: _heroMetaText(series.officialRating!),
        ),
      if (series.yearLabel != null)
        Text(
          series.yearLabel!,
          key: const Key('series-year'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      if (state.seasons.isNotEmpty)
        _HeroPill(
          key: const Key('series-season-count'),
          borderColor: palette.primary,
          child: _heroMetaText('共 ${state.seasons.length} 季'),
        ),
    ];
    return SizedBox(
      key: const Key('series-hero'),
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
          // Top scrim keeps the white bar icons readable on bright artwork.
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (metadata.isNotEmpty)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: metadata,
                  ),
                if (series.genres.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: <Widget>[
                      for (final String genre in series.genres.take(6))
                        InkWell(
                          key: Key('series-genre-$genre'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => context.push(
                            AppRoutes.libraryFor('', genre: genre),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              // Deep navy chip with light-blue copy (S78).
                              color: palette.primary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              genre,
                              style: Theme.of(context).textTheme.labelMedium!
                                  .copyWith(
                                    color: palette.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _heroMetaText(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );

  /// The resume/play row (S78): a wide progress-filled button plus the 选集
  /// chevron, then the current episode S1E2：… line.
  List<Widget> _playBlock(SeriesState state) {
    final MediaItem? target = state.playTarget;
    final MediaItem? season = state.selectedSeason;
    final bool hasEpisodes = state.episodes.isNotEmpty;
    final List<Widget> rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          0,
        ),
        child: state.seasons.isEmpty
            ? Text(
                '暂无可观看的季',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : state.episodes.isEmpty && !state.episodesLoading
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
                      key: const Key('series-play'),
                      label: _playLabel(state, target),
                      progress: target == null ? 0 : _progress(target),
                      onPressed: _openingPlayer || !hasEpisodes
                          ? null
                          : () => unawaited(_play(target!)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SeriesPickerButton(
                    key: const Key('series-episodes'),
                    onPressed: _openingPlayer || !hasEpisodes
                        ? null
                        : () => unawaited(_openEpisodePicker(state)),
                  ),
                ],
              ),
      ),
    ];
    if (target != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Text(
            episodeLabel(target, seasonNumber: season?.indexNumber),
            key: const Key('series-current-episode'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
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
            key: const Key('series-episodes-error'),
            message: state.episodesError!,
            onRetry: () => unawaited(_controller!.refreshEpisodes()),
            retryKey: const Key('series-episodes-retry'),
          ),
        ),
      );
    }
    return rows;
  }

  /// 已播放 / 继续 (剩余: …) / 播放 (S78), with the remaining time of the
  /// episode the button will resume.
  String _playLabel(SeriesState state, MediaItem? target) {
    if (state.watched) return '已播放';
    if (target == null) return '播放';
    final bool resumable =
        !target.userData.played && target.userData.positionTicks > 0;
    if (!resumable) return '播放';
    final Duration remaining = target.duration - target.userData.position;
    return '继续 (剩余: ${durationLabel(remaining.isNegative ? Duration.zero : remaining)})';
  }

  List<Widget> _overview(SeriesState state) {
    final String? overview = state.series?.overview;
    if (overview == null || overview.trim().isEmpty) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
        child: Text(
          overview,
          key: const Key('series-overview'),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ),
    ];
  }

  List<Widget> _writeError(SeriesState state) {
    final String? message = state.writeError;
    if (message == null) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        child: Text(
          message,
          key: const Key('series-write-error'),
          style: Theme.of(context).textTheme.labelMedium!
              .copyWith(color: Theme.of(context).colorScheme.error),
        ),
      ),
    ];
  }

  /// 继续观看 (S78): the current season's unfinished episodes plus the next
  /// unstarted one Yamby previews after them, at most four cards. Two cards are
  /// visible per screen; a card without progress shows the episode duration
  /// instead of the remaining time.
  List<Widget> _continueWatching(SeriesState state) {
    final MediaItem? season = state.selectedSeason;
    final List<MediaItem> episodes = state.continueWatchingEpisodes;
    final List<Widget> cards = <Widget>[
      for (final MediaItem episode in episodes)
        _ResumeCard(
          key: Key('series-resume-${episode.id}'),
          episode: episode,
          label: episodeLabel(episode, seasonNumber: season?.indexNumber),
          pillLabel: _resumePillLabel(episode),
          progress: _progress(episode),
          image: _controller!.episodeImage(episode),
          width: _continueCardWidth(context),
          onTap: _openingPlayer ? null : () => unawaited(_play(episode)),
        ),
    ];
    return <Widget>[
      SeriesSectionHeader(
        '继续观看',
        keyPrefix: 'series-continue',
        onPrevious: () => _page(_continueScroll, -1),
        onNext: () => _page(_continueScroll, 1),
        onSeasons: season == null ? null : () => _openSeason(season),
      ),
      _horizontalRow(
        key: const Key('series-resumable'),
        controller: _continueScroll,
        children: cards,
      ),
    ];
  }

  List<Widget> _seasons(SeriesState state) {
    final Map<String, int> counts = state.seasonCounts;
    final List<Widget> cards = <Widget>[
      for (final MediaItem season in state.seasons)
        _SeasonCard(
          key: Key('season-${season.id}'),
          season: season,
          label: seasonLabel(season),
          count: counts[season.id],
          image: _controller!.posterImage(
            season.id,
            tag: season.imageTag,
            maxWidth: 220,
          ),
          onTap: _openingPlayer ? null : () => _openSeason(season),
        ),
    ];
    return <Widget>[
      const SeriesSectionHeader('季'),
      _horizontalRow(key: const Key('series-seasons'), children: cards),
    ];
  }

  List<Widget> _cast(SeriesState state) {
    final List<Person> people = state.series!.people;
    final List<Widget> cards = <Widget>[
      for (final Person person in people)
        _CastCard(
          key: person.id == null || person.id!.isEmpty
              ? null
              : Key('series-person-${person.id}'),
          person: person,
          image: _controller!.personImage(person),
          onTap: person.id == null || person.id!.isEmpty
              ? null
              : () => context.push(
                  AppRoutes.personFor(person.id!, name: person.name),
                ),
        ),
    ];
    return <Widget>[
      const SeriesSectionHeader('演员'),
      _horizontalRow(key: const Key('series-cast'), children: cards),
    ];
  }

  List<Widget> _artwork(SeriesState state) {
    final MediaItem series = state.series!;
    final List<Widget> tiles = <Widget>[
      for (int index = 0; index < series.backdropTags.length; index++)
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: SizedBox(
            width: 200,
            height: 200 * 9 / 16,
            child: _Artwork(
              image: _controller!.backdropImage(
                series,
                index: index,
                maxWidth: 420,
              ),
            ),
          ),
        ),
    ];
    return <Widget>[
      const SeriesSectionHeader('艺术图'),
      _horizontalRow(key: const Key('series-artwork'), children: tiles),
    ];
  }

  List<Widget> _studios(SeriesState state) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return <Widget>[
      const SeriesSectionHeader('工作室'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final NamedLink studio in state.series!.studios)
              InkWell(
                key: Key('series-studio-${studio.name}'),
                borderRadius: BorderRadius.circular(AppRadii.control),
                onTap: () => context.push(
                  AppRoutes.libraryFor(
                    '',
                    studioId: studio.target,
                    studioName: studio.name,
                  ),
                ),
                child: Text(
                  studio.name,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: palette.onSurface,
                    decoration: TextDecoration.underline,
                    decorationColor: palette.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _externalLinks(SeriesState state) {
    return <Widget>[
      const SeriesSectionHeader('外部链接'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final NamedLink link in state.series!.externalUrls)
              if (link.target != null)
                OutlinedButton.icon(
                  key: Key('series-link-${link.name}'),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: () =>
                      unawaited(_controller!.openLink(link.target!)),
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(link.name),
                ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _similar(SeriesState state) {
    final List<Widget> cards = <Widget>[
      for (final MediaItem similar in state.similar)
        SizedBox(
          width: 120,
          height: 232,
          child: PosterCard(
            key: Key('series-similar-${similar.id}'),
            name: similar.name,
            played: similar.userData.played,
            rating: similar.communityRating,
            unplayedCount: similar.userData.unplayedItemCount,
            subtitle: similar.yearLabel,
            centerTitle: true,
            image: _controller!.posterImage(
              similar.id,
              tag: similar.imageTag,
              maxWidth: 260,
            ),
            onTap: similar.id.isEmpty
                ? null
                : () => similar.type == 'Series'
                      ? context.push(AppRoutes.seriesFor(similar.id))
                      : context.push(AppRoutes.detailFor(similar.id)),
          ),
        ),
    ];
    return <Widget>[
      const SeriesSectionHeader('推荐'),
      _horizontalRow(key: const Key('series-similar'), children: cards),
    ];
  }

  /// Horizontal strip with intrinsic height, so text scaling never clips the
  /// labels under a card.
  Widget _horizontalRow({
    Key? key,
    ScrollController? controller,
    required List<Widget> children,
  }) {
    return SingleChildScrollView(
      key: key,
      controller: controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int index = 0; index < children.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(width: AppSpacing.md),
            children[index],
          ],
        ],
      ),
    );
  }

  void _page(ScrollController controller, int direction) {
    if (!controller.hasClients) return;
    final double page = MediaQuery.sizeOf(context).width * 0.8;
    final double target = (controller.offset + page * direction).clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    unawaited(
      controller.animateTo(
        target,
        duration: AppMotion.base,
        curve: AppMotion.standard,
      ),
    );
  }
}

/// Continue-watching card width: about 46% of the screen so two fit (S78).
double _continueCardWidth(BuildContext context) {
  if (isWide(context)) return 300;
  return MediaQuery.sizeOf(context).width * 0.46;
}

/// The pill on a 继续观看 card: remaining time for an in-progress episode, the
/// full duration for the next unstarted one, null when neither is known (S78).
String? _resumePillLabel(MediaItem episode) {
  if (!episode.userData.played &&
      episode.userData.positionTicks > 0 &&
      episode.runTimeTicks > 0) {
    final Duration remaining = episode.duration - episode.userData.position;
    return '剩余: ${durationLabel(remaining.isNegative ? Duration.zero : remaining)}';
  }
  if (episode.runTimeTicks > 0) return durationLabel(episode.duration);
  return null;
}

/// Episode progress as a 0..1 fraction; 0 for finished or unmeasured episodes.
double _progress(MediaItem episode) {
  if (episode.userData.played || episode.runTimeTicks <= 0) return 0;
  return (episode.userData.positionTicks / episode.runTimeTicks).clamp(
    0.0,
    1.0,
  );
}

/// A bordered metadata pill on the hero gradient (S78). Yamby outlines the
/// official rating and the season count in the accent colour.
class _HeroPill extends StatelessWidget {
  const _HeroPill({super.key, required this.child, required this.borderColor});

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(AppRadii.capsule),
      ),
      child: child,
    );
  }
}

/// 继续观看 card: 16:9 still, a remaining-time/duration pill, S1E2：title and
/// the 2-line overview (S78).
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    super.key,
    required this.episode,
    required this.label,
    required this.pillLabel,
    required this.progress,
    required this.image,
    required this.width,
    required this.onTap,
  });

  final MediaItem episode;
  final String label;

  /// Remaining time when started, the duration for the next unstarted episode.
  final String? pillLabel;
  final double progress;
  final ImageProvider? image;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    image == null
                        ? ColoredBox(
                            color: palette.surfaceContainerHighest,
                            child: Icon(
                              Icons.movie_outlined,
                              size: 20,
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
                    if (pillLabel != null)
                      Positioned(
                        left: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pillLabel!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    if (progress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.black.withValues(alpha: 0.4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (episode.overview != null && episode.overview!.trim().isNotEmpty)
              Text(
                episode.overview!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// Season poster card: 73x113 artwork, episode-count badge, 第 N 季 (S78).
class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    super.key,
    required this.season,
    required this.label,
    required this.count,
    required this.image,
    required this.onTap,
  });

  final MediaItem season;
  final String label;
  final int? count;
  final ImageProvider? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return SizedBox(
      width: 73,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.extraSmall),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.extraSmall),
              child: SizedBox(
                width: 73,
                height: 113,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    image == null
                        ? ColoredBox(
                            color: palette.surfaceContainerHighest,
                            child: Icon(
                              Icons.tv_outlined,
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
                    if (count != null && count! > 0)
                      Positioned(
                        top: AppSpacing.xs,
                        right: AppSpacing.xs,
                        child: Container(
                          key: Key('season-count-${season.id}'),
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(
                              AppRadii.capsule,
                            ),
                          ),
                          child: Text(
                            '$count',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
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
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium!
                  .copyWith(color: palette.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cast card: rounded portrait, name, role and the server's person type (S78).
class _CastCard extends StatelessWidget {
  const _CastCard({
    super.key,
    required this.person,
    required this.image,
    required this.onTap,
  });

  final Person person;
  final ImageProvider? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final String role = person.role ?? '';
    final String type = person.type ?? '';
    return SizedBox(
      width: 104,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: SizedBox(
                width: 104,
                height: 132,
                child: image == null
                    ? ColoredBox(
                        color: palette.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          size: 28,
                          color: palette.outline,
                        ),
                      )
                    : Image(
                        image: image!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: palette.surfaceContainerHighest),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (role.isNotEmpty)
              Text(
                role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
            if (type.isNotEmpty)
              Text(
                type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall!
                    .copyWith(color: palette.outline),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wide artwork tile for the 艺术图 row.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.image});

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    if (image == null) {
      return ColoredBox(
        color: palette.surfaceContainerHighest,
        child: Icon(Icons.image_outlined, color: palette.outline),
      );
    }
    return Image(
      image: image!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          ColoredBox(color: palette.surfaceContainerHighest),
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
              key: const Key('series-retry'),
              onPressed: () => unawaited(onRetry()),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
