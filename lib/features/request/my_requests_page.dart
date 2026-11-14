import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/moviepilot_providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/moviepilot/models/media_request.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loader.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';
import 'request_controller.dart';
import 'request_state.dart';
import 'widgets/my_requests_list.dart';

/// 「我的求片」: the progress list on its own page.
///
/// Reached from the search page after a successful 求片, from the request page
/// toolbar, and from settings; it renders the shared [RequestController] and
/// owns the heartbeat while it is the visible page.
class MyRequestsPage extends ConsumerStatefulWidget {
  const MyRequestsPage({super.key});

  @override
  ConsumerState<MyRequestsPage> createState() => _MyRequestsPageState();
}

class _MyRequestsPageState extends ConsumerState<MyRequestsPage> {
  RequestController? _controller;
  ProviderSubscription<AsyncValue<RequestController?>>? _subscription;

  @override
  void initState() {
    super.initState();
    // The controller is a FutureProvider; listen so the page rebuilds when it
    // finishes loading instead of only pumping once.
    _subscription = ref.listenManual<AsyncValue<RequestController?>>(
      requestControllerProvider,
      (_, _) => _attach(),
      fireImmediately: true,
    );
  }

  void _attach() {
    final controller = ref.read(requestControllerProvider).value;
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onChanged);
    _controller = controller;
    controller?.addListener(_onChanged);
    // The app owns the heartbeat; this only requests a fresh round so the
    // page shows current progress on entry.
    unawaited(controller?.startWatching());
    if (mounted) setState(() {});
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _subscription?.close();
    // The heartbeat belongs to the app, so leaving this page keeps it running.
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  void _play(MediaRequest request) {
    final itemId = request.embyItemId;
    if (itemId == null || itemId.isEmpty) {
      context.go(AppRoutes.library);
      return;
    }
    if (request.isSeries) {
      // A series id has no playable source of its own: open the episode picker.
      context.push(AppRoutes.seriesFor(itemId));
      return;
    }
    context.push(AppRoutes.playerFor(itemId));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final state = controller?.state;
    final ColorScheme palette = Theme.of(context).colorScheme;

    return AppPage(
      title: '我的求片',
      onBack: () => context.pop(),
      actions: <Widget>[
        AppIconButton(
          key: const Key('my-requests-refresh'),
          tooltip: '刷新进度',
          icon: const Icon(Icons.refresh),
          onPressed: controller == null
              ? null
              : () => unawaited(controller.refresh()),
        ),
      ],
      child: controller == null || state == null
          ? const AppLoadingView()
          : _content(controller, state, palette),
    );
  }

  Widget _content(
    RequestController controller,
    RequestState state,
    ColorScheme palette,
  ) {
    if (state.requests.isEmpty) {
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
                  Icons.playlist_add_outlined,
                  size: 32,
                  color: palette.outline,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '还没有求片',
                  key: const Key('my-requests-empty'),
                  style: Theme.of(context).textTheme.bodyLarge!
                      .copyWith(color: palette.onSurface),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '在求片页搜索片名后点“求片”，进度会显示在这里。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  key: const Key('my-requests-to-search'),
                  label: '去求片',
                  onPressed: () => context.go(AppRoutes.request),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: <Widget>[
          if (state.polling) ...<Widget>[
            Text(
              '同步中…',
              key: const Key('my-requests-syncing'),
              style: Theme.of(context).textTheme.labelMedium!
                  .copyWith(color: palette.outline),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (state.pollError != null) ...<Widget>[
            AppTag(
              key: const Key('my-requests-error'),
              label: state.pollError!,
              color: Colors.orange,
              icon: const Icon(Icons.error_outline),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          MyRequestsList(
            requests: state.requests,
            busyIds: state.busyRequestIds,
            onSearchNow: (request) => unawaited(controller.searchNow(request)),
            onCancel: (request) => unawaited(controller.cancel(request)),
            onPlay: _play,
          ),
        ],
      ),
    );
  }
}
