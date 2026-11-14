import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_service.dart';
import '../data/auth/server_session_service.dart';
import '../data/models/auth_session.dart';
import '../data/models/server_entry.dart';
import '../data/endpoints/endpoint_probe.dart';
import '../data/storage/key_value_store.dart';
import '../data/storage/server_directory.dart';
import 'providers.dart';

/// Multi-server wiring (S20).
///
/// Each piece is its own provider so a widget test can override exactly the one
/// it needs (an in-memory store, a fake auth) without rebuilding the whole
/// service graph. The directory holds only non-secret names/addresses; the
/// per-server credentials stay in the secure stores owned by `AuthRepository`.

/// The store backing the server directory. Reads the store created once by
/// [bootstrapProvider] so the app never opens a second backend.
final FutureProvider<KeyValueStore?> serverDirectoryStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// The directory, or null when storage is unavailable.
final FutureProvider<ServerDirectory?> serverDirectoryProvider =
    FutureProvider<ServerDirectory?>((Ref ref) async {
      final store = await ref.watch(serverDirectoryStoreProvider.future);
      return store == null ? null : ServerDirectory(store);
    });

/// The per-server session surface, or null when auth does not support it (for
/// example a single-session test fake). Read lazily on switch/delete so merely
/// rendering the 服务器 section never awaits the service graph.
final FutureProvider<ServerSessionService?> serverAuthProvider =
    FutureProvider<ServerSessionService?>((Ref ref) async {
      final AuthService auth = (await ref.watch(bootstrapProvider.future)).auth;
      // `AuthService` is an interface class, so flow analysis cannot promote it
      // to the unrelated `ServerSessionService`; cast explicitly.
      return auth is ServerSessionService ? auth as ServerSessionService : null;
    });

/// Immutable snapshot of the saved servers and the active one.
class ServersState {
  const ServersState({
    required this.servers,
    required this.activeId,
    this.online = const <String, bool>{},
    this.probing = false,
  });

  final List<ServerEntry> servers;
  final String activeId;

  /// S64: reachability per server id from one `System/Info/Public` probe.
  final Map<String, bool> online;

  /// True while a probe pass is in flight.
  final bool probing;

  static const ServersState empty = ServersState(
    servers: <ServerEntry>[],
    activeId: defaultServerId,
  );
}

/// Loads and mutates the server directory, and performs the active-server
/// switch through [ServerSessionService]. The single active session remains the
/// source of truth; this controller only chooses which server it belongs to.
class ServersController extends AsyncNotifier<ServersState> {
  @override
  Future<ServersState> build() async {
    final directory = await ref.watch(serverDirectoryProvider.future);
    return _load(directory);
  }

  Future<ServersState> _load(ServerDirectory? directory) async {
    if (directory == null) return ServersState.empty;
    return ServersState(
      servers: await directory.read(),
      activeId: await directory.activeId(),
    );
  }

  /// S64: probes every saved server once so the list can show 在线/离线.
  /// Failures are simply offline; this never affects switching.
  Future<void> probeOnline() async {
    final ServersState current = state.value ?? ServersState.empty;
    if (current.servers.isEmpty) return;
    final EndpointProbe? probe = (await ref.read(bootstrapProvider.future))
        .endpointProbe;
    if (probe == null) return;
    state = AsyncData<ServersState>(
      ServersState(
        servers: current.servers,
        activeId: current.activeId,
        online: current.online,
        probing: true,
      ),
    );
    final Map<String, bool> online = <String, bool>{};
    for (final ServerEntry entry in current.servers) {
      final String address = entry.addressLabel;
      if (address.isEmpty) {
        online[entry.id] = false;
        continue;
      }
      try {
        final String? id = await probe.fetchServerId(
          address,
          timeout: const Duration(seconds: 3),
        );
        online[entry.id] = id != null;
      } catch (_) {
        online[entry.id] = false;
      }
    }
    if (!ref.mounted) return;
    state = AsyncData<ServersState>(
      ServersState(
        servers: current.servers,
        activeId: current.activeId,
        online: online,
      ),
    );
  }

  Future<void> _reload() async {
    final directory = await ref.read(serverDirectoryProvider.future);
    final next = await _load(directory);
    if (!ref.mounted) return;
    state = AsyncData<ServersState>(next);
  }

  Future<void> add(ServerEntry entry) async {
    final directory = await ref.read(serverDirectoryProvider.future);
    await directory?.add(entry);
    await _reload();
  }

  Future<void> rename(String id, String name) async {
    final directory = await ref.read(serverDirectoryProvider.future);
    await directory?.rename(id, name);
    await _reload();
  }

  /// Removes a saved server and its stored credentials. Returns the new active
  /// id when the removed server was the active one (so the UI can re-gate),
  /// otherwise null.
  Future<String?> remove(String id) async {
    final directory = await ref.read(serverDirectoryProvider.future);
    if (directory == null) return null;
    final wasActive = (await directory.activeId()) == id;
    await directory.remove(id);
    final auth = await ref.read(serverAuthProvider.future);
    await auth?.clearServer(id);
    String? newActive;
    if (wasActive) {
      newActive = await directory.activeId();
      await auth?.restoreServer(newActive);
    }
    await _reload();
    return newActive;
  }

  /// Makes [id] the active server and restores its session. Returns the session
  /// when one was restored, or null so the UI can route to that server's login.
  Future<AuthSession?> switchTo(String id) async {
    final directory = await ref.read(serverDirectoryProvider.future);
    await directory?.setActive(id);
    final auth = await ref.read(serverAuthProvider.future);
    final session = await auth?.restoreServer(id);
    await _reload();
    return session;
  }
}

final AsyncNotifierProvider<ServersController, ServersState>
serversControllerProvider =
    AsyncNotifierProvider<ServersController, ServersState>(
      ServersController.new,
    );
