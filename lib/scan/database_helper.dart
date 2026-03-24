import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';

class DatabaseHelper {
  static Database? _db;

  // ─── Auto-backup config ────────────────────────────────────────────────────
  // Delay after the LAST write event before the backup actually fires.
  // Resets on every new write, so only one backup runs per burst of activity.
  // Default: 30 minutes. Changeable at runtime via setAutoBackupDelay().
  static Duration _autoBackupDelay  = const Duration(minutes: 30);
  static const _maxAutoBackups      = 5;
  static const _autoBackupSubdir    = 'auto';
  static Timer? _autoBackupTimer;

  /// Change the delay window (call from settings; persists for the session).
  /// Supported values: 30 min, 1 hour. Cancels any pending timer so the
  /// new delay takes effect on the next write event.
  static void setAutoBackupDelay(Duration delay) {
    _autoBackupDelay = delay;
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
  }

  /// Read the current delay setting (for the UI).
  static Duration get autoBackupDelay => _autoBackupDelay;

  /// Last auto-backup result — readable by the UI (settings page).\n
  static DateTime? lastAutoBackupTime;
  static String?   lastAutoBackupPath;
  static bool      lastAutoBackupFailed = false;

  // ─── Connection ────────────────────────────────────────────────────────────

  static Future<Database> get db async {
    if (_db != null) return _db!;

    sqfliteFfiInit();
    final factory = databaseFactoryFfi;

    // Resolve the directory of the running .exe so the database is stored
    // alongside the executable in the release folder:
    //   build\windows\x64\runner\Release\pims_deped.db
    // During flutter run (debug/profile) this resolves to the build cache
    // directory, which also works fine for development.
    final exeDir  = File(Platform.resolvedExecutable).parent.path;
    final dbPath  = p.join(exeDir, 'pims_deped.db');
    final archDir = p.join(exeDir, 'archives');

    // ── Integrity check → archive fallback ───────────────────────────────
    final needsRecovery = !(await _isDatabaseValid(dbPath, factory));
    if (needsRecovery) {
      final recovered = await _recoverFromArchive(dbPath, archDir, factory);
      if (recovered) {
        debugPrint('[DB] Recovered main database from archive.');
      } else {
        debugPrint('[DB] No valid archive found — starting with a fresh database.');
      }
    }

    _db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    return _db!;
  }

  // ─── Validates that a db file exists, is non-empty, and passes SQLite's
  //     own integrity_check pragma. Returns true only if all pass. ──────────

  static Future<bool> _isDatabaseValid(
    String dbPath,
    DatabaseFactory factory,
  ) async {
    final file = File(dbPath);

    // Missing or empty file — SQLite header is 100 bytes minimum
    if (!await file.exists() || await file.length() < 100) {
      debugPrint('[DB] Main database missing or empty at $dbPath');
      return false;
    }

    // Try opening and running integrity_check
    Database? probe;
    try {
      probe = await factory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final rows = await probe.rawQuery('PRAGMA integrity_check');
      final result = rows.isNotEmpty ? rows.first.values.first as String? : null;
      if (result != 'ok') {
        debugPrint('[DB] Integrity check failed: $result');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[DB] Could not open main database for integrity check: $e');
      return false;
    } finally {
      await probe?.close();
    }
  }

  // ─── Scans the archives folder (manual + auto) for the latest backup,
  //     copies it to dbPath, and returns true on success. ───────────────────

  static Future<bool> _recoverFromArchive(
    String dbPath,
    String archDir,
    DatabaseFactory factory,
  ) async {
    final dir     = Directory(archDir);
    final autoDir = Directory(p.join(archDir, _autoBackupSubdir));

    // Collect .db files from both manual archives/ and archives/auto/
    final archives = <File>[];
    for (final d in [dir, autoDir]) {
      if (!await d.exists()) continue;
      final files = await d
          .list()
          .where((e) => e is File && e.path.endsWith('.db'))
          .cast<File>()
          .toList();
      archives.addAll(files);
    }

    if (archives.isEmpty) {
      debugPrint('[DB] No archives found in $archDir — starting fresh.');
      return false;
    }

    // Sort newest-first across both folders (timestamp is in the filename)
    archives.sort((a, b) => b.path.compareTo(a.path));

    for (final candidate in archives) {
      final ok = await _isDatabaseValid(candidate.path, factory);
      if (ok) {
        debugPrint('[DB] Restoring from archive: ${candidate.path}');
        await candidate.copy(dbPath);
        return true;
      } else {
        debugPrint('[DB] Archive invalid, skipping: ${candidate.path}');
      }
    }

    debugPrint('[DB] All archives are invalid — cannot recover.');
    return false;
  }

  // ─── Schema ────────────────────────────────────────────────────────────────

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE wfp (
        id             TEXT PRIMARY KEY,
        title          TEXT NOT NULL,
        targetSize     TEXT NOT NULL,
        indicator      TEXT NOT NULL,
        year           INTEGER NOT NULL,
        fundType       TEXT NOT NULL,
        amount         REAL NOT NULL,
        approvalStatus TEXT NOT NULL DEFAULT 'Pending',
        approvedDate   TEXT,
        dueDate        TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE activities (
        id          TEXT PRIMARY KEY,
        wfpId       TEXT NOT NULL,
        name        TEXT NOT NULL,
        total       REAL NOT NULL,
        projected   REAL NOT NULL,
        disbursed   REAL NOT NULL,
        status      TEXT NOT NULL,
        targetDate  TEXT,
        FOREIGN KEY (wfpId) REFERENCES wfp(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        entityType  TEXT NOT NULL,
        entityId    TEXT NOT NULL,
        action      TEXT NOT NULL,
        timestamp   TEXT NOT NULL,
        diffJson    TEXT NOT NULL
      )
    ''');
  }

  /// Incremental migrations — safe to run on existing databases.
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: approval fields on wfp, targetDate on activities
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'wfp', 'approvalStatus', "TEXT NOT NULL DEFAULT 'Pending'");
      await _addColumnIfMissing(db, 'wfp', 'approvedDate', 'TEXT');
      await _addColumnIfMissing(db, 'activities', 'targetDate', 'TEXT');
    }
    // v2 → v3: dueDate on wfp
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'wfp', 'dueDate', 'TEXT');
    }
    // v3 → v4: audit_log table
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_log (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          entityType  TEXT NOT NULL,
          entityId    TEXT NOT NULL,
          action      TEXT NOT NULL,
          timestamp   TEXT NOT NULL,
          diffJson    TEXT NOT NULL
        )
      ''');
    }
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    } catch (_) {
      // Column already exists — safe to ignore
    }
  }

  // ─── WFP CRUD ──────────────────────────────────────────────────────────────

  static Future<void> insertWFP(WFPEntry entry) async {
    final d = await db;
    await d.insert('wfp', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
    _scheduleAutoBackup();
  }

  static Future<List<WFPEntry>> getAllWFPs() async {
    final d = await db;
    final rows = await d.query('wfp', orderBy: 'year DESC, id ASC');
    return rows.map(WFPEntry.fromMap).toList();
  }

  static Future<WFPEntry?> getWFPById(String id) async {
    final d = await db;
    final rows = await d.query('wfp', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return WFPEntry.fromMap(rows.first);
  }

  static Future<void> updateWFP(WFPEntry entry) async {
    final d = await db;
    await d.update('wfp', entry.toMap(), where: 'id = ?', whereArgs: [entry.id]);
    _scheduleAutoBackup();
  }

  static Future<void> deleteWFP(String id) async {
    final d = await db;
    await d.delete('activities', where: 'wfpId = ?', whereArgs: [id]);
    await d.delete('wfp', where: 'id = ?', whereArgs: [id]);
    _scheduleAutoBackup();
  }

  static Future<int> countWFPsByYear(int year) async {
    final d = await db;
    final result = await d.rawQuery(
      'SELECT COUNT(*) AS cnt FROM wfp WHERE year = ?', [year],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<bool> wfpIdExists(String id) async {
    final d = await db;
    final rows = await d.query('wfp', columns: ['id'], where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty;
  }

  /// Returns WFP entries filtered by year and/or approvalStatus.
  static Future<List<WFPEntry>> getWFPsFiltered({
    int? year,
    String? approvalStatus,
  }) async {
    final d = await db;
    final where = <String>[];
    final args = <dynamic>[];
    if (year != null) { where.add('year = ?'); args.add(year); }
    if (approvalStatus != null) { where.add('approvalStatus = ?'); args.add(approvalStatus); }
    final rows = await d.query(
      'wfp',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'year DESC, id ASC',
    );
    return rows.map(WFPEntry.fromMap).toList();
  }

  /// All distinct years in the wfp table, descending.
  static Future<List<int>> getDistinctYears() async {
    final d = await db;
    final rows = await d.rawQuery('SELECT DISTINCT year FROM wfp ORDER BY year DESC');
    return rows.map((r) => r['year'] as int).toList();
  }

  // ─── Activity CRUD ─────────────────────────────────────────────────────────

  static Future<void> insertActivity(BudgetActivity activity) async {
    final d = await db;
    await d.insert('activities', activity.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
    _scheduleAutoBackup();
  }

  static Future<List<BudgetActivity>> getActivitiesForWFP(String wfpId) async {
    final d = await db;
    final rows = await d.query(
      'activities',
      where: 'wfpId = ?',
      whereArgs: [wfpId],
      orderBy: 'id ASC',
    );
    return rows.map(BudgetActivity.fromMap).toList();
  }

  static Future<void> updateActivity(BudgetActivity activity) async {
    final d = await db;
    await d.update('activities', activity.toMap(), where: 'id = ?', whereArgs: [activity.id]);
    _scheduleAutoBackup();
  }

  static Future<void> deleteActivity(String id) async {
    final d = await db;
    await d.delete('activities', where: 'id = ?', whereArgs: [id]);
    _scheduleAutoBackup();
  }

  static Future<int> countActivitiesForWFP(String wfpId) async {
    final d = await db;
    final result = await d.rawQuery(
      'SELECT COUNT(*) AS cnt FROM activities WHERE wfpId = ?', [wfpId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<bool> activityIdExists(String id) async {
    final d = await db;
    final rows = await d.query('activities', columns: ['id'], where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty;
  }

  static Future<int> countAllActivities() async {
    final d = await db;
    final result = await d.rawQuery('SELECT COUNT(*) AS cnt FROM activities');
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<List<BudgetActivity>> getAllActivities() async {
    final d = await db;
    final rows = await d.query('activities', orderBy: 'id ASC');
    return rows.map(BudgetActivity.fromMap).toList();
  }

  /// Returns activities for a list of WFP IDs, keyed by wfpId (for grouped export).
  static Future<Map<String, List<BudgetActivity>>> getActivitiesForWFPs(
    List<String> wfpIds,
  ) async {
    if (wfpIds.isEmpty) return {};
    final d = await db;
    final placeholders = wfpIds.map((_) => '?').join(', ');
    final rows = await d.rawQuery(
      'SELECT * FROM activities WHERE wfpId IN ($placeholders) ORDER BY wfpId, id ASC',
      wfpIds,
    );
    final result = <String, List<BudgetActivity>>{};
    for (final row in rows) {
      final act = BudgetActivity.fromMap(row);
      result.putIfAbsent(act.wfpId, () => []).add(act);
    }
    return result;
  }

  // ─── Deadline queries ──────────────────────────────────────────────────────

  /// WFP entries whose dueDate falls within [withinDays] days from today.
  static Future<List<WFPEntry>> getWFPsDueSoon(int withinDays) async {
    final d = await db;
    final today = DateTime.now();
    final limit = today.add(Duration(days: withinDays));
    final todayStr = today.toIso8601String().substring(0, 10);
    final limitStr = limit.toIso8601String().substring(0, 10);
    final rows = await d.rawQuery(
      'SELECT * FROM wfp WHERE dueDate IS NOT NULL AND dueDate >= ? AND dueDate <= ?',
      [todayStr, limitStr],
    );
    return rows.map(WFPEntry.fromMap).toList();
  }

  /// Activities whose targetDate falls within [withinDays] days from today.
  static Future<List<BudgetActivity>> getActivitiesDueSoon(int withinDays) async {
    final d = await db;
    final today = DateTime.now();
    final limit = today.add(Duration(days: withinDays));
    final todayStr = today.toIso8601String().substring(0, 10);
    final limitStr = limit.toIso8601String().substring(0, 10);
    final rows = await d.rawQuery(
      'SELECT * FROM activities WHERE targetDate IS NOT NULL AND targetDate >= ? AND targetDate <= ?',
      [todayStr, limitStr],
    );
    return rows.map(BudgetActivity.fromMap).toList();
  }
  // ─── Audit Log ─────────────────────────────────────────────────────────────

  static Future<void> insertAuditLog({
    required String entityType,
    required String entityId,
    required String action,
    required String diffJson,
  }) async {
    final d = await db;
    await d.insert('audit_log', {
      'entityType': entityType,
      'entityId':   entityId,
      'action':     action,
      'timestamp':  DateTime.now().toIso8601String(),
      'diffJson':   diffJson,
    });
  }

  static Future<List<Map<String, dynamic>>> getAuditLog({
    int limit = 200,
    String? entityType,
    String? entityId,
  }) async {
    final d      = await db;
    final where  = <String>[];
    final args   = <dynamic>[];
    if (entityType != null) { where.add('entityType = ?'); args.add(entityType); }
    if (entityId   != null) { where.add('entityId = ?');   args.add(entityId); }
    return d.query(
      'audit_log',
      where:    where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy:  'id DESC',
      limit:    limit,
    );
  }

  static Future<void> clearAuditLog() async {
    final d = await db;
    await d.delete('audit_log');
  }

  // ─── Auto-backup ───────────────────────────────────────────────────────────

  /// Debounced trigger — resets the 30-second timer on every write.
  /// Only one backup fires per burst of activity, not one per save.
  static void _scheduleAutoBackup() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer(_autoBackupDelay, _runAutoBackup);
  }

  /// Performs the actual backup into archives/auto/, then prunes old files.
  /// Uses SQLite's VACUUM INTO instead of File.copy() so the backup is
  /// always consistent even while the database is open and locked.
  static Future<void> _runAutoBackup() async {
    try {
      final exeDir  = File(Platform.resolvedExecutable).parent.path;
      final dbPath  = p.join(exeDir, 'pims_deped.db');
      final autoDir = Directory(p.join(exeDir, 'archives', _autoBackupSubdir));

      // Sanity-check the source before doing anything
      final src = File(dbPath);
      if (!await src.exists() || await src.length() < 100) {
        debugPrint('[AutoBackup] Skipped — main DB is missing or empty.');
        return;
      }

      if (!await autoDir.exists()) await autoDir.create(recursive: true);

      final now   = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final dest = p.join(autoDir.path, 'pims_deped_auto_$stamp.db');

      // VACUUM INTO creates a clean, consistent copy through SQLite itself —
      // safe while the DB is open, no file-lock conflicts on Windows.
      // Use forward slashes: SQLite on Windows accepts both but some builds
      // choke on backslashes inside SQL strings.
      final destForSql = dest.replaceAll('\\', '/');
      final d = await db;
      await d.execute("VACUUM INTO '$destForSql'");

      lastAutoBackupTime   = now;
      lastAutoBackupPath   = dest;
      lastAutoBackupFailed = false;
      debugPrint('[AutoBackup] Saved to $dest');

      // ── Prune oldest auto-backups beyond the cap ───────────────────────
      final files = await autoDir
          .list()
          .where((e) => e is File && e.path.endsWith('.db'))
          .cast<File>()
          .toList();
      if (files.length > _maxAutoBackups) {
        files.sort((a, b) => a.path.compareTo(b.path)); // oldest first
        final toDelete = files.take(files.length - _maxAutoBackups);
        for (final f in toDelete) {
          await f.delete();
          debugPrint('[AutoBackup] Pruned old backup: ${f.path}');
        }
      }
    } catch (e, st) {
      lastAutoBackupFailed = true;
      debugPrint('[AutoBackup] Failed: $e\n$st');
    }
  }

}