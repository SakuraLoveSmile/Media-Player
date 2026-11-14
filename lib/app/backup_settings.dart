import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/backup_service.dart';
import 'providers.dart';

/// The preference backup/restore service (S22).
///
/// Reads the store and the file picker created once by [bootstrapProvider] so
/// the app never opens a second storage backend or plugin instance. Null only
/// in harnesses without storage or a picker; widget tests override it with a
/// [BackupService] backed by an in-memory store and a fake picker.
final FutureProvider<BackupService?> backupServiceProvider =
    FutureProvider<BackupService?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      final store = services.store;
      final picker = services.backupFilePicker;
      if (store == null || picker == null) return null;
      return BackupService(store, picker);
    });
