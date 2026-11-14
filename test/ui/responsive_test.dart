import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/ui/responsive.dart';
import 'package:media_player/ui/theme/app_tokens.dart';

void main() {
  group('posterGridColumns', () {
    test('3 columns below the compact breakpoint', () {
      expect(posterGridColumns(0), 3);
      expect(posterGridColumns(400), 3);
      expect(posterGridColumns(599), 3);
    });

    test('4 columns from compact up to medium', () {
      expect(posterGridColumns(600), 4);
      expect(posterGridColumns(800), 4);
      expect(posterGridColumns(899), 4);
    });

    test('5 columns from medium up to expanded', () {
      expect(posterGridColumns(900), 5);
      expect(posterGridColumns(1024), 5);
      expect(posterGridColumns(1199), 5);
    });

    test('6 columns at expanded and beyond', () {
      expect(posterGridColumns(1200), 6);
      expect(posterGridColumns(1920), 6);
    });
  });

  group('posterGridDelegate', () {
    test('uses the responsive fixed column count and shared geometry', () {
      final delegate =
          posterGridDelegate(1200) as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 6);
      expect(delegate.mainAxisSpacing, AppSpacing.xl);
      expect(delegate.crossAxisSpacing, AppSpacing.md);
      expect(delegate.childAspectRatio, posterAspectRatio);

      final narrow =
          posterGridDelegate(400) as SliverGridDelegateWithFixedCrossAxisCount;
      expect(narrow.crossAxisCount, 3);
    });
  });

  group('context helpers', () {
    Future<void> pumpProbe(
      WidgetTester tester,
      Size size,
      void Function(BuildContext context) probe,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      probe(captured);
    }

    testWidgets('isWide turns on at the medium breakpoint', (tester) async {
      await pumpProbe(tester, const Size(400, 800), (context) {
        expect(isWide(context), isFalse);
      });
      await pumpProbe(tester, const Size(899, 800), (context) {
        expect(isWide(context), isFalse);
      });
      await pumpProbe(tester, const Size(900, 800), (context) {
        expect(isWide(context), isTrue);
      });
      await pumpProbe(tester, const Size(1200, 800), (context) {
        expect(isWide(context), isTrue);
      });
    });

    testWidgets('home metrics keep their narrow values below medium', (
      tester,
    ) async {
      await pumpProbe(tester, const Size(400, 800), (context) {
        expect(homeRowCardWidth(context), 130);
        expect(homeRowHeight(context), closeTo(130 / 0.56 + 28, 0.001));
        expect(homeLibraryCardWidth(context), 170);
        // The cover keeps the server's own 16:9 ratio instead of the old
        // 0.66 box that cropped its sides (S28).
        expect(homeLibraryCardHeight(context), closeTo(170 * 9 / 16, 0.001));
        expect(
          homeLibraryStripHeight(context),
          closeTo(
            homeLibraryCardHeight(context) +
                AppSpacing.sm +
                homeLibraryLabelHeight(context) +
                AppSpacing.xs,
            0.001,
          ),
        );
        expect(homeResumeCardWidth(context), 178);
        expect(homeResumeImageHeight(context), closeTo(100.125, 0.001));
        expect(homeResumeRowHeight(context), closeTo(146.125, 0.001));
        expect(homeBannerHeight(context), closeTo(368 / 2.15, 0.001));
      });
    });

    testWidgets('home metrics scale up on wide surfaces', (tester) async {
      await pumpProbe(tester, const Size(1200, 800), (context) {
        expect(homeRowCardWidth(context), 180);
        expect(homeRowHeight(context), closeTo(180 / 0.56 + 28, 0.001));
        expect(homeLibraryCardWidth(context), 240);
        expect(homeLibraryCardHeight(context), closeTo(240 * 9 / 16, 0.001));
        expect(homeResumeCardWidth(context), 280);
        expect(homeResumeImageHeight(context), 157.5);
        expect(homeResumeRowHeight(context), 203.5);
        expect(homeBannerHeight(context), 260);
      });
    });
  });
}
