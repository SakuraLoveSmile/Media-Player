import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/media_source.dart';
import 'package:media_player/data/models/person.dart';
import 'package:media_player/features/detail/detail_controller.dart';

import '../../support/fake_library_service.dart';

MediaItem detailItem({
  bool isFavorite = false,
  bool played = false,
  List<MediaSource> mediaSources = const <MediaSource>[],
  String? remoteTrailer = 'https://example.com/trailer',
}) {
  return MediaItem(
    id: 'm-1',
    name: '测试影片',
    type: 'Movie',
    productionYear: 2024,
    runTimeTicks: const Duration(minutes: 128).inMicroseconds * 10,
    overview: '一段简介',
    tagline: '一句标语',
    communityRating: 8.5,
    officialRating: 'PG-13',
    genres: const <String>['科幻', '冒险'],
    people: const <Person>[
      Person(name: '演员甲', role: '角色甲', type: 'Actor', id: 'p-1'),
    ],
    remoteTrailer: remoteTrailer,
    userData: UserItemData(isFavorite: isFavorite, played: played),
    mediaSources: mediaSources,
  );
}

const List<MediaSource> twoSources = <MediaSource>[
  MediaSource(
    id: 'src-1',
    name: '1080p',
    container: 'mkv',
    bitrate: 12000000,
    supportsDirectPlay: true,
    supportsDirectStream: true,
  ),
  MediaSource(
    id: 'src-2',
    name: '4K 重制',
    container: 'mp4',
    bitrate: 40000000,
    supportsDirectPlay: true,
    supportsDirectStream: true,
  ),
];

void main() {
  late FakeLibraryService library;
  DetailController? controller;

  setUp(() {
    library = FakeLibraryService();
  });

  tearDown(() => controller?.dispose());

  DetailController build(
    MediaItem item, {
    Future<bool> Function(Uri url)? urlOpener,
  }) {
    library.itemsById = <String, MediaItem>{item.id: item};
    return controller = DetailController(
      itemId: item.id,
      library: library,
      urlOpener: urlOpener,
    );
  }

  test('load exposes the detail fields', () async {
    final detail = build(detailItem(mediaSources: twoSources));

    await detail.load();

    expect(library.detailRequests, <String>['m-1']);
    final item = detail.state.item!;
    expect(item.name, '测试影片');
    expect(item.tagline, '一句标语');
    expect(item.communityRating, 8.5);
    expect(item.officialRating, 'PG-13');
    expect(item.genres, <String>['科幻', '冒险']);
    expect(item.people.single.role, '角色甲');
    expect(item.remoteTrailer, 'https://example.com/trailer');
    expect(item.mediaSources, hasLength(2));
    expect(detail.state.loading, isFalse);
    expect(detail.state.error, isNull);
    expect(detail.state.selectedSourceId, isNull);
  });

  test('a load failure maps to copy, not a raw exception', () async {
    final detail = build(detailItem());
    library.failure = EmbyException(AppErrorCode.networkUnreachable);

    await detail.load();

    expect(detail.state.error, '无法连接服务器，请检查网络');
    expect(detail.state.item, isNull);
  });

  test('an expired session flags unauthorized without copy', () async {
    final detail = build(detailItem());
    library.unauthorized = true;

    await detail.load();

    expect(detail.state.unauthorized, isTrue);
    expect(detail.state.error, isNull);
  });

  test('the favorite toggle flips optimistically and writes', () async {
    final detail = build(detailItem());
    await detail.load();

    final pending = detail.toggleFavorite();
    // Optimistic: the mark flipped before the write completed.
    expect(detail.state.item!.userData.isFavorite, isTrue);
    await pending;

    expect(library.favoriteWrites, <({String itemId, bool favorite})>[
      (itemId: 'm-1', favorite: true),
    ]);
    expect(detail.state.item!.userData.isFavorite, isTrue);
    expect(detail.state.favoriteBusy, isFalse);

    await detail.toggleFavorite();
    expect(library.favoriteWrites.last, (itemId: 'm-1', favorite: false));
    expect(detail.state.item!.userData.isFavorite, isFalse);
  });

  test('a failed favorite write rolls the mark back', () async {
    final detail = build(detailItem());
    await detail.load();
    library.writeFailure = Exception('offline');

    await detail.toggleFavorite();

    expect(detail.state.item!.userData.isFavorite, isFalse);
    expect(detail.state.writeError, '收藏更新失败，请稍后重试');
    expect(detail.state.favoriteBusy, isFalse);
  });

  test('the watched toggle writes and rolls back on failure', () async {
    final detail = build(detailItem());
    await detail.load();

    final pending = detail.togglePlayed();
    expect(detail.state.item!.userData.played, isTrue);
    await pending;
    expect(library.playedWrites, <({String itemId, bool played})>[
      (itemId: 'm-1', played: true),
    ]);

    library.writeFailure = Exception('offline');
    await detail.togglePlayed();
    expect(detail.state.item!.userData.played, isTrue);
    expect(detail.state.writeError, '观看状态更新失败，请稍后重试');
  });

  test('the version pick accepts known ids and clears with null', () async {
    final detail = build(detailItem(mediaSources: twoSources));
    await detail.load();

    detail.selectSource('src-2');
    expect(detail.state.selectedSourceId, 'src-2');

    detail.selectSource('gone');
    expect(detail.state.selectedSourceId, 'src-2');

    detail.selectSource(null);
    expect(detail.state.selectedSourceId, isNull);
  });

  test('refresh drops a version that no longer exists', () async {
    final detail = build(detailItem(mediaSources: twoSources));
    await detail.load();
    detail.selectSource('src-2');

    library.itemsById['m-1'] = detailItem();
    await detail.refresh();

    expect(detail.state.selectedSourceId, isNull);
    expect(detail.state.loading, isFalse);
  });

  test('refresh picks up the server-side watched state', () async {
    final detail = build(detailItem());
    await detail.load();

    library.itemsById['m-1'] = detailItem(played: true);
    await detail.refresh();

    expect(detail.state.item!.userData.played, isTrue);
  });

  test('the trailer opens through the injected launcher', () async {
    final opened = <Uri>[];
    final detail = build(
      detailItem(),
      urlOpener: (Uri url) async {
        opened.add(url);
        return true;
      },
    );
    await detail.load();

    await detail.openTrailer();

    expect(opened, <Uri>[Uri.parse('https://example.com/trailer')]);
    expect(detail.state.writeError, isNull);
  });

  test('a refused or broken trailer launch only surfaces a notice', () async {
    final detail = build(detailItem(), urlOpener: (Uri url) async => false);
    await detail.load();

    await detail.openTrailer();
    expect(detail.state.writeError, '无法打开预告片链接');

    final throwing = build(
      detailItem(),
      urlOpener: (Uri url) async => throw Exception('no handler'),
    );
    await throwing.load();
    await throwing.openTrailer();
    expect(throwing.state.writeError, '无法打开预告片链接');
  });

  test('without a trailer nothing is opened', () async {
    final opened = <Uri>[];
    final detail = build(
      detailItem(remoteTrailer: null),
      urlOpener: (Uri url) async {
        opened.add(url);
        return true;
      },
    );
    await detail.load();

    await detail.openTrailer();

    expect(opened, isEmpty);
  });
}
