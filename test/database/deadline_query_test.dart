import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/database/database_helper.dart';
import 'package:pmis_deped/models/budget_activity.dart';
import 'package:pmis_deped/models/wfp_entry.dart';

void main() {
  late Directory tmpDir;

  String dateOffset(int days) {
    final now = DateTime.now();
    final value = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: days));
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  setUpAll(() async {
    tmpDir = Directory.systemTemp.createTempSync('pmis_deadline_test_');
    final dbPath = p.join(tmpDir.path, 'pmis_deadline_test.db');
    await DatabaseHelper.initForTests(dbPath: dbPath);
  });

  tearDownAll(() async {
    await DatabaseHelper.closeDatabase();
    try {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'due soon queries include overdue records and exclude far-future ones',
    () async {
      final overdueWfp = WFPEntry(
        id: 'DL-WFP-OVERDUE',
        title: 'Overdue WFP',
        targetSize: '10',
        indicator: 'I',
        year: 2026,
        fundType: 'MODE',
        amount: 100,
        dueDate: dateOffset(-2),
      );
      final upcomingWfp = WFPEntry(
        id: 'DL-WFP-UPCOMING',
        title: 'Upcoming WFP',
        targetSize: '10',
        indicator: 'I',
        year: 2026,
        fundType: 'MODE',
        amount: 100,
        dueDate: dateOffset(3),
      );
      final laterWfp = WFPEntry(
        id: 'DL-WFP-LATER',
        title: 'Later WFP',
        targetSize: '10',
        indicator: 'I',
        year: 2026,
        fundType: 'MODE',
        amount: 100,
        dueDate: dateOffset(15),
      );

      await DatabaseHelper.insertWFP(overdueWfp);
      await DatabaseHelper.insertWFP(upcomingWfp);
      await DatabaseHelper.insertWFP(laterWfp);

      final overdueActivity = BudgetActivity(
        id: 'DL-ACT-OVERDUE',
        wfpId: overdueWfp.id,
        name: 'Overdue Activity',
        total: 50,
        projected: 40,
        disbursed: 10,
        status: 'Ongoing',
        targetDate: dateOffset(-1),
      );
      final upcomingActivity = BudgetActivity(
        id: 'DL-ACT-UPCOMING',
        wfpId: upcomingWfp.id,
        name: 'Upcoming Activity',
        total: 50,
        projected: 40,
        disbursed: 10,
        status: 'Ongoing',
        targetDate: dateOffset(4),
      );
      final laterActivity = BudgetActivity(
        id: 'DL-ACT-LATER',
        wfpId: laterWfp.id,
        name: 'Later Activity',
        total: 50,
        projected: 40,
        disbursed: 10,
        status: 'Ongoing',
        targetDate: dateOffset(20),
      );

      await DatabaseHelper.insertActivity(overdueActivity);
      await DatabaseHelper.insertActivity(upcomingActivity);
      await DatabaseHelper.insertActivity(laterActivity);

      final dueWfps = await DatabaseHelper.getWFPsDueSoon(7);
      final dueActivities = await DatabaseHelper.getActivitiesDueSoon(7);

      expect(
        dueWfps.map((entry) => entry.id),
        containsAll(<String>[overdueWfp.id, upcomingWfp.id]),
      );
      expect(dueWfps.map((entry) => entry.id), isNot(contains(laterWfp.id)));

      expect(
        dueActivities.map((entry) => entry.id),
        containsAll(<String>[overdueActivity.id, upcomingActivity.id]),
      );
      expect(
        dueActivities.map((entry) => entry.id),
        isNot(contains(laterActivity.id)),
      );
    },
  );
}
