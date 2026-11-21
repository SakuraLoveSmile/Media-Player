import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../auth/api_session.dart';
import '../models/media_item.dart';
import '../models/media_source.dart';
import 'offline_entry.dart';

/// App-private original-file downloads. The streaming HTTP path is binary-only;
/// JSON policy/detail queries still use the authenticated API session.
class OfflineRepository extends ChangeNotifier {
  OfflineRepository({
    required this.directory,
    required this.session,
    this.onUnauthorized,
  }) : _state = _DirectoryState.attach(directory);

  final Directory directory;
  final ApiSession session;
  final Future<void> Function()? onUnauthorized;
  final List<OfflineEntry> _entries = <OfflineEntry>[];
  final Map<String, _Transfer> _active = <String, _Transfer>{};
  /// Serializes this directory's atomic `index.json` replacements and tracks
  /// its in-flight commits and removals across every repository opened on it.
  final _DirectoryState _state;
  bool _disposed = false;
  Future<void>? _initializing;
  String? initializationError;

  List<OfflineEntry> get entries => List<OfflineEntry>.unmodifiable(_entries);
  File get _index => File('${directory.path}/index.json');

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    await directory.create(recursive: true);
    // Another repository may still be finishing a commit or a removal on this
    // same directory, whose index write is only queued after its file
    // operations. Reading the index before that lands would make this instance
    // observe a state the other one is about to replace, and its own write
    // would then overwrite the settled result.
    await _state.settle();
    if (await _index.exists()) {
      try {
        final decoded =
            jsonDecode(await _index.readAsString()) as List<dynamic>;
        for (final raw in decoded) {
          final entry = OfflineEntry.fromJson(raw as Map<String, dynamic>);
          if (_entries.any((e) => e.id == entry.id)) continue;
          final file = entry.status == OfflineStatus.complete
              ? _file(entry)
              : _part(entry);
          final length = await file.exists() ? await file.length() : 0;
          if (entry.status == OfflineStatus.complete &&
              (entry.total <= 0 || length != entry.total)) {
            entry.status = OfflineStatus.failed;
            entry.error = '本地文件缺失或不完整，请重新下载';
          } else if (entry.status == OfflineStatus.downloading) {
            entry.status = OfflineStatus.paused;
          }
          entry.received = length;
          _entries.add(entry);
        }
      } on FormatException {
        await _recoverIndex();
      } on TypeError {
        await _recoverIndex();
      } on ArgumentError {
        await _recoverIndex();
      }
    }
    await _save();
    _notify();
  }

  Future<void> _recoverIndex() async {
    final backup =
        '${_index.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}';
    await _index.rename(backup);
    initializationError = '离线目录记录损坏，已保留原记录并恢复可识别的本地文件；恢复的未完成任务需重新下载。';
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match = RegExp(r'^([a-f0-9]{64})\.([a-z0-9]{1,8})(\.part)?$')
          .firstMatch(name);
      if (match == null || _entries.any((e) => e.id == match[1])) continue;
      final length = await entity.length();
      _entries.add(
        OfflineEntry(
          id: match[1]!,
          serverId: 'recovered',
          userId: 'recovered',
          itemId: match[1]!,
          sourceId: '',
          title: '恢复的本地媒体 · ${match[1]!.substring(0, 8)}',
          serverName: '本机恢复副本',
          container: match[2]!,
          status: match[3] == null && length > 0
              ? OfflineStatus.complete
              : OfflineStatus.failed,
          received: length,
          total: match[3] == null ? length : 0,
          error: match[3] == null ? null : '原下载记录损坏，请删除此未完成副本后重新下载',
        ),
      );
    }
  }

  static String _identity(
    String server,
    String user,
    String item,
    String source,
  ) => sha256
      .convert(utf8.encode(jsonEncode([server, user, item, source])))
      .toString();

  File _file(OfflineEntry e) => File('${directory.path}/${e.fileName}');
  File _part(OfflineEntry e) => File('${directory.path}/${e.fileName}.part');

  OfflineEntry _find(String id) => _entries.firstWhere((e) => e.id == id);

  bool canResume(OfflineEntry e) =>
      session.endpoint?.serverId == e.serverId &&
      session.userId == e.userId &&
      (session.accessToken?.isNotEmpty ?? false);

  Future<void> enqueue(MediaItem item, {String? sourceId}) async {
    await initialize();
    if (item.type != 'Movie' && item.type != 'Episode') {
      throw StateError('仅支持下载电影或单集');
    }
    final endpoint = session.endpoint;
    final user = session.userId;
    if (endpoint == null || user == null) throw StateError('请先登录服务器');
    // Never trust a stale detail page for download permission or source choice.
    final detail = await _checkedDetail(item.id, endpoint.serverId, user);
    final sources = (detail['MediaSources'] as List<dynamic>? ?? [])
        .map((e) => MediaSource.fromJson(e as Map<String, dynamic>))
        .toList();
    final source = sources
        .where((s) => sourceId == null || s.id == sourceId)
        .firstOrNull;
    if (source == null || source.isLiveTv) throw StateError('没有可下载的原始版本');
    final rawSource = (detail['MediaSources'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['Id'] == source.id);
    _validateSource(rawSource);
    final id = _identity(endpoint.serverId, user, item.id, source.id);
    final existing = _entries.where((e) => e.id == id).firstOrNull;
    if (existing != null) {
      if (existing.status != OfflineStatus.complete &&
          !_active.containsKey(id)) {
        await resume(id);
      }
      return;
    }
    final extension = source.container.toLowerCase();
    final entry = OfflineEntry(
      id: id,
      serverId: endpoint.serverId,
      userId: user,
      itemId: item.id,
      sourceId: source.id,
      title: item.name,
      serverName: session.profile?.name ?? '媒体服务器',
      container: RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)
          ? extension
          : 'mkv',
      total: source.size,
    );
    _entries.insert(0, entry);
    await _save();
    _notify();
    await resume(id);
  }

  static void _validateSource(Map<String, dynamic> source) {
    final container = (source['Container'] as String? ?? '').toLowerCase();
    final path = (source['Path'] as String? ?? '').toLowerCase();
    const videoContainers = {
      'mkv',
      'mp4',
      'm4v',
      'mov',
      'webm',
      'avi',
      'ts',
      'm2ts',
      'mpg',
      'mpeg',
      'wmv',
      'flv',
    };
    if (source['Protocol'] != 'File' ||
        source['IsRemote'] == true ||
        path.endsWith('.strm') ||
        path.startsWith('http:') ||
        path.startsWith('https:') ||
        !videoContainers.contains(container) ||
        ((source['Size'] as num?)?.toInt() ?? 0) <= 0) {
      throw StateError('仅支持有明确文件大小的本地原始视频，暂不支持 STRM 或远程媒体源');
    }
  }

  Future<Map<String, dynamic>> _checkedDetail(
    String item,
    String server,
    String user,
  ) async {
    final endpoint = session.endpoint;
    if (endpoint?.serverId != server ||
        session.userId != user ||
        !(session.accessToken?.isNotEmpty ?? false)) {
      throw StateError('请登录创建此任务的服务器与账号后继续');
    }
    final account = await session.authorizedGet(
      endpoint!.resolve('/Users/${Uri.encodeComponent(user)}'),
    );
    final policy = account['Policy'] as Map<String, dynamic>?;
    if (policy?['EnableContentDownloading'] != true) {
      throw StateError('服务器未允许当前账号下载');
    }
    if (session.endpoint?.serverId != server || session.userId != user) {
      throw StateError('登录会话已切换，请重新操作');
    }
    final detail = await session.authorizedGet(
      endpoint.resolve(
        '/Users/${Uri.encodeComponent(user)}/Items/${Uri.encodeComponent(item)}',
      ),
    );
    if (detail['CanDownload'] != true ||
        (detail['Type'] != 'Movie' && detail['Type'] != 'Episode')) {
      throw StateError('当前条目不允许下载');
    }
    if (session.endpoint?.serverId != server || session.userId != user) {
      throw StateError('登录会话已切换，请重新操作');
    }
    return detail;
  }

  /// Starts asynchronously; completion/progress are exposed through entries.
  Future<void> resume(String id) async {
    final entry = _find(id);
    if (_active.containsKey(id) || entry.status == OfflineStatus.complete) {
      return;
    }
    if (!canResume(entry)) throw StateError('请登录创建此任务的服务器与账号后继续');
    final transfer = _Transfer();
    _active[id] = transfer;
    entry.status = OfflineStatus.downloading;
    entry.error = null;
    transfer.done = _start(entry, transfer);
    unawaited(transfer.done);
    _notify();
  }

  Future<void> _start(OfflineEntry entry, _Transfer transfer) async {
    try {
      await _save();
      if (!transfer.cancelled) await _run(entry, transfer);
    } catch (_) {
      // The download could not even be recorded: fail closed before any later
      // snapshot is taken, so no queued write can persist it as complete.
      entry.status = OfflineStatus.failed;
      entry.error = '无法保存下载记录，请检查磁盘空间和目录权限';
    } finally {
      if (identical(_active[entry.id], transfer)) {
        _active.remove(entry.id);
        if (entry.status == OfflineStatus.downloading) {
          entry.status = OfflineStatus.paused;
        }
        _notify();
      }
    }
  }

  Future<void> _run(OfflineEntry entry, _Transfer transfer) async {
    RandomAccessFile? output;
    // Covers the whole commit window, including the index write that is only
    // queued after the part was renamed into place, so another repository
    // opened on this directory cannot read the index in between.
    _DirectoryOperation? commit;
    try {
      final detail = await _checkedDetail(
        entry.itemId,
        entry.serverId,
        entry.userId,
      );
      if (transfer.cancelled) return;
      final sources = (detail['MediaSources'] as List<dynamic>? ?? []);
      final raw = sources
          .cast<Map<String, dynamic>>()
          .where((s) => s['Id'] == entry.sourceId)
          .firstOrNull;
      if (raw == null) throw StateError('原始版本已变更，请删除任务后重新下载');
      _validateSource(raw);
      final newSize = (raw['Size'] as num?)?.toInt() ?? 0;
      final part = _part(entry);
      var offset = await part.exists() ? await part.length() : 0;
      if (offset >= entry.total ||
          entry.validator == null ||
          (newSize > 0 && entry.total > 0 && newSize != entry.total)) {
        offset = 0;
        entry.validator = null;
      }
      if (newSize > 0) entry.total = newSize;
      if (!canResume(entry) || transfer.cancelled) return;
      final endpoint = session.endpoint!;
      final token = session.accessToken!;
      final deviceId = session.deviceId ?? '';
      final url = endpoint
          .resolve('/Videos/${Uri.encodeComponent(entry.itemId)}/stream')
          .replace(
            queryParameters: {
              'Static': 'true',
              'MediaSourceId': entry.sourceId,
            },
          );
      final http = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      transfer.http = http;
      final request = await http.getUrl(url);
      request.followRedirects = false;
      if (!canResume(entry) ||
          transfer.cancelled ||
          session.endpoint?.baseUrl != endpoint.baseUrl) {
        return;
      }
      request.headers.set('X-Emby-Token', token);
      request.headers.set('X-Emby-Device-Id', deviceId);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        request.headers.set(HttpHeaders.ifRangeHeader, entry.validator!);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode == HttpStatus.unauthorized &&
          canResume(entry) &&
          session.accessToken == token &&
          session.endpoint?.baseUrl == endpoint.baseUrl) {
        await onUnauthorized?.call();
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw StateError('下载被服务器拒绝（HTTP ${response.statusCode}）');
      }
      final validator =
          response.headers.value(HttpHeaders.etagHeader) ??
          response.headers.value(HttpHeaders.lastModifiedHeader);
      if (response.statusCode == HttpStatus.partialContent) {
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
        );
        if (range == null ||
            int.parse(range[1]!) != offset ||
            int.parse(range[2]!) < offset ||
            response.contentLength != int.parse(range[2]!) - offset + 1 ||
            (offset > 0 && validator != entry.validator)) {
          entry.validator = null;
          throw StateError('服务器返回的续传范围不匹配，请重试重新下载');
        }
        final total = int.parse(range[3]!);
        if (int.parse(range[2]!) != total - 1 ||
            (entry.total > 0 && entry.total != total)) {
          throw StateError('媒体大小已变化，请删除任务后重新下载');
        }
        entry.total = total;
      } else {
        offset = 0; // Range ignored or If-Range changed: replace, never append.
        if (response.contentLength <= 0) throw StateError('服务器未提供有效文件长度');
        if (newSize > 0 && response.contentLength != newSize) {
          throw StateError('下载文件大小与媒体信息不一致');
        }
        entry.total = response.contentLength;
      }
      if (transfer.cancelled || !canResume(entry)) return;
      output = await part.open(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      entry.received = offset;
      // Weak ETags are not usable by If-Range.
      entry.validator = validator != null && !validator.startsWith('W/')
          ? validator
          : null;
      await _save();
      var lastNotification = DateTime.now();
      await for (final bytes in response.timeout(const Duration(seconds: 30))) {
        if (transfer.cancelled || !canResume(entry)) break;
        await output.writeFrom(bytes);
        entry.received += bytes.length;
        if (entry.received > entry.total) throw StateError('下载长度超过预期');
        if (DateTime.now().difference(lastNotification).inMilliseconds >= 200) {
          lastNotification = DateTime.now();
          _notify();
        }
      }
      await output.close();
      output = null;
      if (transfer.cancelled || !canResume(entry)) {
        entry.status = OfflineStatus.paused;
      } else {
        if (entry.received != entry.total ||
            await part.length() != entry.total) {
          throw StateError('连接中断，文件未完整下载，可继续重试');
        }
        commit = _state.begin();
        await _commit(entry, transfer, part);
      }
    } catch (error) {
      // A failed commit must not keep claiming a finished file on disk; the
      // queued write already moved this record to `failed` before any later
      // snapshot was taken.
      transfer.committing = false;
      if (!transfer.cancelled) {
        entry.status = OfflineStatus.failed;
        // Only our own StateError messages are user-safe; never persist URI,
        // token, socket exception text, or server error response bodies.
        entry.error = error is StateError
            ? error.message.toString()
            : '下载失败，请检查网络或磁盘空间后重试';
      }
    } finally {
      await output?.close();
      transfer.http?.close(force: true);
      try {
        // A committed download already settled `complete` inside its queued
        // write; do not enqueue another snapshot for it.
        if (!transfer.committing) {
          if (entry.status == OfflineStatus.downloading) {
            entry.status = OfflineStatus.paused;
          }
          if (!_disposed) {
            await _save();
          }
        }
      } finally {
        // Released even when that last snapshot throws: a failed write must
        // never leave this directory's in-flight window closed, which would
        // block every later repository opened on it.
        commit?.settle();
      }
    }
  }

  /// Finishes a complete download: rename the part into place, then queue the
  /// atomic record replacement. That queued write persists this record as
  /// `complete` and flips its memory status in the same operation, so memory
  /// never claims a finished file before the index does. A restart inside the
  /// window between the rename and that replacement still turns the record into
  /// `paused`. The notification is left to `_start`.
  Future<void> _commit(
    OfflineEntry entry,
    _Transfer transfer,
    File part,
  ) async {
    transfer.committing = true;
    await part.rename(_file(entry).path);
    // The queued replacement records this commit as `complete` and settles the
    // in-memory status once the atomic swap succeeded, so memory and every later
    // snapshot agree with the file that is already on disk.
    await _save(completing: entry.id);
  }

  Future<void> pause(String id) async {
    final transfer = _active[id];
    if (transfer != null) {
      transfer.cancelled = true;
      transfer.http?.close(force: true);
      await transfer.done;
    }
    final entry = _find(id);
    if (entry.status != OfflineStatus.complete) {
      entry.status = OfflineStatus.paused;
    }
    await _save();
    _notify();
  }

  Future<void> remove(String id) async {
    // Covers the whole removal, including the index write that is only queued
    // after the files are gone, so a directory reopened right here waits for it
    // instead of resurrecting a record that points at a deleted file.
    final operation = _state.begin();
    try {
      await pause(id);
      final entry = _find(id);
      for (final file in [_part(entry), _file(entry)]) {
        if (await file.exists()) await file.delete();
      }
      _entries.remove(entry);
      await _save();
      _notify();
    } finally {
      operation.settle();
    }
  }

  Future<File> completedFile(String id) async {
    final entry = _find(id);
    final file = _file(entry);
    if (entry.status != OfflineStatus.complete ||
        !await file.exists() ||
        await file.length() != entry.total ||
        entry.total <= 0) {
      throw StateError('本地文件缺失或不完整，请重新下载');
    }
    return file;
  }

  /// Queues an atomic `index.json` replacement. The snapshot is produced when
  /// the queued operation runs, never when it is queued, so what lands on disk
  /// always matches the state observed at that point of the queue.
  ///
  /// The queue belongs to the directory, not to this instance: a repository
  /// opened on the same directory later replaces `index.json` only behind the
  /// writes already queued here, so neither can swap the other's file.
  ///
  /// A record named by [completing] is the commit of a finished download: only
  /// that record is written as `complete`, and its memory status changes inside
  /// this same queued operation once the replacement succeeded. A failed
  /// replacement transitions the record before the next snapshot is taken, so no
  /// later write can persist it as complete. Queued writes always land, even
  /// after dispose(), because a restart must never resurrect a deleted record or
  /// lose a finished file.
  Future<void> _save({String? completing}) {
    return _state.write(() async {
      final snapshot = jsonEncode(
        _entries
            .map(
              (e) => e.id == completing
                  ? {...e.toJson(), 'status': OfflineStatus.complete.name}
                  : e.toJson(),
            )
            .toList(),
      );
      final temporary = File('${_index.path}.tmp');
      try {
        await temporary.writeAsString(snapshot, flush: true);
        await temporary.rename(_index.path);
      } catch (_) {
        _settle(
          completing,
          OfflineStatus.failed,
          '无法保存下载记录，请检查磁盘空间和目录权限',
        );
        rethrow;
      }
      _settle(completing, OfflineStatus.complete, null);
    });
  }

  /// Applies the outcome of a queued commit to memory, once, inside the queued
  /// operation so any following snapshot sees it.
  void _settle(String? id, OfflineStatus status, String? error) {
    if (id == null) return;
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry == null) return;
    entry.status = status;
    entry.error = error;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final transfer in _active.values) {
      transfer.cancelled = true;
      transfer.http?.close(force: true);
    }
    super.dispose();
  }
}

/// Process-wide coordination for one offline directory.
///
/// `index.json` is a single path inside the directory, so two repositories
/// opened on it must neither read the index while the other one still owes a
/// commit or a removal write, nor replace `index.json` through one shared
/// `index.json.tmp` at the same time.
class _DirectoryState {
  _DirectoryState._(this.key);

  /// Kept for the process lifetime: a disposed repository may still owe a write
  /// (a removal queued before dispose, a paused transfer), and those writes must
  /// queue behind the same directory's replacements as any newer instance.
  static final Map<String, _DirectoryState> _open =
      <String, _DirectoryState>{};

  /// The state of [directory], created on demand.
  static _DirectoryState attach(Directory directory) {
    final key = directory.absolute.path;
    return _open.putIfAbsent(key, () => _DirectoryState._(key));
  }

  /// The absolute directory path this state coordinates.
  final String key;

  int _pendingWrites = 0;
  Future<void> _writes = Future<void>.value();
  final Set<_DirectoryOperation> _operations = <_DirectoryOperation>{};

  /// Registers one commit or removal whose index write may only be queued
  /// after its file operations already happened.
  _DirectoryOperation begin() {
    final operation = _DirectoryOperation._(this);
    _operations.add(operation);
    return operation;
  }

  /// Queues one atomic `index.json` replacement behind every replacement
  /// already queued on this directory, whichever repository queued it, so two
  /// instances never fill or swap the same `index.json.tmp`.
  Future<void> write(Future<void> Function() replacement) {
    final result = _writes.then((_) => replacement());
    _pendingWrites++;
    _writes = result.then(
      (_) => _pendingWrites--,
      onError: (Object _) => _pendingWrites--,
    );
    return result;
  }

  /// Waits until no commit or removal is in flight and no queued replacement is
  /// outstanding, so a reopened repository reads the settled index.
  Future<void> settle() async {
    while (true) {
      if (_operations.isNotEmpty) {
        await Future.wait(
          _operations.map((operation) => operation.settled).toList(),
        );
        continue;
      }
      if (_pendingWrites == 0) return;
      await _writes;
    }
  }

  void finish(_DirectoryOperation operation) => _operations.remove(operation);
}

/// One in-flight commit or removal: from its first file operation until the
/// index write it still owed has been persisted.
class _DirectoryOperation {
  _DirectoryOperation._(this._state);

  final _DirectoryState _state;
  final Completer<void> _done = Completer<void>();

  Future<void> get settled => _done.future;

  void settle() {
    if (_done.isCompleted) return;
    _state.finish(this);
    _done.complete();
  }
}

class _Transfer {
  bool cancelled = false;
  HttpClient? http;
  Future<void>? done;

  /// True from the first commit step until the completed record is persisted.
  bool committing = false;
}
