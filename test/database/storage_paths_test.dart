import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/database/database_helper.dart';

void main() {
  late Directory tmpDir;
  late String dbPath;

  setUpAll(() async {
    tmpDir = Directory.systemTemp.createTempSync('pmis_storage_paths_');
    dbPath = p.join(tmpDir.path, 'pmis_deped_test.db');
    await DatabaseHelper.initForTests(dbPath: dbPath);
  });

  tearDownAll(() async {
    await DatabaseHelper.closeDatabase();
    try {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test(
    'test storage overrides keep database artifacts in writable temp root',
    () async {
      final dataDir = await DatabaseHelper.dataDirectoryPath;
      final resolvedDbPath = await DatabaseHelper.databaseFilePath;
      final archiveDir = await DatabaseHelper.archivesDirectoryPath;

      expect(p.normalize(dataDir), p.normalize(tmpDir.path));
      expect(p.normalize(resolvedDbPath), p.normalize(dbPath));
      expect(
        p.normalize(archiveDir),
        p.normalize(p.join(tmpDir.path, 'archives')),
      );
    },
  );

  test('manual archive creation stays inside the writable temp root', () async {
    final manualArchiveDir = await DatabaseHelper.manualArchivesDirectoryPath;
    final archivePath = await DatabaseHelper.createManualArchive(
      label: 'Quarter End Review',
    );
    final listed = await DatabaseHelper.listManualArchivesInfo();

    expect(p.normalize(p.dirname(archivePath)), p.normalize(manualArchiveDir));
    expect(
      p.basename(archivePath),
      startsWith('pmis_deped_manual_Quarter_End_Review_'),
    );
    expect(listed.map((archive) => archive.path), contains(archivePath));
    expect(await DatabaseHelper.validateArchive(archivePath), isTrue);
  });

  test('manual and automatic backups are listed separately', () async {
    final manualPath = await DatabaseHelper.createManualArchive(
      label: 'Before Restore',
    );

    await DatabaseHelper.triggerAutoBackupNow();

    final manualArchives = await DatabaseHelper.listManualArchivesInfo();
    final autoArchives = await DatabaseHelper.listAutoArchivesInfo();

    expect(manualArchives.any((archive) => archive.path == manualPath), isTrue);
    expect(
      manualArchives.every((archive) => archive.isAutoBackup == false),
      isTrue,
    );
    expect(autoArchives, isNotEmpty);
    expect(autoArchives.every((archive) => archive.isAutoBackup), isTrue);
    expect(autoArchives.any((archive) => archive.path == manualPath), isFalse);
  });
}
