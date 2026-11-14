import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cast/dlna_cast_service.dart';
import '../../data/cast/dlna_device.dart';
import '../../data/models/playback_plan.dart';
import '../../data/playback/playback_service.dart';
import '../../ui/app_controls.dart';
import '../../ui/theme/app_tokens.dart';

/// 详情页投屏 (S38): discovers DLNA renderers, negotiates the item's stream on
/// demand and hands the `api_key` URL to the renderer. The player page has its
/// own sheet because it also has to pause the local surface.
class DetailCastSheet extends StatefulWidget {
  const DetailCastSheet({
    super.key,
    required this.cast,
    required this.playback,
    required this.itemId,
    required this.title,
    this.mediaSourceId,
  });

  final DlnaCastService cast;
  final PlaybackService playback;
  final String itemId;
  final String title;
  final String? mediaSourceId;

  @override
  State<DetailCastSheet> createState() => _DetailCastSheetState();
}

class _DetailCastSheetState extends State<DetailCastSheet> {
  List<DlnaDevice>? _devices;
  String? _error;
  bool _busy = false;
  DlnaDevice? _castingTo;

  @override
  void initState() {
    super.initState();
    unawaited(_discover());
  }

  Future<void> _discover() async {
    try {
      final devices = await widget.cast.discover();
      if (!mounted) return;
      setState(() => _devices = devices);
    } catch (_) {
      if (!mounted) return;
      setState(() => _devices = const <DlnaDevice>[]);
    }
  }

  Future<void> _cast(DlnaDevice device) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final PlaybackPlan plan = await widget.playback.resolve(
        widget.itemId,
        mediaSourceId: widget.mediaSourceId,
      );
      if (!mounted) return;
      await widget.cast.cast(device, plan.castUrl, title: widget.title);
      if (!mounted) return;
      setState(() => _castingTo = device);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '投屏失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final DlnaDevice? device = _castingTo;
    if (device == null) return;
    try {
      await widget.cast.stop(device);
    } catch (_) {
      // A renderer that left the LAN must not block clearing the state.
    }
    if (!mounted) return;
    setState(() => _castingTo = null);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final List<DlnaDevice>? devices = _devices;
    return AppCard(
      key: const Key('detail-cast-sheet'),
      color: palette.surfaceContainerLow,
      radius: AppRadii.sheet,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '投屏',
                  style: Theme.of(context).textTheme.titleMedium!
                      .copyWith(color: palette.onSurface),
                ),
              ),
              IconButton(
                key: const Key('detail-cast-close'),
                tooltip: '关闭',
                color: palette.onSurface,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (_castingTo != null) ...<Widget>[
            Text(
              '正在投屏到 ${_castingTo!.name}',
              key: const Key('detail-cast-status'),
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: palette.primary),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const Key('detail-cast-stop'),
              label: '停止投屏',
              variant: AppButtonVariant.tinted,
              onPressed: () => unawaited(_stop()),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (devices == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (devices.isEmpty)
            Padding(
              key: const Key('detail-cast-empty'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                '未发现投屏设备',
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: palette.onSurfaceVariant),
              ),
            )
          else
            for (final DlnaDevice device in devices)
              ListTile(
                key: Key('detail-cast-device-${device.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.tv, color: palette.primary),
                title: Text(
                  device.name,
                  style: TextStyle(color: palette.onSurface),
                ),
                subtitle: Text(
                  device.address,
                  style: Theme.of(context).textTheme.labelMedium!
                      .copyWith(color: palette.onSurfaceVariant),
                ),
                enabled: !_busy,
                onTap: () => unawaited(_cast(device)),
              ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _error!,
                key: const Key('detail-cast-error'),
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: palette.error),
              ),
            ),
        ],
      ),
    );
  }
}
