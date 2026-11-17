import 'package:flutter/material.dart';

import '../data/models/media_item.dart';
import '../data/offline/offline_repository.dart';

/// The repository rechecks server policy and the requested source before any
/// bytes are fetched. An unavailable permission is surfaced, never bypassed.
class OfflineDownloadButton extends StatefulWidget {
  const OfflineDownloadButton({
    super.key,
    required this.repository,
    required this.item,
    this.sourceId,
  });
  final OfflineRepository repository;
  final MediaItem item;
  final String? sourceId;
  @override
  State<OfflineDownloadButton> createState() => _OfflineDownloadButtonState();
}

class _OfflineDownloadButtonState extends State<OfflineDownloadButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.download_outlined),
    label: Text(_busy ? '正在创建…' : '下载原片'),
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await widget.repository.enqueue(
                widget.item,
                sourceId: widget.sourceId,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已加入下载，可在下载与离线媒体中查看')),
                );
              }
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error is StateError
                          ? error.message.toString()
                          : '无法创建下载，请检查服务器权限和网络',
                    ),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}
