import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/auth/auth_service.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/media_item.dart';
import 'series_controller.dart';

/// A read-only season/episode browser. Playback keeps its own detail lookup
/// and server-owned resume position.
class SeriesPage extends ConsumerStatefulWidget {
  const SeriesPage({super.key, required this.seriesId});

  final String seriesId;

  @override
  ConsumerState<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends ConsumerState<SeriesPage> {
  final Map<String, ScrollController> _episodeScrolls = {};
  SeriesController? _controller;
  AuthService? _auth;
  StreamSubscription<AuthSession?>? _session;
  bool _redirecting = false;
  bool _leaving = false;
  bool _openingPlayer = false;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_session?.cancel());
    _controller?.dispose();
    for (final scroll in _episodeScrolls.values) {
      scroll.dispose();
    }
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
    if (_openingPlayer || _redirecting || _leaving) return;
    final session = _auth?.current;
    if (session == null) {
      _toLogin();
      return;
    }
    setState(() => _openingPlayer = true);
    try {
      await context.push<void>(AppRoutes.playerFor(episode.id));
      if (!mounted ||
          _leaving ||
          _redirecting ||
          !identical(_auth?.current, session) ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      await _controller?.refreshEpisodes();
    } finally {
      if (mounted) setState(() => _openingPlayer = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller?.state;
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _leaving = true;
        } else {
          _leave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('series-back'),
            tooltip: '返回',
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            state?.series?.name ?? '剧集',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: _fatal != null
            ? _SeriesError(message: _fatal!, onRetry: _bootstrap)
            : state == null || state.loading
            ? const Center(child: CircularProgressIndicator())
            : _content(state),
      ),
    );
  }

  Widget _content(SeriesState state) {
    final controller = _controller!;
    final error = state.error;
    if (error != null) {
      return _SeriesError(message: error, onRetry: controller.load);
    }
    if (state.seasons.isEmpty) {
      return const Center(child: Text('暂无可观看的季'));
    }

    final seasonId = state.selectedSeasonId;
    final overview = state.series?.overview;
    return Column(
      children: <Widget>[
        if (overview != null && overview.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                overview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        SizedBox(
          height: 56,
          child: LayoutBuilder(
            builder: (context, constraints) => ListView.separated(
              key: const Key('series-seasons'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: state.seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final season = state.seasons[index];
                return ChoiceChip(
                  key: ValueKey('season-${season.id}'),
                  tooltip: season.name,
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (constraints.maxWidth - 96).clamp(48, 320),
                    ),
                    child: Text(
                      season.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      semanticsLabel: season.name,
                    ),
                  ),
                  selected: season.id == seasonId,
                  onSelected: (_) =>
                      unawaited(controller.selectSeason(season.id)),
                );
              },
            ),
          ),
        ),
        SizedBox(
          height: 2,
          child: state.episodesLoading
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        if (state.episodesError != null)
          _SeriesError(
            message: state.episodesError!,
            onRetry: controller.refreshEpisodes,
            compact: true,
          ),
        Expanded(
          key: ValueKey('episode-area-$seasonId'),
          child: state.episodes.isEmpty
              ? Center(
                  child: state.episodesLoading
                      ? const CircularProgressIndicator()
                      : state.episodesError == null
                      ? const Text('这一季暂无分集')
                      : const SizedBox.shrink(),
                )
              : ListView.builder(
                  key: PageStorageKey('episodes-${widget.seriesId}-$seasonId'),
                  controller: _episodeScrolls.putIfAbsent(
                    seasonId!,
                    ScrollController.new,
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: state.episodes.length,
                  itemBuilder: (context, index) {
                    final episode = state.episodes[index];
                    final title = episode.indexNumber == null
                        ? episode.name
                        : '第 ${episode.indexNumber} 集 · ${episode.name}';
                    final details = <String>[
                      if (episode.runTimeTicks > 0)
                        '时长 ${_time(episode.duration)}',
                      if (episode.userData.played) '已看',
                      if (episode.userData.positionTicks > 0)
                        '已观看 ${_time(episode.userData.position)}',
                    ];
                    return Semantics(
                      button: true,
                      label: '播放 $title',
                      child: ListTile(
                        key: ValueKey('episode-${episode.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: details.isEmpty
                            ? null
                            : Text(details.join(' · ')),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: _openingPlayer
                            ? null
                            : () => unawaited(_play(episode)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SeriesError extends StatelessWidget {
  const _SeriesError({
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  final String message;
  final Future<void> Function() onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => unawaited(onRetry()),
            child: const Text('重试'),
          ),
        ],
      ),
    );
    return compact ? content : Center(child: content);
  }
}

String _time(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return duration.inHours > 0
      ? '${duration.inHours}:$minutes:$seconds'
      : '$minutes:$seconds';
}
