import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/library/poster_image_provider.dart';

import '../../support/fake_poster_cache.dart';

void main() {
  final cache = FakePosterCache();

  PosterImageProvider build({
    String itemId = 'movie-1',
    String host = '192.168.1.10:8096',
    String token = 'token-1',
    String? tag = 'abc',
    int? maxWidth = 320,
  }) => PosterImageProvider(
    cache: cache,
    itemId: itemId,
    url: Uri.parse(
      'http://$host/Items/$itemId/Images/Primary'
      '?maxWidth=$maxWidth&tag=$tag&api_key=$token',
    ),
    tag: tag,
    maxWidth: maxWidth,
  );

  test('a token rotation keeps the same image cache key', () {
    final before = build();
    final after = build(token: 'token-2');

    expect(after, before);
    expect(after.hashCode, before.hashCode);
  });

  test('item, tag, width and server each get their own key', () {
    final base = build();
    expect(build(itemId: 'movie-2'), isNot(base));
    expect(build(tag: 'def'), isNot(base));
    expect(build(maxWidth: 640), isNot(base));
    expect(build(host: 'emby.example.com:8096'), isNot(base));
    expect(build(tag: null), isNot(base));
    expect(build(maxWidth: null), isNot(base));
  });

  test('a different cache is a different key', () {
    final other = PosterImageProvider(
      cache: FakePosterCache(),
      itemId: 'movie-1',
      url: build().url,
      tag: 'abc',
      maxWidth: 320,
    );
    expect(other, isNot(build()));
  });

  test('obtainKey resolves synchronously to the provider itself', () async {
    final provider = build();
    expect(await provider.obtainKey(ImageConfiguration.empty), same(provider));
  });

  test('the description never leaks the url or the token', () {
    final description = build().toString();
    expect(description, contains('movie-1'));
    expect(description, isNot(contains('api_key')));
    expect(description, isNot(contains('token-1')));
    expect(description, isNot(contains('http')));
  });
}
