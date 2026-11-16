import 'dart:convert';

import '../../core/network/endpoint_kind.dart';
import '../models/server_entry.dart';
import '../models/server_profile.dart';
import 'key_value_store.dart';
import 'profile_store.dart';

/// Persists the saved-server list (S20): non-secret names and addresses only.
///
/// The directory never stores credentials. Each entry's [ServerEntry.id] keys
/// the secure per-server session stores; the single active connection still
/// lives `AuthRepository`. The legacy single-server install is migrated to a
/// `default` entry whose credentials reuse the original storage keys.
class ServerDirectory {
  ServerDirectory(this._store);

  static const String key = 'servers.v1';
  static const int schemaVersion = 2;

  /// Versions [fromJson] can still read. S80 (v2) only added optional entry
  /// fields, so a v1 payload loads unchanged and is rewritten as v2 on the next
  /// write; accepting it keeps every existing install's servers on upgrade.
  static const Set<int> readableVersions = <int>{1, 2};

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

  /// Applies [change] to the entry with [id]; a missing id is a no-op.
  Future<void> update(
    String id,
    ServerEntry Function(ServerEntry entry) change,
  ) async {
    final entries = <ServerEntry>[...await read()];
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    entries[index] = change(entries[index]);
    await _write(entries, await activeId());
  }

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

  /// Repairs stored profiles from their directory cards (S81).
  ///
  /// The S80 card editor wrote only the directory, so a WAN added there never
  /// reached the profile that login and playback actually use. On startup this
  /// fills or updates any non-empty entry address that differs; a missing entry
  /// address is left alone so an older card cannot erase a working profile.
  /// A forced preference that points at a now-missing address falls back to
  /// auto, keeping the profile resolvable.
  Future<void> reconcileProfiles() async {
    for (final entry in await read()) {
      final profileStore = ProfileStore(_store, serverId: entry.id);
      final profile = await profileStore.read();
      if (profile == null) continue;

      var updated = profile;
      var changed = false;
      final lan = entry.lanUrl;
      if (lan != null && lan.isNotEmpty && lan != profile.lanUrl) {
        updated = updated.copyWith(lanUrl: lan);
        changed = true;
      }
      final wan = entry.wanUrl;
      if (wan != null && wan.isNotEmpty && wan != profile.wanUrl) {
        updated = updated.copyWith(wanUrl: wan);
        changed = true;
      }
      if (updated.preference == EndpointPreference.lan &&
          (updated.lanUrl ?? '').isEmpty) {
        updated = updated.copyWith(preference: EndpointPreference.auto);
        changed = true;
      }
      if (updated.preference == EndpointPreference.wan &&
          (updated.wanUrl ?? '').isEmpty) {
        updated = updated.copyWith(preference: EndpointPreference.auto);
        changed = true;
      }
      if (changed) await profileStore.write(updated);
    }
  }

  Future<Map<String, dynamic>?> _readMap() async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final version = map['schemaVersion'];
      if (version is! int || !readableVersions.contains(version)) return null;
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
