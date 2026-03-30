import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/models/budget_activity.dart';

void main() {
  test('BudgetActivity balance computed correctly', () {
    final a = BudgetActivity(
      id: 'A1',
      wfpId: 'W1',
      name: 'Act',
      total: 1000,
      projected: 900,
      disbursed: 200,
      status: 'Ongoing',
    );
    expect(a.balance, 800);
  });

  test('toMap/fromMap and copyWith', () {
    final a = BudgetActivity(
      id: 'A2',
      wfpId: 'W2',
      name: 'Act2',
      total: 500,
      projected: 400,
      disbursed: 100,
      status: 'Completed',
      targetDate: '2025-12-31',
    );

    final map = a.toMap();
    final b = BudgetActivity.fromMap(map);
    expect(b.id, a.id);
    expect(b.targetDate, a.targetDate);

    final changed = a.copyWith(disbursed: 200);
    expect(changed.disbursed, 200);
    expect(changed.balance, 300);
  });
}
