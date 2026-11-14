import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/device/brightness.dart';
import 'package:media_player/features/player/player_gestures.dart';

class FakeBrightness implements BrightnessService {
  double value = 0.5;
  final List<double> sets = <double>[];
  int resets = 0;

  @override
  Future<double> current() async => value;

  @override
  Future<void> set(double v) async {
    value = v;
    sets.add(v);
  }

  @override
  Future<void> reset() async => resets++;
}

void main() {
  group('gesture math', () {
    test(
      'vertical swipe up increases, down decreases, full height = full range',
      () {
        expect(verticalLevelDelta(-400, 400), 1.0);
        expect(verticalLevelDelta(400, 400), -1.0);
        expect(verticalLevelDelta(-100, 400), 0.25);
        expect(verticalLevelDelta(0, 0), 0);
      },
    );

    test('seek span caps at 90s but uses whole item when shorter', () {
      expect(
        seekSpan(const Duration(seconds: 50)),
        const Duration(seconds: 50),
      );
      expect(
        seekSpan(const Duration(seconds: 1000)),
        const Duration(seconds: 90),
      );
      expect(seekSpan(Duration.zero), Duration.zero);
    });

    test('horizontal delta scales by width and span', () {
      expect(
        horizontalSeekDelta(100, 400, const Duration(seconds: 90)),
        const Duration(milliseconds: 22500),
      );
      expect(
        horizontalSeekDelta(-100, 400, const Duration(seconds: 90)),
        const Duration(milliseconds: -22500),
      );
      expect(
        horizontalSeekDelta(100, 0, const Duration(seconds: 90)),
        Duration.zero,
      );
    });

    test('clampDuration bounds to [0, max]', () {
      expect(
        clampDuration(const Duration(seconds: -1), const Duration(seconds: 10)),
        Duration.zero,
      );
      expect(
        clampDuration(const Duration(seconds: 20), const Duration(seconds: 10)),
        const Duration(seconds: 10),
      );
      expect(
        clampDuration(const Duration(seconds: 5), const Duration(seconds: 10)),
        const Duration(seconds: 5),
      );
    });
  });

  group('PlayerGestureLayer', () {
    late FakeBrightness brightness;
    late List<double> volumes;
    late List<Duration> seeks;

    setUp(() {
      brightness = FakeBrightness();
      volumes = <double>[];
      seeks = <Duration>[];
    });

    Widget pumpLayer(WidgetTester tester, {VoidCallback? onTap}) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 400,
              child: PlayerGestureLayer(
                volume: 0.5,
                onVolume: volumes.add,
                position: const Duration(seconds: 60),
                duration: const Duration(seconds: 1000),
                onSeek: seeks.add,
                brightness: brightness,
                onTap: onTap,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'right-half vertical drag raises volume live and shows indicator',
      (tester) async {
        await tester.pumpWidget(pumpLayer(tester));
        await tester.pump();

        final gesture = await tester.startGesture(const Offset(300, 200));
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump();

        expect(volumes, isNotEmpty);
        expect(volumes.last, greaterThan(0.5));
        expect(volumes.last, lessThanOrEqualTo(1.0));
        expect(brightness.sets, isEmpty);
        expect(find.textContaining('音量'), findsOneWidget);
        expect(
          tester
              .widget<Material>(
                find
                    .ancestor(
                      of: find.byIcon(Icons.volume_up),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color,
          Colors.black.withValues(alpha: 0.6),
        );

        await gesture.up();
        await tester.pump();
        expect(find.textContaining('音量'), findsNothing);
        expect(seeks, isEmpty);
      },
    );

    testWidgets('left-half vertical drag drives brightness, not volume', (
      tester,
    ) async {
      await tester.pumpWidget(pumpLayer(tester));
      await tester.pump();

      final gesture = await tester.startGesture(const Offset(100, 200));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();

      expect(brightness.sets, isNotEmpty);
      expect(brightness.sets.last, greaterThan(0.5));
      expect(volumes, isEmpty);
      expect(find.textContaining('亮度'), findsOneWidget);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('horizontal drag previews then seeks once on release', (
      tester,
    ) async {
      await tester.pumpWidget(pumpLayer(tester));
      await tester.pump();

      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();

      // Preview visible, but no seek committed yet.
      expect(find.textContaining('/'), findsOneWidget);
      expect(seeks, isEmpty);

      await gesture.up();
      await tester.pump();

      expect(seeks, hasLength(1));
      expect(seeks.single, greaterThan(const Duration(seconds: 60)));
      expect(seeks.single, lessThanOrEqualTo(const Duration(seconds: 150)));
      expect(volumes, isEmpty);
      expect(brightness.sets, isEmpty);
    });

    testWidgets('drags starting in the system-gesture margin are ignored', (
      tester,
    ) async {
      await tester.pumpWidget(pumpLayer(tester));
      await tester.pump();

      // Left 16dp margin.
      final left = await tester.startGesture(const Offset(5, 200));
      await left.moveBy(const Offset(0, -100));
      await tester.pump();
      await left.up();

      // Bottom 16dp margin.
      final bottom = await tester.startGesture(const Offset(200, 395));
      await bottom.moveBy(const Offset(100, 0));
      await tester.pump();
      await bottom.up();
      await tester.pump();

      expect(volumes, isEmpty);
      expect(brightness.sets, isEmpty);
      expect(seeks, isEmpty);
    });

    testWidgets('a plain tap invokes onTap; a drag does not', (tester) async {
      int taps = 0;
      await tester.pumpWidget(pumpLayer(tester, onTap: () => taps++));
      await tester.pump();

      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      expect(taps, 1);

      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(taps, 1);
    });
  });
}
