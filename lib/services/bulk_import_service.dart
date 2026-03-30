import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../models/budget_activity.dart';
import '../models/wfp_entry.dart';
import '../utils/record_validator.dart';
import 'app_state.dart';

class BulkImportIssue {
  final String sheetName;
  final int rowNumber;
  final String message;
  final bool isError;

  const BulkImportIssue({
    required this.sheetName,
    required this.rowNumber,
    required this.message,
    required this.isError,
  });
}

class BulkImportRowPreview {
  final String sheetName;
  final int rowNumber;
  final Map<String, String> values;

  const BulkImportRowPreview({
    required this.sheetName,
    required this.rowNumber,
    required this.values,
  });
}

class BulkImportPreview {
  final String sourcePath;
  final List<WFPEntry> wfps;
  final List<BudgetActivity> activities;
  final List<BulkImportIssue> issues;
  final List<BulkImportRowPreview> previewRows;

  const BulkImportPreview({
    required this.sourcePath,
    required this.wfps,
    required this.activities,
    required this.issues,
    required this.previewRows,
  });

  int get errorCount => issues.where((issue) => issue.isError).length;
  int get warningCount => issues.where((issue) => !issue.isError).length;
  bool get canImport =>
      errorCount == 0 && (wfps.isNotEmpty || activities.isNotEmpty);
}

class BulkImportService {
  static const wfpSheetName = 'WFP';
  static const activitiesSheetName = 'Activities';

  static const _wfpHeaderAliases = <String, String>{
    'wfp id': 'id',
    'id': 'id',
    'title': 'title',
    'program title': 'title',
    'target size': 'targetSize',
    'indicator': 'indicator',
    'details': 'indicator',
    'year': 'year',
    'fund type': 'fundType',
    'fund': 'fundType',
    'section': 'viewSection',
    'view section': 'viewSection',
    'amount': 'amount',
    'approval status': 'approvalStatus',
    'approved date': 'approvedDate',
    'due date': 'dueDate',
  };

  static const _activityHeaderAliases = <String, String>{
    'activity id': 'id',
    'id': 'id',
    'parent wfp id': 'wfpId',
    'wfp id': 'wfpId',
    'parent id': 'wfpId',
    'activity name': 'name',
    'name': 'name',
    'total ar': 'total',
    'total': 'total',
    'projected': 'projected',
    'projected obligated': 'projected',
    'projected / obligated': 'projected',
    'disbursed': 'disbursed',
    'status': 'status',
    'target date': 'targetDate',
  };

  static Future<String?> saveTemplate() async {
    String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save bulk import template',
      fileName: 'PMIS_Bulk_Import_Template.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (outputPath == null) {
      return null;
    }
    if (!outputPath.toLowerCase().endsWith('.xlsx')) {
      outputPath = '$outputPath.xlsx';
    }

    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', wfpSheetName);
    final wfpSheet = workbook[wfpSheetName];
    final activitySheet = workbook[activitiesSheetName];
    final guideSheet = workbook['Instructions'];

    _appendTextRow(wfpSheet, const [
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
    _appendTextRow(wfpSheet, const [
      'WFP-2026-0001',
      'Sample Training Program',
      '50',
      'Capacity building sessions',
      '2026',
      'MODE',
      'HRD',
      '125000',
      'Approved',
      '2026-04-01',
      '2026-04-20',
    ]);

    _appendTextRow(activitySheet, const [
      'Activity ID',
      'Parent WFP ID',
      'Name',
      'Total AR',
      'Projected / Obligated',
      'Disbursed',
      'Status',
      'Target Date',
    ]);
    _appendTextRow(activitySheet, const [
      'ACT-WFP-2026-0001-01',
      'WFP-2026-0001',
      'Venue booking',
      '40000',
      '25000',
      '10000',
      'Ongoing',
      '2026-04-12',
    ]);

    _appendTextRow(guideSheet, const ['Sheet', 'Instructions']);
    _appendTextRow(guideSheet, const [
      wfpSheetName,
      'Use one row per WFP. IDs must be unique and dates should be YYYY-MM-DD.',
    ]);
    _appendTextRow(guideSheet, const [
      activitiesSheetName,
      'Use one row per activity. Parent WFP ID must already exist in the workbook or live data.',
    ]);

    final bytes = workbook.encode();
    if (bytes == null) {
      throw Exception('Failed to encode bulk import template.');
    }
    await File(outputPath).writeAsBytes(bytes, flush: true);
    return outputPath;
  }

  static Future<BulkImportPreview> previewFromFile({
    required String sourcePath,
    required AppState appState,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final workbook = Excel.decodeBytes(bytes);

    final issues = <BulkImportIssue>[];
    final previewRows = <BulkImportRowPreview>[];
    final parsedWfps = <WFPEntry>[];
    final parsedActivities = <BudgetActivity>[];

    final existingWfps = appState.wfpEntries.toList(growable: false);
    final existingActivities = appState.allActivities.toList(growable: false);
    final existingWfpIds = existingWfps.map((item) => item.id).toSet();
    final existingActivityIds = existingActivities
        .map((item) => item.id)
        .toSet();
    final workbookWfpIds = <String>{};
    final workbookActivityIds = <String>{};

    final wfpSheet = workbook.tables[wfpSheetName];
    if (wfpSheet == null || wfpSheet.rows.isEmpty) {
      issues.add(
        const BulkImportIssue(
          sheetName: wfpSheetName,
          rowNumber: 1,
          message: 'Missing required WFP sheet or header row.',
          isError: true,
        ),
      );
    } else {
      final headers = _resolveHeaders(wfpSheet.rows.first, _wfpHeaderAliases);
      for (var index = 1; index < wfpSheet.rows.length; index++) {
        final row = wfpSheet.rows[index];
        final rowNumber = index + 1;
        final values = _extractRowValues(row, headers);
        if (_isEmptyRow(values)) {
          continue;
        }
        previewRows.add(
          BulkImportRowPreview(
            sheetName: wfpSheetName,
            rowNumber: rowNumber,
            values: values,
          ),
        );

        final id = values['id']?.trim() ?? '';
        if (id.isEmpty) {
          issues.add(
            BulkImportIssue(
              sheetName: wfpSheetName,
              rowNumber: rowNumber,
              message: 'WFP ID is required.',
              isError: true,
            ),
          );
          continue;
        }
        if (existingWfpIds.contains(id) || workbookWfpIds.contains(id)) {
          issues.add(
            BulkImportIssue(
              sheetName: wfpSheetName,
              rowNumber: rowNumber,
              message: 'WFP ID "$id" already exists.',
              isError: true,
            ),
          );
          continue;
        }

        final year = _tryParseInt(values['year']);
        final amount = _tryParseDouble(values['amount']);
        if (year == null || amount == null) {
          issues.add(
            BulkImportIssue(
              sheetName: wfpSheetName,
              rowNumber: rowNumber,
              message: 'Year and amount must be valid numbers.',
              isError: true,
            ),
          );
          continue;
        }

        final entry = WFPEntry(
          id: id,
          title: values['title']?.trim() ?? '',
          targetSize: values['targetSize']?.trim() ?? '',
          indicator: values['indicator']?.trim() ?? '',
          year: year,
          fundType: values['fundType']?.trim() ?? '',
          viewSection: (values['viewSection']?.trim().isEmpty ?? true)
              ? 'HRD'
              : values['viewSection']!.trim(),
          amount: amount,
          approvalStatus: (values['approvalStatus']?.trim().isEmpty ?? true)
              ? 'Pending'
              : values['approvalStatus']!.trim(),
          approvedDate: _normalizedDate(values['approvedDate']),
          dueDate: _normalizedDate(values['dueDate']),
        );

        final validation = RecordValidator.validateWfp(
          title: entry.title,
          targetSize: entry.targetSize,
          indicator: entry.indicator,
          amount: entry.amount,
          year: entry.year,
          fundType: entry.fundType,
          viewSection: entry.viewSection,
          approvalStatus: entry.approvalStatus,
          approvedDate: entry.approvedDate,
          dueDate: entry.dueDate,
          existingEntries: [...existingWfps, ...parsedWfps],
        );
        if (validation != null) {
          issues.add(
            BulkImportIssue(
              sheetName: wfpSheetName,
              rowNumber: rowNumber,
              message: validation,
              isError: true,
            ),
          );
          continue;
        }

        workbookWfpIds.add(id);
        parsedWfps.add(entry);
      }
    }

    final activitySheet = workbook.tables[activitiesSheetName];
    if (activitySheet != null && activitySheet.rows.isNotEmpty) {
      final headers = _resolveHeaders(
        activitySheet.rows.first,
        _activityHeaderAliases,
      );
      for (var index = 1; index < activitySheet.rows.length; index++) {
        final row = activitySheet.rows[index];
        final rowNumber = index + 1;
        final values = _extractRowValues(row, headers);
        if (_isEmptyRow(values)) {
          continue;
        }
        previewRows.add(
          BulkImportRowPreview(
            sheetName: activitiesSheetName,
            rowNumber: rowNumber,
            values: values,
          ),
        );

        final id = values['id']?.trim() ?? '';
        final parentId = values['wfpId']?.trim() ?? '';
        if (id.isEmpty || parentId.isEmpty) {
          issues.add(
            BulkImportIssue(
              sheetName: activitiesSheetName,
              rowNumber: rowNumber,
              message: 'Activity ID and Parent WFP ID are required.',
              isError: true,
            ),
          );
          continue;
        }
        if (existingActivityIds.contains(id) ||
            workbookActivityIds.contains(id)) {
          issues.add(
            BulkImportIssue(
              sheetName: activitiesSheetName,
              rowNumber: rowNumber,
              message: 'Activity ID "$id" already exists.',
              isError: true,
            ),
          );
          continue;
        }

        final total = _tryParseDouble(values['total']);
        final projected = _tryParseDouble(values['projected']);
        final disbursed = _tryParseDouble(values['disbursed']);
        if (total == null || projected == null || disbursed == null) {
          issues.add(
            BulkImportIssue(
              sheetName: activitiesSheetName,
              rowNumber: rowNumber,
              message:
                  'Total AR, projected/obligated, and disbursed must be valid numbers.',
              isError: true,
            ),
          );
          continue;
        }

        WFPEntry? parent;
        for (final entry in parsedWfps) {
          if (entry.id == parentId) {
            parent = entry;
            break;
          }
        }
        parent ??= _firstWhereOrNull(
          existingWfps,
          (entry) => entry.id == parentId,
        );
        if (parent == null) {
          issues.add(
            BulkImportIssue(
              sheetName: activitiesSheetName,
              rowNumber: rowNumber,
              message: 'Parent WFP "$parentId" was not found.',
              isError: true,
            ),
          );
          continue;
        }

        final activity = BudgetActivity(
          id: id,
          wfpId: parentId,
          name: values['name']?.trim() ?? '',
          total: total,
          projected: projected,
          disbursed: disbursed,
          status: (values['status']?.trim().isEmpty ?? true)
              ? 'Not Started'
              : values['status']!.trim(),
          targetDate: _normalizedDate(values['targetDate']),
        );

        final sameParentExisting = existingActivities
            .where((item) => item.wfpId == parentId)
            .toList(growable: false);
        final sameParentParsed = parsedActivities
            .where((item) => item.wfpId == parentId)
            .toList(growable: false);
        final validation = RecordValidator.validateActivity(
          selectedWFP: parent,
          name: activity.name,
          total: activity.total,
          projected: activity.projected,
          disbursed: activity.disbursed,
          targetDate: activity.targetDate,
          existingActivities: [...sameParentExisting, ...sameParentParsed],
        );
        if (validation != null) {
          issues.add(
            BulkImportIssue(
              sheetName: activitiesSheetName,
              rowNumber: rowNumber,
              message: validation,
              isError: true,
            ),
          );
          continue;
        }

        workbookActivityIds.add(id);
        parsedActivities.add(activity);
      }
    }

    return BulkImportPreview(
      sourcePath: sourcePath,
      wfps: parsedWfps,
      activities: parsedActivities,
      issues: issues,
      previewRows: previewRows,
    );
  }

  static Map<int, String> _resolveHeaders(
    List<Data?> headerRow,
    Map<String, String> aliases,
  ) {
    final headers = <int, String>{};
    for (var index = 0; index < headerRow.length; index++) {
      final cellText = _normalizeHeader(_cellToString(headerRow[index]));
      final canonical = aliases[cellText];
      if (canonical != null) {
        headers[index] = canonical;
      }
    }
    return headers;
  }

  static Map<String, String> _extractRowValues(
    List<Data?> row,
    Map<int, String> headers,
  ) {
    final values = <String, String>{};
    headers.forEach((columnIndex, key) {
      if (columnIndex < row.length) {
        values[key] = _cellToString(row[columnIndex]).trim();
      }
    });
    return values;
  }

  static bool _isEmptyRow(Map<String, String> values) {
    return values.values.every((value) => value.trim().isEmpty);
  }

  static String _normalizeHeader(String value) {
    return value
        .toLowerCase()
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cellToString(Data? cell) {
    final value = cell?.value;
    switch (value) {
      case null:
        return '';
      case TextCellValue():
        return value.value.toString();
      case IntCellValue():
        return value.value.toString();
      case DoubleCellValue():
        return value.value.toString();
      case BoolCellValue():
        return value.value ? 'true' : 'false';
      case DateCellValue():
        return _formatDateParts(value.year, value.month, value.day);
      case DateTimeCellValue():
        return _formatDateParts(value.year, value.month, value.day);
      case TimeCellValue():
        return '${value.hour}:${value.minute}:${value.second}';
      case FormulaCellValue():
        return value.formula.toString();
    }
  }

  static String? _normalizedDate(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text;
    }
    return _formatDateParts(parsed.year, parsed.month, parsed.day);
  }

  static String _formatDateParts(int year, int month, int day) {
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  static int? _tryParseInt(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return int.tryParse(text) ?? double.tryParse(text)?.round();
  }

  static double? _tryParseDouble(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text.replaceAll(',', ''));
  }

  static void _appendTextRow(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map(TextCellValue.new).toList(growable: false));
  }

  static T? _firstWhereOrNull<T>(
    Iterable<T> values,
    bool Function(T value) test,
  ) {
    for (final value in values) {
      if (test(value)) {
        return value;
      }
    }
    return null;
  }
}
