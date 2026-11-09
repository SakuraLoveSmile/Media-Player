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
import 'widgets/my_requests_list.dart';
import 'widgets/search_result_card.dart';

/// 求片: search MoviePilot, subscribe, and watch the progress (plan S11).
///
/// The page owns the controller and its poll: leaving the page stops the
/// heartbeat, so MoviePilot is only queried while the user is watching.
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
  String? _fatal;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _query.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _fatal = null);
    try {
      final service = await ref.read(moviePilotServiceProvider.future);
      final configStore = await ref.read(moviePilotConfigStoreProvider.future);
      final requestStore = await ref.read(requestStoreProvider.future);
      final library = await ref.read(requestLibraryProvider.future);
      if (!mounted) return;
      if (service == null ||
          configStore == null ||
          requestStore == null ||
          library == null) {
        setState(() => _fatal = '无法读取本地存储，请重启 App 后重试');
        return;
      }
      final controller = RequestController(
        service: service,
        requestStore: requestStore,
        configStore: configStore,
        library: library,
        heartbeat: widget.heartbeat,
        pollInterval: widget.pollInterval ?? const Duration(seconds: 8),
      )..addListener(_onChanged);
      setState(() => _controller = controller);
      await controller.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '求片页加载失败，请稍后重试');
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

  void _play(MediaRequest request) {
    final itemId = request.embyItemId;
    if (itemId == null || itemId.isEmpty) {
      context.go(AppRoutes.library);
      return;
    }
    if (request.isSeries) {
      // A series has no playable source of its own, so it opens the episode
      // picker; picking an episode then starts playback.
      context.push(AppRoutes.seriesFor(itemId));
      return;
    }
    context.push(AppRoutes.playerFor(itemId));
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(GlassRadii.capsule),
                        child: const LinearProgressIndicator(minHeight: 3),
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
                '在设置中填写 MoviePilot 的地址与 API_TOKEN 后即可求片。',
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
        const RequestSectionHeader(title: '搜索结果'),
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
      RequestSectionHeader(
        title: '我的求片',
        trailing: state.requests.isEmpty
            ? null
            : Text(
                '${state.requests.length}',
                style: GlassType.caption1.copyWith(
                  color: palette.tertiaryLabel,
                ),
              ),
      ),
      MyRequestsList(
        requests: state.requests,
        busyIds: state.busyRequestIds,
        onSearchNow: (request) => unawaited(controller.searchNow(request)),
        onCancel: (request) => unawaited(controller.cancel(request)),
        onPlay: _play,
      ),
    ];
  }

  Future<void> _requestFromSearch(MpMediaInfo media) async {
    final controller = _controller;
    if (controller == null) return;

    if (media.isSeries) {
      final season = await showSeasonPickerFor(context, controller, media);
      if (season == null) return;
      if (!mounted) return;
      await controller.subscribe(media, season: season);
      return;
    }

    // The controller checks the library first, so a title that is already
    // there comes back playable. It is not opened automatically: the user
    // asked for a request, and a surprise navigation would be worse than one
    // extra tap on the card that now offers 去播放.
    await controller.subscribe(media);
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
