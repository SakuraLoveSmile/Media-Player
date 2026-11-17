import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/router/app_routes.dart';
import '../../data/library/library_service.dart';
import '../../data/watch_together/watch_together_client.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';
import 'watch_media_picker.dart';

class WatchTogetherPage extends ConsumerStatefulWidget {
  const WatchTogetherPage({
    super.key,
    this.initialItemId,
    this.initialSourceId,
  });
  final String? initialItemId;
  final String? initialSourceId;
  @override
  ConsumerState<WatchTogetherPage> createState() => _WatchTogetherPageState();
}

class _WatchTogetherPageState extends ConsumerState<WatchTogetherPage> {
  final _url = TextEditingController();
  final _code = TextEditingController();
  WatchTogetherClient? _client;
  LibraryService? _library;
  WatchMediaSelection? _selection;
  String? _error;
  bool _busy = false;
  bool _openingPlayer = false;
  bool _fromProgress = false;
  String? _seenRoom;
  bool _wasConnected = false;
  int _lastLaunchRevision = -1;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _client?.removeListener(_changed);
    if (!_openingPlayer) _client?.reportStatus('away');
    _url.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final services = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      final client = services.watchTogether;
      if (client == null) {
        setState(() => _error = '一起看服务暂不可用');
        return;
      }
      _client = client;
      _library = services.library;
      _url.text = client.baseUrl?.toString() ?? '';
      client.addListener(_changed);
      if (widget.initialItemId != null) {
        final item = await services.library.item(widget.initialItemId!);
        if (!mounted) return;
        _selection = WatchMediaSelection(
          item,
          widget.initialSourceId ?? item.mediaSources.firstOrNull?.id,
        );
      }
      _changed();
    } catch (_) {
      if (mounted) setState(() => _error = '无法初始化一起看，请检查登录与服务器连接');
    }
  }

  void _changed() {
    if (!mounted) return;
    final client = _client!;
    final room = client.room;
    if (room != null && _seenRoom != room.roomId) {
      _seenRoom = room.roomId;
      _lastLaunchRevision = room.playback.revision;
      _wasConnected = false;
    }
    // REST admission precedes the websocket handshake. Only the connected
    // lobby can announce participation, once per connection rather than once
    // per snapshot (which would otherwise echo its own status forever).
    final announce =
        room != null &&
        client.connected &&
        !_wasConnected &&
        !_openingPlayer &&
        ModalRoute.of(context)?.isCurrent == true;
    _wasConnected = client.connected;
    if (announce) {
      client.reportStatus('loading');
    }
    setState(() {});
    if (room != null &&
        client.connected &&
        !_openingPlayer &&
        ModalRoute.of(context)?.isCurrent == true &&
        (room.playback.state == 'waiting' ||
            room.playback.state == 'playing') &&
        room.playback.revision > _lastLaunchRevision) {
      _lastLaunchRevision = room.playback.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          unawaited(_enterPlayer());
        }
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = _client?.error ?? '操作失败，请检查服务地址、登录与网络后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _configure() => _run(() async {
    final value = _url.text.trim();
    if (value.isEmpty) {
      await _client!.configure(null);
      return;
    }
    final url = Uri.tryParse(value);
    if (url == null ||
        !url.hasAuthority ||
        !['http', 'https'].contains(url.scheme) ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      setState(() => _error = '请输入完整的 http(s) 服务地址，不含账号、查询参数或片段');
      return;
    }
    if (!await _confirm(
      '信任这个一起看服务？',
      '服务会使用当前 Emby 会话向它配置的服务器核验你的身份和播放权限。请只填写自己部署或信任的服务地址。更换地址会离开当前同步连接。',
    )) {
      return;
    }
    if (!mounted) return;
    await _client!.configure(url);
  });
  Future<void> _pick() async {
    if (_library == null || _busy) return;
    final selection = await Navigator.of(context).push<WatchMediaSelection>(
      MaterialPageRoute(builder: (_) => WatchMediaPicker(library: _library!)),
    );
    if (mounted && selection != null) {
      setState(() {
        _selection = selection;
        _fromProgress = false;
      });
    }
  }

  Future<void> _create() => _run(() async {
    final selection = _selection;
    if (selection == null) return;
    await _client!.create(
      itemId: selection.item.id,
      mediaSourceId: selection.sourceId,
      positionMs: _fromProgress
          ? selection.item.userData.position.inMilliseconds
          : 0,
    );
  });
  Future<void> _changeMedia() => _run(() async {
    final selection = _selection;
    if (selection == null) return;
    if (!await _confirm('换成这部并开始放映？', '服务会先核实所有成员对该影片和版本的播放权限，通过后一起加载新影片。')) {
      return;
    }
    await _client!.changeItem(
      itemId: selection.item.id,
      mediaSourceId: selection.sourceId,
    );
  });
  Future<void> _enterPlayer() async {
    final room = _client?.room;
    if (_openingPlayer || room == null || !(_client?.connected ?? false)) {
      return;
    }
    _openingPlayer = true;
    _lastLaunchRevision = room.playback.revision;
    try {
      await context.push(
        AppRoutes.playerFor(
          room.media.itemId,
          source: room.media.mediaSourceId,
          room: room.roomId,
        ),
      );
    } finally {
      _openingPlayer = false;
      if (mounted) {
        final current = _client?.room;
        if (current != null) _lastLaunchRevision = current.playback.revision;
        _client?.reportStatus('away');
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final room = client?.room;
    final selection = _selection;
    final enabled = !_busy && client != null;
    return AppPage(
      title: '一起看',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('watch-together-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: [
          if (_busy || client == null && _error == null)
            const LinearProgressIndicator(),
          if (_error != null || client?.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error ?? client!.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          AppSection(
            header: '同步服务',
            footer: '各自从 Emby 播放视频；同步服务只管理房间和进度。每个人都需要有播放权限的账号。',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  key: const Key('watch-service-url'),
                  controller: _url,
                  enabled: enabled,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '自建一起看服务地址',
                    hintText: 'https://watch.example.com',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: enabled ? _configure : null,
                      child: const Text('保存服务地址'),
                    ),
                    if (client?.baseUrl != null && room == null)
                      TextButton(
                        onPressed: enabled ? () => _run(client.restore) : null,
                        child: const Text('恢复房间'),
                      ),
                  ],
                ),
              ),
              if (room != null)
                ListTile(
                  leading: Icon(
                    client!.connected
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  title: Text(
                    client.connected
                        ? '已连接'
                        : client.reconnecting
                        ? '重新连接中，本机播放已暂停'
                        : '未连接',
                  ),
                  trailing: !client.connected
                      ? TextButton(
                          onPressed: enabled
                              ? () => _run(client.restore)
                              : null,
                          child: const Text('重连'),
                        )
                      : null,
                ),
            ],
          ),
          if (room == null) ...[
            AppSection(
              header: '创建房间',
              children: [
                ListTile(
                  title: Text(selection?.item.name ?? '选择电影或剧集单集'),
                  subtitle: Text(
                    selection?.sourceId == null
                        ? '每位成员使用相同影片版本'
                        : '片源：${selection!.sourceId}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: enabled ? _pick : null,
                ),
                if (selection != null &&
                    selection.item.userData.position > Duration.zero)
                  SwitchListTile(
                    title: const Text('从我的观看进度开始'),
                    value: _fromProgress,
                    onChanged: enabled
                        ? (value) => setState(() => _fromProgress = value)
                        : null,
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    key: const Key('watch-create'),
                    onPressed:
                        enabled && client.baseUrl != null && selection != null
                        ? _create
                        : null,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('创建房间'),
                  ),
                ),
              ],
            ),
            AppSection(
              header: '加入朋友的房间',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    key: const Key('watch-room-code'),
                    controller: _code,
                    enabled: enabled,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: '6 位房间码'),
                    onSubmitted: (_) => enabled && client.baseUrl != null
                        ? _run(() => client.join(_code.text.trim()))
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    key: const Key('watch-join'),
                    onPressed: enabled && client.baseUrl != null
                        ? () => _run(() => client.join(_code.text.trim()))
                        : null,
                    child: const Text('加入房间'),
                  ),
                ),
              ],
            ),
          ] else ...[
            AppSection(
              header: '房间',
              children: [
                ListTile(
                  title: SelectableText(
                    room.code,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  subtitle: Text('${room.members.length} / ${room.capacity} 人'),
                  trailing: IconButton(
                    tooltip: '复制房间码',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: room.code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('房间码已复制')));
                      }
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.movie_outlined),
                  title: Text(room.media.title),
                  subtitle: Text(
                    '同一片源 · ${room.media.mediaSourceId ?? "默认版本"}',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        key: const Key('watch-start'),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('开始放映'),
                        onPressed: enabled && client.connected
                            ? () => _run(() async {
                                client.reportStatus('loading');
                                await client.command('play');
                                if (mounted) await _enterPlayer();
                              })
                            : null,
                      ),
                      OutlinedButton(
                        onPressed: enabled && client.connected
                            ? _enterPlayer
                            : null,
                        child: const Text('进入播放'),
                      ),
                      OutlinedButton(
                        onPressed: enabled && client.connected
                            ? () => _run(() => client.command('pause'))
                            : null,
                        child: const Text('全员暂停'),
                      ),
                    ],
                  ),
                ),
                if (room.playback.state == 'waiting')
                  ListTile(
                    leading: const Icon(Icons.hourglass_top),
                    title: const Text('正在等待成员加载就绪'),
                    subtitle: Text(
                      room.members
                          .where(
                            (member) => room.playback.waitingMemberIds.contains(
                              member.memberId,
                            ),
                          )
                          .map((member) => member.name)
                          .join('、'),
                    ),
                  ),
                if (room.members.any((member) => member.lagging))
                  const ListTile(title: Text('有成员暂未跟上，准备好后将自动对齐')),
              ],
            ),
            AppSection(
              header: '房间成员',
              children: [
                for (final member in room.members)
                  ListTile(
                    leading: Icon(
                      member.role == 'owner'
                          ? Icons.workspace_premium_outlined
                          : Icons.person_outline,
                    ),
                    title: Text(
                      '${member.name}${member.memberId == client!.memberId ? "（我）" : ""}',
                    ),
                    subtitle: Text(
                      '${member.role == "owner" ? "房主 · " : ""}${member.connected ? _status(member.status) : "重新连接中"}${member.lagging ? " · 没跟上" : ""}',
                    ),
                    trailing:
                        client.isOwner && member.memberId != client.memberId
                        ? TextButton(
                            onPressed: enabled
                                ? () => _run(() async {
                                    if (await _confirm(
                                      '移出成员？',
                                      '移出后，该成员不能重新加入当前房间。',
                                    )) {
                                      await client.kick(member.memberId);
                                    }
                                  })
                                : null,
                            child: const Text('移出'),
                          )
                        : null,
                  ),
              ],
            ),
            AppSection(
              header: '更换影片',
              children: [
                ListTile(
                  title: Text(selection?.item.name ?? '选择其他电影或单集'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: enabled ? _pick : null,
                ),
                if (selection != null)
                  TextButton(
                    onPressed: enabled && client.connected
                        ? _changeMedia
                        : null,
                    child: const Text('换成这部并开始放映'),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: enabled
                        ? () => _run(() async {
                            if (await _confirm(
                              '离开房间？',
                              '关闭播放器不会退房；离开后需要房间码重新加入。',
                            )) {
                              await client.leave();
                            }
                          })
                        : null,
                    child: const Text('离开房间'),
                  ),
                  if (client!.isOwner)
                    TextButton(
                      onPressed: enabled
                          ? () => _run(() async {
                              if (await _confirm(
                                '解散房间？',
                                '所有成员都会结束同步，当前房间码立即失效。',
                              )) {
                                await client.end();
                              }
                            })
                          : null,
                      child: Text(
                        '解散房间',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _status(String status) => switch (status) {
    'loading' => '加载中',
    'ready' => '已就绪',
    'playing' => '播放中',
    'paused' => '已暂停',
    'buffering' => '缓冲中',
    'ended' => '播放结束',
    'error' => '播放异常',
    _ => '未在观看',
  };
}
