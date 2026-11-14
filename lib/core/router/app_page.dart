import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Builds the [MaterialPage] every app route is mounted on (S79).
///
/// go_router resolves its default page by looking for a `material_ui`
/// `MaterialApp` ancestor. This app builds with the `MaterialApp` from
/// `package:flutter/material.dart`, which is a different class, so that lookup
/// fails and go_router silently falls back to `NoTransitionPage`: navigation
/// becomes a hard cut and `PageTransitionsTheme` (the app-wide cross-fade)
/// never runs. Declaring the page explicitly keeps the theme's transitions -
/// and the Android back gesture - in charge.
///
/// The key, name, arguments and restoration id mirror what go_router passes to
/// its own material page builder, so route identity and state restoration are
/// unchanged.
Page<void> appPage(GoRouterState state, Widget child) {
  return MaterialPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    arguments: <String, String>{
      ...state.pathParameters,
      ...state.uri.queryParameters,
    },
    restorationId: state.pageKey.value,
    child: child,
  );
}
