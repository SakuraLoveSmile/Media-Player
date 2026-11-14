import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/library/poster_cache.dart';

void main() {
  late Directory root;
  late Directory directory;
  late List<Uri> fetched;

  const token = 'super-secret-token';
  final poster = Uint8List.fromList(List<int>.generate(64, (i) => i));

  Uri url({String host = '192.168.1.10', String? key}) => Uri.parse(
    'http://$host:8096/Items/item-1/Images/Primary'
    '?maxWidth=400&tag=abc&quality=90&api_key=${key ?? token}',
  );

  Future<Uint8List> fetch(Uri requested) async {
    fetched.add(requested);
    return poster;
  }

  FilePosterCache buildCache({int maxBytes = 1024 * 1024}) =>
      FilePosterCache(directory: directory, fetch: fetch, maxBytes: maxBytes);

  Future<List<File>> files() async => await directory.exists()
      ? (await directory.list().toList()).whereType<File>().toList()
      : <File>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mp_poster_cache_');
    directory = Directory('${root.path}/posters');
    fetched = <Uri>[];
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('a second load is served from disk without a fetch', () async {
    expect(
      await buildCache().load('item-1', url(), maxWidth: 400, tag: 'abc'),
      poster,
    );
    expect(fetched, hasLength(1));

    // A fresh instance models the next app launch: only the disk survives.
    final second = await buildCache().load(
      'item-1',
      url(),
      maxWidth: 400,
      tag: 'abc',
    );
    expect(second, poster);
    expect(fetched, hasLength(1));
  });

  test('a token rotation still hits the cache', () async {
    await buildCache().load('item-1', url(), maxWidth: 400, tag: 'abc');
    final rotated = await buildCache().load(
      'item-1',
      url(key: 'rotated-token'),
      maxWidth: 400,
      tag: 'abc',
    );

    expect(rotated, poster);
    expect(fetched, hasLength(1));
  });

  test('the item tag and width are separate entries', () async {
    final cache = buildCache();
    await cache.load('item-1', url(), maxWidth: 400, tag: 'abc');
    await cache.load('item-1', url(), maxWidth: 400, tag: 'def');
    await cache.load('item-1', url(), maxWidth: 800, tag: 'abc');
    await cache.load('item-2', url(), maxWidth: 400, tag: 'abc');

    expect(fetched, hasLength(4));
    expect(await directory.list().length, 4);
  });

  test('two servers never share an entry for the same item id', () async {
    final cache = buildCache();
    await cache.load('item-1', url(), maxWidth: 400);
    await cache.load('item-1', url(host: 'emby.example.com'), maxWidth: 400);

    expect(fetched, hasLength(2));
  });

  test('nothing on disk names or contains the url, token or api_key', () async {
    await buildCache().load('item-1', url(), maxWidth: 400, tag: 'abc');

    final entities = await directory.list(recursive: true).toList();
    expect(entities, isNotEmpty);
    for (final entity in entities) {
      expect(entity.path, isNot(contains(token)));
      expect(entity.path, isNot(contains('api_key')));
      expect(entity.path, isNot(contains('item-1')));
      if (entity is File) {
        final bytes = await entity.readAsBytes();
        expect(bytes, poster);
        final text = latin1.decode(bytes, allowInvalid: true);
        expect(text, isNot(contains(token)));
        expect(text, isNot(contains('api_key')));
      }
    }
  });

  test('the oldest entries are evicted once the budget is exceeded', () async {
    final cache = buildCache(maxBytes: poster.length * 2);
    final base = DateTime(2026);
    final paths = <String, String>{};

    Future<void> put(String id, int ageInMinutes) async {
      final before = (await files()).map((f) => f.path).toSet();
      await cache.load(id, url(), maxWidth: 400);
      final added = (await files()).firstWhere((f) => !before.contains(f.path));
      paths[id] = added.path;
      // Filesystem mtime granularity is coarser than one write, so pin it.
      await added.setLastModified(base.add(Duration(minutes: ageInMinutes)));
    }

    await put('item-1', 0);
    await put('item-2', 1);
    await put('item-3', 2);

    expect(await File(paths['item-1']!).exists(), isFalse);
    final remaining = await files();
    expect(remaining, hasLength(2));
    final total = remaining.fold<int>(0, (sum, f) => sum + f.lengthSync());
    expect(total, lessThanOrEqualTo(poster.length * 2));

    // The evicted item is a miss again; the survivors are still hits.
    fetched.clear();
    await cache.load('item-2', url(), maxWidth: 400);
    await cache.load('item-3', url(), maxWidth: 400);
    expect(fetched, isEmpty);
    await cache.load('item-1', url(), maxWidth: 400);
    expect(fetched, hasLength(1));
  });

  test(
    'the budget holds across a run of writes and across a relaunch',
    () async {
      final budget = poster.length * 3;
      final cache = buildCache(maxBytes: budget);
      for (var i = 0; i < 8; i++) {
        await cache.load('item-$i', url(), maxWidth: 400);
      }

      Future<void> expectBudget() async {
        final remaining = await files();
        expect(remaining, hasLength(3));
        expect(
          remaining.fold<int>(0, (sum, f) => sum + f.lengthSync()),
          lessThanOrEqualTo(budget),
        );
      }

      await expectBudget();
      expect(fetched, hasLength(8));

      // A new instance must re-measure the directory rather than assume empty.
      await buildCache(maxBytes: budget).load('item-9', url(), maxWidth: 400);
      await expectBudget();
    },
  );

  test('a fetch failure propagates and leaves no entry behind', () async {
    final cache = FilePosterCache(
      directory: directory,
      fetch: (_) async => throw StateError('offline'),
    );

    await expectLater(cache.load('item-1', url()), throwsA(isA<StateError>()));
    expect(await directory.exists(), isFalse);
  });

  test('an empty body is not cached', () async {
    final cache = FilePosterCache(
      directory: directory,
      fetch: (_) async => Uint8List(0),
    );

    expect(await cache.load('item-1', url()), isEmpty);
    expect(await cache.load('item-1', url()), isEmpty);
    expect(await directory.exists(), isFalse);
  });

  test('a truncated entry is a miss, not a decode failure forever', () async {
    await buildCache().load('item-1', url(), maxWidth: 400);
    final file = (await files()).single;
    await file.writeAsBytes(<int>[]);

    expect(await buildCache().load('item-1', url(), maxWidth: 400), poster);
    expect(fetched, hasLength(2));
  });

  test('an unwritable directory degrades to no caching', () async {
    // A file where the cache directory should be: create() fails, load() must
    // still return the fetched bytes.
    final blocked = File('${root.path}/blocked');
    await blocked.writeAsString('not a directory');
    final cache = FilePosterCache(
      directory: Directory(blocked.path),
      fetch: fetch,
    );

    expect(await cache.load('item-1', url()), poster);
    expect(await cache.load('item-1', url()), poster);
    expect(fetched, hasLength(2));
  });
}
