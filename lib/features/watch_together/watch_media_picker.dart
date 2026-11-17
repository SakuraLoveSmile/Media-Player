import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/library/library_service.dart';
import '../../data/models/media_item.dart';
import '../../ui/app_page.dart';

class WatchMediaSelection {
  const WatchMediaSelection(this.item, this.sourceId);
  final MediaItem item;
  final String? sourceId;
}

/// Reuses the signed-in library: the room never invents or shares stream URLs.
class WatchMediaPicker extends StatefulWidget {
  const WatchMediaPicker({super.key, required this.library});
  final LibraryService library;
  @override
  State<WatchMediaPicker> createState() => _WatchMediaPickerState();
}

class _WatchMediaPickerState extends State<WatchMediaPicker> {
  final _query = TextEditingController();
  List<MediaItem> _items = [];
  String? _error;
  bool _busy = false;
  int _generation = 0;
  String _heading = '继续观看与最近入库';
  String? _selectedSeriesId;
  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _fetch(
    Future<List<MediaItem>> Function() read,
    String heading,
  ) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _heading = heading;
    });
    try {
      final items = await read();
      if (mounted && generation == _generation) setState(() => _items = items);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '无法读取媒体，请检查连接后重试');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _search() => _fetch(() async {
    final query = _query.text.trim();
    if (query.isNotEmpty) {
      return (await widget.library.search(
        query,
        types: 'Movie,Series,Episode',
      )).items;
    }
    final recent = await widget.library.resumable();
    final latest = await widget.library.items(
      '',
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
      limit: 30,
      includeItemTypes: 'Movie,Series,Episode',
    );
    final unique = <String, MediaItem>{
      for (final item in [...recent.items, ...latest.items]) item.id: item,
    };
    return unique.values
        .where((item) => ['Movie', 'Series', 'Episode'].contains(item.type))
        .toList();
  }, '选择电影或单集');
  Future<void> _select(MediaItem item) async {
    if (item.type == 'Series') {
      _selectedSeriesId = item.id;
      await _fetch(() => widget.library.seasons(item.id), item.name);
      return;
    }
    if (item.type == 'Season') {
      final series = item.seriesId ?? _selectedSeriesId;
      if (series == null) {
        setState(() => _error = '此季缺少剧集信息，请从剧集详情重新选择');
        return;
      }
      await _fetch(
        () => widget.library.episodes(seriesId: series, seasonId: item.id),
        item.name,
      );
      return;
    }
    if (item.type != 'Movie' && item.type != 'Episode') return;
    setState(() => _busy = true);
    try {
      final detail = await widget.library.item(item.id);
      if (!mounted) return;
      final sources = detail.mediaSources;
      String? source = sources.firstOrNull?.id;
      if (sources.length > 1) {
        source = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('所有成员使用同一版本'),
            children: [
              for (final entry in sources)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, entry.id),
                  child: Text(
                    entry.name?.isNotEmpty == true
                        ? entry.name!
                        : entry.container,
                  ),
                ),
            ],
          ),
        );
        if (source == null) return;
      }
      if (mounted) Navigator.pop(context, WatchMediaSelection(detail, source));
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取片源，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '选择一起看的影片',
    onBack: () => Navigator.pop(context),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('watch-media-search'),
            controller: _query,
            decoration: InputDecoration(
              labelText: '搜索电影、剧集或单集',
              suffixIcon: IconButton(
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: Text(_heading)),
              TextButton(
                onPressed: _busy ? null : _search,
                child: const Text('返回搜索'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (!_busy && _items.isEmpty)
                const ListTile(title: Text('暂无结果，试试搜索影片名称')),
              for (final item in _items)
                ListTile(
                  key: ValueKey('watch-pick-${item.id}'),
                  leading: Icon(
                    item.type == 'Series' || item.type == 'Season'
                        ? Icons.video_library_outlined
                        : Icons.movie_outlined,
                  ),
                  title: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.type == 'Series'
                        ? '选择剧集的具体季与单集'
                        : item.type == 'Season'
                        ? '选择单集'
                        : item.type == 'Episode'
                        ? '单集'
                        : '电影',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _select(item),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
