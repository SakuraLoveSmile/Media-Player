import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/ui/theme/app_accent.dart';
import 'package:media_player/ui/theme/app_theme.dart';

void main() {
  group('buildAppTheme accent override', () {
    test('default light theme keeps the brand seed', () {
      final ThemeData theme = buildAppTheme(Brightness.light);
      final ColorScheme expected = ColorScheme.fromSeed(
        seedColor: appDefaultAccent,
        brightness: Brightness.light,
      );
      expect(theme.colorScheme.primary, expected.primary);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('default dark theme keeps the brand seed', () {
      final ThemeData theme = buildAppTheme(Brightness.dark);
      final ColorScheme expected = ColorScheme.fromSeed(
        seedColor: appDefaultAccent,
        brightness: Brightness.dark,
      );
      expect(theme.colorScheme.primary, expected.primary);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('an accent replaces the tint in light mode', () {
      const Color accent = Color(0xFFE91E63);
      final ThemeData theme = buildAppTheme(Brightness.light, accent: accent);
      final ColorScheme expected = ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
      );
      expect(theme.colorScheme.primary, expected.primary);
      // It must actually differ from the untouched brand palette.
      expect(
        theme.colorScheme.primary,
        isNot(buildAppTheme(Brightness.light).colorScheme.primary),
      );
    });

    test('an accent replaces the tint in dark mode', () {
      const Color accent = Color(0xFF4CAF50);
      final ThemeData theme = buildAppTheme(Brightness.dark, accent: accent);
      final ColorScheme expected = ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      );
      expect(theme.colorScheme.primary, expected.primary);
      expect(
        theme.colorScheme.primary,
        isNot(buildAppTheme(Brightness.dark).colorScheme.primary),
      );
    });

    test('derived tint roles follow the accent in both brightnesses', () {
      const Color accent = Color(0xFF9C27B0);
      for (final Brightness brightness in Brightness.values) {
        final ThemeData theme = buildAppTheme(brightness, accent: accent);
        final ColorScheme scheme = theme.colorScheme;
        // These roles are all derived from the seed, so they must track it.
        expect(theme.sliderTheme.activeTrackColor, scheme.primary);
        expect(theme.sliderTheme.thumbColor, scheme.primary);
        expect(theme.progressIndicatorTheme.color, scheme.primary);
        expect(
          theme.filledButtonTheme.style!.backgroundColor!.resolve(
            <WidgetState>{},
          ),
          scheme.primary,
        );
        expect(
          theme.textButtonTheme.style!.foregroundColor!.resolve(
            <WidgetState>{},
          ),
          scheme.primary,
        );
      }
    });

    test('a null accent is identical to omitting it', () {
      for (final Brightness brightness in Brightness.values) {
        expect(
          buildAppTheme(brightness, accent: null).colorScheme.primary,
          buildAppTheme(brightness).colorScheme.primary,
        );
      }
    });
  });

  group('accent presets', () {
    test('expose the six expected presets in order', () {
      expect(
        AppAccentPresets.all.map((AppAccentPreset p) => p.name).toList(),
        <String>['default', 'blue', 'green', 'purple', 'pink', 'orange'],
      );
      expect(
        AppAccentPresets.all.map((AppAccentPreset p) => p.label).toList(),
        <String>['默认', '蓝', '绿', '紫', '粉', '橙'],
      );
    });

    test('the default preset is the brand seed', () {
      expect(AppAccentPresets.defaultPreset.color, appDefaultAccent);
    });

    test('every preset seeds a distinct primary', () {
      final Set<Color> primaries = <Color>{};
      for (final AppAccentPreset preset in AppAccentPresets.all) {
        final Color primary = buildAppTheme(
          Brightness.light,
          accent: preset.color,
        ).colorScheme.primary;
        expect(primaries.add(primary), isTrue, reason: preset.name);
      }
      expect(primaries.length, AppAccentPresets.all.length);
    });

    test('byName resolves known ids and rejects unknown ones', () {
      expect(AppAccentPresets.byName('green'), AppAccentPresets.green);
      expect(
        AppAccentPresets.byName('default'),
        AppAccentPresets.defaultPreset,
      );
      expect(AppAccentPresets.byName('neon'), isNull);
      expect(AppAccentPresets.byName(null), isNull);
      expect(AppAccentPresets.byName(''), isNull);
    });
  });
}
