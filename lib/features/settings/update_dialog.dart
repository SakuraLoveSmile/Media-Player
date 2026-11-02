import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/update_providers.dart';

/// Whether a dialog is being shown or is already on screen.
///
/// Set synchronously so that two callers reacting to the same state change
/// (the app-level listener and a manual "check update") cannot stack dialogs
/// in the same frame, before the route has had a chance to build.
bool _dialogVisible = false;

/// Route of the dialog that is currently on screen, if any.
///
/// Visibility is also tracked through the route so that a route dropped by the
/// navigator without being popped (whole tree torn down, e.g. between widget
/// tests) cannot leave the guard stuck forever.
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
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
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
/// [UpdateState].
class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(updateControllerProvider);
    final release = state.release;
    // Dismissed/reset: keep the route but draw nothing so that the caller's
    // pop always works, even while the state is being cleared.
    if (release == null) return const SizedBox.shrink();

    final status = state.status;
    final busy =
        status == UpdateStatus.downloading || status == UpdateStatus.installing;
    final asset = state.asset;
    final notes = release.notes.trim();

    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text('发现新版本 ${release.tagName}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('更新说明', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: Text(
                      notes.isEmpty ? '暂无更新说明' : notes,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                if (asset != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    '安装包：${asset.name}',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '大小：${formatBytes(asset.sizeBytes)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (status == UpdateStatus.downloading) ...<Widget>[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: state.progress.clamp(0.0, 1.0),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Text(
                        _percent(state.progress),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      if (state.totalBytes > 0)
                        Text(
                          '${formatBytes(state.receivedBytes)} / '
                          '${formatBytes(state.totalBytes)}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
                if (status == UpdateStatus.installing) ...<Widget>[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text('正在准备安装…', style: theme.textTheme.bodyMedium),
                ],
                if (status == UpdateStatus.error &&
                    state.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    state.errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (status == UpdateStatus.available &&
                    asset == null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    '当前平台暂未提供安装包，请打开下载页手动下载。',
                    style: theme.textTheme.bodyMedium,
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
    final controller = ref.read(updateControllerProvider.notifier);

    switch (state.status) {
      case UpdateStatus.downloading:
        return <Widget>[
          TextButton(
            onPressed: controller.cancelDownload,
            child: const Text('取消下载'),
          ),
        ];
      case UpdateStatus.downloaded:
        return <Widget>[
          TextButton(
            onPressed: () => _dismissAndClose(context, ref),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => unawaited(_install(context, ref)),
            child: const Text('立即安装'),
          ),
        ];
      case UpdateStatus.error:
        return <Widget>[
          TextButton(
            onPressed: () => unawaited(controller.openReleasePage()),
            child: const Text('打开下载页'),
          ),
          FilledButton(
            onPressed: () => unawaited(controller.retryDownload()),
            child: const Text('重试'),
          ),
        ];
      case UpdateStatus.available:
        if (state.asset == null) {
          return <Widget>[
            TextButton(
              onPressed: () => _popDialog(context),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () => unawaited(controller.openReleasePage()),
              child: const Text('打开下载页'),
            ),
          ];
        }
        return <Widget>[
          TextButton(
            onPressed: () => _dismissAndClose(context, ref),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => unawaited(controller.startDownload()),
            child: const Text('立即更新'),
          ),
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
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) navigator.pop();
  }

  String _percent(double progress) =>
      '${(progress.clamp(0.0, 1.0) * 100).round()}%';
}

/// Human-readable size used for the package and the download progress.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final int digits = unit == 0 ? 0 : (size >= 100 ? 0 : 1);
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}
