import 'package:flutter/material.dart';

import 'theme/app_tokens.dart';

/// Opens a Material dialog. Replaces the frosted iOS-style alert route.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String barrierLabel = 'dismiss',
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    builder: builder,
  );
}

/// A Material alert dialog with a title, optional message/content and a vertical
/// stack of action buttons.
///
/// Everything scrolls inside one height-limited sheet instead of relying on
/// [AlertDialog]'s fixed action bar. A form taller than the space left by the
/// software keyboard used to overflow its own layout and paint the buttons on
/// top of the fields (the MoviePilot login form with the keyboard up); a
/// scrollable column keeps every field and every action reachable at any screen
/// height. [Dialog] already lifts the sheet above the keyboard by adding
/// `MediaQuery.viewInsets` to [insetPadding].
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.title,
    this.message,
    required this.actions,
    this.content,
    this.maxWidth = 360,
  });

  final String? title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme palette = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.xxl,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (title != null) ...<Widget>[
                Text(title!, style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.md),
              ],
              if (message != null)
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              if (message != null && content != null)
                const SizedBox(height: AppSpacing.lg),
              ?content,
              for (int index = 0; index < actions.length; index++) ...<Widget>[
                SizedBox(height: index == 0 ? AppSpacing.xl : AppSpacing.sm),
                actions[index],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
