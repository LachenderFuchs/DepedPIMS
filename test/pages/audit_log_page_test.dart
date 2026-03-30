import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/pages/audit_log_page.dart';
import 'package:pmis_deped/services/app_state.dart';

void main() {
  testWidgets('legacy update audit entries render without crashing', (
    tester,
  ) async {
    final appState = _FakeAuditAppState([
      {
        'id': 3,
        'entityType': 'WFP',
        'entityId': 'WFP-2026-0001',
        'action': 'UPDATE',
        'actorName': 'admin',
        'actorRole': 'Admin',
        'actorComment': null,
        'timestamp': '2026-03-29T12:47:00.000',
        'diffJson':
            '{"title":"Legacy Update","targetSize":"20","indicator":"Testing 1","year":2026,"fundType":"SBFP","viewSection":"HRD","amount":2000000.0,"approvalStatus":"Approved","approvedDate":"2026-03-29","dueDate":"2026-03-31"}',
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AuditLogPage(appState: appState)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Legacy Update'), findsOneWidget);

    await tester.tap(find.text('Legacy Update'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('older entry only stored the recorded values'),
      findsOneWidget,
    );
    expect(find.text('Program Title'), findsOneWidget);
  });
}

class _FakeAuditAppState extends AppState {
  _FakeAuditAppState(this._entries);

  final List<Map<String, dynamic>> _entries;

  @override
  Future<List<Map<String, dynamic>>> getAuditLog({
    int limit = 200,
    String? entityType,
    String? entityId,
  }) async {
    return _entries.take(limit).map(Map<String, dynamic>.from).toList();
  }

  @override
  Future<void> clearAuditLog() async {}
}
