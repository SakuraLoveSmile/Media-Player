import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import 'player_controller.dart';

/// Playback screen: engine surface plus the §5 control set.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  PlayerController? _controller;
  bool _redirecting = false;
  bool _leaving = false;
  String? _fatal;
  double _volume = 1;

  /// Slider value while the thumb is held, in milliseconds: seeking only
  /// happens when the drag ends (contract §10.9 c reports one seek, not one
  /// per frame).
  double? _dragMillis;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    // Single teardown point: the controller sends `Stopped` here and is
    // idempotent, so the back gesture may run it early (contract §10.9 c).
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      final controller = PlayerController(
        itemId: widget.itemId,
        library: services.library,
        playback: services.playback,
        engine: services.createEngine(),
        reporter: services.createReporter(),
      )..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '播放初始化失败，请稍后重试');
    }
  }

  /// Retrying re-negotiates the session, so it rebuilds the controller instead
  /// of calling `load()` again: the reporter latches "already stopped" after
  /// its final report, so a reused one would either leave the previous
  /// `PlaySessionId` without `Sessions/Playing/Stopped` (contract §3.6) or
  /// silence the new session. Disposing first sends that `Stopped` and frees
  /// the engine exactly once (contract §10.9 c).
  Future<void> _reload() async {
    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_onChanged);
      // Detached before disposing so `State.dispose()` cannot reach this
      // instance again.
      _controller = null;
      previous.dispose();
    }
    if (!mounted) return;
    setState(() => _fatal = null);
    await _bootstrap();
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

  void _leave() {
    if (_leaving || _redirecting) return;
    _leaving = true;
    if (context.canPop()) {
      context.pop();
    } else {
      // The library entered through `go`, so there is nothing to pop back to.
      context.go(AppRoutes.library);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop is false so the system back and the in-page button share one
      // exit path; leaving unmounts the page, which disposes the controller.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    final fatal = _fatal;
    if (fatal != null) {
      return _NoticeView(message: fatal, onBack: _leave, onRetry: _reload);
    }

    final controller = _controller;
    final state = controller?.state;
    if (controller == null || state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.unsupported) {
      return _NoticeView(
        message: state.error ?? '这个条目暂不支持播放',
        onBack: _leave,
      );
    }
    final error = state.error;
    if (error != null && !state.ready) {
      return _NoticeView(
        message: error,
        onBack: _leave,
        onRetry: _reload,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // §10.9 b: the engine owns the render widget; the page only places it.
        if (state.ready) controller.surface,
        if (state.loading)
          const Center(child: CircularProgressIndicator())
        else if (state.buffering)
          const Center(child: CircularProgressIndicator()),
        if (error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 160,
            child: _Banner(message: error, emphasis: true),
          ),
        Positioned(top: 0, left: 0, right: 0, child: _topBar(state)),
        if (state.ready)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _controlBar(controller, state),
          ),
      ],
    );
  }

  Widget _topBar(PlayerState state) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.black87, Colors.transparent],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  key: const Key('player-back'),
                  tooltip: '返回媒体库',
                  color: Colors.white,
                  onPressed: _leave,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    state.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                if (state.ready)
                  _DirectStatus(
                    videoDirect: state.videoDirect,
                    audioTranscoded: state.audioTranscoded,
                  ),
              ],
            ),
            if (state.resumedFrom != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: _Banner(
                  key: const Key('player-resume-hint'),
                  message: '已从 ${formatPlaybackTime(state.resumedFrom!)} 继续播放',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controlBar(PlayerController controller, PlayerState state) {
    final theme = Theme.of(context);
    final total = state.duration;
    final max =
        total > Duration.zero ? total.inMilliseconds.toDouble() : 1.0;
    final value = (_dragMillis ?? state.position.inMilliseconds.toDouble())
        .clamp(0.0, max);
    final shown = _dragMillis == null
        ? state.position
        : Duration(milliseconds: _dragMillis!.round());

    final progress = Slider(
      key: const Key('player-progress'),
      value: value,
      max: max,
      label: formatPlaybackTime(shown),
      onChanged: total > Duration.zero
          ? (next) => setState(() => _dragMillis = next)
          : null,
      onChangeEnd: total > Duration.zero
          ? (next) {
              setState(() => _dragMillis = null);
              unawaited(
                controller.seekTo(Duration(milliseconds: next.round())),
              );
            }
          : null,
    );

    final volume = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          _volume == 0 ? Icons.volume_off : Icons.volume_up,
          color: Colors.white70,
          size: 20,
        ),
        SizedBox(
          width: 120,
          child: Slider(
            key: const Key('player-volume'),
            value: _volume,
            label: '音量 ${(_volume * 100).round()}%',
            onChanged: (next) {
              setState(() => _volume = next);
              unawaited(controller.setVolume(next));
            },
          ),
        ),
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Colors.black87],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 12, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final time = Text(
              '${formatPlaybackTime(shown)} / ${formatPlaybackTime(total)}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
            );
            final toggle = IconButton(
              key: const Key('player-play-toggle'),
              tooltip: state.playing ? '暂停' : '播放',
              color: Colors.white,
              iconSize: 32,
              onPressed: () => unawaited(controller.togglePlayPause()),
              icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
            );

            // Narrow windows and phones get the volume on its own line.
            if (constraints.maxWidth < 520) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  progress,
                  Row(
                    children: <Widget>[
                      toggle,
                      time,
                      const Spacer(),
                      volume,
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: <Widget>[
                toggle,
                time,
                Expanded(child: progress),
                volume,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Direct-play verdict from §10.9 f: `null` is "unconfirmed", never "direct".
class _DirectStatus extends StatelessWidget {
  const _DirectStatus({required this.videoDirect, required this.audioTranscoded});

  final bool? videoDirect;
  final bool audioTranscoded;

  @override
  Widget build(BuildContext context) {
    final (String message, bool emphasis) = switch (videoDirect) {
      false => ('服务器正在转码，未直连', true),
      true => (audioTranscoded ? '直连播放（音频转码）' : '直连播放', false),
      null => ('直连状态未确认', false),
    };

    return _Banner(
      key: const Key('player-direct-status'),
      message: message,
      emphasis: emphasis,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.message, this.emphasis = false});

  final String message;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: emphasis ? scheme.errorContainer : Colors.white24,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        message,
        style: theme.textTheme.labelMedium?.copyWith(
          color: emphasis ? scheme.onErrorContainer : Colors.white,
        ),
      ),
    );
  }
}

class _NoticeView extends StatelessWidget {
  const _NoticeView({required this.message, required this.onBack, this.onRetry});

  final String message;
  final VoidCallback onBack;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;

    return Center(
      key: const Key('player-error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: <Widget>[
                OutlinedButton(
                  key: const Key('player-back'),
                  onPressed: onBack,
                  child: const Text('返回'),
                ),
                if (retry != null)
                  FilledButton(
                    onPressed: () => unawaited(retry()),
                    child: const Text('重试'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `mm:ss`, widened to `hh:mm:ss` only for long items.
String formatPlaybackTime(Duration value) {
  final total = value.isNegative ? Duration.zero : value;
  final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (total.inHours > 0) {
    return '${total.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
