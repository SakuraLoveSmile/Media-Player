import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Cross-fades pages on navigation (S79).
///
/// Material's stock builders zoom, slide or scale the whole page, which reads
/// as a hard cut next to the app's soft list entrance (S67). This builder keeps
/// one continuous dissolve instead: a push fades the incoming page in over the
/// outgoing one, a pop fades the leaving page out to reveal the page underneath.
/// Nothing ever moves or scales, so a page full of posters keeps its geometry
/// and the transition only touches opacity.
///
/// Because the fading page keeps painting its own background, the frame is
/// never empty mid-transition - there is no black flash between two pages.
class AppFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const AppFadePageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.pageIn;

  @override
  Duration get reverseTransitionDuration => AppMotion.pageOut;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The initial route is already at full opacity when the app starts, so it
    // simply renders; every navigation dissolves. 系统「移除动画」/「减弱动态
    // 效果」turns the cross-fade off entirely.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: AppMotion.pageInCurve,
        reverseCurve: AppMotion.pageOutCurve,
      ),
      child: child,
    );
  }
}
