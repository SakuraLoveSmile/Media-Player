import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/offline/offline_entry.dart';
import 'package:media_player/data/offline/offline_repository.dart';

import 'offline_test_session.dart';

const movie = MediaItem(id: 'movie', name: '测试电影', type: 'Movie');

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out awaiting download state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory directory;
  late HttpServer server;
  late OfflineTestSession session;
  late OfflineRepository repository;
  late bool stall;
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
    session = OfflineTestSession('http://127.0.0.1:${server.port}');
    repository = OfflineRepository(directory: directory, session: session);
    stall = false;
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
      expect(request.uri.path, '/Videos/movie/stream');
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
        if (stall) {
          response.add(data.sublist(offset, offset + 4));
          await response.flush();
          // The response remains open until the client pauses it.
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
    await repository.enqueue(movie);
    await waitFor(
      () => repository.entries.single.status == OfflineStatus.complete,
    );
    final id = repository.entries.single.id;
    repository.dispose();
    session.endpoint = null;
    session.accessToken = null;
    session.userId = null;
    final calls = session.jsonCalls;
    repository = OfflineRepository(directory: directory, session: session);
    await repository.initialize();
    expect(await (await repository.completedFile(id)).readAsBytes(), data);
    expect(session.jsonCalls, calls);
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
}
