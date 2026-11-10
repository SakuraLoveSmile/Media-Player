import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/moviepilot_providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/moviepilot/models/media_request.dart';
import '../../data/moviepilot/models/mp_media_info.dart';
import '../../ui/glass/glass_controls.dart';
import '../../ui/glass/glass_shell.dart';
import '../../ui/glass/glass_surface.dart';
import '../../ui/glass/glass_theme.dart';
import '../../ui/glass/glass_tokens.dart';
import 'request_controller.dart';
import 'request_state.dart';
import 'widgets/search_result_card.dart';

/// 求片: search MoviePilot and subscribe (plan S11/S12).
///
/// Searching is all this page does; the progress list lives on its own page
/// (`/request/mine`) so a fresh request is not buried under the search results.
/// The controller is shared with that page, and this one keeps the heartbeat
/// alive only while it is visible.
class RequestPage extends ConsumerStatefulWidget {
  const RequestPage({super.key, this.heartbeat, this.pollInterval});

  /// Overrides the poll heartbeat. Widget tests pass an empty stream so the
  /// page makes no scheduled requests; production uses the default periodic one.
  final Stream<void>? heartbeat;

  /// Fallback cadence when [heartbeat] is null.
  final Duration? pollInterval;

  @override
  ConsumerState<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends ConsumerState<RequestPage> {
  final TextEditingController _query = TextEditingController();
  RequestController? _controller;
  ProviderSubscription<AsyncValue<RequestController?>>? _subscription;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _subscription?.close();
    _query.dispose();
    // The controller and its heartbeat outlive this page: the app-level wiring
    // owns the poll so a 求片 finishing off-screen can still notify. Leaving
    // only detaches this listener.
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _fatal = null);
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
    // The heartbeat is started by the app, not by this page; asking for a round
    // here just makes the page look alive on entry.
    unawaited(controller?.startWatching());
    if (!mounted) return;
    if (controller == null) {
      setState(() => _fatal = '无法读取本地存储，请重启 App 后重试');
    } else {
      setState(() => _fatal = null);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _search() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.search(_query.text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final state = controller?.state;
    final GlassPalette palette = context.glass;

    return GlassPage(
      title: '求片',
      onBack: () => context.pop(),
      actions: <Widget>[
        GlassIconButton(
          key: const Key('request-open-mine-top'),
          tooltip: '我的求片',
          icon: const Icon(Icons.downloading_outlined),
          onPressed: _openMine,
        ),
        GlassIconButton(
          key: const Key('request-settings'),
          tooltip: 'MoviePilot 设置',
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
            : RefreshIndicator(
                onRefresh: controller.refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    GlassSpacing.lg,
                    GlassSpacing.md,
                    GlassSpacing.lg,
                    GlassSpacing.xxxl,
                  ),
                  children: <Widget>[
                    _searchBar(state, palette),
                    if (state.polling) ...<Widget>[
                      const SizedBox(height: GlassSpacing.sm),
                      Text(
                        '同步中…',
                        key: const Key('request-syncing'),
                        style: GlassType.caption1.copyWith(
                          color: palette.tertiaryLabel,
                        ),
                      ),
                    ],
                    ..._body(controller, state, palette),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _searchBar(RequestState state, GlassPalette palette) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: const Key('request-search-field'),
            controller: _query,
            enabled: state.configured,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_search()),
            decoration: const InputDecoration(
              hintText: '搜索片名',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: GlassSpacing.sm),
        GlassButton(
          key: const Key('request-search-button'),
          label: '搜索',
          loading: state.searching,
          height: 44,
          onPressed: state.configured && !state.searching
              ? () => unawaited(_search())
              : null,
        ),
      ],
    );
  }

  List<Widget> _body(
    RequestController controller,
    RequestState state,
    GlassPalette palette,
  ) {
    if (state.needsConfiguration) {
      return <Widget>[
        const SizedBox(height: GlassSpacing.xxl),
        GlassSurface(
          radius: GlassRadii.cardLarge,
          padding: const EdgeInsets.all(GlassSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.cloud_off_outlined,
                size: 32,
                color: palette.tertiaryLabel,
              ),
              const SizedBox(height: GlassSpacing.md),
              Text(
                state.configInvalid ? 'MoviePilot 连接已断开' : '还没有连接 MoviePilot',
                style: GlassType.body.copyWith(color: palette.label),
              ),
              const SizedBox(height: GlassSpacing.sm),
              Text(
                '在设置中登录 MoviePilot 账号后即可求片。',
                textAlign: TextAlign.center,
                style: GlassType.footnote.copyWith(
                  color: palette.secondaryLabel,
                ),
              ),
              const SizedBox(height: GlassSpacing.lg),
              GlassButton(
                key: const Key('request-go-settings'),
                label: '去设置',
                onPressed: () => context.push(AppRoutes.settings),
              ),
            ],
          ),
        ),
      ];
    }

    return <Widget>[
      if (state.pollError != null) ...<Widget>[
        const SizedBox(height: GlassSpacing.md),
        GlassTag(
          key: const Key('request-poll-error'),
          label: state.pollError!,
          color: palette.orange,
          icon: const Icon(Icons.error_outline),
        ),
      ],
      if (state.searchError != null) ...<Widget>[
        const SizedBox(height: GlassSpacing.md),
        Text(
          state.searchError!,
          key: const Key('request-search-error'),
          style: GlassType.footnote.copyWith(color: palette.red),
        ),
      ],
      if (state.searchResults.isNotEmpty) ...<Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GlassSpacing.xs,
            GlassSpacing.xl,
            GlassSpacing.xs,
            GlassSpacing.sm,
          ),
          child: Text(
            '搜索结果',
            style: GlassType.footnote.copyWith(
              color: palette.secondaryLabel,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        for (final media in state.searchResults)
          Padding(
            padding: const EdgeInsets.only(bottom: GlassSpacing.md),
            child: SearchResultCard(
              media: media,
              busy: state.subscribeInFlight,
              onRequest: () => unawaited(_requestFromSearch(media)),
            ),
          ),
      ],
      if (state.hasRequests) ...<Widget>[
        const SizedBox(height: GlassSpacing.xl),
        _MyRequestsEntry(
          count: state.requests.length,
          inFlight: state.requests
              .where((request) => !request.isFinished && !request.isCancelled)
              .length,
          onTap: _openMine,
        ),
      ],
    ];
  }

  /// Opens 我的求片; the controller keeps its poll for this page until the push
  /// finishes, then `_attach` resumes it on return.
  void _openMine() {
    unawaited(context.push(AppRoutes.myRequests));
  }

  Future<void> _requestFromSearch(MpMediaInfo media) async {
    final controller = _controller;
    if (controller == null) return;

    final MediaRequest? record;
    if (media.isSeries) {
      final season = await showSeasonPickerFor(context, controller, media);
      if (season == null) return;
      if (!mounted) return;
      record = await controller.subscribe(media, season: season);
    } else {
      // The controller checks the library first, so a title that is already
      // there comes back playable instead of creating a subscription.
      record = await controller.subscribe(media);
    }

    if (!mounted || record == null) return;
    // A request the user just made is what they want to watch next, so the
    // progress page opens on it. One that was already in the library is shown
    // as a card there too, with 去播放 waiting.
    _openMine();
  }
}

/// Season picker for a series hit (plan S12).
Future<int?> showSeasonPickerFor(
  BuildContext context,
  RequestController controller,
  MpMediaInfo media,
) async {
  final choice = await controller.seasons(media);
  if (!context.mounted) return null;
  if (choice.seasons.isEmpty) {
    // No season list from the source: fall back to the first, which is what
    // MoviePilot would resolve on its own.
    return choice.error == null ? 1 : null;
  }
  return showGlassDialog<int>(
    context: context,
    builder: (BuildContext dialogContext) => _SeasonPickerDialog(choice: choice),
  );
}

class _SeasonPickerDialog extends StatelessWidget {
  const _SeasonPickerDialog({required this.choice});

  final RequestSeasonChoice choice;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    return Material(
      type: MaterialType.transparency,
      child: GlassDialog(
        title: choice.media.title,
        message: '选择要订阅的季',
        maxWidth: 380,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (choice.error != null)
              Text(
                choice.error!,
                style: GlassType.footnote.copyWith(color: palette.red),
              )
            else
              // Plain tappable rows rather than ListTile: the dialog body is a
              // decorated glass surface, where a ListTile's own ink would be
              // hidden (and the framework asserts about it).
              for (final season in choice.seasons)
                InkWell(
                  key: Key('season-${season.seasonNumber}'),
                  borderRadius: BorderRadius.circular(GlassRadii.control),
                  onTap: () =>
                      Navigator.of(context).pop(season.seasonNumber),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GlassSpacing.sm,
                      vertical: GlassSpacing.md,
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          season.label,
                          style: GlassType.body.copyWith(
                            color: palette.label,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: palette.tertiaryLabel,
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
        actions: <Widget>[
          GlassButton(
            label: '取消',
            variant: GlassButtonVariant.plain,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
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
              const SizedBox(height: GlassSpacing.lg),
              GlassButton(label: '重试', onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry from the search page into 我的求片.
class _MyRequestsEntry extends StatelessWidget {
  const _MyRequestsEntry({
    required this.count,
    required this.inFlight,
    required this.onTap,
  });

  final int count;
  final int inFlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = context.glass;
    // A plain tappable row, not a ListTile: GlassCard paints a background, and
    // a ListTile inside it hides its own ink (the framework asserts about it).
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: const Key('request-open-mine'),
        borderRadius: BorderRadius.circular(GlassRadii.cardLarge),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GlassSpacing.lg,
            vertical: GlassSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.downloading_outlined, color: palette.tint, size: 22),
              const SizedBox(width: GlassSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '我的求片',
                      style: GlassType.body.copyWith(color: palette.label),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      inFlight > 0
                          ? '$count 个求片，$inFlight 个进行中'
                          : '$count 个求片',
                      style: GlassType.caption1.copyWith(
                        color: palette.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: palette.tertiaryLabel,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
