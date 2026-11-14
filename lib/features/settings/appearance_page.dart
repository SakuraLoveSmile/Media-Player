import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/appearance_settings.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loader.dart';
import '../../ui/app_page.dart';
import '../../ui/theme/app_tokens.dart';

/// 外观 settings (S62): the navigation style Yamby lets you pick between a
/// floating capsule and the standard bottom bar.
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

    return AppPage(
      title: '外观',
      onBack: () => context.pop(),
      child: ListView(
        key: const Key('appearance-page'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
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
}
