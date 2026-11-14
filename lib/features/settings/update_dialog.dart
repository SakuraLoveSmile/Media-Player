import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/update_providers.dart';
import '../../data/update/update_models.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_dialog.dart';
import '../../ui/theme/app_tokens.dart';

/// Whether a dialog is being shown or is already on screen.
///
/// Set synchronously so that two callers reacting to the same state change
/// (the app-level listener and a manual "check update") cannot stack dialogs
/// in the same frame, before the route has had a chance to build.
bool _dialogVisible = false;

/// Route of the dialog that is currently on screen, if any.
///
/// Visibility is also tracked through the route so that a route dropped by
/// the navigator without being popped (whole tree torn down, e.g. between
/// widget tests) cannot leave the guard stuck forever.
Route<dynamic>? _visibleRoute;

bool _isDialogOpen() {
  if (!_dialogVisible) return false;
  final Route<dynamic>? route = _visibleRoute;
  return route == null || route.isActive;
}

/// Opens the update dialog on the root navigator.
///
/// A second call while the dialog is already open is a no-op.
/// [barrierDismissible] is always false: closing must go through the explicit
/// buttons so that a download/install can never be left behind by a stray tap.
Future<void> showUpdateDialog(BuildContext context) async {
  if (_isDialogOpen()) return;
  _dialogVisible = true;
  _visibleRoute = null;
  try {
    await showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        _visibleRoute = ModalRoute.of(dialogContext);
        return const UpdateDialog();
      },
    );
  } finally {
    _dialogVisible = false;
    _visibleRoute = null;
  }
}

/// Release notes, download progress and the actions that fit the current
/// [UpdateState], presented as a Material alert dialog.
class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final UpdateState state = ref.watch(updateControllerProvider);
    final AppRelease? release = state.release;
    // Dismissed/reset: keep the route but draw nothing so that the caller's
    // pop always works, even while the state is being cleared.
    if (release == null) return const SizedBox.shrink();

    final UpdateStatus status = state.status;
    final bool busy =
        status == UpdateStatus.downloading || status == UpdateStatus.installing;
    final ReleaseAsset? asset = state.asset;
    final String notes = release.notes.trim();

    return PopScope(
      canPop: !busy,
      child: AppDialog(
        title: '发现新版本 ${release.tagName}',
        maxWidth: 400,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '更新说明',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: palette.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  radius: AppRadii.control,
                  elevation: 0,
                  color: palette.surfaceContainerHighest,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Text(
                        notes.isEmpty ? '暂无更新说明' : notes,
                        style: Theme.of(context).textTheme.bodySmall!
                            .copyWith(color: palette.onSurface, height: 1.45),
                      ),
                    ),
                  ),
                ),
                if (asset != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '安装包：${asset.name}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '大小：${formatBytes(asset.sizeBytes)}',
                    style: Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
                ],
                if (status == UpdateStatus.downloading) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.capsule),
                    child: LinearProgressIndicator(
                      value: state.progress.clamp(0.0, 1.0),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Text(
                        _percent(state.progress),
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: palette.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (state.totalBytes > 0)
                        Text(
                          '${formatBytes(state.receivedBytes)} / '
                          '${formatBytes(state.totalBytes)}',
                          style: Theme.of(context).textTheme.labelMedium!
                              .copyWith(color: palette.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
                if (status == UpdateStatus.installing) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.capsule),
                    child: const LinearProgressIndicator(minHeight: 6),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '正在准备安装…',
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
                ],
                if (status == UpdateStatus.error &&
                    state.errorMessage != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    state.errorMessage!,
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: palette.error),
                  ),
                ],
                if (status == UpdateStatus.available &&
                    asset == null) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '当前平台暂未提供安装包，请打开下载页手动下载。',
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: palette.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: _buildActions(context, ref, state),
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    UpdateState state,
  ) {
    final UpdateController controller = ref.read(
      updateControllerProvider.notifier,
    );

    AppButton secondary(String label, VoidCallback? onPressed) => AppButton(
      label: label,
      variant: AppButtonVariant.plain,
      onPressed: onPressed,
    );

    AppButton primary(String label, VoidCallback? onPressed) =>
        AppButton(label: label, onPressed: onPressed);

    switch (state.status) {
      case UpdateStatus.downloading:
        return <Widget>[secondary('取消下载', controller.cancelDownload)];
      case UpdateStatus.downloaded:
        return <Widget>[
          secondary('稍后', () => _dismissAndClose(context, ref)),
          primary('立即安装', () => unawaited(_install(context, ref))),
        ];
      case UpdateStatus.error:
        return <Widget>[
          secondary('打开下载页', () => unawaited(controller.openReleasePage())),
          primary('重试', () => unawaited(controller.retryDownload())),
        ];
      case UpdateStatus.available:
        if (state.asset == null) {
          return <Widget>[
            secondary('关闭', () => _popDialog(context)),
            primary('打开下载页', () => unawaited(controller.openReleasePage())),
          ];
        }
        return <Widget>[
          secondary('稍后', () => _dismissAndClose(context, ref)),
          primary('立即更新', () => unawaited(controller.startDownload())),
        ];
      case UpdateStatus.checking:
      case UpdateStatus.installing:
      case UpdateStatus.idle:
        return const <Widget>[];
    }
  }

  /// "稍后": clear the pending update, then close.
  void _dismissAndClose(BuildContext context, WidgetRef ref) {
    ref.read(updateControllerProvider.notifier).dismiss();
    _popDialog(context);
  }

  /// Android returns to `idle` after the installer takes over, which means the
  /// dialog has done its job; other platforms exit the process inside install.
  Future<void> _install(BuildContext context, WidgetRef ref) async {
    await ref.read(updateControllerProvider.notifier).install();
    if (!context.mounted) return;
    if (ref.read(updateControllerProvider).status == UpdateStatus.idle) {
      _popDialog(context);
    }
  }

  void _popDialog(BuildContext context) {
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) navigator.pop();
  }

  String _percent(double progress) =>
      '${(progress.clamp(0.0, 1.0) * 100).round()}%';
}

/// Human-readable size used for the package and the download progress.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final int digits = unit == 0 ? 0 : (size >= 100 ? 0 : 1);
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}
