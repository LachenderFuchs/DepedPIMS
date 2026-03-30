import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/database/database_helper.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = Directory.systemTemp.createTempSync('pmis_audit_test_');
    final dbPath = p.join(tmpDir.path, 'pmis_deped_audit_test.db');
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

  test('audit log persists actor metadata', () async {
    await DatabaseHelper.clearAuditLog();

    await DatabaseHelper.insertAuditLog(
      entityType: 'WFP',
      entityId: 'WFP-ACTOR-0001',
      action: 'CREATE',
      actorName: 'Alice Reyes',
      actorRole: 'Admin',
      actorComment: 'Initial import',
      diffJson: '{}',
    );

    final entries = await DatabaseHelper.getAuditLog(
      limit: 1,
      entityId: 'WFP-ACTOR-0001',
    );

    expect(entries, hasLength(1));
    expect(entries.first['actorName'], 'Alice Reyes');
    expect(entries.first['actorRole'], 'Admin');
    expect(entries.first['actorComment'], 'Initial import');
  });
}
