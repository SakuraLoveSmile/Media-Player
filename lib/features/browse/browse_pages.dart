import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/models/items_page.dart';
import '../../data/models/media_item.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loader.dart';
import '../../ui/app_page.dart';
import '../../ui/poster_card.dart';
import '../../ui/responsive.dart';
import '../../ui/theme/app_tokens.dart';

/// 演员作品页 (S34): every Movie/Series the person appears in, from
/// `PersonIds`.
class PersonPage extends StatelessWidget {
  const PersonPage({super.key, required this.personId, this.name});

  final String personId;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return _BrowseGridPage(
      key: const Key('person-page'),
      title: name == null || name!.isEmpty ? '演员' : name!,
      emptyText: '暂无该演员的作品',
      load: (LibraryService library) => library.itemsByPerson(personId),
    );
  }
}

/// 合集详情页 (S34): a BoxSet's children.
class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, required this.collectionId, this.name});

  final String collectionId;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return _BrowseGridPage(
      key: const Key('collection-page'),
      title: name == null || name!.isEmpty ? '合集' : name!,
      emptyText: '合集中暂无影片',
      load: (LibraryService library) => library.collectionItems(collectionId),
    );
  }
}

class _BrowseGridPage extends ConsumerStatefulWidget {
  const _BrowseGridPage({
    super.key,
    required this.title,
    required this.emptyText,
    required this.load,
  });

  final String title;
  final String emptyText;
  final Future<ItemsPage> Function(LibraryService library) load;

  @override
  ConsumerState<_BrowseGridPage> createState() => _BrowseGridPageState();
}

class _BrowseGridPageState extends ConsumerState<_BrowseGridPage> {
  Future<ItemsPage>? _future;
  PosterCache? _posters;
  LibraryService? _library;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      setState(() {
        _library = services.library;
        _posters = services.posters;
        _future = widget.load(services.library);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _fatal = '加载失败，请稍后重试');
    }
  }

  Future<void> _retry() async {
    final LibraryService? library = _library;
    if (library == null) {
      setState(() => _fatal = null);
      await _bootstrap();
      return;
    }
    setState(() => _future = widget.load(library));
  }

  ImageProvider? _imageFor(MediaItem item) {
    final PosterCache? posters = _posters;
    final LibraryService? library = _library;
    if (posters == null || library == null) return null;
    final Uri? url = library.imageUrl(
      item.id,
      tag: item.imageTag,
      maxWidth: 320,
    );
    if (url == null) return null;
    return PosterImageProvider(
      cache: posters,
      itemId: item.id,
      url: url,
      tag: item.imageTag,
      maxWidth: 320,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: widget.title,
      onBack: () => context.pop(),
      child: _fatal != null
          ? _MessageView(
              message: _fatal!,
              action: AppButton(label: '重试', onPressed: _retry),
            )
          : _future == null
          ? const AppLoadingView()
          : FutureBuilder<ItemsPage>(
              future: _future,
              builder: (BuildContext context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const AppLoadingView();
                }
                if (snapshot.hasError) {
                  return _MessageView(
                    message: '加载失败，请稍后重试',
                    action: AppButton(label: '重试', onPressed: _retry),
                  );
                }
                final List<MediaItem> items =
                    snapshot.data?.items ?? const <MediaItem>[];
                if (items.isEmpty) {
                  return _MessageView(message: widget.emptyText);
                }
                return LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
                      gridDelegate: posterGridDelegate(constraints.maxWidth),
                      itemCount: items.length,
                      itemBuilder: (BuildContext context, int index) {
                        final MediaItem item = items[index];
                        return PosterCard(
                          name: item.name,
                          played: item.userData.played,
                          rating: item.communityRating,
                          unplayedCount: item.userData.unplayedItemCount,
                          subtitle: item.yearLabel,
                          image: _imageFor(item),
                          onTap: item.id.isEmpty
                              ? null
                              : () => item.type == 'Series'
                                    ? context.push(AppRoutes.seriesFor(item.id))
                                    : context.push(
                                        AppRoutes.detailFor(item.id),
                                      ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, this.action});

  final String message;
  final Widget? action;

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
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
