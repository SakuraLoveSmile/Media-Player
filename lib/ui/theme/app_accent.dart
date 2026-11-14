import 'package:flutter/material.dart';

/// The brand seed colour used when no accent override is selected.
///
/// Every palette role (primary, secondary containers, sliders, buttons…) is
/// derived from this seed by [ColorScheme.fromSeed], so replacing the seed is
/// what re-tints the whole app.
const Color appDefaultAccent = Color(0xFF0088FF);

/// One selectable accent preset (设置 → 外观 → 主题色).
///
/// [name] is the stable id persisted in `app.accent.v1`; [label] is the Chinese
/// chip caption; [color] is the seed handed to `buildAppTheme`.
class AppAccentPreset {
  const AppAccentPreset({
    required this.name,
    required this.label,
    required this.color,
  });

  final String name;
  final String label;
  final Color color;
}

/// The preset accent set. `default` keeps the original brand seed; the others
/// are distinct hues so the choice is visible on every Material role.
abstract final class AppAccentPresets {
  static const AppAccentPreset defaultPreset = AppAccentPreset(
    name: 'default',
    label: '默认',
    color: appDefaultAccent,
  );
  static const AppAccentPreset blue = AppAccentPreset(
    name: 'blue',
    label: '蓝',
    color: Color(0xFF2196F3),
  );
  static const AppAccentPreset green = AppAccentPreset(
    name: 'green',
    label: '绿',
    color: Color(0xFF4CAF50),
  );
  static const AppAccentPreset purple = AppAccentPreset(
    name: 'purple',
    label: '紫',
    color: Color(0xFF9C27B0),
  );
  static const AppAccentPreset pink = AppAccentPreset(
    name: 'pink',
    label: '粉',
    color: Color(0xFFE91E63),
  );
  static const AppAccentPreset orange = AppAccentPreset(
    name: 'orange',
    label: '橙',
    color: Color(0xFFFF9800),
  );

  /// Display order, also the chip order in settings.
  static const List<AppAccentPreset> all = <AppAccentPreset>[
    defaultPreset,
    blue,
    green,
    purple,
    pink,
    orange,
  ];

  /// Looks a preset up by its stable storage id; unknown or null means none.
  static AppAccentPreset? byName(String? name) {
    if (name == null) return null;
    for (final AppAccentPreset preset in all) {
      if (preset.name == name) return preset;
    }
    return null;
  }
}
