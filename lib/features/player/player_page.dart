import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../ui/glass/glass_controls.dart';
import '../../ui/glass/glass_surface.dart';
import '../../ui/glass/glass_theme.dart';
import '../../ui/glass/glass_tokens.dart';
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
    // Also covers exits that bypass _leave; an earlier stop is idempotent.
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

  Future<void> _leave() async {
    if (_leaving || _redirecting) return;
    _leaving = true;
    // Report before pop to avoid Video teardown zeroing the position first.
    await _controller?.stop();
    if (!mounted || _redirecting) return;
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
    final GlassPalette palette = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GlassSpacing.sm,
        GlassSpacing.sm,
        GlassSpacing.sm,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GlassSurface(
            radius: GlassRadii.cardLarge,
            blur: 28,
            padding: const EdgeInsets.fromLTRB(
              GlassSpacing.xs,
              GlassSpacing.xs,
              GlassSpacing.md,
              GlassSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                IconButton(
                  key: const Key('player-back'),
                  tooltip: '返回媒体库',
                  color: palette.label,
                  onPressed: _leave,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    state.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GlassType.headline.copyWith(color: palette.label),
                  ),
                ),
                if (state.ready) ...<Widget>[
                  const SizedBox(width: GlassSpacing.sm),
                  _DirectStatus(
                    videoDirect: state.videoDirect,
                    audioTranscoded: state.audioTranscoded,
                  ),
                ],
              ],
            ),
          ),
          if (state.resumedFrom != null)
            Padding(
              padding: const EdgeInsets.only(
                left: GlassSpacing.lg,
                top: GlassSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _Banner(
                  key: const Key('player-resume-hint'),
                  message: '已从 ${formatPlaybackTime(state.resumedFrom!)} 继续播放',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controlBar(PlayerController controller, PlayerState state) {
    final Duration total = state.duration;
    final double max =
        total > Duration.zero ? total.inMilliseconds.toDouble() : 1.0;
    final double value =
        (_dragMillis ?? state.position.inMilliseconds.toDouble())
            .clamp(0.0, max);
    final Duration shown = _dragMillis == null
        ? state.position
        : Duration(milliseconds: _dragMillis!.round());

    final SliderThemeData sliderTheme = SliderTheme.of(context).copyWith(
      activeTrackColor: Colors.white.withValues(alpha: 0.92),
      inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
      thumbColor: Colors.white,
      overlayColor: Colors.white.withValues(alpha: 0.12),
      trackHeight: 4.5,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
    );

    final Widget progress = SliderTheme(
      data: sliderTheme,
      child: Slider(
        key: const Key('player-progress'),
        value: value,
        max: max,
        label: formatPlaybackTime(shown),
        onChanged: total > Duration.zero
            ? (double next) => setState(() => _dragMillis = next)
            : null,
        onChangeEnd: total > Duration.zero
            ? (double next) {
                setState(() => _dragMillis = null);
                unawaited(
                  controller.seekTo(Duration(milliseconds: next.round())),
                );
              }
            : null,
      ),
    );

    final Widget volume = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          _volume == 0 ? Icons.volume_off : Icons.volume_up,
          color: Colors.white.withValues(alpha: 0.75),
          size: 18,
        ),
        SizedBox(
          width: 116,
          child: SliderTheme(
            data: sliderTheme,
            child: Slider(
              key: const Key('player-volume'),
              value: _volume,
              label: '音量 ${(_volume * 100).round()}%',
              onChanged: (double next) {
                setState(() => _volume = next);
                unawaited(controller.setVolume(next));
              },
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GlassSpacing.sm,
        0,
        GlassSpacing.sm,
        GlassSpacing.sm,
      ),
      child: GlassSurface(
        radius: GlassRadii.sheet,
        blur: 30,
        tintColor: const Color(0xFF1C1C1E),
        tintOpacity: 0.42,
        padding: const EdgeInsets.fromLTRB(
          GlassSpacing.lg,
          GlassSpacing.xs,
          GlassSpacing.lg,
          GlassSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            progress,
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget time = Text(
                  '${formatPlaybackTime(shown)} / ${formatPlaybackTime(total)}',
                  style: GlassType.caption1.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                );
                final Widget toggle = IconButton(
                  key: const Key('player-play-toggle'),
                  tooltip: state.playing ? '暂停' : '播放',
                  color: Colors.white,
                  iconSize: 34,
                  onPressed: () => unawaited(controller.togglePlayPause()),
                  icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
                );

                // Narrow windows and phones get the volume on its own line.
                if (constraints.maxWidth < 520) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          toggle,
                          const SizedBox(width: GlassSpacing.sm),
                          time,
                          const Spacer(),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: volume,
                      ),
                    ],
                  );
                }

                return Row(
                  children: <Widget>[
                    toggle,
                    const SizedBox(width: GlassSpacing.sm),
                    time,
                    const Spacer(),
                    volume,
                  ],
                );
              },
            ),
          ],
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
    final GlassPalette palette = context.glass;
    return GlassSurface(
      radius: GlassRadii.capsule,
      blur: 16,
      tintColor: emphasis ? palette.red : Colors.white,
      tintOpacity: emphasis ? 0.3 : 0.16,
      border: false,
      shadow: false,
      padding: const EdgeInsets.symmetric(
        horizontal: GlassSpacing.md,
        vertical: GlassSpacing.xs,
      ),
      child: Text(
        message,
        style: GlassType.caption1.copyWith(
          color: emphasis ? const Color(0xFFFFD9D6) : Colors.white,
          fontWeight: FontWeight.w600,
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
    final Future<void> Function()? retry = onRetry;
    final GlassPalette palette = context.glass;

    return Center(
      key: const Key('player-error'),
      child: Padding(
        padding: const EdgeInsets.all(GlassSpacing.xxxl),
        child: GlassSurface(
          radius: GlassRadii.cardLarge,
          blur: 28,
          padding: const EdgeInsets.all(GlassSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                color: palette.secondaryLabel,
                size: 28,
              ),
              const SizedBox(height: GlassSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GlassType.body.copyWith(color: palette.label),
              ),
              const SizedBox(height: GlassSpacing.xl),
              Wrap(
                spacing: GlassSpacing.md,
                runSpacing: GlassSpacing.sm,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  GlassButton(
                    key: const Key('player-back'),
                    label: '返回',
                    variant: GlassButtonVariant.glass,
                    onPressed: onBack,
                  ),
                  if (retry != null)
                    GlassButton(
                      label: '重试',
                      onPressed: () => unawaited(retry()),
                    ),
                ],
              ),
            ],
          ),
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
