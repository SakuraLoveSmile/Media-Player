import 'package:flutter/material.dart';

import '../core/network/url_normalizer.dart';
import '../data/models/server_entry.dart';
import 'app_controls.dart';
import 'theme/app_tokens.dart';

/// Emby's brand green, used by the default server glyph and the online dot
/// (S80, matching Yamby's server cards).
const Color serverAccent = Color(0xFF52B54B);

/// Material glyph for each [serverIconIds] preset. The ids live in the data
/// layer so it stays free of Flutter; an unknown id falls back to the default.
const Map<String, IconData> _glyphs = <String, IconData>{
  'diamond': Icons.play_arrow_rounded,
  'tv': Icons.tv_rounded,
  'movie': Icons.movie_rounded,
  'router': Icons.router_rounded,
  'cloud': Icons.cloud_rounded,
  'home': Icons.home_rounded,
  'star': Icons.star_rounded,
  'game': Icons.sports_esports_rounded,
  'music': Icons.music_note_rounded,
  'storage': Icons.storage_rounded,
};

/// The glyph of a preset icon id (S80).
IconData serverGlyphFor(String iconId) =>
    _glyphs[iconId] ?? Icons.play_arrow_rounded;

/// Icon choices shown by 自定义图标, in the order they are offered.
List<IconData> get serverGlyphChoices => <IconData>[
  for (final String id in serverIconIds) serverGlyphFor(id),
];

/// The server's leading glyph: the custom pick or Emby's default diamond.
class ServerGlyph extends StatelessWidget {
  const ServerGlyph({super.key, required this.entry, this.size = 28});

  final ServerEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      serverGlyphFor(entry.customIcon),
      size: size,
      color: serverAccent,
    );
  }
}

/// 显示上次播放时间 text: relative for today/yesterday, a date otherwise.
String formatLastPlayed(DateTime at, {DateTime? now}) {
  final DateTime reference = now ?? DateTime.now();
  final DateTime day = DateTime(at.year, at.month, at.day);
  final DateTime today = DateTime(reference.year, reference.month, reference.day);
  final String time =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  final int days = today.difference(day).inDays;
  if (days == 0) return '今天 $time';
  if (days == 1) return '昨天 $time';
  if (at.year == reference.year) return '${at.month}月${at.day}日 $time';
  return '${at.year}年${at.month}月${at.day}日';
}

/// One saved server (S80), laid out like Yamby's server card: the server glyph,
/// the name, and a second line with the online dot plus the optional user name
/// and last-played time. Tapping the card switches to it; the trailing ⋮ opens
/// the per-server menu.
class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.entry,
    required this.active,
    required this.onTap,
    required this.onMenu,
    this.userName,
    this.online,
  });

  final ServerEntry entry;
  final bool active;
  final VoidCallback onTap;

  /// Receives the menu button's context so the menu can anchor to it.
  final ValueChanged<BuildContext> onMenu;

  /// Signed-in user of the *active* server; null hides it.
  final String? userName;

  /// Reachability from the S64 probe; null while unknown.
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final String address = UrlNormalizer.display(entry.addressLabel);
    final bool nameIsAddress = entry.name.isEmpty;
    final String name = nameIsAddress ? address : entry.name;
    final String user = userName ?? '';
    final List<String> details = <String>[
      if (entry.showUserName && user.isNotEmpty) user,
      if (entry.showLastPlayed && entry.lastPlayedAt != null)
        formatLastPlayed(entry.lastPlayedAt!),
    ];

    return ListTile(
      key: Key('server-${entry.id}'),
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      leading: ServerGlyph(entry: entry, size: 30),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.onSurface,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (active) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.check_circle,
              key: Key('server-active-${entry.id}'),
              size: 16,
              color: palette.primary,
            ),
          ],
        ],
      ),
      subtitle: _Subtitle(
        online: online,
        entryId: entry.id,
        details: details,
        // The address is only worth a second line when the title is a name;
        // otherwise the card would print it twice.
        fallback: details.isEmpty && !nameIsAddress ? address : null,
      ),
      trailing: Builder(
        builder: (BuildContext buttonContext) => AppIconButton(
          key: Key('server-menu-${entry.id}'),
          icon: const Icon(Icons.more_vert),
          tooltip: '服务器操作',
          size: 36,
          iconSize: 20,
          brightness: palette.brightness,
          onPressed: () => onMenu(buttonContext),
        ),
      ),
    );
  }
}

/// Online dot + the optional user / last-played text, or the address when both
/// toggles are off and nothing would otherwise be shown.
class _Subtitle extends StatelessWidget {
  const _Subtitle({
    required this.entryId,
    required this.details,
    this.online,
    this.fallback,
  });

  final String entryId;
  final List<String> details;
  final bool? online;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    final ColorScheme palette = Theme.of(context).colorScheme;
    final String? hint = fallback;
    return Row(
      children: <Widget>[
        if (online != null) ...<Widget>[
          Container(
            key: Key('server-online-$entryId'),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online! ? serverAccent : palette.outline,
            ),
          ),
          if (details.isNotEmpty || hint != null)
            const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Text(
            hint ?? details.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
