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
    Widget? body;
    if (message != null && content != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(message!),
          const SizedBox(height: AppSpacing.lg),
          content!,
        ],
      );
    } else {
      body = content ?? (message != null ? Text(message!) : null);
    }

    return AlertDialog(
      title: title == null ? null : Text(title!),
      content: body,
      constraints: BoxConstraints(maxWidth: maxWidth),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.sm,
        AppSpacing.xxl,
        AppSpacing.lg,
      ),
      actions: <Widget>[
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int index = 0; index < actions.length; index++) ...<Widget>[
                if (index > 0) const SizedBox(height: AppSpacing.sm),
                actions[index],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
