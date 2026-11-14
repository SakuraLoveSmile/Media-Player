import 'dart:convert';

import '../models/server_entry.dart';
import '../models/server_profile.dart';
import 'key_value_store.dart';

/// Persists the saved-server list (S20): non-secret names and addresses only.
///
/// The directory never stores credentials. Each entry's [ServerEntry.id] keys
/// the secure per-server session stores; the single active connection still
/// lives in `AuthRepository`. The legacy single-server install is migrated to a
/// `default` entry whose credentials reuse the original storage keys.
class ServerDirectory {
  ServerDirectory(this._store);

  static const String key = 'servers.v1';
  static const int schemaVersion = 1;

  final KeyValueStore _store;

  /// All saved entries in insertion order; empty when nothing is stored yet.
  Future<List<ServerEntry>> read() async {
    final map = await _readMap();
    if (map == null) return const <ServerEntry>[];
    final servers = map['servers'];
    if (servers is! List) return const <ServerEntry>[];
    final entries = <ServerEntry>[];
    for (final item in servers) {
      if (item is! Map) continue;
      final entry = ServerEntry.fromJson(Map<String, dynamic>.from(item));
      if (entry.id.isEmpty) continue;
      entries.add(entry);
    }
    return entries;
  }

  /// The id of the server the app should restore on launch. Falls back to
  /// [defaultServerId] when unset or pointing at a removed entry.
  Future<String> activeId() async {
    final map = await _readMap();
    final entries = await read();
    final stored = map == null ? null : map['activeId'];
    if (stored is String && stored.isNotEmpty) {
      final exists = entries.any((entry) => entry.id == stored);
      if (exists) return stored;
    }
    return entries.isNotEmpty ? entries.first.id : defaultServerId;
  }

  Future<ServerEntry?> find(String id) async {
    for (final entry in await read()) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Inserts or replaces the entry with the same id, preserving order.
  Future<void> upsert(ServerEntry entry) async {
    if (entry.id.isEmpty) return;
    final entries = <ServerEntry>[...await read()];
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index >= 0) {
      entries[index] = entry;
    } else {
      entries.add(entry);
    }
    await _write(entries, await activeId());
  }

  Future<void> add(ServerEntry entry) => upsert(entry);

  /// Removes an entry. When it was active, the first remaining entry (or
  /// [defaultServerId]) becomes active.
  Future<void> remove(String id) async {
    final entries = <ServerEntry>[...await read()];
    final active = await activeId();
    entries.removeWhere((entry) => entry.id == id);
    final nextActive = active == id
        ? (entries.isNotEmpty ? entries.first.id : defaultServerId)
        : active;
    await _write(entries, nextActive);
  }

  Future<void> rename(String id, String name) async {
    final entries = <ServerEntry>[...await read()];
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    entries[index] = entries[index].copyWith(name: name);
    await _write(entries, await activeId());
  }

  Future<void> setActive(String id) async {
    final entries = await read();
    await _write(entries, id);
  }

  /// Creates the first `default` entry from a legacy single-server profile when
  /// the directory is still empty (S20 migration). The legacy token/session are
  /// left untouched: the `default` id reuses their original storage keys.
  ///
  /// Returns true when a migration entry was created.
  Future<bool> migrateLegacyProfile(ServerProfile? profile) async {
    if (profile == null || !profile.hasAnyAddress) return false;
    if ((await read()).isNotEmpty) return false;
    await upsert(
      ServerEntry(
        id: defaultServerId,
        name: profile.name.isEmpty ? '服务器' : profile.name,
        lanUrl: profile.lanUrl,
        wanUrl: profile.wanUrl,
      ),
    );
    await setActive(defaultServerId);
    return true;
  }

  Future<Map<String, dynamic>?> _readMap() async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['schemaVersion'] != schemaVersion) return null;
      return map;
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(List<ServerEntry> entries, String activeId) {
    return _store.write(
      key,
      jsonEncode(<String, dynamic>{
        'schemaVersion': schemaVersion,
        'activeId': activeId,
        'servers': <Map<String, dynamic>>[
          for (final entry in entries) entry.toJson(),
        ],
      }),
    );
  }
}
