/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 0 — where the replica lives on disk.
///
/// Kept apart from [LocalDatabase] so that class stays pure Dart with no
/// Flutter binding: the replication layer and all of its tests run on the plain
/// VM, and only this file needs a platform.
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_database.dart';

class LocalDatabaseFactory {
  const LocalDatabaseFactory._();

  /// File name inside the application support directory. WAL mode adds
  /// `-wal`/`-shm` siblings; all three belong together.
  static const fileName = 'mary_pos_replica.db';

  /// Opens the replica in the OS's per-application support directory.
  ///
  /// Application support, not documents or temp: the replica is recreatable
  /// (it can always be rebuilt from `/sync/pull`) but must survive restarts and
  /// must not be user-visible or eligible for cleanup while a shift is running.
  static Future<LocalDatabase> openDefault() async {
    final dir = await getApplicationSupportDirectory();
    return LocalDatabase.open(p.join(dir.path, fileName));
  }

  /// The resolved path, for diagnostics on the sync-status screen.
  static Future<String> resolvePath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, fileName);
  }

  /// The SQLite build actually loaded at runtime — worth surfacing in
  /// diagnostics, since the native library comes from `sqlite3_flutter_libs`
  /// on device and from the host system when running tests.
  static String get sqliteVersion => sqlite3.version.libVersion;
}
