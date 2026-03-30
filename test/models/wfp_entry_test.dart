import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/models/wfp_entry.dart';

void main() {
  test('WFPEntry toMap and fromMap roundtrip', () {
    final e = WFPEntry(
      id: 'WFP-2025-0001',
      title: 'Project A',
      targetSize: '100',
      indicator: 'Indicator',
      year: 2025,
      fundType: 'GAA',
      amount: 1234.5,
      approvalStatus: 'Pending',
    );

    final map = e.toMap();
    final from = WFPEntry.fromMap(map);
    expect(from.id, e.id);
    expect(from.title, e.title);
    expect(from.amount, e.amount);
  });

  test('isApproved and copyWith behave correctly', () {
    final e = WFPEntry(
      id: 'W1',
      title: 'T',
      targetSize: 't',
      indicator: 'i',
      year: 2024,
      fundType: 'X',
      amount: 0,
      approvalStatus: 'Approved',
    );
    expect(e.isApproved, isTrue);

    final changed = e.copyWith(approvalStatus: 'Pending', clearApprovedDate: true);
    expect(changed.isApproved, isFalse);
  });
}
