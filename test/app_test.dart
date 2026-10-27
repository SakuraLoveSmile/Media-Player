import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/router/app_routes.dart';

void main() {
  test('player route carries the item id', () {
    expect(AppRoutes.playerFor('42'), '/player/42');
  });

  test('only transport-level failures are retryable', () {
    expect(AppErrorCode.networkUnreachable.retryable, isTrue);
    expect(AppErrorCode.serverError.retryable, isTrue);
    expect(AppErrorCode.unauthorized.retryable, isFalse);
    expect(AppErrorCode.serverMismatch.retryable, isFalse);
  });
}
