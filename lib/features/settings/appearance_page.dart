import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/accent_settings.dart';
import '../../app/appearance_settings.dart';
import '../../app/theme_mode_settings.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loader.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_accent.dart';
import '../../ui/theme/app_tokens.dart';

/// 外观 (S62): the app-wide theme mode / accent plus the navigation style
/// Yamby lets you pick between a floating capsule and the standard bottom bar.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final AsyncValue<AppearanceSettings> async = ref.watch(
      appearanceSettingsControllerProvider,
    );
    final AppearanceSettings settings =
        async.value ?? const AppearanceSettings();
    final bool loading = async.isLoading;
    final AppearanceSettingsController controller = ref.read(
      appearanceSettingsControllerProvider.notifier,
    );

    // App-wide theme + accent. The root MaterialApp watches the same providers,
    // so a tap here repaints every page without a restart.
    final AsyncValue<ThemeMode> themeModeAsync = ref.watch(
      themeModeControllerProvider,
    );
    final ThemeMode themeMode = themeModeAsync.value ?? ThemeMode.system;
    final AsyncValue<AccentPreference> accentAsync = ref.watch(
      accentControllerProvider,
    );
    final AccentPreference accent =
        accentAsync.value ?? AccentPreference.defaults;

    return AppPage(
      title: '外观',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('appearance-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          AppSection(
            header: '主题',
            footer: '播放页始终使用深色，不受此设置影响',
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.contrast, color: palette.primary),
                title: const Text('主题模式'),
                subtitle: Text(
                  themeModeAsync.isLoading
                      ? '读取中…'
                      : '当前：${_themeModeLabel(themeMode)}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final ThemeMode mode in ThemeMode.values)
                      ChoiceChip(
                        key: Key('settings-theme-${mode.name}'),
                        label: Text(_themeModeLabel(mode)),
                        selected: themeMode == mode,
                        onSelected: themeModeAsync.isLoading
                            ? null
                            : (_) => unawaited(
                                _selectThemeMode(context, ref, mode),
                              ),
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: Icon(Icons.palette_outlined, color: palette.primary),
                title: const Text('主题色'),
                subtitle: Text(
                  accentAsync.isLoading ? '读取中…' : '当前：${_accentLabel(accent)}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final AppAccentPreset preset in AppAccentPresets.all)
                      ChoiceChip(
                        key: Key('settings-accent-${preset.name}'),
                        avatar: _AccentDot(color: preset.color),
                        label: Text(preset.label),
                        // While Monet is on the system colour wins, so no preset
                        // chip reads as selected; the stored preset is only the
                        // fallback for platforms without dynamic colour.
                        selected:
                            accent.mode != AccentMode.monet &&
                            (accent.preset ?? 'default') == preset.name,
                        onSelected: accentAsync.isLoading
                            ? null
                            : (_) => unawaited(
                                _selectAccent(context, ref, preset.name),
                              ),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                key: const Key('settings-monet'),
                secondary: Icon(
                  Icons.auto_awesome_outlined,
                  color: palette.primary,
                ),
                title: const Text('跟随系统 (Monet)'),
                subtitle: const Text('Android 12+ 使用系统主题色；不可用时回退到上方主题色'),
                value: accent.mode == AccentMode.monet,
                onChanged: accentAsync.isLoading
                    ? null
                    : (bool enabled) =>
                          unawaited(_setMonet(context, ref, enabled)),
              ),
            ],
          ),
          AppSection(
            header: '导航栏',
            footer: '悬浮胶囊与 Yamby 一致；标准底栏占用底部安全区',
            children: <Widget>[
              ListTile(
                leading: Icon(
                  Icons.space_dashboard_outlined,
                  color: palette.primary,
                ),
                title: const Text('导航栏样式'),
                subtitle: Text(settings.floatingNav ? '悬浮胶囊' : '标准底栏'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: AppButton(
                        key: const Key('appearance-nav-floating'),
                        label: '悬浮胶囊',
                        expand: true,
                        variant: settings.floatingNav
                            ? AppButtonVariant.tinted
                            : AppButtonVariant.plain,
                        onPressed: loading
                            ? null
                            : () => unawaited(controller.setFloatingNav(true)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppButton(
                        key: const Key('appearance-nav-standard'),
                        label: '标准底栏',
                        expand: true,
                        variant: settings.floatingNav
                            ? AppButtonVariant.plain
                            : AppButtonVariant.tinted,
                        onPressed: loading
                            ? null
                            : () => unawaited(controller.setFloatingNav(false)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSection(
            header: '加载动画',
            footer: '加载页面与列表时使用的动画样式',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: <Widget>[
                    for (final AppLoaderStyle style in AppLoaderStyle.values)
                      InkWell(
                        // Stable appearance-loader-<style> keys from AppLoaderStyle.keyName.
                        key: Key(style.keyName),
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        onTap: loading
                            ? null
                            : () => unawaited(
                                controller.setLoaderStyle(style.name),
                              ),
                        child: Container(
                          width: 92,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: settings.loaderStyle == style.name
                                ? palette.primaryContainer.withValues(
                                    alpha: 0.5,
                                  )
                                : palette.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                            border: settings.loaderStyle == style.name
                                ? Border.all(color: palette.primary, width: 2)
                                : null,
                          ),
                          child: Column(
                            children: <Widget>[
                              AppLoader(size: 32, previewStyle: style),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                style.label,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          AppSection(
            header: '列表动画',
            footer: '列表与网格首次出现时的淡入上移效果',
            children: <Widget>[
              SwitchListTile(
                key: const Key('appearance-list-animation'),
                secondary: Icon(Icons.animation, color: palette.primary),
                title: const Text('启用列表动画'),
                subtitle: const Text('关闭后列表直接显示，不做淡入'),
                value: settings.listAnimation,
                onChanged: loading
                    ? null
                    : (bool value) =>
                          unawaited(controller.setListAnimation(value)),
              ),
            ],
          ),
          AppSection(
            header: '悬浮导航栏',
            footer: '仅在使用悬浮胶囊时生效',
            children: <Widget>[
              SwitchListTile(
                key: const Key('appearance-nav-auto-hide'),
                secondary: Icon(
                  Icons.visibility_off_outlined,
                  color: palette.primary,
                ),
                title: const Text('自动隐藏悬浮导航栏'),
                subtitle: const Text('向下滚动时收起，向上滚动时出现'),
                value: settings.autoHideNav,
                onChanged: loading
                    ? null
                    : (bool value) =>
                          unawaited(controller.setAutoHideNav(value)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Persists the appearance mode; failures keep the previous palette.
  Future<void> _selectThemeMode(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(themeModeControllerProvider.notifier).setMode(mode);
    } on ThemeModeSettingsException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Persists the accent preset; failures keep the previous colour.
  Future<void> _selectAccent(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accentControllerProvider.notifier).selectPreset(name);
    } on AccentSettingsException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Persists the Monet toggle; failures keep the previous colour.
  Future<void> _setMonet(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accentControllerProvider.notifier).setMonet(enabled);
    } on AccentSettingsException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };
}

String _accentLabel(AccentPreference preference) {
  if (preference.mode == AccentMode.monet) return '跟随系统 (Monet)';
  return AppAccentPresets.byName(preference.preset)?.label ?? '默认';
}

/// A small colour swatch shown inside each accent preset chip.
class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
    );
  }
}
