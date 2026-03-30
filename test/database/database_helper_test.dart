import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/database/database_helper.dart';
import 'package:pmis_deped/models/wfp_entry.dart';
import 'package:pmis_deped/models/budget_activity.dart';

void main() {
  late Directory tmpDir;
  setUpAll(() async {
    tmpDir = Directory.systemTemp.createTempSync('pmis_db_test_');
    final dbPath = p.join(tmpDir.path, 'pmis_deped_test.db');
    await DatabaseHelper.initForTests(dbPath: dbPath);
  });

  tearDownAll(() async {
    await DatabaseHelper.closeDatabase();
    try {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('insert and query WFP entry', () async {
    final w = WFPEntry(
      id: 'WFP-TEST-0001',
      title: 'Test WFP',
      targetSize: '10',
      indicator: 'I',
      year: 2026,
      fundType: 'GAA',
      amount: 1000.0,
    );
    await DatabaseHelper.insertWFP(w);
    final all = await DatabaseHelper.getAllWFPs();
    expect(all.any((e) => e.id == w.id), isTrue);

    final cnt = await DatabaseHelper.countWFPsByYear(2026);
    expect(cnt, greaterThanOrEqualTo(1));
  });

  test('insert and query activity', () async {
    final a = BudgetActivity(
      id: 'ACT-TEST-01',
      wfpId: 'WFP-TEST-0001',
      name: 'Activity 1',
      total: 500,
      projected: 400,
      disbursed: 100,
      status: 'Ongoing',
    );
    await DatabaseHelper.insertActivity(a);
    final acts = await DatabaseHelper.getActivitiesForWFP('WFP-TEST-0001');
    expect(acts.any((x) => x.id == a.id), isTrue);

    final count = await DatabaseHelper.countActivitiesForWFP('WFP-TEST-0001');
    expect(count, greaterThanOrEqualTo(1));
  });
}
