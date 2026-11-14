import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/router/app_routes.dart';

void main() {
  test('player route carries the item id', () {
    expect(AppRoutes.playerFor('42'), '/player/42');
  });

  test('player route carries the picked version when present', () {
    expect(
      AppRoutes.playerFor('42', source: 'src-2'),
      '/player/42?source=src-2',
    );
    expect(AppRoutes.playerFor('42', source: ''), '/player/42');
  });

  test('player route can pin portrait playback for continuous play', () {
    expect(
      AppRoutes.playerFor('42', source: 'src-2', portrait: true),
      '/player/42?source=src-2&portrait=1',
    );
    expect(AppRoutes.playerFor('42', portrait: true), '/player/42?portrait=1');
    expect(AppRoutes.playerFor('42'), '/player/42');
  });

  test('series route carries the series id', () {
    expect(AppRoutes.seriesFor('series-42'), '/series/series-42');
  });

  test('detail route carries the item id', () {
    expect(AppRoutes.detailFor('42'), '/detail/42');
  });

  test('only transport-level failures are retryable', () {
    expect(AppErrorCode.networkUnreachable.retryable, isTrue);
    expect(AppErrorCode.serverError.retryable, isTrue);
    expect(AppErrorCode.unauthorized.retryable, isFalse);
    expect(AppErrorCode.serverMismatch.retryable, isFalse);
  });
}
