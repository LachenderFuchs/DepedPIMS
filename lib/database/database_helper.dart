import 'dart:async';
import 'dart:convert';
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
  // Default to 30 seconds on app startup as the recommended quick auto-backup
  // behavior. This can be changed by the user in Settings during the session.
  static Duration _autoBackupDelay  = const Duration(seconds: 30);
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

  /// Trigger an immediate auto-backup (useful for startup scheduling).
  /// This runs the same logic as the debounced auto-backup routine.
  static Future<void> triggerAutoBackupNow() async {
    try {
      await _runAutoBackup();
    } catch (e, st) {
      debugPrint('[AutoBackup] trigger failed: $e\n$st');
    }
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
        version: 7,
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
        viewSection    TEXT NOT NULL DEFAULT 'HRD',
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

    await db.execute('''
      CREATE TABLE recycle_bin (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        entryType      TEXT NOT NULL DEFAULT 'WFP',
        wfpJson        TEXT NOT NULL DEFAULT '',
        activitiesJson TEXT NOT NULL DEFAULT '[]',
        activityJson   TEXT,
        wfpId          TEXT,
        deletedAt      TEXT NOT NULL
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
    // v4 → v5: viewSection column on wfp (bug-fix migration — was missing)
    if (oldVersion < 5) {
      await _addColumnIfMissing(db, 'wfp', 'viewSection', "TEXT NOT NULL DEFAULT 'HRD'");
    }
    // v5 → v6: recycle_bin table
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS recycle_bin (
          id             INTEGER PRIMARY KEY AUTOINCREMENT,
          wfpJson        TEXT NOT NULL DEFAULT '',
          activitiesJson TEXT NOT NULL DEFAULT '[]',
          deletedAt      TEXT NOT NULL
        )
      ''');
    }
    // v6 → v7: activity soft-delete support in recycle_bin
    if (oldVersion < 7) {
      await _addColumnIfMissing(db, 'recycle_bin', 'entryType',    "TEXT NOT NULL DEFAULT 'WFP'");
      await _addColumnIfMissing(db, 'recycle_bin', 'activityJson', 'TEXT');
      await _addColumnIfMissing(db, 'recycle_bin', 'wfpId',        'TEXT');
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

  // ─── Recycle Bin ───────────────────────────────────────────────────────────

  /// Moves a WFP and all its activities into the recycle_bin as JSON snapshots,
  /// then hard-deletes them from the live tables. Returns the bin row id.
  static Future<int> softDeleteWFP(WFPEntry entry, List<BudgetActivity> activities) async {
    final d = await db;
    final wfpJson        = jsonEncode(entry.toMap());
    final activitiesJson = jsonEncode(activities.map((a) => a.toMap()).toList());
    int binId = -1;
    await d.transaction((txn) async {
      final pragma = await txn.rawQuery("PRAGMA table_info('recycle_bin')");
      final columns = pragma
          .map((row) => (row['name'] as String).toLowerCase())
          .toSet();

      final entryMap = <String, dynamic>{
        if (columns.contains('entrytype')) 'entryType': 'WFP',
        if (columns.contains('wfpjson')) 'wfpJson': wfpJson,
        if (columns.contains('activitiesjson')) 'activitiesJson': activitiesJson,
        'deletedAt': DateTime.now().toIso8601String(),
      };

      binId = await txn.insert('recycle_bin', entryMap);
      await txn.delete('activities', where: 'wfpId = ?', whereArgs: [entry.id]);
      await txn.delete('wfp',        where: 'id = ?',    whereArgs: [entry.id]);
    });
    _scheduleAutoBackup();
    return binId;
  }

  /// Moves a single BudgetActivity into the recycle_bin, then hard-deletes it.
  /// [parentWfpId] is stored for display context in the recycle bin UI.
  static Future<void> softDeleteActivity(BudgetActivity activity) async {
    final d = await db;
    await d.transaction((txn) async {
      // Handle old DB versions where some columns may not exist yet.
      final pragma = await txn.rawQuery("PRAGMA table_info('recycle_bin')");
      final columns = pragma
          .map((row) => (row['name'] as String).toLowerCase())
          .toSet();

      final entry = <String, dynamic>{
        if (columns.contains('entrytype')) 'entryType': 'Activity',
        if (columns.contains('activityjson'))
          'activityJson': jsonEncode(activity.toMap()),
        if (columns.contains('wfpid')) 'wfpId': activity.wfpId,
        if (columns.contains('wfpjson')) 'wfpJson': '',
        if (columns.contains('activitiesjson')) 'activitiesJson': '[]',
        'deletedAt': DateTime.now().toIso8601String(),
      };

      await txn.insert('recycle_bin', entry);
      await txn.delete('activities', where: 'id = ?', whereArgs: [activity.id]);
    });
    _scheduleAutoBackup();
  }

  /// Returns all recycle bin entries, newest first.
  static Future<List<Map<String, dynamic>>> getRecycleBinEntries() async {
    final d = await db;
    return d.query('recycle_bin', orderBy: 'id DESC');
  }

  /// Count of items currently in the recycle bin (for the sidebar badge).
  static Future<int> countRecycleBin() async {
    final d = await db;
    final result = await d.rawQuery('SELECT COUNT(*) AS cnt FROM recycle_bin');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Restores a WFP bin entry (entryType == 'WFP') back into live tables.
  /// Returns false if the WFP id already exists (conflict), true on success.
  static Future<bool> restoreWFPFromBin(
    int binId,
    WFPEntry wfp,
    List<BudgetActivity> activities,
  ) async {
    final d = await db;
    // Guard: don't restore if id already exists in live table
    final existing = await d.query('wfp', columns: ['id'], where: 'id = ?', whereArgs: [wfp.id]);
    if (existing.isNotEmpty) return false;

    await d.insert('wfp', wfp.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
    for (final a in activities) {
      await d.insert('activities', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await d.delete('recycle_bin', where: 'id = ?', whereArgs: [binId]);
    _scheduleAutoBackup();
    return true;
  }

  /// Restores a single Activity bin entry (entryType == 'Activity') back into
  /// the activities table. Returns false if the activity id already exists OR
  /// if the parent WFP no longer exists in the live table.
  static Future<bool> restoreActivityFromBin(
    int binId,
    BudgetActivity activity,
  ) async {
    final d = await db;
    // Guard: parent WFP must still exist
    final wfpRows = await d.query('wfp', columns: ['id'],
        where: 'id = ?', whereArgs: [activity.wfpId]);
    if (wfpRows.isEmpty) return false;
    // Guard: activity id must not already exist
    final actRows = await d.query('activities', columns: ['id'],
        where: 'id = ?', whereArgs: [activity.id]);
    if (actRows.isNotEmpty) return false;

    await d.insert('activities', activity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail);
    await d.delete('recycle_bin', where: 'id = ?', whereArgs: [binId]);
    _scheduleAutoBackup();
    return true;
  }

  // Keep old name as a redirect so any call sites outside AppState still compile.
  static Future<bool> restoreFromBin(
    int binId,
    WFPEntry wfp,
    List<BudgetActivity> activities,
  ) => restoreWFPFromBin(binId, wfp, activities);

  /// Permanently removes a single entry from the recycle bin.
  static Future<void> permanentlyDeleteFromBin(int binId) async {
    final d = await db;
    await d.delete('recycle_bin', where: 'id = ?', whereArgs: [binId]);
  }

  /// Empties the entire recycle bin permanently.
  static Future<void> emptyRecycleBin() async {
    final d = await db;
    await d.delete('recycle_bin');
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

  // ─── Manual snapshot helpers ───────────────────────────────────────────

  /// Returns a list of available archive db files (manual + auto), newest-first.
  static Future<List<String>> listArchives() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final archDir = Directory(p.join(exeDir, 'archives'));
    final files = <File>[];
    if (await archDir.exists()) {
      files.addAll(await archDir
          .list(recursive: true)
          .where((e) => e is File && e.path.endsWith('.db'))
          .cast<File>()
          .toList());
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.map((f) => f.path).toList();
  }

  /// Validate a candidate archive DB file by running SQLite's integrity_check.
  /// Returns true only if the file exists and the integrity check returns 'ok'.
  static Future<bool> validateArchive(String archivePath) async {
    try {
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;
      return await _isDatabaseValid(archivePath, factory);
    } catch (e) {
      debugPrint('[DB] validateArchive failed: $e');
      return false;
    }
  }

  /// Close the open database connection (if any). Useful before replacing
  /// the main DB file on disk.
  static Future<void> closeDatabase() async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
  }

  /// Restore the main database from an archive file. Performs a quick
  /// integrity check on the candidate archive before replacing the live DB.
  /// Returns true on success.
  static Future<bool> restoreFromArchivePath(String archivePath) async {
    try {
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;
      final ok = await _isDatabaseValid(archivePath, factory);
      if (!ok) return false;

      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final dbPath = p.join(exeDir, 'pims_deped.db');

      // Make a timestamped backup of current DB before overwrite
      final src = File(dbPath);
      if (await src.exists()) {
        final now = DateTime.now();
        final stamp =
            '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
        final backup = p.join(exeDir, 'pims_deped_pre_restore_$stamp.db');
        try {
          await src.copy(backup);
        } catch (_) {}
      }

      // Close DB, overwrite, and reset internal handle so next db getter reopens
      await closeDatabase();
      final archFile = File(archivePath);
      if (!await archFile.exists()) return false;
      final destFile = File(dbPath);
      if (await destFile.exists()) await destFile.delete();
      await archFile.copy(dbPath);
      _db = null;
      return true;
    } catch (e) {
      debugPrint('[DB] restoreFromArchivePath failed: $e');
      return false;
    }
  }

  /// Run maintenance and normalization tasks on the live database.
  /// Returns true on success. Performs an integrity check, PRAGMA optimize,
  /// VACUUM, and ANALYZE. Use sparingly as VACUUM can be expensive.
  static Future<bool> normalizeDatabase() async {
    try {
      final d = await db;

      // Quick integrity check first
      try {
        final rows = await d.rawQuery('PRAGMA integrity_check');
        final result = rows.isNotEmpty ? rows.first.values.first as String? : null;
        if (result != 'ok') {
          debugPrint('[DB] integrity_check failed: $result');
          return false;
        }
      } catch (e) {
        debugPrint('[DB] integrity_check error: $e');
        return false;
      }

      // Try PRAGMA optimize (no-op on older SQLite but safe)
      try {
        await d.execute('PRAGMA optimize');
      } catch (_) {}

      // VACUUM to rebuild the database file and reclaim space
      try {
        await d.execute('VACUUM');
      } catch (e) {
        debugPrint('[DB] VACUUM failed: $e');
        // Not fatal — continue
      }

      // ANALYZE to update sqlite statistics
      try {
        await d.execute('ANALYZE');
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('[DB] normalizeDatabase error: $e');
      return false;
    }
  }

}