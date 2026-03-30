import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/database/database_helper.dart';
import 'package:pmis_deped/models/wfp_entry.dart';
import 'package:pmis_deped/models/budget_activity.dart';

void main() {
  late Directory tmpDir;
  setUpAll(() async {
    tmpDir = Directory.systemTemp.createTempSync('pmis_db_recycle_test_');
    final dbPath = p.join(tmpDir.path, 'pmis_deped_recycle_test.db');
    await DatabaseHelper.initForTests(dbPath: dbPath);
  });

  tearDownAll(() async {
    await DatabaseHelper.closeDatabase();
    try {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('softDeleteWFP moves WFP and activities to recycle_bin and removes live', () async {
    final w = WFPEntry(
      id: 'RB-WFP-001',
      title: 'Recycle Test',
      targetSize: '10',
      indicator: 'I',
      year: 2026,
      fundType: 'GAA',
      amount: 111.0,
    );
    final a1 = BudgetActivity(
      id: 'RB-A1',
      wfpId: w.id,
      name: 'Act1',
      total: 50,
      projected: 40,
      disbursed: 10,
      status: 'Ongoing',
    );

    await DatabaseHelper.insertWFP(w);
    await DatabaseHelper.insertActivity(a1);

    // Verify inserted
    expect((await DatabaseHelper.getWFPById(w.id))?.id, w.id);
    expect((await DatabaseHelper.getActivitiesForWFP(w.id)).any((x) => x.id == a1.id), isTrue);

    final binId = await DatabaseHelper.softDeleteWFP(w, [a1]);
    expect(binId, greaterThan(0));

    // Live tables should no longer contain them
    expect(await DatabaseHelper.getWFPById(w.id), isNull);
    expect((await DatabaseHelper.getActivitiesForWFP(w.id)).isEmpty, isTrue);

    // Recycle bin should report at least one entry
    final entries = await DatabaseHelper.getRecycleBinEntries();
    expect(entries.any((e) => e['id'] == binId), isTrue);
  });

  test('restoreWFPFromBin restores WFP and activities back to live tables', () async {
    final w = WFPEntry(
      id: 'RB-WFP-002',
      title: 'Restore Sim',
      targetSize: '5',
      indicator: 'X',
      year: 2026,
      fundType: 'SDD',
      amount: 200.0,
    );
    final a = BudgetActivity(
      id: 'RB-A2',
      wfpId: w.id,
      name: 'ActR',
      total: 200,
      projected: 100,
      disbursed: 0,
      status: 'Pending',
    );

    // Insert live records, move them to the recycle bin, then restore them.
    await DatabaseHelper.insertWFP(w);
    await DatabaseHelper.insertActivity(a);
    final binId = await DatabaseHelper.softDeleteWFP(w, [a]);

    // Now restore
    final restored = await DatabaseHelper.restoreWFPFromBin(binId, w, [a]);
    expect(restored, isTrue);

    // Live tables should contain restored records
    expect((await DatabaseHelper.getWFPById(w.id))?.id, w.id);
    expect((await DatabaseHelper.getActivitiesForWFP(w.id)).any((x) => x.id == a.id), isTrue);
  });
}
