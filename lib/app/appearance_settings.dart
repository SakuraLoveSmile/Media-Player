import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import 'providers.dart';

/// App-wide appearance preferences (S62). Yamby's 外观 page switches between
/// its floating capsule navigation and the standard bottom bar.
class AppearanceSettings {
  const AppearanceSettings({
    this.floatingNav = true,
    this.autoHideNav = true,
    this.loaderStyle = 'blob',
    this.listAnimation = true,
  });

  static const String storageKey = 'app.appearance.v1';

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    return AppearanceSettings(
      floatingNav: json['floatingNav'] as bool? ?? true,
      autoHideNav: json['autoHideNav'] as bool? ?? true,
      loaderStyle: json['loaderStyle'] as String? ?? 'blob',
      listAnimation: json['listAnimation'] as bool? ?? true,
    );
  }

  /// True keeps the capsule nav (S28); false renders the Material bar.
  final bool floatingNav;

  /// Scroll the capsule away while the user moves down a list (Yamby's
  /// 自动隐藏悬浮导航栏); it returns on the first upward scroll.
  final bool autoHideNav;

  /// Which loading animation the app draws (S66); matches AppLoaderStyle.name.
  final String loaderStyle;

  /// Fade/slide the first N rows of a grid in when it appears (Yamby's
  /// 启用列表动画).
  final bool listAnimation;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'floatingNav': floatingNav,
    'autoHideNav': autoHideNav,
    'loaderStyle': loaderStyle,
    'listAnimation': listAnimation,
  };

  AppearanceSettings copyWith({
    bool? floatingNav,
    bool? autoHideNav,
    String? loaderStyle,
    bool? listAnimation,
  }) {
    return AppearanceSettings(
      floatingNav: floatingNav ?? this.floatingNav,
      autoHideNav: autoHideNav ?? this.autoHideNav,
      loaderStyle: loaderStyle ?? this.loaderStyle,
      listAnimation: listAnimation ?? this.listAnimation,
    );
  }
}

/// Key/value store backing the appearance preferences.
final FutureProvider<KeyValueStore?> appearanceSettingsStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

class AppearanceSettingsController extends AsyncNotifier<AppearanceSettings> {
  @override
  Future<AppearanceSettings> build() async {
    final KeyValueStore? store = await ref.watch(
      appearanceSettingsStoreProvider.future,
    );
    if (store == null) return const AppearanceSettings();
    try {
      final String? raw = await store.read(AppearanceSettings.storageKey);
      if (raw == null || raw.isEmpty) return const AppearanceSettings();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const AppearanceSettings();
      return AppearanceSettings.fromJson(decoded);
    } catch (_) {
      return const AppearanceSettings();
    }
  }

  Future<void> setListAnimation(bool enabled) async {
    final AppearanceSettings next = (state.value ?? const AppearanceSettings())
        .copyWith(listAnimation: enabled);
    final KeyValueStore? store = await ref.read(
      appearanceSettingsStoreProvider.future,
    );
    if (store != null) {
      await store.write(
        AppearanceSettings.storageKey,
        jsonEncode(next.toJson()),
      );
    }
    if (!ref.mounted) return;
    state = AsyncData<AppearanceSettings>(next);
  }

  Future<void> setLoaderStyle(String style) async {
    final AppearanceSettings next = (state.value ?? const AppearanceSettings())
        .copyWith(loaderStyle: style);
    final KeyValueStore? store = await ref.read(
      appearanceSettingsStoreProvider.future,
    );
    if (store != null) {
      await store.write(
        AppearanceSettings.storageKey,
        jsonEncode(next.toJson()),
      );
    }
    if (!ref.mounted) return;
    state = AsyncData<AppearanceSettings>(next);
  }

  Future<void> setAutoHideNav(bool enabled) async {
    final AppearanceSettings next = (state.value ?? const AppearanceSettings())
        .copyWith(autoHideNav: enabled);
    final KeyValueStore? store = await ref.read(
      appearanceSettingsStoreProvider.future,
    );
    if (store != null) {
      await store.write(
        AppearanceSettings.storageKey,
        jsonEncode(next.toJson()),
      );
    }
    if (!ref.mounted) return;
    state = AsyncData<AppearanceSettings>(next);
  }

  Future<void> setFloatingNav(bool floating) async {
    final AppearanceSettings next = (state.value ?? const AppearanceSettings())
        .copyWith(floatingNav: floating);
    final KeyValueStore? store = await ref.read(
      appearanceSettingsStoreProvider.future,
    );
    if (store != null) {
      await store.write(
        AppearanceSettings.storageKey,
        jsonEncode(next.toJson()),
      );
    }
    if (!ref.mounted) return;
    state = AsyncData<AppearanceSettings>(next);
  }
}

final AsyncNotifierProvider<AppearanceSettingsController, AppearanceSettings>
appearanceSettingsControllerProvider =
    AsyncNotifierProvider<AppearanceSettingsController, AppearanceSettings>(
      AppearanceSettingsController.new,
    );
