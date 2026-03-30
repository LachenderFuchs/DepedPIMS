import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/database/database_helper.dart';
import 'package:pmis_deped/models/wfp_entry.dart';
import 'package:pmis_deped/services/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('pmis_app_state_audit_');
    await DatabaseHelper.initForTests(
      dbPath: p.join(tmpDir.path, 'pmis_deped_app_state_test.db'),
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeDatabase();
    try {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test(
    'update audit logs use diff-shaped payloads when the previous row is missing',
    () async {
      final appState = AppState();
      appState.startSession(username: 'admin');

      final entry = WFPEntry(
        id: 'WFP-2026-0999',
        title: 'Fallback Update',
        targetSize: '25',
        indicator: 'Legacy-safe payload',
        year: 2026,
        fundType: 'SBFP',
        viewSection: 'HRD',
        amount: 1500000,
        approvalStatus: 'Approved',
        approvedDate: '2026-03-29',
        dueDate: '2026-03-31',
      );

      await appState.updateWFP(entry);

      final entries = await DatabaseHelper.getAuditLog(
        limit: 1,
        entityId: entry.id,
      );

      expect(entries, hasLength(1));
      expect(entries.first['action'], 'UPDATE');

      final payload = jsonDecode(entries.first['diffJson'] as String) as Map;
      final fields = Map<String, dynamic>.from(payload['fields'] as Map);
      final titleChange = Map<String, dynamic>.from(fields['title'] as Map);
      final dueDateChange = Map<String, dynamic>.from(fields['dueDate'] as Map);

      expect(payload['_meta'], isA<Map>());
      expect(titleChange['from'], isNull);
      expect(titleChange['to'], 'Fallback Update');
      expect(dueDateChange['from'], isNull);
      expect(dueDateChange['to'], '2026-03-31');
    },
  );
}
