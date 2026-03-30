import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/bulk_import_service.dart';
import '../theme/app_theme.dart';

class ImportPreviewDialog extends StatefulWidget {
  final BulkImportPreview preview;
  final Future<bool> Function() onImport;

  const ImportPreviewDialog({
    super.key,
    required this.preview,
    required this.onImport,
  });

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  bool _importing = false;

  Future<void> _handleImport() async {
    setState(() => _importing = true);
    final ok = await widget.onImport();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _importing = false);
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final issues = preview.issues.take(12).toList(growable: false);
    final rows = preview.previewRows.take(10).toList(growable: false);

    return AlertDialog(
      title: const Text('Bulk Import Preview'),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.basename(preview.sourcePath),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This import will create ${preview.wfps.length} WFP entr${preview.wfps.length == 1 ? 'y' : 'ies'} '
                'and ${preview.activities.length} activit${preview.activities.length == 1 ? 'y' : 'ies'}. '
                'A rollback snapshot is created before any changes are applied.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _summaryTile(
                    'WFP rows',
                    '${preview.wfps.length}',
                    AppColors.primary,
                  ),
                  _summaryTile(
                    'Activity rows',
                    '${preview.activities.length}',
                    AppColors.info,
                  ),
                  _summaryTile(
                    'Errors',
                    '${preview.errorCount}',
                    AppColors.danger,
                  ),
                  _summaryTile(
                    'Warnings',
                    '${preview.warningCount}',
                    AppColors.warning,
                  ),
                ],
              ),
              if (issues.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'Validation issues',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ...issues.map(_issueTile),
                if (preview.issues.length > issues.length) ...[
                  const SizedBox(height: 6),
                  Text(
                    '+ ${preview.issues.length - issues.length} more issue(s)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'Row preview',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ...rows.map(_rowTile),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: preview.canImport && !_importing ? _handleImport : null,
          icon: _importing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.file_upload_outlined),
          label: Text(_importing ? 'Importing...' : 'Import workbook'),
        ),
      ],
    );
  }

  Widget _summaryTile(String label, String value, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tint(color, 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _issueTile(BulkImportIssue issue) {
    final color = issue.isError ? AppColors.danger : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.tint(color, 0.24)),
      ),
      child: Text(
        '${issue.sheetName} row ${issue.rowNumber}: ${issue.message}',
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }

  Widget _rowTile(BulkImportRowPreview row) {
    final previewText = row.values.entries
        .take(4)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('  |  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '${row.sheetName} row ${row.rowNumber}: $previewText',
        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      ),
    );
  }
}
