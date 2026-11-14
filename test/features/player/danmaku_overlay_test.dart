import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/danmaku/danmaku_settings.dart';
import 'package:media_player/data/danmaku/models/danmaku_comment.dart';
import 'package:media_player/features/player/danmaku_overlay.dart';

DanmakuComment comment(
  int id, {
  double seconds = 0,
  int mode = 1,
  String? text,
}) {
  return DanmakuComment(
    id: id,
    time: Duration(milliseconds: (seconds * 1000).round()),
    mode: mode,
    color: 16777215,
    text: text ?? '弹幕$id',
  );
}

void main() {
  /// Fixed 800×400 video box: half area = 200px → 6 lanes at the default
  /// 28.8px line height; full area = 400px → 13 lanes.
  Future<void> pumpOverlay(
    WidgetTester tester, {
    required List<DanmakuComment> comments,
    Duration position = Duration.zero,
    bool playing = false,
    DanmakuSettings settings = const DanmakuSettings(enabled: true),
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 400,
            child: DanmakuOverlay(
              comments: comments,
              position: position,
              playing: playing,
              settings: settings,
            ),
          ),
        ),
      ),
    );
  }

  Finder overlayTexts() => find.descendant(
    of: find.byKey(const Key('danmaku-overlay')),
    matching: find.byType(Text),
  );

  testWidgets('comments spawn once the position reaches their time', (
    tester,
  ) async {
    final List<DanmakuComment> comments = <DanmakuComment>[
      comment(1, seconds: 1),
      comment(2, seconds: 3),
      comment(3, seconds: 6),
    ];
    await pumpOverlay(tester, comments: comments);
    expect(overlayTexts(), findsNothing);

    await pumpOverlay(
      tester,
      comments: comments,
      position: const Duration(seconds: 4),
    );
    expect(find.text('弹幕1'), findsOneWidget);
    expect(find.text('弹幕2'), findsOneWidget);
    expect(find.text('弹幕3'), findsNothing);

    // Steps stay under the 5 s seek-jump threshold so this is playback,
    // not a seek.
    await pumpOverlay(
      tester,
      comments: comments,
      position: const Duration(seconds: 7),
    );
    expect(find.text('弹幕3'), findsOneWidget);
  });

  testWidgets('scroll comments travel right to left and then exit', (
    tester,
  ) async {
    await pumpOverlay(
      tester,
      comments: <DanmakuComment>[comment(1, text: '滚动')],
      playing: true,
    );
    final double start = tester.getTopLeft(find.text('滚动')).dx;
    expect(start, closeTo(800, 1));

    await tester.pump(const Duration(seconds: 2));
    final double midway = tester.getTopLeft(find.text('滚动')).dx;
    expect(midway, lessThan(start));
    expect(midway, greaterThan(0));

    // Base travel time is 8 s; after it the comment is pruned.
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('滚动'), findsNothing);
  });

  testWidgets('a paused overlay freezes mid-flight', (tester) async {
    // The same list instance across rebuilds: a new list is a new episode
    // and would (correctly) reset the lanes.
    final List<DanmakuComment> comments = <DanmakuComment>[
      comment(1, text: '滚动'),
    ];
    await pumpOverlay(tester, comments: comments, playing: true);
    await tester.pump(const Duration(seconds: 2));
    final double paused = tester.getTopLeft(find.text('滚动')).dx;

    await pumpOverlay(tester, comments: comments);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(find.text('滚动')).dx, paused);
  });

  testWidgets('density caps the concurrent comments', (tester) async {
    final List<DanmakuComment> comments = <DanmakuComment>[
      for (int i = 0; i < 12; i++) comment(i),
    ];

    await pumpOverlay(tester, comments: comments);
    // Half area: 6 lanes, density 1.0 → 6 concurrent.
    expect(overlayTexts(), findsNWidgets(6));

    await pumpOverlay(
      tester,
      comments: comments,
      settings: const DanmakuSettings(enabled: true, density: 0.1),
    );
    expect(overlayTexts(), findsNWidgets(1));
  });

  testWidgets('the full area allows more lanes than the top half', (
    tester,
  ) async {
    final List<DanmakuComment> comments = <DanmakuComment>[
      for (int i = 0; i < 12; i++) comment(i),
    ];

    await pumpOverlay(
      tester,
      comments: comments,
      settings: const DanmakuSettings(enabled: true, fullArea: true),
    );
    expect(overlayTexts(), findsNWidgets(12));
  });

  testWidgets('opacity is applied to the whole layer', (tester) async {
    await pumpOverlay(
      tester,
      comments: <DanmakuComment>[comment(1)],
      settings: const DanmakuSettings(enabled: true, opacity: 0.4),
    );

    final Opacity opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const Key('danmaku-overlay')),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0.4);
  });

  testWidgets('the speed multiplier shortens the travel time', (tester) async {
    await pumpOverlay(
      tester,
      comments: <DanmakuComment>[comment(1, text: '快速')],
      playing: true,
      settings: const DanmakuSettings(enabled: true, speed: 2),
    );

    // 8 s base / 2x speed = 4 s on screen.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('快速'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('快速'), findsNothing);
  });

  testWidgets('disabling hides every comment and re-enabling restores', (
    tester,
  ) async {
    final List<DanmakuComment> comments = <DanmakuComment>[comment(1)];
    await pumpOverlay(tester, comments: comments);
    expect(find.text('弹幕1'), findsOneWidget);

    await pumpOverlay(
      tester,
      comments: comments,
      settings: const DanmakuSettings(),
    );
    expect(find.byKey(const Key('danmaku-overlay')), findsNothing);
    expect(find.text('弹幕1'), findsNothing);

    await pumpOverlay(tester, comments: comments);
    expect(find.text('弹幕1'), findsOneWidget);
  });

  testWidgets('mode 5 pins top and mode 4 pins bottom above the band', (
    tester,
  ) async {
    await pumpOverlay(
      tester,
      comments: <DanmakuComment>[
        comment(1, mode: 5, text: '顶部'),
        comment(2, mode: 4, text: '底部'),
      ],
    );

    // The box is centered in the 800×600 test viewport; measure relative
    // to the overlay itself.
    final Rect box = tester.getRect(find.byKey(const Key('danmaku-overlay')));
    final Rect top = tester.getRect(find.text('顶部'));
    expect(top.top - box.top, closeTo(0, 1));
    expect(top.center.dx - box.center.dx, closeTo(0, 1));

    final Rect bottom = tester.getRect(find.text('底部'));
    // Bottom edge sits above the reserved 8% subtitle band (400 * 0.08 = 32).
    expect(box.bottom - bottom.bottom, closeTo(32, 1));
    expect(bottom.center.dx - box.center.dx, closeTo(0, 1));
  });

  testWidgets('a backward seek clears the lanes instead of replaying', (
    tester,
  ) async {
    final List<DanmakuComment> comments = <DanmakuComment>[
      comment(1, seconds: 2),
    ];
    await pumpOverlay(tester, comments: comments);
    await pumpOverlay(
      tester,
      comments: comments,
      position: const Duration(seconds: 4),
    );
    expect(find.text('弹幕1'), findsOneWidget);

    await pumpOverlay(tester, comments: comments);
    expect(find.text('弹幕1'), findsNothing);
  });

  testWidgets('a large forward jump skips the comments in between', (
    tester,
  ) async {
    final List<DanmakuComment> comments = <DanmakuComment>[
      comment(1, seconds: 2),
      comment(2, seconds: 30),
      comment(3, seconds: 40),
    ];
    await pumpOverlay(tester, comments: comments);
    await pumpOverlay(
      tester,
      comments: comments,
      position: const Duration(seconds: 4),
    );
    expect(find.text('弹幕1'), findsOneWidget);

    await pumpOverlay(
      tester,
      comments: comments,
      position: const Duration(seconds: 40),
    );
    // The jump clears the lanes and re-seeds at the new position: comments
    // between 4 s and 40 s are skipped, the one due at 40 s spawns.
    expect(find.text('弹幕1'), findsNothing);
    expect(find.text('弹幕2'), findsNothing);
    expect(find.text('弹幕3'), findsOneWidget);
  });

  testWidgets('the layer ignores pointers so gestures pass through', (
    tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 400,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                GestureDetector(
                  key: const Key('under'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
                DanmakuOverlay(
                  comments: <DanmakuComment>[comment(1)],
                  position: Duration.zero,
                  playing: false,
                  settings: const DanmakuSettings(enabled: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('弹幕1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('under')));
    expect(taps, 1);

    final IgnorePointer ignore = tester.widget<IgnorePointer>(
      find.byKey(const Key('danmaku-overlay')),
    );
    expect(ignore.ignoring, isTrue);
  });
}
