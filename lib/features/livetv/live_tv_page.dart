import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/models/live_tv_channel.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loader.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';
import 'live_tv_controller.dart';

/// Live TV (S21): a channel list with logo, number, the airing program and a
/// progress bar. Tapping a channel opens the player for that channel id, so the
/// existing PlaybackInfo negotiation handles the live stream.
class LiveTvPage extends ConsumerStatefulWidget {
  const LiveTvPage({super.key});

  @override
  ConsumerState<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends ConsumerState<LiveTvPage> {
  LiveTvController? _controller;
  bool _redirecting = false;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      final liveTv = services.liveTv;
      if (liveTv == null) {
        setState(() => _fatal = '直播不可用，请稍后重试');
        return;
      }
      final controller = LiveTvController(liveTv, services.posters)
        ..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '直播加载失败，请稍后重试');
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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final state = controller?.state;

    return AppPage(
      key: const Key('livetv-page'),
      title: '直播',
      onBack: () => context.pop(),
      actions: <Widget>[
        AppIconButton(
          key: const Key('livetv-refresh'),
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: controller == null
              ? null
              : () => unawaited(controller.load()),
        ),
      ],
      child: _fatal != null
          ? _ErrorView(message: _fatal!, onRetry: _bootstrap)
          : controller == null || state == null
          ? const AppLoadingView()
          : _body(controller, state),
    );
  }

  Widget _body(LiveTvController controller, LiveTvState state) {
    if (state.error != null && state.isEmpty) {
      return _ErrorView(
        message: state.error!,
        onRetry: () => unawaited(controller.load()),
      );
    }
    if (state.loading && state.isEmpty) {
      return const AppLoadingView();
    }
    if (state.loaded && state.isEmpty) {
      return const _MessageView(message: '服务器没有可用的直播频道');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: state.channels.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (BuildContext context, int index) {
        final channel = state.channels[index];
        return _ChannelTile(
          channel: channel,
          image: controller.posterImage(
            channel.id,
            tag: channel.imageTag,
            maxWidth: 160,
          ),
          onTap: channel.id.isEmpty
              ? null
              : () => context.push(AppRoutes.playerFor(channel.id)),
        );
      },
    );
  }
}

/// One channel row: logo, name + number, the airing program and its progress.
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.image,
    required this.onTap,
  });

  final LiveTvChannel channel;
  final ImageProvider? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final program = channel.currentProgram;
    final double? progress = program?.progressAt(DateTime.now());
    final String number = channel.number ?? '';

    return AppCard(
      key: Key('livetv-channel-${channel.id}'),
      radius: AppRadii.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.extraSmall),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: ColoredBox(
                    color: palette.surfaceContainerHighest,
                    child: image == null
                        ? Icon(Icons.live_tv, size: 28, color: palette.outline)
                        : Image(
                            image: image!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.live_tv,
                              size: 28,
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
                    Row(
                      children: <Widget>[
                        if (number.isNotEmpty) ...<Widget>[
                          AppTag(
                            label: number,
                            dense: true,
                            color: palette.primary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Expanded(
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall!.copyWith(
                              color: palette.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      program == null || program.name.isEmpty
                          ? '暂无节目信息'
                          : program.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall!.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                    if (progress != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      LinearProgressIndicator(
                        key: Key('livetv-progress-${channel.id}'),
                        value: progress,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(AppRadii.capsule),
                        backgroundColor: palette.surfaceContainerHighest,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.play_circle_outline, color: palette.primary),
            ],
          ),
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
