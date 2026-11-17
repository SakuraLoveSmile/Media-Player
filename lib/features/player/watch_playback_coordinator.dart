import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/watch_together/watch_together_client.dart';
import 'player_controller.dart';

/// One room-bound playback instance. Local actions request a new room revision;
/// authoritative snapshots use a separate local path and can never echo back.
class WatchPlaybackCoordinator extends ChangeNotifier {
  WatchPlaybackCoordinator({
    required this.client,
    required this.controller,
    required this.roomId,
    required this.itemId,
    String? mediaSourceId,
  }) : mediaSourceId = mediaSourceId ?? client.room?.media.mediaSourceId {
    final room = client.room;
    controller.enableWatchTogether(
      startAt: Duration(
        milliseconds:
            room?.playback.targetAt(client.serverNowMs, room.media.runTimeMs) ??
            0,
      ),
      command: _request,
      onRateRejected: () => _setNotice('一起看时播放速度固定为 1 倍'),
      canPlay: () =>
          !_closed &&
          _foreground &&
          client.connected &&
          client.room?.roomId == roomId &&
          client.room?.media.itemId == itemId &&
          client.room?.media.mediaSourceId == this.mediaSourceId &&
          client.room?.playback.state == 'playing' &&
          client.serverNowMs >= (client.room?.playback.serverTime ?? 0),
      onSleep: () {
        setForeground(false);
        _setNotice('睡眠定时已到，本机已暂停；重新进入播放可继续一起看');
      },
    );
    client.addListener(_changed);
    controller.addListener(_playerChanged);
  }
  final WatchTogetherClient client;
  final PlayerController controller;
  final String roomId, itemId;
  final String? mediaSourceId;
  Timer? _timer;
  bool _foreground = true,
      _started = false,
      _closed = false,
      _disposed = false,
      _syncing = false,
      _again = false;
  String? _notice;
  String? get notice => _notice;
  bool get active => !_closed && client.room?.roomId == roomId;
  String? _lastStatus;
  int _lastRevision = -1, _lastStatusAt = 0;
  final Stopwatch _clock = Stopwatch()..start();
  Future<void> start() async {
    if (_closed || _started) return;
    _started = true;
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_sync()),
    );
    await _sync();
  }

  Future<void> _request(String action, Duration position) async {
    if (_closed || !_foreground) {
      _setNotice('当前未参与放映，请回到房间重新进入播放');
      return;
    }
    try {
      await client.command(action, positionMs: position.inMilliseconds);
    } on WatchTogetherException catch (e) {
      _setNotice(e.message);
    }
  }

  void _changed() {
    if (_started) {
      unawaited(_sync());
    }
  }

  void _playerChanged() {
    // Do not synchronize for every high-frequency position tick. The periodic
    // loop handles drift; state transitions need prompt ready/buffering status.
    if (_started && controller.state.buffering && _lastStatus != 'buffering') {
      unawaited(_sync());
    }
  }

  void setForeground(bool active) {
    if (_closed || _foreground == active) return;
    _foreground = active;
    _lastStatus = null;
    if (!active) {
      client.reportStatus(
        'away',
        positionMs: controller.state.position.inMilliseconds,
      );
      unawaited(
        controller.applyWatchState(
          playing: false,
          position: controller.state.position,
          seek: false,
        ),
      );
    }
    unawaited(_sync());
  }

  Future<void> _sync() async {
    if (_closed || !_started) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _again = false;
        await _apply();
      } while (_again && !_closed);
    } catch (_) {
      _setNotice('一起看同步暂时失败，请检查播放与网络');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _apply() async {
    final room = client.room;
    var state = controller.state;
    if (!_foreground ||
        !client.connected ||
        room == null ||
        room.roomId != roomId ||
        room.media.itemId != itemId ||
        room.media.mediaSourceId != mediaSourceId) {
      if (state.ready) {
        await controller.applyWatchState(
          playing: false,
          position: state.position,
          seek: false,
        );
      }
      if (!_foreground) return;
      if (room == null || room.roomId != roomId) {
        _setNotice(client.error ?? '房间已结束，播放已暂停');
      } else if (!client.connected) {
        _setNotice('一起看连接中断，已暂停，重连后自动对齐');
      }
      return;
    }
    if (!state.ready) {
      _reportStatus(
        state.error != null ? 'error' : 'loading',
        room.playback.revision,
        state.position.inMilliseconds,
      );
      return;
    }
    final playback = room.playback;
    final target = playback.targetAt(client.serverNowMs, room.media.runTimeMs);
    final delta = target - state.position.inMilliseconds;
    if (playback.state == 'waiting') {
      await controller.applyWatchState(
        playing: false,
        position: Duration(milliseconds: target),
        seek: delta.abs() > 100,
      );
      if (_closed ||
          !_foreground ||
          !client.connected ||
          client.room?.roomId != roomId ||
          client.room?.media.itemId != itemId ||
          client.room?.media.mediaSourceId != mediaSourceId ||
          client.room?.playback.revision != playback.revision) {
        return;
      }
      state = controller.state;
      if (!state.ready) return;
    }
    final status = state.error != null
        ? 'error'
        : state.buffering
        ? 'buffering'
        : playback.state == 'waiting'
        ? 'ready'
        : state.completed
        ? 'ended'
        : state.playing
        ? 'playing'
        : 'paused';
    _reportStatus(
      status,
      playback.revision,
      controller.state.position.inMilliseconds,
    );
    if (playback.state == 'waiting') return;
    if (playback.state != 'playing' ||
        client.serverNowMs < playback.serverTime) {
      await controller.applyWatchState(
        playing: false,
        position: Duration(milliseconds: target),
        seek: delta.abs() > 100,
      );
      return;
    }
    final hardSeek = delta.abs() > 2000;
    final rate = hardSeek || delta.abs() <= 250
        ? 1.0
        : delta > 0
        ? 1.05
        : 0.95;
    await controller.applyWatchState(
      playing: !state.buffering && state.error == null && !state.completed,
      position: Duration(milliseconds: target),
      rate: rate,
      seek: hardSeek,
    );
  }

  void _reportStatus(String status, int revision, int position) {
    if (status == _lastStatus &&
        revision == _lastRevision &&
        _clock.elapsedMilliseconds - _lastStatusAt < 2000) {
      return;
    }
    _lastStatus = status;
    _lastRevision = revision;
    _lastStatusAt = _clock.elapsedMilliseconds;
    client.reportStatus(status, positionMs: position);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    client.removeListener(_changed);
    controller.removeListener(_playerChanged);
    final room = client.room;
    if (room?.roomId == roomId &&
        room?.media.itemId == itemId &&
        room?.media.mediaSourceId == mediaSourceId) {
      client.reportStatus(
        'away',
        positionMs: controller.state.position.inMilliseconds,
      );
    }
    await controller.applyWatchState(
      playing: false,
      position: controller.state.position,
      seek: false,
    );
  }

  void _setNotice(String value) {
    if (_notice == value) return;
    _notice = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
