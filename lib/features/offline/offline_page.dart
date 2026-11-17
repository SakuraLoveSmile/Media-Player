import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/endpoint_kind.dart';
import '../../data/models/playback_plan.dart';
import '../../data/offline/offline_entry.dart';
import '../../data/offline/offline_repository.dart';
import '../../data/playback/playback_engine.dart';
import '../../data/playback/playback_settings.dart';
import '../../data/playback/mpv_config.dart';
import '../../ui/app_page.dart';

/// Local copies stay accessible even when server login/restore is unavailable.
class OfflinePage extends StatelessWidget {
  const OfflinePage({
    super.key,
    required this.repository,
    required this.createEngine,
    this.settings = const PlaybackSettings(),
  });
  final OfflineRepository repository;
  final PlaybackEngine Function() createEngine;
  final PlaybackSettings settings;

  Future<void> _perform(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError ? error.message.toString() : '本地文件操作失败，请稍后重试',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '下载与离线媒体',
    onBack: () => Navigator.of(context).pop(),
    child: ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final entries = repository.entries;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (repository.initializationError != null)
              Text(repository.initializationError!),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('本机保存的媒体可断网播放。继续下载需登录原服务器与账号；外置字幕、评论和在线弹幕不会随视频保存。'),
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('还没有离线媒体，请在电影或单集详情中下载'),
              ),
            for (final entry in entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('${entry.serverName} · 账号 ${entry.userId}'),
                      const SizedBox(height: 8),
                      if (entry.status == OfflineStatus.downloading)
                        LinearProgressIndicator(value: entry.progress),
                      Text(
                        '${_status(entry.status)} · ${_bytes(entry.received)} / ${entry.total > 0 ? _bytes(entry.total) : "未知大小"}',
                      ),
                      if (entry.error != null)
                        Text(
                          entry.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (entry.status == OfflineStatus.downloading)
                            TextButton(
                              onPressed: () => _perform(
                                context,
                                () => repository.pause(entry.id),
                              ),
                              child: const Text('暂停'),
                            )
                          else if (entry.status != OfflineStatus.complete)
                            TextButton(
                              onPressed: repository.canResume(entry)
                                  ? () => _perform(
                                      context,
                                      () => repository.resume(entry.id),
                                    )
                                  : null,
                              child: Text(
                                entry.status == OfflineStatus.failed
                                    ? '重试'
                                    : '继续',
                              ),
                            ),
                          if (entry.status == OfflineStatus.complete)
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('播放'),
                              onPressed: () => _perform(context, () async {
                                final file = await repository.completedFile(
                                  entry.id,
                                );
                                if (!context.mounted) return;
                                await Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => OfflinePlayerPage(
                                      title: entry.title,
                                      fileUri: file.uri.toString(),
                                      createEngine: createEngine,
                                      settings: settings,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          TextButton(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('删除离线副本？'),
                                  content: Text(
                                    '将删除「${entry.title}」的本地文件和下载任务，服务器原片会保留。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && context.mounted) {
                                await _perform(
                                  context,
                                  () => repository.remove(entry.id),
                                );
                              }
                            },
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  static String _status(OfflineStatus status) => switch (status) {
    OfflineStatus.downloading => '下载中',
    OfflineStatus.paused => '已暂停',
    OfflineStatus.failed => '下载失败',
    OfflineStatus.complete => '已完成',
  };
  static String _bytes(int bytes) => bytes >= 1073741824
      ? '${(bytes / 1073741824).toStringAsFixed(2)} GB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

/// Uses only the engine: it never negotiates, authenticates, or reports a
/// local playback to an Emby server.
class OfflinePlayerPage extends StatefulWidget {
  const OfflinePlayerPage({
    super.key,
    required this.title,
    required this.fileUri,
    required this.createEngine,
    this.settings = const PlaybackSettings(),
  });
  final String title;
  final String fileUri;
  final PlaybackEngine Function() createEngine;
  final PlaybackSettings settings;
  @override
  State<OfflinePlayerPage> createState() => _OfflinePlayerPageState();
}

class _OfflinePlayerPageState extends State<OfflinePlayerPage> {
  late final PlaybackEngine _engine;
  StreamSubscription<PlaybackSnapshot>? _subscription;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  String? _error;
  String? _qualityWarning;
  bool _appliedVo = false;
  @override
  void initState() {
    super.initState();
    _engine = widget.createEngine();
    _subscription = _engine.state.listen((value) {
      if (mounted) {
        setState(() {
          _snapshot = value;
          if (value.error != null) _error = '本地媒体播放失败';
        });
        if (!_appliedVo && widget.settings.gpuNext && value.videoWidth > 0) {
          _appliedVo = true;
          unawaited(_applyVo());
        }
      }
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _engine.open(
        PlaybackPlan(
          itemId: 'offline',
          mode: PlaybackMode.direct,
          endpointKind: EndpointKind.lan,
          url: widget.fileUri,
          headers: const {},
          mediaSourceId: '',
          playSessionId: '',
        ),
      );
      if (mounted) await _applySettings();
    } catch (_) {
      if (mounted) setState(() => _error = '本地媒体播放失败');
    }
  }

  Future<void> _applyVo() async {
    try {
      await _engine.setAdvancedVideo(
        gpuNext: widget.settings.gpuNext,
        deband: widget.settings.deband,
        yuv420: widget.settings.yuv420,
      );
    } catch (_) {
      if (mounted) setState(() => _qualityWarning = '部分视频设置无法应用，播放将继续');
    }
  }

  Future<void> _applySettings() async {
    final settings = widget.settings;
    try {
      await _engine.setHwdecEnabled(settings.hwdecEnabled);
      if (!mounted) return;
      await _engine.setForceStereo(settings.forceStereo);
      if (!mounted) return;
      await _engine.setVolumeMax(settings.volumeGainPercent);
      if (!mounted) return;
      await _engine.setCacheConfig(
        cacheSecs: settings.cacheSecs,
        demuxerMaxBytes: settings.demuxerMaxBytes,
      );
      if (!mounted) return;
      await _engine.setAdvancedVideo(
        gpuNext: settings.gpuNext,
        deband: settings.deband,
        yuv420: settings.yuv420,
        applyVo: false,
      );
    } catch (_) {
      if (mounted) setState(() => _qualityWarning = '部分视频设置无法应用，播放将继续');
    }
    if (!mounted) return;
    final engine = _engine;
    if (engine is MpvConfigEngine) {
      try {
        await (engine as MpvConfigEngine).applyMpvConfig(
          MpvConfig.resolve(
            settings.mpvQualityPreset,
            settings.mpvCustomConfig,
          ),
        );
      } catch (_) {
        var warning = '画质配置无法应用，请检查 MPV 设置';
        try {
          await (engine as MpvConfigEngine).applyMpvConfig(MpvConfig.defaults);
          warning = '画质配置无法应用，已恢复默认；请检查 MPV 设置';
        } catch (_) {
          /* do not claim reset succeeded */
        }
        if (mounted) setState(() => _qualityWarning = warning);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_engine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.title,
    onBack: () => Navigator.pop(context),
    child: Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: Center(child: _engine.createSurface()),
          ),
        ),
        if (_error != null) Text(_error!),
        if (_qualityWarning != null) Text(_qualityWarning!),
        if (_snapshot.buffering) const LinearProgressIndicator(),
        Slider(
          value: _snapshot.position.inMilliseconds.toDouble().clamp(
            0,
            _snapshot.duration.inMilliseconds.toDouble(),
          ),
          max: _snapshot.duration.inMilliseconds > 0
              ? _snapshot.duration.inMilliseconds.toDouble()
              : 1,
          onChanged: _snapshot.duration > Duration.zero
              ? (value) => unawaited(
                  _engine.seekTo(Duration(milliseconds: value.round())),
                )
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${_time(_snapshot.position)} / ${_time(_snapshot.duration)}'),
            IconButton(
              tooltip: _snapshot.playing ? '暂停' : '播放',
              onPressed: () => unawaited(
                _snapshot.playing ? _engine.pause() : _engine.play(),
              ),
              icon: Icon(_snapshot.playing ? Icons.pause : Icons.play_arrow),
            ),
          ],
        ),
      ],
    ),
  );
  static String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, "0")}';
}
