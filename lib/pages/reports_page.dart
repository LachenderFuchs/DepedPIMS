import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';
import '../services/app_state.dart';
import '../services/report_exporter.dart';
import '../utils/currency_formatter.dart';

class ReportsPage extends StatefulWidget {
  final AppState appState;

  const ReportsPage({super.key, required this.appState});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  WFPEntry? _selectedWFP;
  List<BudgetActivity> _activities = [];
  bool _loadingActivities = false;
  bool _exporting = false;

  // ─── WFP Selection ────────────────────────────────────────────────────────

  Future<void> _selectWFP(WFPEntry entry) async {
    setState(() {
      _selectedWFP = entry;
      _loadingActivities = true;
      _activities = [];
    });
    // Load activities for preview
    final acts = await widget.appState.loadActivitiesForReport(entry.id);
    setState(() {
      _activities = acts;
      _loadingActivities = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedWFP = null;
      _activities = [];
    });
  }

  // ─── Export ───────────────────────────────────────────────────────────────

  Future<void> _export() async {
    if (_selectedWFP == null) return;
    setState(() => _exporting = true);
    try {
      final path = await ReportExporter.exportSummaryReport(
        wfp: _selectedWFP!,
        activities: _activities,
      );
      if (!mounted) return;
      _showResultDialog(path);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showResultDialog(String path) {
    final folder = path.substring(
      0,
      path.lastIndexOf('\\').clamp(0, path.length),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 10),
            Text('Report Exported'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your summary report has been saved to:'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                path,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff2F3E46),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Open Folder'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final uri = Uri.file(folder);
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final entries = widget.appState.wfpEntries;

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left: WFP selector list ─────────────────────────────────
              SizedBox(
                width: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reports',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff2F3E46),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select a WFP entry to generate a report',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (entries.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No WFP entries yet. Add entries in WFP Management first.',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Expanded(
                        child: Card(
                          elevation: 2,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: entries.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: Colors.grey.shade200,
                              ),
                              itemBuilder: (_, i) {
                                final e = entries[i];
                                final isSelected = _selectedWFP?.id == e.id;
                                return InkWell(
                                  onTap: () => _selectWFP(e),
                                  child: Container(
                                    color: isSelected
                                        ? const Color(
                                            0xff2F3E46,
                                          ).withValues(alpha: 0.07)
                                        : null,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    child: Row(
                                      children: [
                                        if (isSelected)
                                          Container(
                                            width: 3,
                                            height: 36,
                                            margin: const EdgeInsets.only(
                                              right: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xff2F3E46),
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                e.title,
                                                style: TextStyle(
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.w500,
                                                  fontSize: 13,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${e.id}  •  ${e.fundType}  •  ${e.year}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          CurrencyFormatter.format(e.amount),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 28),

              // ── Right: Report preview + export ──────────────────────────
              Expanded(
                child: _selectedWFP == null
                    ? _buildEmptyState()
                    : _buildReportPreview(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.summarize_outlined,
              size: 52,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No WFP entry selected',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a WFP entry from the list to preview and export its summary report.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildReportPreview() {
    final wfp = _selectedWFP!;

    // Aggregated totals from loaded activities
    final totalAR = _activities.fold<double>(0, (s, a) => s + a.total);
    final totalProjected = _activities.fold<double>(
      0,
      (s, a) => s + a.projected,
    );
    final totalDisbursed = _activities.fold<double>(
      0,
      (s, a) => s + a.disbursed,
    );
    final totalBalance = _activities.fold<double>(0, (s, a) => s + a.balance);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Preview header bar ──────────────────────────────────────
          Row(
            children: [
              const Text(
                'Report Preview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _clearSelection,
                child: const Text('Clear'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff2F3E46),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: Text(_exporting ? 'Exporting…' : 'Export to Excel'),
                onPressed: _exporting ? null : _export,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Report document preview ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade100,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Center(
                  child: Text(
                    'SUMMARY REPORT',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xff2F3E46),
                      letterSpacing: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 16),

                // Header block — 2 column layout
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _headerRow(
                            'Operating Unit:',
                            'Department of Education',
                          ),
                          const SizedBox(height: 8),
                          _headerRow('Program:', wfp.title),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        children: [
                          _headerRow('Type Fund:', wfp.fundType),
                          const SizedBox(height: 8),
                          _headerRow('Title:', wfp.title),
                          const SizedBox(height: 8),
                          _headerRow('Indicator:', wfp.indicator),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 16),

                // Financial summary block
                if (_loadingActivities)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _summaryRow(
                    'Total AR Amount:',
                    CurrencyFormatter.format(totalAR),
                  ),
                  const SizedBox(height: 8),
                  _summaryRow(
                    'Total AR Amount (Projected / Obligated):',
                    CurrencyFormatter.format(totalProjected),
                  ),
                  const SizedBox(height: 8),
                  _summaryRow(
                    'Total AR Disbursed:',
                    CurrencyFormatter.format(totalDisbursed),
                  ),
                  const SizedBox(height: 8),
                  _summaryRow(
                    'Total AR Balance:',
                    CurrencyFormatter.format(totalBalance),
                    valueColor: totalBalance >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),

                  const SizedBox(height: 24),
                  Divider(color: Colors.grey.shade300),
                  const SizedBox(height: 16),

                  // Activities table
                  Text(
                    'BUDGET ACTIVITIES',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: const Color(0xff2F3E46),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (_activities.isEmpty)
                    Text(
                      'No activities linked to this WFP entry.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    )
                  else
                    Table(
                      border: TableBorder.all(color: Colors.grey.shade200),
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(3),
                        2: FlexColumnWidth(2),
                        3: FlexColumnWidth(2),
                        4: FlexColumnWidth(2),
                        5: FlexColumnWidth(2),
                        6: FlexColumnWidth(1.5),
                      },
                      children: [
                        // Header row
                        TableRow(
                          decoration: const BoxDecoration(
                            color: Color(0xff2F3E46),
                          ),
                          children:
                              [
                                    'Activity ID',
                                    'Activity Name',
                                    'Total AR (₱)',
                                    'Projected (₱)',
                                    'Disbursed (₱)',
                                    'Balance (₱)',
                                    'Status',
                                  ]
                                  .map(
                                    (h) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 7,
                                      ),
                                      child: Text(
                                        h,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                        // Data rows
                        ..._activities.asMap().entries.map((entry) {
                          final i = entry.key;
                          final a = entry.value;
                          return TableRow(
                            decoration: BoxDecoration(
                              color: i.isEven
                                  ? Colors.white
                                  : Colors.grey.shade50,
                            ),
                            children:
                                [
                                      a.id,
                                      a.name,
                                      CurrencyFormatter.format(a.total),
                                      CurrencyFormatter.format(a.projected),
                                      CurrencyFormatter.format(a.disbursed),
                                      CurrencyFormatter.format(a.balance),
                                      a.status,
                                    ]
                                    .map(
                                      (v) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        child: Text(
                                          v,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          );
                        }),
                        // Totals row
                        TableRow(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                          ),
                          children:
                              [
                                    'TOTAL',
                                    '',
                                    CurrencyFormatter.format(totalAR),
                                    CurrencyFormatter.format(totalProjected),
                                    CurrencyFormatter.format(totalDisbursed),
                                    CurrencyFormatter.format(totalBalance),
                                    '',
                                  ]
                                  .map(
                                    (v) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 7,
                                      ),
                                      child: Text(
                                        v,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor ?? const Color(0xff2F3E46),
          ),
        ),
      ],
    );
  }
}
