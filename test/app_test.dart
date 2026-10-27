import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/router/app_routes.dart';

void main() {
  testWidgets('startup page is the initial route', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MediaPlayerApp()));

    expect(find.text('Media Player'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
  });

  testWidgets('startup routes to the login placeholder', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MediaPlayerApp()));

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('登录页占位'), findsOneWidget);
  });

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
