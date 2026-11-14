import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin/admin_service.dart';
import '../data/models/auth_session.dart';
import 'providers.dart';

/// Admin wiring (S24).
///
/// Each piece is its own provider so a widget test can override exactly the
/// one it needs (a fake service) without rebuilding the whole service graph.

/// The read-only admin repository, or null in harnesses without one.
final FutureProvider<AdminService?> adminServiceProvider =
    FutureProvider<AdminService?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.admin;
    });

/// The active session as a stream, so the admin gate re-runs on login, logout
/// and server switch (S20) instead of caching a stale answer.
final StreamProvider<AuthSession?> authSessionProvider =
    StreamProvider<AuthSession?>((Ref ref) async* {
      final services = await ref.watch(bootstrapProvider.future);
      yield services.auth.current;
      yield* services.auth.session;
    });

/// Whether the signed-in user is an administrator (S24).
///
/// The settings entry watches this and stays hidden while it resolves or when
/// it is false; a failed check (offline, expired token) also reads as false so
/// the entry never appears for a session that cannot prove itself.
final FutureProvider<bool> isAdminProvider = FutureProvider<bool>((
  Ref ref,
) async {
  ref.watch(authSessionProvider);
  final AdminService? service = await ref.watch(adminServiceProvider.future);
  if (service == null) return false;
  try {
    return await service.isAdmin();
  } catch (_) {
    return false;
  }
});
