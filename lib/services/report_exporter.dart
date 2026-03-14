import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';

/// Generates and saves a Summary Report .xlsx file for a given WFP entry
/// and its associated budget activities.
class ReportExporter {
  ReportExporter._();

  /// Exports the summary report and returns the saved file path.
  /// Throws on failure.
  static Future<String> exportSummaryReport({
    required WFPEntry wfp,
    required List<BudgetActivity> activities,
  }) async {
    final excel = Excel.createExcel();

    // Remove default sheet, create ours
    excel.rename('Sheet1', 'Summary Report');
    final sheet = excel['Summary Report'];

    // ── Styles ────────────────────────────────────────────────────────────────

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 14,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#2F3E46'),
      horizontalAlign: HorizontalAlign.Center,
    );

    final headerLabelStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#2F3E46'),
      backgroundColorHex: ExcelColor.fromHexString('#E8EEF2'),
    );

    final headerValueStyle = CellStyle(
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );

    final sectionHeaderStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#3A7CA5'),
    );

    final colHeaderStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#2F3E46'),
      horizontalAlign: HorizontalAlign.Center,
    );

    final dataStyle = CellStyle(fontSize: 10);

    final currencyStyle = CellStyle(
      fontSize: 10,
      numberFormat: NumFormat.custom(formatCode: '₱#,##0.00'),
    );

    final totalLabelStyle = CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#E8EEF2'),
    );

    final totalCurrencyStyle = CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#E8EEF2'),
      numberFormat: NumFormat.custom(formatCode: '₱#,##0.00'),
    );

    // ── Helper: set cell with style ───────────────────────────────────────────

    void setCell(int row, int col, dynamic value, CellStyle style) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: col,
        rowIndex: row,
      ));
      if (value is double) {
        cell.value = DoubleCellValue(value);
      } else if (value is int) {
        cell.value = IntCellValue(value);
      } else {
        cell.value = TextCellValue(value?.toString() ?? '');
      }
      cell.cellStyle = style;
    }

    void setFormula(int row, int col, String formula, CellStyle style) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: col,
        rowIndex: row,
      ));
      cell.value = FormulaCellValue(formula);
      cell.cellStyle = style;
    }

    // ── Column widths ─────────────────────────────────────────────────────────
    sheet.setColumnWidth(0, 28); // Activity ID
    sheet.setColumnWidth(1, 36); // Activity Name
    sheet.setColumnWidth(2, 20); // Total AR
    sheet.setColumnWidth(3, 22); // Projected
    sheet.setColumnWidth(4, 20); // Disbursed
    sheet.setColumnWidth(5, 20); // Balance
    sheet.setColumnWidth(6, 16); // Status

    // ── Row 0: Report Title ───────────────────────────────────────────────────
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0),
    );
    setCell(0, 0, 'SUMMARY REPORT', titleStyle);
    sheet.setRowHeight(0, 28);

    // ── Row 1: blank spacer
    sheet.setRowHeight(1, 6);

    // ── Rows 2-5: WFP Header block ────────────────────────────────────────────
    // Row 2: Operating Unit | Fund Type
    setCell(2, 0, 'Operating Unit:', headerLabelStyle);
    setCell(2, 1, 'Department of Education', headerValueStyle);
    setCell(2, 3, 'Type Fund:', headerLabelStyle);
    setCell(2, 4, wfp.fundType, headerValueStyle);

    // Row 3: Program | Title
    setCell(3, 0, 'Program:', headerLabelStyle);
    setCell(3, 1, wfp.title, headerValueStyle);
    setCell(3, 3, 'Title:', headerLabelStyle);
    setCell(3, 4, wfp.title, headerValueStyle);

    // Row 4: blank left | Indicator
    setCell(4, 3, 'Indicator:', headerLabelStyle);
    // Merge cols 4-6 for indicator value
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 4),
    );
    setCell(4, 4, wfp.indicator, headerValueStyle);

    // ── Row 5: blank spacer
    sheet.setRowHeight(5, 6);

    // ── Rows 6-9: Financial Summary block ─────────────────────────────────────
    // Activities are written at 0-indexed rows 13, 14, 15...
    // Excel is 1-indexed, so 0-indexed row 13 = Excel row 14.
    final dataStartRow  = 14; // 1-indexed Excel row where activity data begins
    final dataEndRow    = dataStartRow + activities.length - 1;
    const totalArCol    = 'C';
    const projectedCol  = 'D';
    const disbursedCol  = 'E';
    const balanceCol    = 'F';

    // Pre-compute real totals so the summary always shows correct values
    // even if the host app doesn't auto-calculate formulas on open.
    final realTotalAR        = activities.fold<double>(0, (s, a) => s + a.total);
    final realTotalProjected = activities.fold<double>(0, (s, a) => s + a.projected);
    final realTotalDisbursed = activities.fold<double>(0, (s, a) => s + a.disbursed);
    final realTotalBalance   = activities.fold<double>(0, (s, a) => s + a.balance);

    setCell(6, 0, 'Total AR Amount:', headerLabelStyle);
    setCell(6, 2, realTotalAR, totalCurrencyStyle);
    if (activities.isNotEmpty) {
      setFormula(6, 2,
          'SUM(${totalArCol}${dataStartRow}:${totalArCol}${dataEndRow})',
          totalCurrencyStyle);
    }

    setCell(7, 0, 'Total AR Amount (Projected / Obligated):', headerLabelStyle);
    setCell(7, 2, realTotalProjected, totalCurrencyStyle);
    if (activities.isNotEmpty) {
      setFormula(7, 2,
          'SUM(${projectedCol}${dataStartRow}:${projectedCol}${dataEndRow})',
          totalCurrencyStyle);
    }

    setCell(8, 0, 'Total AR Disbursed:', headerLabelStyle);
    setCell(8, 2, realTotalDisbursed, totalCurrencyStyle);
    if (activities.isNotEmpty) {
      setFormula(8, 2,
          'SUM(${disbursedCol}${dataStartRow}:${disbursedCol}${dataEndRow})',
          totalCurrencyStyle);
    }

    setCell(9, 0, 'Total AR Balance:', headerLabelStyle);
    setCell(9, 2, realTotalBalance, totalCurrencyStyle);
    if (activities.isNotEmpty) {
      setFormula(9, 2,
          'SUM(${balanceCol}${dataStartRow}:${balanceCol}${dataEndRow})',
          totalCurrencyStyle);
    }

    // ── Row 10: blank spacer
    sheet.setRowHeight(10, 6);

    // ── Row 11: Activities section header ─────────────────────────────────────
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 11),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 11),
    );
    setCell(11, 0, 'BUDGET ACTIVITIES', sectionHeaderStyle);

    // ── Row 12: Column headers (0-indexed = row 12) ───────────────────────────
    const colHeaders = [
      'Activity ID',
      'Activity Name',
      'Total AR Amount (₱)',
      'Projected / Obligated (₱)',
      'Disbursed Amount (₱)',
      'Balance (₱)',
      'Status',
    ];
    for (var i = 0; i < colHeaders.length; i++) {
      setCell(12, i, colHeaders[i], colHeaderStyle);
    }

    // ── Rows 13+: Activity data ───────────────────────────────────────────────
    for (var i = 0; i < activities.length; i++) {
      final a = activities[i];
      final row = 13 + i; // 0-indexed
      setCell(row, 0, a.id, dataStyle);
      setCell(row, 1, a.name, dataStyle);
      setCell(row, 2, a.total, currencyStyle);
      setCell(row, 3, a.projected, currencyStyle);
      setCell(row, 4, a.disbursed, currencyStyle);
      // Balance = Total - Disbursed as formula
      final excelRow = row + 1; // 1-indexed
      setFormula(row, 5, '${totalArCol}${excelRow}-${disbursedCol}${excelRow}',
          currencyStyle);
      setCell(row, 6, a.status, dataStyle);
    }

    // ── Totals row ────────────────────────────────────────────────────────────
    if (activities.isNotEmpty) {
      final totalsRow = 13 + activities.length; // 0-indexed
      setCell(totalsRow, 0, 'TOTAL', totalLabelStyle);
      setCell(totalsRow, 1, '', totalLabelStyle);
      // Write real values first so Excel shows them without needing recalculation
      setCell(totalsRow, 2, realTotalAR,        totalCurrencyStyle);
      setCell(totalsRow, 3, realTotalProjected, totalCurrencyStyle);
      setCell(totalsRow, 4, realTotalDisbursed, totalCurrencyStyle);
      setCell(totalsRow, 5, realTotalBalance,   totalCurrencyStyle);
      // Then overwrite with SUM formulas so editing individual cells auto-updates
      setFormula(totalsRow, 2,
          'SUM(${totalArCol}${dataStartRow}:${totalArCol}${dataEndRow})',
          totalCurrencyStyle);
      setFormula(totalsRow, 3,
          'SUM(${projectedCol}${dataStartRow}:${projectedCol}${dataEndRow})',
          totalCurrencyStyle);
      setFormula(totalsRow, 4,
          'SUM(${disbursedCol}${dataStartRow}:${disbursedCol}${dataEndRow})',
          totalCurrencyStyle);
      setFormula(totalsRow, 5,
          'SUM(${balanceCol}${dataStartRow}:${balanceCol}${dataEndRow})',
          totalCurrencyStyle);
      setCell(totalsRow, 6, '', totalLabelStyle);
    }

    // ── Save file ─────────────────────────────────────────────────────────────
    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = wfp.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .substring(0, wfp.title.length.clamp(0, 40));
    final fileName = 'SummaryReport_${wfp.id}_$safeTitle.xlsx';
    final filePath = p.join(dir.path, fileName);

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file.');
    await File(filePath).writeAsBytes(bytes);

    return filePath;
  }
}