import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/main.dart';

void main() {
  testWidgets('app boots to a stable first frame', (tester) async {
    await tester.pumpWidget(const MediaPlayerApp());

    expect(find.text('Media Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
