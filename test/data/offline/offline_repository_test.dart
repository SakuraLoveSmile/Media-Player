import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/offline/offline_entry.dart';
import 'package:media_player/data/offline/offline_repository.dart';

import 'offline_test_session.dart';

const movie = MediaItem(id: 'movie', name: '测试电影', type: 'Movie');

/// A second item, so one test can run two original-file downloads whose
/// completion writes land in the same `index.json` queue.
const secondMovie = MediaItem(id: 'movie2', name: '测试剧集', type: 'Episode');

/// Resolves real `dart:io` files without re-entering any test override.
final class _NoOverrides extends IOOverrides {}

/// Serves the original file of [secondMovie] as well, so two downloads can
/// reach their commit inside one repository.
final class _TwoItemSession extends OfflineTestSession {
  _TwoItemSession(super.base);

  @override
  Future<Map<String, dynamic>> authorizedGet(Uri url) async {
    if (!url.path.endsWith('/Items/${secondMovie.id}')) {
      return super.authorizedGet(url);
    }
    jsonCalls++;
    onGet?.call(url);
    return {
      'Id': secondMovie.id,
      'Type': secondMovie.type,
      'CanDownload': canDownload,
      'MediaSources': [
        {
          'Id': 'source',
          'Container': container,
          'Protocol': protocol,
          'Size': size,
        },
      ],
    };
  }
}

/// Holds selected atomic renames and deletions, so a test can observe an
/// in-flight write without relying on timing.
final class _RenameGate extends IOOverrides {
  _RenameGate({
    this.holdIndexWrite,
    this.holdPartRename,
    this.holdDelete,
    this.holdLength,
  });

  /// Holds an `index.json.tmp` replacement whose snapshot matches.
  final bool Function(String snapshot)? holdIndexWrite;

  /// Holds renaming a finished `*.part` file into place.
  final bool Function(String from)? holdPartRename;

  /// Holds deleting a file whose path matches.
  final bool Function(String path)? holdDelete;

  /// Holds reading the length of a file whose path matches.
  final bool Function(String path)? holdLength;

  final List<Completer<void>> _index = <Completer<void>>[];
  final List<Completer<void>> _parts = <Completer<void>>[];
  final List<Completer<void>> _deletes = <Completer<void>>[];
  final List<Completer<void>> _lengths = <Completer<void>>[];

  /// Completed the first time each kind of rename is held, so a regression
  /// fails fast instead of waiting for a rename that is never paused.
  final Completer<void> indexPaused = Completer<void>();
  final Completer<void> partPaused = Completer<void>();
  final Completer<void> deletePaused = Completer<void>();
  final Completer<void> lengthPaused = Completer<void>();

  /// The `index.json` contents each read returned, in order. A repository that
  /// starts reading the index while another one still owes a write is visible
  /// here.
  final List<String> indexReads = <String>[];

  /// The replacement that throws once it is released.
  Completer<void>? _failing;

  int get indexHolds => _index.length;
  int get partHolds => _parts.length;

  Completer<void> holdIndex() {
    final hold = Completer<void>();
    _index.add(hold);
    if (!indexPaused.isCompleted) indexPaused.complete();
    return hold;
  }

  Completer<void> holdPart() {
    final hold = Completer<void>();
    _parts.add(hold);
    if (!partPaused.isCompleted) partPaused.complete();
    return hold;
  }

  Completer<void> parkDelete() {
    final hold = Completer<void>();
    _deletes.add(hold);
    if (!deletePaused.isCompleted) deletePaused.complete();
    return hold;
  }

  Completer<void> parkLength() {
    final hold = Completer<void>();
    _lengths.add(hold);
    if (!lengthPaused.isCompleted) lengthPaused.complete();
    return hold;
  }

  /// Releases parked part renames, so that download can queue its completion
  /// write behind a held replacement.
  void openParts() {
    for (final hold in _parts) {
      if (!hold.isCompleted) hold.complete();
    }
  }

  /// Releases parked file deletions.
  void openDeletes() {
    for (final hold in _deletes) {
      if (!hold.isCompleted) hold.complete();
    }
  }

  /// Releases parked length reads.
  void openLengths() {
    for (final hold in _lengths) {
      if (!hold.isCompleted) hold.complete();
    }
  }

  /// Releases every held replacement without failing any of them.
  void openIndex() {
    for (final hold in _index) {
      if (!hold.isCompleted) hold.complete();
    }
  }

  /// Releases the held replacements, failing the first still-pending one with an
  /// injected `FileSystemException`.
  void failFirstIndex() {
    _failing = _index.where((hold) => !hold.isCompleted).firstOrNull;
    openIndex();
  }

  /// Releases everything, so no failure can leave a hold pending forever.
  void open() {
    openParts();
    openDeletes();
    openLengths();
    openIndex();
  }

  /// Installs the gate process-wide: the index write runs from the repository's
  /// own future continuation, which a zone-scoped override would never reach.
  IOOverrides? install() {
    final previous = IOOverrides.current;
    IOOverrides.global = this;
    return previous;
  }

  /// Restores the overrides that were active before [install].
  void restore(IOOverrides? previous) => IOOverrides.global = previous;

  @override
  File createFile(String path) => _GateFile(path, this);
}

/// Delegates to the real file, holding or failing the renames the gate selects.
class _GateFile extends _DelegatingFile {
  _GateFile(super.path, this._gate);
  final _RenameGate _gate;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    if (_gate.holdDelete?.call(path) ?? false) {
      await _gate.parkDelete().future;
    }
    return super.delete(recursive: recursive);
  }

  @override
  Future<File> rename(String newPath) async {
    if (path.endsWith('index.json.tmp')) {
      final matches = _gate.holdIndexWrite;
      if (matches != null && matches(await readAsString())) {
        final hold = _gate.holdIndex();
        await hold.future;
        if (identical(_gate._failing, hold)) {
          _gate._failing = null;
          throw const FileSystemException('injected commit write failure');
        }
      }
    } else if (path.endsWith('.part') &&
        (_gate.holdPartRename?.call(path) ?? false)) {
      await _gate.holdPart().future;
    }
    return super.rename(newPath);
  }

  @override
  Future<int> length() async {
    if (_gate.holdLength?.call(path) ?? false) {
      await _gate.parkLength().future;
    }
    return super.length();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    final contents = await super.readAsString(encoding: encoding);
    if (path.endsWith('index.json')) _gate.indexReads.add(contents);
    return contents;
  }
}

/// A [File] that forwards every operation to the real file at [path].
class _DelegatingFile implements File {
  _DelegatingFile(this.path);

  @override
  final String path;

  /// Built outside the gate's zone, so delegation can never recurse into itself.
  File get _target =>
      IOOverrides.runWithIOOverrides(() => File(path), _NoOverrides());

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      _target.create(recursive: recursive, exclusive: exclusive);
  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      _target.createSync(recursive: recursive, exclusive: exclusive);
  @override
  Future<File> copy(String newPath) => _target.copy(newPath);
  @override
  File copySync(String newPath) => _target.copySync(newPath);
  @override
  Future<File> rename(String newPath) => _target.rename(newPath);
  @override
  File renameSync(String newPath) => _target.renameSync(newPath);
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _target.delete(recursive: recursive);
  @override
  void deleteSync({bool recursive = false}) =>
      _target.deleteSync(recursive: recursive);
  @override
  Future<bool> exists() => _target.exists();
  @override
  bool existsSync() => _target.existsSync();
  @override
  Future<int> length() => _target.length();
  @override
  int lengthSync() => _target.lengthSync();
  @override
  Future<DateTime> lastAccessed() => _target.lastAccessed();
  @override
  DateTime lastAccessedSync() => _target.lastAccessedSync();
  @override
  Future setLastAccessed(DateTime time) => _target.setLastAccessed(time);
  @override
  void setLastAccessedSync(DateTime time) => _target.setLastAccessedSync(time);
  @override
  Future<DateTime> lastModified() => _target.lastModified();
  @override
  DateTime lastModifiedSync() => _target.lastModifiedSync();
  @override
  Future setLastModified(DateTime time) => _target.setLastModified(time);
  @override
  void setLastModifiedSync(DateTime time) => _target.setLastModifiedSync(time);
  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _target.openSync(mode: mode);
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _target.open(mode: mode);
  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _target.openRead(start, end);
  @override
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) => _target.openWrite(mode: mode, encoding: encoding);
  @override
  Future<Uint8List> readAsBytes() => _target.readAsBytes();
  @override
  Uint8List readAsBytesSync() => _target.readAsBytesSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _target.readAsString(encoding: encoding);
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      _target.readAsStringSync(encoding: encoding);
  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      _target.readAsLines(encoding: encoding);
  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      _target.readAsLinesSync(encoding: encoding);
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _target.writeAsBytes(bytes, mode: mode, flush: flush);
  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _target.writeAsBytesSync(bytes, mode: mode, flush: flush);
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _target.writeAsString(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _target.writeAsStringSync(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
  @override
  Future<FileStat> stat() => _target.stat();
  @override
  FileStat statSync() => _target.statSync();
  @override
  Future<String> resolveSymbolicLinks() => _target.resolveSymbolicLinks();
  @override
  String resolveSymbolicLinksSync() => _target.resolveSymbolicLinksSync();
  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => _target.watch(events: events, recursive: recursive);
  @override
  Uri get uri => _target.uri;
  @override
  File get absolute => _target.absolute;
  @override
  Directory get parent => _target.parent;
  @override
  bool get isAbsolute => _target.isAbsolute;
  @override
  String toString() => _target.toString();
}

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out awaiting download state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Lets queued microtasks and zero-delay timers run for a bounded number of
/// event-loop turns. Used to observe that a reopened repository is still
/// blocked, without treating the wait as a timing guarantee for the outcome.
Future<void> pumpEventLoop([int turns = 40]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory directory;
  late HttpServer server;
  late OfflineTestSession session;
  late OfflineRepository repository;
  late bool stall;

  /// Stream requests that stay open after their first 4 bytes, so a test can
  /// park one download mid-transfer while another finishes.
  late int stallStreams;

  /// When set, a stalled response continues once this completes.
  Completer<void>? stallRelease;
  late bool ignoreRange;
  late bool badRange;
  late bool redirect;
  late int binaryStatus;
  void Function()? onBinary;
  late List<String?> ranges;
  late List<String?> tokens;
  final data = List<int>.generate(12, (i) => i + 1);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    session = _TwoItemSession('http://127.0.0.1:${server.port}');
    repository = OfflineRepository(directory: directory, session: session);
    stall = false;
    stallStreams = 0;
    stallRelease = null;
    ignoreRange = false;
    badRange = false;
    redirect = false;
    binaryStatus = HttpStatus.ok;
    onBinary = null;
    ranges = [];
    tokens = [];
    server.listen((request) async {
      ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      tokens.add(request.headers.value('X-Emby-Token'));
      onBinary?.call();
      expect(
        request.uri.path,
        anyOf('/Videos/movie/stream', '/Videos/${secondMovie.id}/stream'),
      );
      expect(request.uri.queryParameters, {
        'Static': 'true',
        'MediaSourceId': 'source',
      });
      final response = request.response;
      response.bufferOutput = false;
      if (binaryStatus != HttpStatus.ok) {
        response.statusCode = binaryStatus;
        await response.close();
        return;
      }
      if (redirect) {
        response.statusCode = 302;
        response.headers.set(
          'location',
          'http://127.0.0.1:${server.port}/leak',
        );
        await response.close();
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final offset = range != null && !ignoreRange
          ? int.parse(RegExp(r'\d+').firstMatch(range)![0]!)
          : 0;
      if (offset > 0) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${badRange ? offset + 1 : offset}-11/12',
        );
        expect(request.headers.value(HttpHeaders.ifRangeHeader), '"v1"');
      }
      response.headers.set(HttpHeaders.etagHeader, '"v1"');
      response.contentLength = 12 - offset;
      try {
        if (stall || stallStreams > 0) {
          if (stallStreams > 0) stallStreams--;
          response.add(data.sublist(offset, offset + 4));
          await response.flush();
          final release = stallRelease;
          if (release != null) {
            await release.future;
            response.add(data.sublist(offset + 4));
            await response.close();
          }
          // Otherwise the response stays open until the client pauses it.
        } else {
          response.add(data.sublist(offset));
          await response.close();
        }
      } catch (_) {
        /* expected when pause aborts a streaming response */
      }
    });
    await repository.initialize();
  });
  tearDown(() async {
    repository.dispose();
    await server.close(force: true);
    // dispose cancels HTTP synchronously; let its finally close file handles.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await directory.delete(recursive: true);
  });

  test(
    'downloads an original file and persists no credential or URL',
    () async {
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      final file = await repository.completedFile(repository.entries.single.id);
      expect(await file.readAsBytes(), data);
      expect(tokens, ['secret-token']);
      final metadata = await File('${directory.path}/index.json')
          .readAsString();
      expect(metadata, isNot(contains('secret-token')));
      expect(metadata, isNot(contains('http://')));
    },
  );

  test('server download permission denies before fetching binary', () async {
    session.allowed = false;
    await expectLater(repository.enqueue(movie), throwsStateError);
    expect(repository.entries, isEmpty);
    expect(tokens, isEmpty);
  });

  test('pause and validated HTTP Range resume preserve exact bytes', () async {
    stall = true;
    await repository.enqueue(movie);
    await waitFor(() {
      final e = repository.entries.single;
      if (e.status == OfflineStatus.failed) fail('Download failed: ${e.error}');
      return e.received == 4;
    });
    final id = repository.entries.single.id;
    await repository.pause(id);
    expect(repository.entries.single.status, OfflineStatus.paused);
    stall = false;
    await repository.resume(id);
    await waitFor(
      () => repository.entries.single.status == OfflineStatus.complete,
    );
    expect(ranges, [null, 'bytes=4-']);
    expect(await (await repository.completedFile(id)).readAsBytes(), data);
  });

  test(
    'server ignoring Range replaces the part instead of appending',
    () async {
      stall = true;
      await repository.enqueue(movie);
      await waitFor(() {
        final e = repository.entries.single;
        if (e.status == OfflineStatus.failed) {
          fail('Download failed: ${e.error}');
        }
        return e.received == 4;
      });
      final id = repository.entries.single.id;
      await repository.pause(id);
      stall = false;
      ignoreRange = true;
      await repository.resume(id);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      expect(await (await repository.completedFile(id)).readAsBytes(), data);
    },
  );

  test('invalid Content-Range cannot become a completed file', () async {
    stall = true;
    await repository.enqueue(movie);
    await waitFor(() {
      final e = repository.entries.single;
      if (e.status == OfflineStatus.failed) fail('Download failed: ${e.error}');
      return e.received == 4;
    });
    final id = repository.entries.single.id;
    await repository.pause(id);
    stall = false;
    badRange = true;
    await repository.resume(id);
    await waitFor(
      () => repository.entries.single.status == OfflineStatus.failed,
    );
    expect(repository.entries.single.validator, isNull);
    await expectLater(repository.completedFile(id), throwsStateError);
  });

  test(
    'resume refuses another account and redirect never forwards token',
    () async {
      redirect = true;
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.failed,
      );
      expect(tokens, hasLength(1));
      session.userId = 'other-user';
      await expectLater(
        repository.resume(repository.entries.single.id),
        throwsStateError,
      );
      expect(tokens, hasLength(1));
    },
  );

  test('complete file is available after restart without a session', () async {
    // Hold the atomic `index.json` replacement that persists the completed
    // record: a restart in that window must never resurrect a finished file.
    final gate = _RenameGate(
      holdIndexWrite: (snapshot) => snapshot.contains('"status":"complete"'),
    );
    final previous = gate.install();
    try {
      await repository.enqueue(movie);
      await gate.indexPaused.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('The completed index write was never paused'),
      );
      // The part was already renamed, yet the record must still be in flight.
      expect(repository.entries.single.status, OfflineStatus.downloading);
    } finally {
      gate.open();
      gate.restore(previous);
    }
    final id = repository.entries.single.id;
    await waitFor(
      () => repository.entries.single.status == OfflineStatus.complete,
    );
    // First observation of `complete` is the restart point: dispose right here,
    // with the index already atomically replaced by the commit.
    expect(tokens, ['secret-token']);
    repository.dispose();
    session.endpoint = null;
    session.accessToken = null;
    session.userId = null;
    final calls = session.jsonCalls;
    final downloads = List<String?>.of(tokens);
    repository = OfflineRepository(directory: directory, session: session);
    await repository.initialize();
    expect(repository.entries.single.id, id);
    expect(repository.entries.single.status, OfflineStatus.complete);
    expect(await (await repository.completedFile(id)).readAsBytes(), data);
    expect(session.jsonCalls, calls);
    expect(tokens, downloads);
    await repository.remove(id);
    expect(repository.entries, isEmpty);
    expect(
      await directory.list().where((e) => e.path.endsWith('.mkv')).isEmpty,
      isTrue,
    );
  });

  test(
    'corrupt index is retained and recognizable local files recover',
    () async {
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      repository.dispose();
      await File('${directory.path}/index.json').writeAsString('{broken');
      repository = OfflineRepository(directory: directory, session: session);
      await repository.initialize();
      expect(repository.initializationError, isNotNull);
      expect(repository.entries.single.status, OfflineStatus.complete);
      expect(
        await (await repository.completedFile(repository.entries.single.id))
            .readAsBytes(),
        data,
      );
      final files = await directory.list().toList();
      expect(files.where((e) => e.path.contains('.corrupt-')), hasLength(1));
    },
  );

  test(
    'restart turns persisted downloading into paused without network calls',
    () async {
      stall = true;
      await repository.enqueue(movie);
      await waitFor(() {
        final e = repository.entries.single;
        if (e.status == OfflineStatus.failed) {
          fail('Download failed: ${e.error}');
        }
        return e.received == 4;
      });
      final id = repository.entries.single.id;
      await repository.pause(id);
      final index = File('${directory.path}/index.json');
      final raw = jsonDecode(await index.readAsString()) as List<dynamic>;
      raw.single['status'] = 'downloading';
      await index.writeAsString(jsonEncode(raw));
      repository.dispose();
      session.endpoint = null;
      repository = OfflineRepository(directory: directory, session: session);
      await repository.initialize();
      expect(repository.entries.single.status, OfflineStatus.paused);
      expect(repository.entries.single.received, 4);
    },
  );
  test('remote and STRM sources are refused before binary download', () async {
    session.protocol = 'Http';
    await expectLater(repository.enqueue(movie), throwsStateError);
    session.protocol = 'File';
    session.container = 'strm';
    await expectLater(repository.enqueue(movie), throwsStateError);
    expect(tokens, isEmpty);
    expect(repository.entries, isEmpty);
  });

  test(
    'a full part from interrupted finalization restarts without invalid Range',
    () async {
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      final entry = repository.entries.single;
      final file = await repository.completedFile(entry.id);
      await file.rename('${file.path}.part');
      await repository.pause(
        entry.id,
      ); // settle the completed transfer's finally
      repository.dispose();
      final index = File('${directory.path}/index.json');
      final raw = jsonDecode(await index.readAsString()) as List<dynamic>;
      raw.single['status'] = 'paused';
      await index.writeAsString(jsonEncode(raw));
      repository = OfflineRepository(directory: directory, session: session);
      await repository.initialize();
      await repository.resume(entry.id);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      expect(ranges, [null, null]);
      expect(
        await (await repository.completedFile(entry.id)).readAsBytes(),
        data,
      );
    },
  );

  test(
    'a failed notification may reenter resume without losing the new transfer',
    () async {
      redirect = true;
      var retried = false;
      repository.addListener(() {
        if (repository.entries.isNotEmpty &&
            repository.entries.single.status == OfflineStatus.failed &&
            !retried) {
          retried = true;
          redirect = false;
          unawaited(repository.resume(repository.entries.single.id));
        }
      });
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      expect(retried, isTrue);
      expect(tokens, hasLength(2));
      expect(
        await (await repository.completedFile(repository.entries.single.id))
            .readAsBytes(),
        data,
      );
    },
  );
  test('missing item download permission fails closed', () async {
    session.canDownload = null;
    await expectLater(repository.enqueue(movie), throwsStateError);
    expect(tokens, isEmpty);
    expect(repository.entries, isEmpty);
  });

  test(
    'account change during policy query stops before item query or binary',
    () async {
      session.onGet = (_) {
        session.userId = 'other';
      };
      await expectLater(repository.enqueue(movie), throwsStateError);
      expect(session.jsonCalls, 1);
      expect(tokens, isEmpty);
      expect(repository.entries, isEmpty);
    },
  );
  test(
    'binary 401 invalidates only the still-matching authenticated session',
    () async {
      var unauthorizedCalls = 0;
      repository.dispose();
      repository = OfflineRepository(
        directory: directory,
        session: session,
        onUnauthorized: () async {
          unauthorizedCalls++;
          session.accessToken = null;
        },
      );
      await repository.initialize();
      binaryStatus = HttpStatus.unauthorized;
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.failed,
      );
      expect(unauthorizedCalls, 1);
    },
  );

  test(
    '401 from an old transfer cannot log out a replacement account',
    () async {
      var unauthorizedCalls = 0;
      repository.dispose();
      repository = OfflineRepository(
        directory: directory,
        session: session,
        onUnauthorized: () async {
          unauthorizedCalls++;
        },
      );
      await repository.initialize();
      binaryStatus = HttpStatus.unauthorized;
      onBinary = () {
        session.userId = 'replacement-user';
        session.accessToken = 'replacement-token';
      };
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.failed,
      );
      expect(unauthorizedCalls, 0);
      expect(session.accessToken, 'replacement-token');
    },
  );

  test('a commit that cannot save its record fails closed', () async {
    // The rename succeeds but persisting `complete` throws: the entry must not
    // claim a readable file, and a restart must not resurrect it as complete.
    final gate = _RenameGate(
      holdIndexWrite: (snapshot) => snapshot.contains('"status":"complete"'),
    );
    final previous = gate.install();
    try {
      await repository.enqueue(movie);
      await gate.indexPaused.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('The completed index write was never paused'),
      );
    } finally {
      gate.failFirstIndex();
      gate.restore(previous);
    }
    await waitFor(
      () => repository.entries.single.status == OfflineStatus.failed,
    );
    await expectLater(
      repository.completedFile(repository.entries.single.id),
      throwsStateError,
    );
    final id = repository.entries.single.id;
    repository.dispose();
    repository = OfflineRepository(directory: directory, session: session);
    await repository.initialize();
    expect(repository.entries.single.id, id);
    expect(repository.entries.single.status, isNot(OfflineStatus.complete));
  });

  test(
    'a failing completion write cannot persist another queued completion',
    () async {
      // A finishes its transfer first, but its `index.json` replacement is
      // held. B then finishes and queues its own completion behind that held
      // write. Disposing the repository and failing A's replacement must leave
      // A unpersisted while B keeps a readable completed record.
      stallStreams = 1;
      stallRelease = Completer<void>();
      await repository.enqueue(movie);
      await waitFor(() {
        final entry = repository.entries.single;
        if (entry.status == OfflineStatus.failed) {
          fail('Download failed: ${entry.error}');
        }
        return entry.received == 4;
      });
      final firstId = repository.entries.single.id;
      var heldPart = false;
      final gate = _RenameGate(
        // Park whichever download finishes first, before it queues its commit.
        holdPartRename: (from) {
          if (heldPart || !from.endsWith('.part')) return false;
          return heldPart = true;
        },
        holdIndexWrite: (snapshot) =>
            (jsonDecode(snapshot) as List<dynamic>).any(
              (raw) =>
                  (raw as Map<String, dynamic>)['id'] == firstId &&
                  raw['status'] == OfflineStatus.complete.name,
            ),
      );
      late String secondId;
      final previous = gate.install();
      try {
        await repository.enqueue(secondMovie);
        secondId = repository.entries
            .firstWhere((e) => e.itemId == secondMovie.id)
            .id;
        await gate.partPaused.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('The finished part was never held'),
        );
        // Let A finish: its completion write is now held, with B parked right
        // before the write that must queue behind it.
        stallRelease!.complete();
        await gate.indexPaused.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('The failing completion write was never held'),
        );
        gate.openParts();
        await waitFor(
          () => File('${directory.path}/$secondId.mkv').existsSync(),
        );
        for (var i = 0; i < 10; i++) {
          // Let B's completion write reach the queue; the assertions below do
          // not depend on how far it got, only on what is persisted.
          await Future<void>.delayed(Duration.zero);
        }
        repository.dispose();
        gate.failFirstIndex();
      } finally {
        gate.open();
        gate.restore(previous);
      }
      final index = File('${directory.path}/index.json');
      await waitFor(() {
        if (!index.existsSync()) return false;
        return (jsonDecode(index.readAsStringSync()) as List<dynamic>).any(
          (raw) =>
              (raw as Map<String, dynamic>)['id'] == secondId &&
              raw['status'] == OfflineStatus.complete.name,
        );
      });
      // No login session: a restart can only rely on the persisted index.
      session.endpoint = null;
      session.accessToken = null;
      session.userId = null;
      final calls = session.jsonCalls;
      final downloads = List<String?>.of(tokens);
      repository = OfflineRepository(directory: directory, session: session);
      await repository.initialize();
      expect(session.jsonCalls, calls);
      expect(tokens, downloads);
      final failed = repository.entries.firstWhere((e) => e.id == firstId);
      expect(failed.status, isNot(OfflineStatus.complete));
      await expectLater(repository.completedFile(firstId), throwsStateError);
      final complete = repository.entries.firstWhere((e) => e.id == secondId);
      expect(complete.id, secondId);
      expect(complete.status, OfflineStatus.complete);
      expect(
        await (await repository.completedFile(secondId)).readAsBytes(),
        data,
      );
    },
  );

  test('a removal queued before dispose still lands', () async {
    await repository.enqueue(movie);
    await waitFor(
      () => repository.entries.single.status == OfflineStatus.complete,
    );
    final id = repository.entries.single.id;
    // Park the removal right before the index write it still owes, so that
    // write is only queued once the repository is already disposed.
    final gate = _RenameGate(holdDelete: (path) => path.endsWith('$id.mkv'));
    final previous = gate.install();
    late Future<void> removal;
    try {
      removal = repository.remove(id);
      await gate.deletePaused.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('The removal never reached its file deletion'),
      );
      repository.dispose();
    } finally {
      gate.open();
      gate.restore(previous);
    }
    await removal;
    final index = File('${directory.path}/index.json');
    // The removal only completes once its queued index write landed.
    expect(jsonDecode(await index.readAsString()), isEmpty);
    expect(
      await directory.list().where((e) => e.path.contains(id)).isEmpty,
      isTrue,
    );
    // No login session: a restart can only rely on the persisted index, which
    // must not keep a record pointing at the deleted file.
    session.endpoint = null;
    session.accessToken = null;
    session.userId = null;
    repository = OfflineRepository(directory: directory, session: session);
    await repository.initialize();
    expect(repository.entries, isEmpty);
    expect(jsonDecode(await index.readAsString()), isEmpty);
  });

  test(
    'a completion in flight when the directory reopens keeps both files',
    () async {
      // A is already complete and settled on disk.
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      final firstId = repository.entries.single.id;
      // B renames its part into place, but its `complete` record is only about
      // to be queued: the reopen below lands inside that exact window.
      var heldOnce = false;
      final gate = _RenameGate(
        holdIndexWrite: (snapshot) {
          if (heldOnce) return false;
          final holds = (jsonDecode(snapshot) as List<dynamic>).any(
            (raw) =>
                (raw as Map<String, dynamic>)['itemId'] == secondMovie.id &&
                raw['status'] == OfflineStatus.complete.name,
          );
          return heldOnce = holds;
        },
      );
      final previous = gate.install();
      late OfflineRepository reopened;
      try {
        await repository.enqueue(secondMovie);
        final secondId = repository.entries
            .firstWhere((e) => e.itemId == secondMovie.id)
            .id;
        await gate.indexPaused.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('The completion write was never held'),
        );
        // The finished file is already in place; only its record is in flight.
        expect(File('${directory.path}/$secondId.mkv').existsSync(), isTrue);
        // Restart with no login session: only the directory can be trusted.
        session.endpoint = null;
        session.accessToken = null;
        session.userId = null;
        final calls = session.jsonCalls;
        final downloads = List<String?>.of(tokens);
        repository.dispose();
        reopened = OfflineRepository(directory: directory, session: session);
        // Handed to tearDown immediately, so a failure below cannot dispose the
        // repository that was already disposed above.
        repository = reopened;
        var settled = false;
        final reopening = reopened.initialize();
        unawaited(
          reopening.then(
            (_) => settled = true,
            onError: (Object _) => settled = true,
          ),
        );
        await pumpEventLoop();
        // It must wait for the commit the old instance still owes instead of
        // reading the stale index, which its own write would then overwrite.
        expect(settled, isFalse, reason: 'the reopen read the index too early');
        expect(gate.indexReads, isEmpty);
        gate.openIndex();
        await reopening;
        expect(reopened.entries, hasLength(2));
        final first = reopened.entries.firstWhere((e) => e.id == firstId);
        expect(first.status, OfflineStatus.complete);
        expect(
          await (await reopened.completedFile(firstId)).readAsBytes(),
          data,
        );
        final second = reopened.entries.firstWhere((e) => e.id == secondId);
        expect(second.status, OfflineStatus.complete);
        expect(
          await (await reopened.completedFile(secondId)).readAsBytes(),
          data,
        );
        expect(session.jsonCalls, calls);
        expect(tokens, downloads);
      } finally {
        gate.open();
        gate.restore(previous);
      }
    },
  );

  test(
    'a deletion in flight when the directory reopens does not resurrect it',
    () async {
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      final id = repository.entries.single.id;
      // The file deletion is parked, so the removal still owes its index write
      // when the directory is reopened.
      final gate = _RenameGate(holdDelete: (path) => path.endsWith('$id.mkv'));
      final previous = gate.install();
      late OfflineRepository reopened;
      late Future<void> removal;
      try {
        removal = repository.remove(id);
        await gate.deletePaused.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('The removal never reached its file deletion'),
        );
        session.endpoint = null;
        session.accessToken = null;
        session.userId = null;
        final calls = session.jsonCalls;
        final downloads = List<String?>.of(tokens);
        repository.dispose();
        reopened = OfflineRepository(directory: directory, session: session);
        repository = reopened;
        var settled = false;
        final reopening = reopened.initialize();
        unawaited(
          reopening.then(
            (_) => settled = true,
            onError: (Object _) => settled = true,
          ),
        );
        await pumpEventLoop();
        // The stale index still lists the entry and its file still exists, so
        // reading it here would resurrect a record the removal already dropped.
        expect(
          settled,
          isFalse,
          reason: 'the reopen read the index before the removal settled',
        );
        expect(gate.indexReads, isEmpty);
        gate.openDeletes();
        await reopening;
        await removal;
        final index = File('${directory.path}/index.json');
        expect(reopened.entries, isEmpty);
        expect(jsonDecode(await index.readAsString()), isEmpty);
        expect(
          await directory.list().where((e) => e.path.contains(id)).isEmpty,
          isTrue,
        );
        expect(session.jsonCalls, calls);
        expect(tokens, downloads);
      } finally {
        gate.open();
        gate.restore(previous);
      }
    },
  );

  test(
    'a length check in flight when the directory reopens pauses the download',
    () async {
      // A is already complete and settled on disk.
      await repository.enqueue(movie);
      await waitFor(
        () => repository.entries.single.status == OfflineStatus.complete,
      );
      final firstId = repository.entries.single.id;
      // B's final length read is the last asynchronous step before it would
      // register a commit: the reopen below lands inside exactly that window.
      var heldOnce = false;
      final gate = _RenameGate(
        holdLength: (path) {
          if (heldOnce || !path.endsWith('.part')) return false;
          return heldOnce = true;
        },
      );
      final previous = gate.install();
      late OfflineRepository reopened;
      try {
        await repository.enqueue(secondMovie);
        final secondId = repository.entries
            .firstWhere((e) => e.itemId == secondMovie.id)
            .id;
        await gate.lengthPaused.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('The final length read was never held'),
        );
        // Restart with no login session: only the directory can be trusted.
        session.endpoint = null;
        session.accessToken = null;
        session.userId = null;
        final calls = session.jsonCalls;
        final downloads = List<String?>.of(tokens);
        repository.dispose();
        reopened = OfflineRepository(directory: directory, session: session);
        repository = reopened;
        await reopened.initialize();
        // The stale transfer registered no commit, so the reopen reads the
        // index as it stands and B stays an unfinished download.
        final unfinished = reopened.entries.firstWhere((e) => e.id == secondId);
        expect(unfinished.status, OfflineStatus.paused);
        expect(File('${directory.path}/$secondId.mkv').existsSync(), isFalse);
        expect(
          File('${directory.path}/$secondId.mkv.part').existsSync(),
          isTrue,
        );
        final finished = reopened.entries.firstWhere((e) => e.id == firstId);
        expect(finished.status, OfflineStatus.complete);
        expect(
          await (await reopened.completedFile(firstId)).readAsBytes(),
          data,
        );
        // Releasing the stale read must neither rename the part nor replace the
        // index the reopened repository already settled.
        gate.openLengths();
        await pumpEventLoop(120);
        expect(File('${directory.path}/$secondId.mkv').existsSync(), isFalse);
        expect(
          File('${directory.path}/$secondId.mkv.part').existsSync(),
          isTrue,
        );
        final persisted = jsonDecode(
          await File('${directory.path}/index.json').readAsString(),
        ) as List<dynamic>;
        final record = persisted.cast<Map<String, dynamic>>().firstWhere(
          (raw) => raw['id'] == secondId,
        );
        expect(record['status'], OfflineStatus.paused.name);
        expect(
          reopened.entries.firstWhere((e) => e.id == secondId).status,
          OfflineStatus.paused,
        );
        await expectLater(reopened.completedFile(secondId), throwsStateError);
        expect(session.jsonCalls, calls);
        expect(tokens, downloads);
      } finally {
        gate.open();
        gate.restore(previous);
      }
    },
  );
}
