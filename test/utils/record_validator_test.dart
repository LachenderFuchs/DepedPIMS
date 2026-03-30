import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/models/budget_activity.dart';
import 'package:pmis_deped/models/wfp_entry.dart';
import 'package:pmis_deped/utils/record_validator.dart';

void main() {
  group('RecordValidator.validateWfp', () {
    test('flags duplicate WFP signatures within the same year and section', () {
      final existing = [
        const WFPEntry(
          id: 'WFP-2026-0001',
          title: 'Teacher Training',
          targetSize: '50',
          indicator: 'Sessions',
          year: 2026,
          fundType: 'MODE',
          viewSection: 'HRD',
          amount: 1000,
        ),
      ];

      final error = RecordValidator.validateWfp(
        title: '  teacher   training ',
        targetSize: '55',
        indicator: 'Updated sessions',
        amount: 1200,
        year: 2026,
        fundType: 'MODE',
        viewSection: 'HRD',
        approvalStatus: 'Pending',
        approvedDate: null,
        dueDate: '2026-07-01',
        existingEntries: existing,
      );

      expect(error, isNotNull);
    });

    test('flags due dates earlier than approved dates', () {
      final error = RecordValidator.validateWfp(
        title: 'Reading Program',
        targetSize: '20',
        indicator: 'Learners',
        amount: 500,
        year: 2026,
        fundType: 'GASS',
        viewSection: 'PRS',
        approvalStatus: 'Approved',
        approvedDate: '2026-06-10',
        dueDate: '2026-06-09',
        existingEntries: const [],
      );

      expect(error, 'Due date cannot be earlier than the approved date.');
    });
  });

  group('RecordValidator.validateActivity', () {
    const selectedWfp = WFPEntry(
      id: 'WFP-2026-0009',
      title: 'Nutrition Drive',
      targetSize: '100',
      indicator: 'Beneficiaries',
      year: 2026,
      fundType: 'SBFP',
      viewSection: 'SHNS',
      amount: 1000,
      approvalStatus: 'Approved',
      approvedDate: '2026-06-01',
      dueDate: '2026-07-01',
    );

    test('flags duplicate activity names inside the selected WFP', () {
      final error = RecordValidator.validateActivity(
        selectedWFP: selectedWfp,
        name: ' feeding  kickoff ',
        total: 100,
        projected: 80,
        disbursed: 10,
        targetDate: '2026-06-15',
        existingActivities: const [
          BudgetActivity(
            id: 'ACT-1',
            wfpId: 'WFP-2026-0009',
            name: 'Feeding Kickoff',
            total: 90,
            projected: 60,
            disbursed: 5,
            status: 'Ongoing',
          ),
        ],
      );

      expect(
        error,
        'An activity with this name already exists for the selected WFP.',
      );
    });

    test('flags target dates beyond the parent WFP due date', () {
      final error = RecordValidator.validateActivity(
        selectedWFP: selectedWfp,
        name: 'Closeout',
        total: 100,
        projected: 80,
        disbursed: 10,
        targetDate: '2026-07-02',
        existingActivities: const [],
      );

      expect(error, 'Target date cannot be later than the WFP due date.');
    });
  });
}
