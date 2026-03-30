import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';

class ArchiveSnapshotInfo {
  const ArchiveSnapshotInfo({
    required this.path,
    required this.modifiedAt,
    required this.sizeBytes,
    required this.isAutoBackup,
  });

  final String path;
  final DateTime modifiedAt;
  final int sizeBytes;
  final bool isAutoBackup;

  String get fileName => p.basename(path);

  String get displayName {
    final baseName = p.basenameWithoutExtension(path);

    if (isAutoBackup) {
      return 'Automatic backup';
    }

    if (baseName.startsWith('pmis_deped_pre_restore_')) {
      return 'Pre-restore safeguard';
    }

    if (baseName.startsWith('pmis_deped_manual_')) {
      var label = baseName.substring('pmis_deped_manual_'.length);
      final stampMatch = RegExp(r'_(\d{8}_\d{6})$').firstMatch(label);
      if (stampMatch != null) {
        label = label.substring(0, stampMatch.start);
      }
      final cleaned = label.replaceAll(RegExp(r'[_-]+'), ' ').trim();
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }

    if (baseName.startsWith('pmis_deped_')) {
      return 'Manual backup';
    }

    return baseName.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }
}

class DatabaseHelper {
  static Database? _db;
  static const _databaseFileName = 'pmis_deped.db';
  static const _legacyDatabaseFileName = 'pims_deped.db';
  static const _appDataFolderName = 'PMIS DepED';
  static const _archivesFolderName = 'archives';
  static String? _dataRootPathOverride;
  static String? _databasePathOverride;
  static String? _archivesPathOverride;
  static String? _cachedDataRootPath;

  // â”€â”€â”€ Auto-backup config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Delay after the LAST write event before the backup actually fires.
  // Resets on every new write, so only one backup runs per burst of activity.
  // Default: 30 minutes. Changeable at runtime via setAutoBackupDelay().
  // Default to 30 seconds on app startup as the recommended quick auto-backup
  // behavior. This can be changed by the user in Settings during the session.
  static Duration _autoBackupDelay = const Duration(seconds: 30);
  static int _maxAutoBackups = 5;
  static const _autoBackupSubdir = 'auto';
  static const _manualBackupSubdir = 'manual';
  static const _prefsAutoBackupDelayKey = 'autoBackupDelaySeconds';
  static const _prefsAutoBackupRetentionKey = 'autoBackupRetentionCount';
  static Timer? _autoBackupTimer;

  /// Load persisted backup settings for this Windows desktop install.
  static Future<void> loadBackupSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final delaySeconds = prefs.getInt(_prefsAutoBackupDelayKey);
    final retention = prefs.getInt(_prefsAutoBackupRetentionKey);
    if (delaySeconds != null && delaySeconds > 0) {
      _autoBackupDelay = Duration(seconds: delaySeconds);
    }
    if (retention != null && retention > 0) {
      _maxAutoBackups = retention;
    }
  }

  /// Change the delay window and persist it for later launches. Cancels any
  /// pending timer so the
  /// new delay takes effect on the next write event.
  static Future<void> setAutoBackupDelay(Duration delay) async {
    _autoBackupDelay = delay;
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsAutoBackupDelayKey, delay.inSeconds);
  }

  /// Change the maximum number of retained auto-backups.
  static Future<void> setAutoBackupRetention(int maxBackups) async {
    _maxAutoBackups = maxBackups < 1 ? 1 : maxBackups;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsAutoBackupRetentionKey, _maxAutoBackups);
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
  static int get autoBackupRetention => _maxAutoBackups;

  /// Last auto-backup result â€” readable by the UI (settings page).\n
  static DateTime? lastAutoBackupTime;
  static String? lastAutoBackupPath;
  static bool lastAutoBackupFailed = false;

  static String _timestamp(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}_'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';

  static Future<String> get installDirectoryPath async =>
      File(Platform.resolvedExecutable).parent.path;

  static Future<String> get dataDirectoryPath async {
    final override = _dataRootPathOverride;
    if (override != null && override.isNotEmpty) {
      return _ensureDirectoryPath(override);
    }
    if (_cachedDataRootPath != null && _cachedDataRootPath!.isNotEmpty) {
      return _cachedDataRootPath!;
    }

    final String basePath;
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        basePath = localAppData;
      } else {
        final supportDir = await getApplicationSupportDirectory();
        basePath = supportDir.path;
      }
    } else {
      final supportDir = await getApplicationSupportDirectory();
      basePath = supportDir.path;
    }

    _cachedDataRootPath = await _ensureDirectoryPath(
      p.join(basePath, _appDataFolderName),
    );
    return _cachedDataRootPath!;
  }

  static Future<String> get databaseFilePath async {
    final override = _databasePathOverride;
    if (override != null && override.isNotEmpty) {
      await Directory(p.dirname(override)).create(recursive: true);
      return override;
    }
    return p.join(await dataDirectoryPath, _databaseFileName);
  }

  static Future<String> get archivesDirectoryPath async {
    final override = _archivesPathOverride;
    if (override != null && override.isNotEmpty) {
      return _ensureDirectoryPath(override);
    }
    return _ensureDirectoryPath(
      p.join(await dataDirectoryPath, _archivesFolderName),
    );
  }

  static Future<String> get autoArchivesDirectoryPath async =>
      _ensureDirectoryPath(
        p.join(await archivesDirectoryPath, _autoBackupSubdir),
      );

  static Future<String> get manualArchivesDirectoryPath async =>
      _ensureDirectoryPath(
        p.join(await archivesDirectoryPath, _manualBackupSubdir),
      );

  static Future<String> _ensureDirectoryPath(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<String> _createArchiveSnapshot({
    required String fileName,
    String? subdirectory,
  }) async {
    final archivesRoot = Directory(await archivesDirectoryPath);
    final targetDir = Directory(
      subdirectory == null || subdirectory.isEmpty
          ? archivesRoot.path
          : p.join(archivesRoot.path, subdirectory),
    );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final dest = p.join(targetDir.path, fileName);
    final destForSql = dest.replaceAll('\\', '/');
    final d = await db;
    await d.execute("VACUUM INTO '$destForSql'");

    final valid = await validateArchive(dest);
    if (!valid) {
      try {
        final invalid = File(dest);
        if (await invalid.exists()) await invalid.delete();
      } catch (_) {}
      throw Exception('Created snapshot failed integrity validation.');
    }

    return dest;
  }

  static Future<void> _migrateLegacyDatabaseFile({
    required String legacyDbPath,
    required String dbPath,
    required DatabaseFactory factory,
  }) async {
    if (legacyDbPath == dbPath) return;

    final currentFile = File(dbPath);
    if (await currentFile.exists()) return;

    final legacyFile = File(legacyDbPath);
    if (!await legacyFile.exists()) return;

    final legacyValid = await _isDatabaseValid(legacyDbPath, factory);
    if (!legacyValid) {
      debugPrint('[DB] Skipped legacy database migration from $legacyDbPath');
      return;
    }

    try {
      await legacyFile.rename(dbPath);
      debugPrint('[DB] Migrated legacy database to $dbPath');
    } on FileSystemException {
      await legacyFile.copy(dbPath);
      debugPrint('[DB] Copied legacy database to $dbPath');
    }
  }

  static Future<void> _migrateLegacyArchives({
    required String legacyArchivesPath,
    required String targetArchivesPath,
  }) async {
    if (p.equals(
      p.normalize(legacyArchivesPath),
      p.normalize(targetArchivesPath),
    )) {
      return;
    }

    final legacyDir = Directory(legacyArchivesPath);
    if (!await legacyDir.exists()) return;

    final targetDir = Directory(targetArchivesPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    await for (final entity in legacyDir.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = p.relative(entity.path, from: legacyDir.path);
      final destinationPath = p.join(targetDir.path, relativePath);

      if (entity is Directory) {
        await Directory(destinationPath).create(recursive: true);
        continue;
      }
      if (entity is! File) continue;

      final destinationFile = File(destinationPath);
      if (await destinationFile.exists()) continue;

      await Directory(p.dirname(destinationPath)).create(recursive: true);
      try {
        await entity.copy(destinationPath);
      } catch (e) {
        debugPrint(
          '[DB] Failed to migrate archive ${entity.path} -> $destinationPath: $e',
        );
      }
    }
  }

  // â”€â”€â”€ Connection â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<Database> get db async {
    if (_db != null) return _db!;

    sqfliteFfiInit();
    final factory = databaseFactoryFfi;

    // Production installs keep writable files in a per-user app data folder
    // instead of beside the executable. We still migrate older exe-adjacent
    // databases and archives forward on first launch.
    final installDir = await installDirectoryPath;
    final dataDir = await dataDirectoryPath;
    final dbPath = await databaseFilePath;
    final archDir = await archivesDirectoryPath;
    final installedDbPath = p.join(installDir, _databaseFileName);
    final installedLegacyDbPath = p.join(installDir, _legacyDatabaseFileName);
    final dataDirLegacyDbPath = p.join(dataDir, _legacyDatabaseFileName);

    await _migrateLegacyDatabaseFile(
      legacyDbPath: installedDbPath,
      dbPath: dbPath,
      factory: factory,
    );
    await _migrateLegacyDatabaseFile(
      legacyDbPath: installedLegacyDbPath,
      dbPath: dbPath,
      factory: factory,
    );
    await _migrateLegacyDatabaseFile(
      legacyDbPath: dataDirLegacyDbPath,
      dbPath: dbPath,
      factory: factory,
    );
    await _migrateLegacyArchives(
      legacyArchivesPath: p.join(installDir, _archivesFolderName),
      targetArchivesPath: archDir,
    );

    // â”€â”€ Integrity check â†’ archive fallback â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final needsRecovery = !(await _isDatabaseValid(dbPath, factory));
    if (needsRecovery) {
      final recovered = await _recoverFromArchive(dbPath, archDir, factory);
      if (recovered) {
        debugPrint('[DB] Recovered main database from archive.');
      } else {
        debugPrint(
          '[DB] No valid archive found - starting with a fresh database.',
        );
      }
    }

    _db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    return _db!;
  }

  // â”€â”€â”€ Validates that a db file exists, is non-empty, and passes SQLite's
  //     own integrity_check pragma. Returns true only if all pass. â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<bool> _isDatabaseValid(
    String dbPath,
    DatabaseFactory factory,
  ) async {
    final file = File(dbPath);

    // Missing or empty file â€” SQLite header is 100 bytes minimum
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
      final result = rows.isNotEmpty
          ? rows.first.values.first as String?
          : null;
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

  // â”€â”€â”€ Scans the archives folder (manual + auto) for the latest backup,
  //     copies it to dbPath, and returns true on success. â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<bool> _recoverFromArchive(
    String dbPath,
    String archDir,
    DatabaseFactory factory,
  ) async {
    final archives = await listArchivesInfo();
    if (archives.isEmpty) {
      debugPrint('[DB] No archives found in $archDir - starting fresh.');
      return false;
    }

    for (final candidate in archives) {
      final ok = await _isDatabaseValid(candidate.path, factory);
      if (ok) {
        debugPrint('[DB] Restoring from archive: ${candidate.path}');
        await File(candidate.path).copy(dbPath);
        return true;
      } else {
        debugPrint('[DB] Archive invalid, skipping: ${candidate.path}');
      }
    }

    debugPrint('[DB] All archives are invalid - cannot recover.');
    return false;
  }

  // â”€â”€â”€ Schema â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        actorName   TEXT NOT NULL,
        actorRole   TEXT NOT NULL DEFAULT 'Admin',
        actorComment TEXT,
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

  /// Incremental migrations â€” safe to run on existing databases.
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // v1 â†’ v2: approval fields on wfp, targetDate on activities
    if (oldVersion < 2) {
      await _addColumnIfMissing(
        db,
        'wfp',
        'approvalStatus',
        "TEXT NOT NULL DEFAULT 'Pending'",
      );
      await _addColumnIfMissing(db, 'wfp', 'approvedDate', 'TEXT');
      await _addColumnIfMissing(db, 'activities', 'targetDate', 'TEXT');
    }
    // v2 â†’ v3: dueDate on wfp
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'wfp', 'dueDate', 'TEXT');
    }
    // v3 â†’ v4: audit_log table
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_log (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          entityType  TEXT NOT NULL,
          entityId    TEXT NOT NULL,
          action      TEXT NOT NULL,
          actorName   TEXT NOT NULL,
          actorRole   TEXT NOT NULL DEFAULT 'Admin',
          actorComment TEXT,
          timestamp   TEXT NOT NULL,
          diffJson    TEXT NOT NULL
        )
      ''');
    }
    // v4 â†’ v5: viewSection column on wfp (bug-fix migration â€” was missing)
    if (oldVersion < 5) {
      await _addColumnIfMissing(
        db,
        'wfp',
        'viewSection',
        "TEXT NOT NULL DEFAULT 'HRD'",
      );
    }
    // v5 â†’ v6: recycle_bin table
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
    // v6 â†’ v7: activity soft-delete support in recycle_bin
    if (oldVersion < 7) {
      await _addColumnIfMissing(
        db,
        'recycle_bin',
        'entryType',
        "TEXT NOT NULL DEFAULT 'WFP'",
      );
      await _addColumnIfMissing(db, 'recycle_bin', 'activityJson', 'TEXT');
      await _addColumnIfMissing(db, 'recycle_bin', 'wfpId', 'TEXT');
    }
    // v7 â†’ v8: actor metadata on audit_log
    if (oldVersion < 8) {
      await _addColumnIfMissing(
        db,
        'audit_log',
        'actorName',
        "TEXT NOT NULL DEFAULT 'Unknown user'",
      );
      await _addColumnIfMissing(
        db,
        'audit_log',
        'actorRole',
        "TEXT NOT NULL DEFAULT 'Admin'",
      );
      await _addColumnIfMissing(db, 'audit_log', 'actorComment', 'TEXT');
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
      // Column already exists â€” safe to ignore
    }
  }

  // â”€â”€â”€ WFP CRUD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> insertWFP(WFPEntry entry) async {
    final d = await db;
    await d.insert(
      'wfp',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
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
    await d.update(
      'wfp',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
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
      'SELECT COUNT(*) AS cnt FROM wfp WHERE year = ?',
      [year],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<bool> wfpIdExists(String id) async {
    final d = await db;
    final rows = await d.query(
      'wfp',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
    );
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
    if (year != null) {
      where.add('year = ?');
      args.add(year);
    }
    if (approvalStatus != null) {
      where.add('approvalStatus = ?');
      args.add(approvalStatus);
    }
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
    final rows = await d.rawQuery(
      'SELECT DISTINCT year FROM wfp ORDER BY year DESC',
    );
    return rows.map((r) => r['year'] as int).toList();
  }

  // â”€â”€â”€ Activity CRUD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> insertActivity(BudgetActivity activity) async {
    final d = await db;
    await d.insert(
      'activities',
      activity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
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
    await d.update(
      'activities',
      activity.toMap(),
      where: 'id = ?',
      whereArgs: [activity.id],
    );
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
      'SELECT COUNT(*) AS cnt FROM activities WHERE wfpId = ?',
      [wfpId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<bool> activityIdExists(String id) async {
    final d = await db;
    final rows = await d.query(
      'activities',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
    );
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

  // â”€â”€â”€ Deadline queries â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// WFP entries whose dueDate falls within [withinDays] days from today.
  static Future<List<WFPEntry>> getWFPsDueSoon(int withinDays) async {
    final d = await db;
    final today = DateTime.now();
    final limit = today.add(Duration(days: withinDays));
    final limitStr = limit.toIso8601String().substring(0, 10);
    final rows = await d.rawQuery(
      'SELECT * FROM wfp '
      'WHERE dueDate IS NOT NULL AND dueDate <= ? '
      'ORDER BY dueDate ASC, id ASC',
      [limitStr],
    );
    return rows.map(WFPEntry.fromMap).toList();
  }

  /// Activities whose targetDate falls within [withinDays] days from today.
  static Future<List<BudgetActivity>> getActivitiesDueSoon(
    int withinDays,
  ) async {
    final d = await db;
    final today = DateTime.now();
    final limit = today.add(Duration(days: withinDays));
    final limitStr = limit.toIso8601String().substring(0, 10);
    final rows = await d.rawQuery(
      'SELECT * FROM activities '
      'WHERE targetDate IS NOT NULL AND targetDate <= ? '
      'ORDER BY targetDate ASC, id ASC',
      [limitStr],
    );
    return rows.map(BudgetActivity.fromMap).toList();
  }
  // â”€â”€â”€ Audit Log â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> insertAuditLog({
    required String entityType,
    required String entityId,
    required String action,
    required String actorName,
    required String actorRole,
    required String diffJson,
    String? actorComment,
  }) async {
    final d = await db;
    await d.insert('audit_log', {
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'actorName': actorName,
      'actorRole': actorRole,
      'actorComment': actorComment,
      'timestamp': DateTime.now().toIso8601String(),
      'diffJson': diffJson,
    });
  }

  static Future<List<Map<String, dynamic>>> getAuditLog({
    int limit = 200,
    String? entityType,
    String? entityId,
  }) async {
    final d = await db;
    final where = <String>[];
    final args = <dynamic>[];
    if (entityType != null) {
      where.add('entityType = ?');
      args.add(entityType);
    }
    if (entityId != null) {
      where.add('entityId = ?');
      args.add(entityId);
    }
    return d.query(
      'audit_log',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  static Future<void> clearAuditLog() async {
    final d = await db;
    await d.delete('audit_log');
  }

  // â”€â”€â”€ Recycle Bin â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Moves a WFP and all its activities into the recycle_bin as JSON snapshots,
  /// then hard-deletes them from the live tables. Returns the bin row id.
  static Future<int> softDeleteWFP(
    WFPEntry entry,
    List<BudgetActivity> activities,
  ) async {
    final d = await db;
    final wfpJson = jsonEncode(entry.toMap());
    final activitiesJson = jsonEncode(
      activities.map((a) => a.toMap()).toList(),
    );
    int binId = -1;
    await d.transaction((txn) async {
      final pragma = await txn.rawQuery("PRAGMA table_info('recycle_bin')");
      final columns = pragma
          .map((row) => (row['name'] as String).toLowerCase())
          .toSet();

      final entryMap = <String, dynamic>{
        if (columns.contains('entrytype')) 'entryType': 'WFP',
        if (columns.contains('wfpjson')) 'wfpJson': wfpJson,
        if (columns.contains('activitiesjson'))
          'activitiesJson': activitiesJson,
        'deletedAt': DateTime.now().toIso8601String(),
      };

      binId = await txn.insert('recycle_bin', entryMap);
      await txn.delete('activities', where: 'wfpId = ?', whereArgs: [entry.id]);
      await txn.delete('wfp', where: 'id = ?', whereArgs: [entry.id]);
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
    final existing = await d.query(
      'wfp',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [wfp.id],
    );
    if (existing.isNotEmpty) return false;

    await d.insert(
      'wfp',
      wfp.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
    for (final a in activities) {
      await d.insert(
        'activities',
        a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
    final wfpRows = await d.query(
      'wfp',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [activity.wfpId],
    );
    if (wfpRows.isEmpty) return false;
    // Guard: activity id must not already exist
    final actRows = await d.query(
      'activities',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [activity.id],
    );
    if (actRows.isNotEmpty) return false;

    await d.insert(
      'activities',
      activity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
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

  // â”€â”€â”€ Auto-backup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Debounced trigger â€” resets the 30-second timer on every write.
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
      final now = DateTime.now();
      final dest = await _createArchiveSnapshot(
        fileName: 'pmis_deped_auto_${_timestamp(now)}.db',
        subdirectory: _autoBackupSubdir,
      );

      lastAutoBackupTime = now;
      lastAutoBackupPath = dest;
      lastAutoBackupFailed = false;
      debugPrint('[AutoBackup] Saved to $dest');

      final autoDir = Directory(await autoArchivesDirectoryPath);
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

  static String _sanitizeArchiveLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Backup name cannot be empty.');
    }

    final cleaned = trimmed
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'[^\w-]'), '')
        .replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');

    if (cleaned.isEmpty) {
      throw ArgumentError('Backup name must include letters or numbers.');
    }

    return cleaned;
  }

  static Future<ArchiveSnapshotInfo?> _buildArchiveInfo(
    File file, {
    required bool isAutoBackup,
  }) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        return null;
      }
      return ArchiveSnapshotInfo(
        path: file.path,
        modifiedAt: stat.modified,
        sizeBytes: stat.size,
        isAutoBackup: isAutoBackup,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<ArchiveSnapshotInfo>> _listArchiveInfoFromDirectory(
    String directoryPath, {
    required bool isAutoBackup,
  }) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      return const [];
    }

    final files = await dir
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.db'))
        .cast<File>()
        .toList();

    final snapshots = await Future.wait(
      files.map((file) => _buildArchiveInfo(file, isAutoBackup: isAutoBackup)),
    );

    return snapshots.whereType<ArchiveSnapshotInfo>().toList(growable: false);
  }

  static Future<List<ArchiveSnapshotInfo>> listArchivesInfo({
    bool includeManual = true,
    bool includeAuto = true,
  }) async {
    final archives = <ArchiveSnapshotInfo>[];

    if (includeManual) {
      final archivesRoot = Directory(await archivesDirectoryPath);
      if (await archivesRoot.exists()) {
        final legacyRootFiles = await archivesRoot
            .list(followLinks: false)
            .where((entity) => entity is File && entity.path.endsWith('.db'))
            .cast<File>()
            .toList();
        final legacySnapshots = await Future.wait(
          legacyRootFiles.map(
            (file) => _buildArchiveInfo(file, isAutoBackup: false),
          ),
        );
        archives.addAll(legacySnapshots.whereType<ArchiveSnapshotInfo>());
      }

      archives.addAll(
        await _listArchiveInfoFromDirectory(
          await manualArchivesDirectoryPath,
          isAutoBackup: false,
        ),
      );
    }

    if (includeAuto) {
      archives.addAll(
        await _listArchiveInfoFromDirectory(
          await autoArchivesDirectoryPath,
          isAutoBackup: true,
        ),
      );
    }

    archives.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return archives;
  }

  static Future<List<ArchiveSnapshotInfo>> listManualArchivesInfo() =>
      listArchivesInfo(includeAuto: false);

  static Future<List<ArchiveSnapshotInfo>> listAutoArchivesInfo() =>
      listArchivesInfo(includeManual: false);

  static Future<String> createManualArchive({String? label}) async {
    final now = DateTime.now();
    final timestamp = _timestamp(now);
    final fileName = label == null
        ? 'pmis_deped_$timestamp.db'
        : 'pmis_deped_manual_${_sanitizeArchiveLabel(label)}_$timestamp.db';
    return _createArchiveSnapshot(
      fileName: fileName,
      subdirectory: _manualBackupSubdir,
    );
  }

  // â”€â”€â”€ Manual snapshot helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Returns a list of available archive db files (manual + auto), newest-first.
  static Future<List<String>> listArchives() async =>
      (await listArchivesInfo()).map((archive) => archive.path).toList();

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

  /// Initialize a temporary database for tests.
  /// If [dbPath] is omitted a temp file is used. This method sets the
  /// internal `_db` handle so the rest of the static helpers operate
  /// against the test database.
  static Future<void> initForTests({String? dbPath}) async {
    try {
      await closeDatabase();
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;
      final pathToUse =
          dbPath ??
          p.join(
            Directory.systemTemp.createTempSync().path,
            'pmis_deped_test.db',
          );
      _cachedDataRootPath = null;
      _dataRootPathOverride = p.dirname(pathToUse);
      _databasePathOverride = pathToUse;
      _archivesPathOverride = p.join(
        _dataRootPathOverride!,
        _archivesFolderName,
      );
      _db = await factory.openDatabase(
        pathToUse,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } catch (e) {
      debugPrint('[DB Test Init] failed: $e');
      rethrow;
    }
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

      final dbPath = await databaseFilePath;
      final manualArchivesPath = await manualArchivesDirectoryPath;
      final stamp = _timestamp(DateTime.now());
      String? preRestoreBackup;

      try {
        preRestoreBackup = await _createArchiveSnapshot(
          fileName: 'pmis_deped_pre_restore_$stamp.db',
          subdirectory: _manualBackupSubdir,
        );
      } catch (_) {
        final src = File(dbPath);
        if (await src.exists()) {
          final fallback = p.join(
            manualArchivesPath,
            'pmis_deped_pre_restore_$stamp.db',
          );
          try {
            await src.copy(fallback);
            preRestoreBackup = fallback;
          } catch (_) {}
        }
      }

      // Close DB, overwrite, and reset internal handle so next db getter reopens
      await closeDatabase();
      final archFile = File(archivePath);
      if (!await archFile.exists()) return false;
      final destFile = File(dbPath);
      if (await destFile.exists()) await destFile.delete();
      await archFile.copy(dbPath);
      final restoredValid = await _isDatabaseValid(dbPath, factory);
      if (!restoredValid) {
        if (preRestoreBackup != null) {
          final backupFile = File(preRestoreBackup);
          if (await backupFile.exists()) {
            if (await destFile.exists()) await destFile.delete();
            await backupFile.copy(dbPath);
          }
        }
        _db = null;
        return false;
      }
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
        final result = rows.isNotEmpty
            ? rows.first.values.first as String?
            : null;
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
        // Not fatal â€” continue
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
