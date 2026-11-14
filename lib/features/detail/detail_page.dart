import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/cast/dlna_cast_service.dart';
import '../../data/playback/playback_service.dart';
import '../../ui/theme/app_theme.dart';
import 'detail_cast_sheet.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_source.dart';
import '../../data/models/media_stream.dart';
import '../../data/models/person.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_dialog.dart';
import '../../ui/poster_card.dart';
import '../../ui/responsive.dart';
import '../../ui/app_loader.dart';
import '../../ui/theme/app_tokens.dart';
import 'detail_controller.dart';

/// Movie detail (S7/S28), laid out like Yamby's: a full-bleed backdrop with
/// the watched/favorite actions on top, the rating row, genre chips, the
/// current video/audio/subtitle rows, the resume-progress play button, the
/// overview, cast, artwork, studios, external links, 推荐 and 媒体信息.
class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.itemId, this.urlOpener});

  final String itemId;

  /// Injectable trailer/link launcher (widget tests); production uses
  /// url_launcher.
  final Future<bool> Function(Uri url)? urlOpener;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  final ScrollController _scroll = ScrollController();
  DetailController? _controller;
  bool _redirecting = false;
  bool _openingPlayer = false;
  String? _fatal;

  /// Cast plumbing (S38): the sheet is only offered when the environment
  /// provides a DLNA renderer service (null in test harnesses that never cast).
  DlnaCastService? _cast;
  PlaybackService? _playback;

  @override
  void initState() {
    super.initState();
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
      final controller = DetailController(
        itemId: widget.itemId,
        library: services.library,
        posters: services.posters,
        urlOpener: widget.urlOpener,
      )..addListener(_onChanged);
      setState(() {
        _controller = controller;
        _cast = services.cast;
        _playback = services.playback;
      });
      await controller.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '详情加载失败，请稍后重试');
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

  Future<void> _play() async {
    final controller = _controller;
    final item = controller?.state.item;
    if (controller == null || item == null || _openingPlayer) return;
    setState(() => _openingPlayer = true);
    try {
      await context.push<void>(
        AppRoutes.playerFor(
          item.id,
          source: controller.state.selectedSourceId,
          audio: controller.state.selectedAudioIndex,
          subtitle: controller.state.selectedSubtitleIndex,
        ),
      );
      if (!mounted || _redirecting) return;
      // The player reported progress; re-read the watched state quietly.
      await controller.refresh();
    } finally {
      if (mounted) setState(() => _openingPlayer = false);
    }
  }

  Future<void> _pickVersion() async {
    final controller = _controller;
    final item = controller?.state.item;
    if (controller == null || item == null) return;
    final ColorScheme palette = Theme.of(context).colorScheme;
    final selected = await showAppDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AppDialog(
        title: '选择版本',
        maxWidth: 360,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _VersionRow(
              key: const Key('detail-source-default'),
              selected: controller.state.selectedSourceId == null,
              title: '默认',
              subtitle: '由服务器选择版本',
              palette: palette,
              onTap: () => Navigator.of(dialogContext).pop(''),
            ),
            for (final (int index, MediaSource source)
                in item.mediaSources.indexed)
              _VersionRow(
                key: Key('detail-source-${source.id}'),
                selected: controller.state.selectedSourceId == source.id,
                title: source.name ?? '版本 ${index + 1}',
                subtitle: _sourceSpec(source),
                palette: palette,
                onTap: () => Navigator.of(dialogContext).pop(source.id),
              ),
          ],
        ),
        actions: <Widget>[
          AppButton(
            label: '取消',
            variant: AppButtonVariant.plain,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    controller.selectSource(selected.isEmpty ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final DetailState? state = controller?.state;
    final MediaItem? item = state?.item;

    if (_fatal != null) {
      return Scaffold(
        body: SafeArea(
          child: _ErrorView(message: _fatal!, onRetry: _bootstrap),
        ),
      );
    }
    if (controller == null || state == null) {
      return const Scaffold(body: AppLoadingView());
    }
    if (state.error != null && item == null) {
      return Scaffold(
        body: SafeArea(
          child: _ErrorView(
            message: state.error!,
            onRetry: () => unawaited(controller.load()),
          ),
        ),
      );
    }
    if (item == null) {
      return const Scaffold(body: AppLoadingView());
    }

    return Scaffold(
      key: const Key('detail-page'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: isWide(context)
          ? Center(
              child: ConstrainedBox(
                key: const Key('detail-wide-content'),
                constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.detailMaxWidth,
                ),
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: <Widget>[
                    Row(
                      key: const Key('detail-two-column'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 440,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            child: _hero(controller, state, item),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              ..._metaWidgets(controller, state, item),
                              ..._streamRows(controller, state, item),
                              ..._sections(controller, state, item),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: <Widget>[
                _hero(controller, state, item),
                ..._metaWidgets(controller, state, item),
                ..._streamRows(controller, state, item),
                ..._sections(controller, state, item),
              ],
            ),
    );
  }

  /// Backdrop hero with the top action row (back, title, watched, favorite)
  /// and a fade into the page background.
  Widget _hero(DetailController controller, DetailState state, MediaItem item) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final bool wide = isWide(context);
    final ImageProvider? art =
        controller.backdropImage(item, maxWidth: 1100) ??
        controller.posterImage(item.id, tag: item.imageTag, maxWidth: 780);
    return SizedBox(
      height: wide ? 340 : 300,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            color: palette.surfaceContainerHighest,
            child: art == null
                ? const SizedBox.shrink()
                : Image(
                    image: art,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const <double>[0, 0.35, 1],
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.05),
                    palette.surface,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
            child: Row(
              children: <Widget>[
                _RoundIcon(
                  key: const Key('detail-back'),
                  icon: Icons.arrow_back,
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    item.name,
                    key: const Key('detail-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      shadows: const <Shadow>[
                        Shadow(blurRadius: 6, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
                _RoundIcon(
                  key: const Key('detail-watched'),
                  icon: item.userData.played
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  color: item.userData.played
                      ? Colors.greenAccent
                      : Colors.white,
                  onPressed: state.playedBusy
                      ? null
                      : () => unawaited(controller.togglePlayed()),
                ),
                _RoundIcon(
                  key: const Key('detail-favorite'),
                  icon: item.userData.isFavorite
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: item.userData.isFavorite
                      ? Colors.pinkAccent
                      : Colors.white,
                  onPressed: state.favoriteBusy
                      ? null
                      : () => unawaited(controller.toggleFavorite()),
                ),
                if (_cast != null)
                  _RoundIcon(
                    key: const Key('detail-cast-action'),
                    icon: Icons.cast,
                    onPressed: () => unawaited(_openCast()),
                  ),
                PopupMenuButton<String>(
                  key: const Key('detail-overflow'),
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (String value) {
                    if (value == 'refresh') unawaited(controller.refresh());
                    if (value == 'trailer') unawaited(controller.openTrailer());
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        if (item.remoteTrailer != null &&
                            item.remoteTrailer!.isNotEmpty)
                          const PopupMenuItem<String>(
                            value: 'trailer',
                            child: Text('预告片'),
                          ),
                        const PopupMenuItem<String>(
                          value: 'refresh',
                          child: Text('刷新'),
                        ),
                      ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Rating row, genre chips, the play/resume button, trailer and version
  /// rows — everything directly under the hero.
  List<Widget> _metaWidgets(
    DetailController controller,
    DetailState state,
    MediaItem item,
  ) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final List<String> facts = <String>[
      if (item.officialRating != null) item.officialRating!,
      if (item.productionYear != null) '${item.productionYear}',
      if (item.runTimeTicks > 0) _runtime(item.duration),
    ];
    final double progress = item.runTimeTicks > 0
        ? (item.userData.positionTicks / item.runTimeTicks).clamp(0.0, 1.0)
        : 0.0;
    final bool resumable = progress > 0.0 && !item.userData.played;
    // Yamby's button reads 已播放 for a finished item (S40); tapping still
    // starts it again from the beginning.
    final String playLabel = item.userData.played
        ? '已播放'
        : resumable
        ? '继续 (剩余: ${_remainingLabel(item.duration - item.userData.position)})'
        : '播放';
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (item.communityRating != null)
              Row(
                key: const Key('detail-rating'),
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFFFFC94D),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    item.communityRating!.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      color: palette.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            for (final String fact in facts)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.outlineVariant),
                ),
                child: Text(
                  fact,
                  style: Theme.of(context).textTheme.labelMedium!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
      if (item.genres.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              // S46: a chip opens the library filtered to that genre.
              for (final String genre in item.genres)
                InkWell(
                  key: Key('detail-genre-$genre'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () =>
                      context.push(AppRoutes.libraryFor('', genre: genre)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      genre,
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: palette.onSurface),
                    ),
                  ),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          0,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _PlayButton(
                key: const Key('detail-play'),
                label: playLabel,
                progress: resumable ? progress : 0,
                onPressed: _openingPlayer ? null : () => unawaited(_play()),
              ),
            ),
            if (item.mediaSources.length > 1) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              AppIconButton(
                key: const Key('detail-version'),
                tooltip: '选择版本',
                icon: const Icon(Icons.expand_more),
                onPressed: _pickVersion,
              ),
            ],
          ],
        ),
      ),
      if ((item.remoteTrailer != null && item.remoteTrailer!.isNotEmpty) ||
          state.selectedSourceId != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              if (item.remoteTrailer != null && item.remoteTrailer!.isNotEmpty)
                AppButton(
                  key: const Key('detail-trailer'),
                  label: '预告片',
                  variant: AppButtonVariant.tinted,
                  leading: const Icon(Icons.smart_display_outlined),
                  onPressed: () => unawaited(controller.openTrailer()),
                ),
              if (state.selectedSourceId != null)
                AppTag(
                  key: const Key('detail-source-label'),
                  label: _selectedVersionLabel(item, state.selectedSourceId),
                ),
            ],
          ),
        ),
      if (state.writeError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Text(
            state.writeError!,
            key: const Key('detail-write-error'),
            style: Theme.of(context).textTheme.labelMedium!
                .copyWith(color: palette.error),
          ),
        ),
    ];
  }

  /// Current video / audio / subtitle rows (Yamby's pre-playback track rows).
  /// Audio and subtitle rows are pickers (S37): the choice rides on the player
  /// route so the first playback starts with it.
  List<Widget> _streamRows(
    DetailController controller,
    DetailState state,
    MediaItem item,
  ) {
    final MediaSource? source = item.mediaSources.isEmpty
        ? null
        : item.mediaSources.first;
    if (source == null) return const <Widget>[];
    MediaStream? video;
    MediaStream? audio;
    MediaStream? subtitle;
    for (final MediaStream stream in source.streams) {
      switch (stream.type) {
        case MediaStreamType.video:
          video ??= stream;
        case MediaStreamType.audio:
          audio ??= stream;
        case MediaStreamType.subtitle:
          subtitle ??= stream;
        case MediaStreamType.unknown:
          break;
      }
    }

    // Picks override the defaults shown from the server stream list. A stream
    // list may be empty (e.g. a video-only file), so every lookup is guarded.
    final int? pickedAudio = state.selectedAudioIndex;
    MediaStream? pickAudioStream() {
      if (source.audios.isEmpty) return null;
      if (pickedAudio != null) {
        return source.audios.firstWhere(
          (stream) => stream.index == pickedAudio,
          orElse: () => audio ?? source.audios.first,
        );
      }
      return source.audios.firstWhere(
        (stream) => stream.isDefault,
        orElse: () => audio ?? source.audios.first,
      );
    }

    final MediaStream? shownAudio = pickAudioStream();
    final int? pickedSubtitle = state.selectedSubtitleIndex;
    final bool subtitlesOff = pickedSubtitle != null && pickedSubtitle < 0;
    MediaStream? pickSubtitleStream() {
      if (subtitlesOff || source.subtitles.isEmpty) return null;
      if (pickedSubtitle != null) {
        return source.subtitles.firstWhere(
          (stream) => stream.index == pickedSubtitle,
          orElse: () => subtitle ?? source.subtitles.first,
        );
      }
      return source.subtitles.firstWhere(
        (stream) => stream.isDefault,
        orElse: () => subtitle ?? source.subtitles.first,
      );
    }

    final MediaStream? shownSubtitle = pickSubtitleStream();

    final List<Widget> rows = <Widget>[];
    if (video != null) {
      rows.add(
        _StreamRow(
          icon: Icons.movie_outlined,
          title: _videoTitle(video),
          subtitle: video.profile,
        ),
      );
    }
    if (source.audios.isNotEmpty) {
      rows.add(
        _StreamRow(
          key: const Key('detail-audio-row'),
          icon: Icons.music_note_outlined,
          title: shownAudio == null ? '音轨' : _audioTitle(shownAudio),
          subtitle: shownAudio?.displayLanguage ?? shownAudio?.language,
          onTap: () => unawaited(_pickAudio(controller, source)),
          trailing: const Icon(Icons.chevron_right, size: 18),
        ),
      );
    }
    if (source.subtitles.isNotEmpty) {
      rows.add(
        _StreamRow(
          key: const Key('detail-subtitle-row'),
          icon: Icons.subtitles_outlined,
          title: shownSubtitle == null
              ? '字幕：关闭'
              : _subtitleTitle(shownSubtitle),
          subtitle: shownSubtitle == null
              ? null
              : shownSubtitle.displayLanguage ?? shownSubtitle.language,
          onTap: () => unawaited(_pickSubtitle(controller, source)),
          trailing: const Icon(Icons.chevron_right, size: 18),
        ),
      );
    }
    if (rows.isEmpty) return const <Widget>[];
    return <Widget>[
      const _SectionLabel('当前轨道'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: <Widget>[
            for (final Widget row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: row,
              ),
          ],
        ),
      ),
    ];
  }

  /// S38: DLNA picker from the detail hero. The renderer gets the negotiated
  /// stream (with `api_key`), so nothing has to start on the phone first.
  Future<void> _openCast() async {
    final DlnaCastService? cast = _cast;
    final PlaybackService? playback = _playback;
    final MediaItem? item = _controller?.state.item;
    if (cast == null || playback == null || item == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Theme(
        data: buildAppTheme(Brightness.dark),
        child: SafeArea(
          child: DetailCastSheet(
            cast: cast,
            playback: playback,
            itemId: item.id,
            title: item.name,
            mediaSourceId: _controller?.state.selectedSourceId,
          ),
        ),
      ),
    );
  }

  /// Audio picker: 默认 plus one entry per server audio stream.
  Future<void> _pickAudio(
    DetailController controller,
    MediaSource source,
  ) async {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final int? picked = await showAppDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => AppDialog(
        title: '选择音轨',
        maxWidth: 360,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _VersionRow(
              key: const Key('detail-audio-default'),
              selected: controller.state.selectedAudioIndex == null,
              title: '默认',
              subtitle: '由服务器/播放器决定',
              palette: palette,
              onTap: () => Navigator.of(dialogContext).pop(-1),
            ),
            for (final MediaStream stream in source.audios)
              _VersionRow(
                key: Key('detail-audio-option-${stream.index}'),
                selected: controller.state.selectedAudioIndex == stream.index,
                title: _audioTitle(stream),
                subtitle: <String>[
                  if (stream.displayLanguage != null) stream.displayLanguage!,
                  if (stream.isDefault) '(默认)',
                ].join(' '),
                palette: palette,
                onTap: () => Navigator.of(dialogContext).pop(stream.index),
              ),
          ],
        ),
        actions: <Widget>[
          AppButton(
            label: '取消',
            variant: AppButtonVariant.plain,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    controller.selectAudio(picked < 0 ? null : picked);
  }

  /// Subtitle picker: 关闭, 默认 and one entry per server subtitle stream.
  Future<void> _pickSubtitle(
    DetailController controller,
    MediaSource source,
  ) async {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final int? picked = await showAppDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => AppDialog(
        title: '选择字幕',
        maxWidth: 360,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _VersionRow(
              key: const Key('detail-subtitle-off'),
              selected: (controller.state.selectedSubtitleIndex ?? 0) < 0,
              title: '关闭',
              subtitle: '不显示字幕',
              palette: palette,
              onTap: () => Navigator.of(dialogContext).pop(-2),
            ),
            _VersionRow(
              key: const Key('detail-subtitle-default'),
              selected: controller.state.selectedSubtitleIndex == null,
              title: '默认',
              subtitle: '由服务器/播放器决定',
              palette: palette,
              onTap: () => Navigator.of(dialogContext).pop(-1),
            ),
            for (final MediaStream stream in source.subtitles)
              _VersionRow(
                key: Key('detail-subtitle-option-${stream.index}'),
                selected:
                    controller.state.selectedSubtitleIndex == stream.index,
                title: _subtitleTitle(stream),
                subtitle: <String>[
                  if (stream.displayLanguage != null) stream.displayLanguage!,
                  if (stream.isExternal) '外挂',
                  if (stream.isDefault) '(默认)',
                ].join(' · '),
                palette: palette,
                onTap: () => Navigator.of(dialogContext).pop(stream.index),
              ),
          ],
        ),
        actions: <Widget>[
          AppButton(
            label: '取消',
            variant: AppButtonVariant.plain,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    controller.selectSubtitle(picked == -2 ? -1 : (picked < 0 ? null : picked));
  }

  /// Overview, cast, artwork, studios, external links, 推荐 and 媒体信息.
  List<Widget> _sections(
    DetailController controller,
    DetailState state,
    MediaItem item,
  ) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final List<Person> directors = item.people
        .where((Person person) => person.type == 'Director')
        .toList(growable: false);
    return <Widget>[
      if (item.tagline != null && item.tagline!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            0,
          ),
          child: Text(
            item.tagline!,
            key: const Key('detail-tagline'),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: palette.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      if (item.overview != null && item.overview!.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Text(
            item.overview!,
            key: const Key('detail-overview'),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: palette.onSurfaceVariant, height: 1.5),
          ),
        ),
      if (directors.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                '导演: ',
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
              for (final (int index, Person person)
                  in directors.indexed) ...<Widget>[
                if (index > 0)
                  Text(
                    ', ',
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
                // S54: a director name opens their filmography, like the
                // cast cards (S46).
                if (person.id != null && person.id!.isNotEmpty)
                  InkWell(
                    key: Key('detail-director-${person.id}'),
                    onTap: () => context.push(
                      AppRoutes.personFor(person.id!, name: person.name),
                    ),
                    child: Text(
                      person.name,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: palette.onSurface,
                        decoration: TextDecoration.underline,
                        decorationColor: palette.outline,
                      ),
                    ),
                  )
                else
                  Text(
                    person.name,
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
              ],
            ],
          ),
        ),
      if (item.people.isNotEmpty) ...<Widget>[
        const _SectionLabel('演职人员'),
        SizedBox(
          height: 168,
          child: ListView.separated(
            key: const Key('detail-cast'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: item.people.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (BuildContext context, int index) =>
                _person(controller, item.people[index]),
          ),
        ),
      ],
      if (item.backdropTags.length > 1) ...<Widget>[
        const _SectionLabel('艺术图'),
        SizedBox(
          height: 110,
          child: ListView.separated(
            key: const Key('detail-artwork'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: item.backdropTags.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (BuildContext context, int index) => ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: SizedBox(
                width: 180,
                child: _ArtworkTile(
                  image: controller.backdropImage(
                    item,
                    index: index,
                    maxWidth: 380,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      if (item.studios.isNotEmpty) ...<Widget>[
        const _SectionLabel('工作室'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              // S60: every studio opens the library filtered to it. Emby does
              // not always send a studio Id on this payload, so the name is the
              // fallback the query filters by.
              for (final NamedLink studio in item.studios)
                InkWell(
                  key: Key('detail-studio-${studio.name}'),
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
      ],
      if (item.externalUrls.isNotEmpty) ...<Widget>[
        const _SectionLabel('外部链接'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final NamedLink link in item.externalUrls)
                if (link.target != null)
                  OutlinedButton.icon(
                    key: Key('detail-link-${link.name}'),
                    onPressed: () =>
                        unawaited(controller.openLink(link.target!)),
                    icon: const Icon(Icons.link, size: 16),
                    label: Text(link.name),
                  ),
            ],
          ),
        ),
      ],
      if (state.similar.isNotEmpty) ...<Widget>[
        const _SectionLabel('推荐'),
        SizedBox(
          height: 232,
          child: ListView.separated(
            key: const Key('detail-similar'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: state.similar.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (BuildContext context, int index) {
              final MediaItem similar = state.similar[index];
              return SizedBox(
                width: 120,
                child: PosterCard(
                  name: similar.name,
                  played: similar.userData.played,
                  rating: similar.communityRating,
                  unplayedCount: similar.userData.unplayedItemCount,
                  subtitle: similar.yearLabel,
                  centerTitle: true,
                  image: controller.posterImage(
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
              );
            },
          ),
        ),
      ],
      if (item.mediaSources.isNotEmpty) ...<Widget>[
        const _SectionLabel('媒体信息'),
        _MediaInfo(item: item),
      ],
    ];
  }

  Widget _person(DetailController controller, Person person) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final ImageProvider? image = controller.personImage(person);
    final String role = person.role ?? '';
    final String type = person.type ?? '';
    final String? personId = person.id;
    // S46: a cast card opens that person's filmography (the search page has
    // the same route, this makes the entry reachable from where people look).
    final Widget card = Column(
      children: <Widget>[
        CircleAvatar(
          radius: 32,
          backgroundColor: palette.surfaceContainerHighest,
          backgroundImage: image,
          child: image == null
              ? Icon(Icons.person, color: palette.outline)
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          person.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium!
              .copyWith(color: palette.onSurface, fontWeight: FontWeight.w500),
        ),
        if (role.isNotEmpty)
          Text(
            role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall!
                .copyWith(color: palette.onSurfaceVariant),
          ),
        if (type.isNotEmpty)
          Text(
            type,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall!
                .copyWith(color: palette.outline),
          ),
      ],
    );
    return SizedBox(
      width: 84,
      child: personId == null || personId.isEmpty
          ? card
          : InkWell(
              key: Key('detail-person-$personId'),
              borderRadius: BorderRadius.circular(AppRadii.control),
              onTap: () => context.push(
                AppRoutes.personFor(personId, name: person.name),
              ),
              child: card,
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall!.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The resume button: the primary fill doubles as a progress bar (Yamby's
/// `继续 (剩余: …)` button), so the played fraction is visible before resting.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    super.key,
    required this.label,
    required this.progress,
    required this.onPressed,
  });

  final String label;
  final double progress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    final Color background = enabled
        ? palette.primary
        : palette.primary.withValues(alpha: 0.4);
    final Color foreground = enabled
        ? palette.onPrimary
        : palette.onPrimary.withValues(alpha: 0.7);
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (progress > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.play_arrow_rounded, color: foreground, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall!.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A track row (video / audio / subtitle) under the genre chips.
class _StreamRow extends StatelessWidget {
  const _StreamRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return Material(
      color: palette.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 20, color: palette.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium!
                          .copyWith(color: palette.onSurface),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall!
                            .copyWith(color: palette.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                IconTheme(
                  data: IconThemeData(color: palette.onSurfaceVariant),
                  child: trailing!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// File summary plus one field card per stream (Yamby's 媒体信息).
class _MediaInfo extends StatelessWidget {
  const _MediaInfo({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final MediaSource source = item.mediaSources.first;
    final MediaStream? video = _first(source, MediaStreamType.video);
    final String resolution = video == null
        ? source.container.toUpperCase()
        : video.displayTitle ?? '${video.height ?? ''}p';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${item.name}${item.productionYear == null ? '' : ' (${item.productionYear})'} - $resolution',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              Text(
                source.container.toUpperCase(),
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
              if (source.size > 0)
                Text(
                  _fileSize(source.size),
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
              if (item.dateCreated != null)
                Text(
                  '添加于: ${_dateLabel(item.dateCreated!)}',
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 250,
            child: ListView.separated(
              key: const Key('detail-media-info'),
              scrollDirection: Axis.horizontal,
              itemCount: source.streams.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (BuildContext context, int index) {
                final MediaStream stream = source.streams[index];
                return Container(
                  width: 220,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: palette.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      for (final (String label, String value) in _streamInfo(
                        stream,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '$label: $value',
                            style: Theme.of(context).textTheme.labelSmall!
                                .copyWith(color: palette.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static MediaStream? _first(MediaSource source, MediaStreamType type) {
    for (final MediaStream stream in source.streams) {
      if (stream.type == type) return stream;
    }
    return null;
  }

  static List<(String, String)> _streamInfo(MediaStream stream) {
    return <(String, String)>[
      ('类型', _typeName(stream.type)),
      ('编号', '${stream.index}'),
      if (stream.displayTitle != null) ('显示标题', stream.displayTitle!),
      if (stream.title != null && stream.title != stream.displayTitle)
        ('标题', stream.title!),
      if (stream.codec != null) ('编码器', stream.codec!),
      if (stream.width != null && stream.height != null)
        ('分辨率', '${stream.width}x${stream.height}'),
      if (stream.frameRate != null) ('帧率', '${stream.frameRate}'),
      if (stream.videoRange != null) ('动态范围', stream.videoRange!),
      if (stream.profile != null) ('配置', stream.profile!),
      if (stream.bitRate != null)
        ('比特率', '${(stream.bitRate! / 1000000).toStringAsFixed(2)} Mbps'),
      if (stream.bitDepth != null) ('位深度', '${stream.bitDepth}'),
      if (stream.colorSpace != null) ('色域', stream.colorSpace!),
      if (stream.pixelFormat != null) ('像素格式', stream.pixelFormat!),
      if (stream.channels != null) ('声道', '${stream.channels}'),
      if (stream.channelLayout != null) ('声道布局', stream.channelLayout!),
      if (stream.language != null) ('语言', stream.language!),
      if (stream.displayLanguage != null) ('显示语言', stream.displayLanguage!),
      ('默认', '${stream.isDefault}'),
      ('强制', '${stream.isForced}'),
      ('外部', '${stream.isExternal}'),
    ];
  }

  static String _typeName(MediaStreamType type) {
    return switch (type) {
      MediaStreamType.video => 'Video',
      MediaStreamType.audio => 'Audio',
      MediaStreamType.subtitle => 'Subtitle',
      MediaStreamType.unknown => 'Unknown',
    };
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final ColorScheme palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle : Icons.circle,
              color: selected ? palette.primary : palette.outline,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge!
                        .copyWith(color: palette.onSurface),
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: palette.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _selectedVersionLabel(MediaItem item, String? selectedId) {
  if (selectedId == null) return '默认版本';
  final int index = item.mediaSources.indexWhere((s) => s.id == selectedId);
  if (index < 0) return '默认版本';
  final MediaSource source = item.mediaSources[index];
  return source.name ?? '版本 ${index + 1}';
}

String _sourceSpec(MediaSource source) {
  return <String>[
    if (source.container.isNotEmpty) source.container.toUpperCase(),
    if (source.bitrate > 0)
      '${(source.bitrate / 1000000).toStringAsFixed(1)} Mbps',
  ].join(' · ');
}

String _videoTitle(MediaStream stream) {
  if (stream.displayTitle != null && stream.displayTitle!.isNotEmpty) {
    return stream.displayTitle!;
  }
  final String res = stream.height == null ? '' : '${stream.height}p';
  final String codec = stream.codec == null ? '' : stream.codec!.toUpperCase();
  return <String>[
    if (res.isNotEmpty) res,
    if (codec.isNotEmpty) codec,
  ].join(' ');
}

String _audioTitle(MediaStream stream) {
  if (stream.displayTitle != null && stream.displayTitle!.isNotEmpty) {
    return stream.displayTitle!;
  }
  final String codec = stream.codec == null ? '' : stream.codec!.toUpperCase();
  final String channels = stream.channels == null ? '' : '${stream.channels}.0';
  return <String>[
    if (codec.isNotEmpty) codec,
    if (channels.isNotEmpty) channels,
    if (stream.isDefault) '(默认)',
  ].join(' ');
}

String _subtitleTitle(MediaStream stream) {
  if (stream.displayTitle != null && stream.displayTitle!.isNotEmpty) {
    return stream.displayTitle!;
  }
  final String title = stream.title ?? stream.displayLanguage ?? '字幕';
  return stream.isDefault ? '$title (默认)' : title;
}

String _runtime(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return minutes > 0 ? '$hours小时$minutes分' : '$hours小时';
  }
  return '$minutes分钟';
}

/// `45分 6秒` (Yamby's remaining-time wording).
String _remainingLabel(Duration value) {
  final Duration total = value.isNegative ? Duration.zero : value;
  final int hours = total.inHours;
  final int minutes = total.inMinutes.remainder(60);
  final int seconds = total.inSeconds.remainder(60);
  final StringBuffer buffer = StringBuffer();
  if (hours > 0) buffer.write('$hours时');
  if (minutes > 0) buffer.write('$minutes分 ');
  buffer.write('$seconds秒');
  return buffer.toString().trim();
}

String _fileSize(int bytes) {
  const double gb = 1024 * 1024 * 1024;
  const double mb = 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

String _dateLabel(String iso) {
  final DateTime? parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final DateTime local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
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

class _ArtworkTile extends StatelessWidget {
  const _ArtworkTile({required this.image});

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    return ColoredBox(
      color: palette.surfaceContainerHighest,
      child: image == null
          ? const SizedBox.shrink()
          : Image(
              image: image!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
    );
  }
}

/// A circular translucent icon button drawn over artwork.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.32),
        minimumSize: const Size(40, 40),
        fixedSize: const Size(40, 40),
      ),
    );
  }
}
