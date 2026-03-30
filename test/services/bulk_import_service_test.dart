import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/services/app_state.dart';
import 'package:pmis_deped/services/bulk_import_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pmis_import_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('previewFromFile parses valid workbook rows', () async {
    final file = await _writeWorkbook(
      tempDir.path,
      wfpRows: const [
        [
          'WFP-2026-0001',
          'Training Program',
          '50',
          'Capacity building',
          '2026',
          'MODE',
          'HRD',
          '125000',
          'Approved',
          '2026-04-01',
          '2026-04-20',
        ],
      ],
      activityRows: const [
        [
          'ACT-2026-0001',
          'WFP-2026-0001',
          'Venue booking',
          '40000',
          '25000',
          '10000',
          'Ongoing',
          '2026-04-10',
        ],
      ],
    );

    final preview = await BulkImportService.previewFromFile(
      sourcePath: file.path,
      appState: AppState(),
    );

    expect(preview.canImport, isTrue);
    expect(preview.errorCount, 0);
    expect(preview.wfps, hasLength(1));
    expect(preview.activities, hasLength(1));
  });

  test('previewFromFile reports missing parent WFP errors', () async {
    final file = await _writeWorkbook(
      tempDir.path,
      wfpRows: const [],
      activityRows: const [
        [
          'ACT-2026-0002',
          'WFP-MISSING-0001',
          'Hotel booking',
          '40000',
          '25000',
          '10000',
          'Ongoing',
          '2026-04-10',
        ],
      ],
    );

    final preview = await BulkImportService.previewFromFile(
      sourcePath: file.path,
      appState: AppState(),
    );

    expect(preview.canImport, isFalse);
    expect(preview.errorCount, greaterThan(0));
    expect(
      preview.issues.any((issue) => issue.message.contains('was not found')),
      isTrue,
    );
  });
}

Future<File> _writeWorkbook(
  String directoryPath, {
  required List<List<String>> wfpRows,
  required List<List<String>> activityRows,
}) async {
  final workbook = Excel.createExcel();
  workbook.rename('Sheet1', BulkImportService.wfpSheetName);
  final wfpSheet = workbook[BulkImportService.wfpSheetName];
  final activitySheet = workbook[BulkImportService.activitiesSheetName];

  _appendRow(wfpSheet, const [
    'WFP ID',
    'Title',
    'Target Size',
    'Indicator',
    'Year',
    'Fund Type',
    'Section',
    'Amount',
    'Approval Status',
    'Approved Date',
    'Due Date',
  ]);
  for (final row in wfpRows) {
    _appendRow(wfpSheet, row);
  }

  _appendRow(activitySheet, const [
    'Activity ID',
    'Parent WFP ID',
    'Name',
    'Total AR',
    'Projected / Obligated',
    'Disbursed',
    'Status',
    'Target Date',
  ]);
  for (final row in activityRows) {
    _appendRow(activitySheet, row);
  }

  final output = File(p.join(directoryPath, 'bulk_import_test.xlsx'));
  await output.writeAsBytes(workbook.encode()!, flush: true);
  return output;
}

void _appendRow(Sheet sheet, List<String> values) {
  sheet.appendRow(values.map(TextCellValue.new).toList(growable: false));
}
