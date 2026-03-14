import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';
import '../services/app_state.dart';
import '../services/report_exporter.dart';
import '../utils/currency_formatter.dart';

// ─── Sort options ─────────────────────────────────────────────────────────────

enum _SortField { id, title, fundType, year, amount, approvalStatus, dueDate }

extension _SortFieldLabel on _SortField {
  String get label {
    switch (this) {
      case _SortField.id:             return 'WFP ID';
      case _SortField.title:          return 'Title';
      case _SortField.fundType:       return 'Fund Type';
      case _SortField.year:           return 'Year';
      case _SortField.amount:         return 'Amount';
      case _SortField.approvalStatus: return 'Approval';
      case _SortField.dueDate:        return 'Due Date';
    }
  }

  IconData get icon {
    switch (this) {
      case _SortField.id:             return Icons.tag;
      case _SortField.title:          return Icons.sort_by_alpha;
      case _SortField.fundType:       return Icons.category_outlined;
      case _SortField.year:           return Icons.calendar_today_outlined;
      case _SortField.amount:         return Icons.attach_money;
      case _SortField.approvalStatus: return Icons.approval_outlined;
      case _SortField.dueDate:        return Icons.event_outlined;
    }
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class ReportsPage extends StatefulWidget {
  final AppState appState;

  const ReportsPage({super.key, required this.appState});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  // Selection
  WFPEntry? _selectedWFP;
  List<BudgetActivity> _activities = [];
  bool _loadingActivities = false;
  bool _exporting = false;

  // Sort
  _SortField _sortField     = _SortField.year;
  bool       _sortAscending = false; // newest first by default

  // Filter
  String _searchQuery      = '';
  String? _filterFundType;
  String? _filterApproval;
  final _searchCtrl = TextEditingController();

  // Pagination
  int _currentPage  = 0;
  int _rowsPerPage  = 10;
  static const _pageSizeOptions = [5, 10, 25, 50];

  // ─── Computed list ──────────────────────────────────────────────────────────

  List<WFPEntry> get _allEntries => widget.appState.wfpEntries.toList();

  List<WFPEntry> get _filtered {
    final q = _searchQuery.toLowerCase();
    return _allEntries.where((e) {
      final matchesSearch = q.isEmpty ||
          e.id.toLowerCase().contains(q) ||
          e.title.toLowerCase().contains(q) ||
          e.fundType.toLowerCase().contains(q) ||
          e.year.toString().contains(q) ||
          e.approvalStatus.toLowerCase().contains(q);

      final matchesFundType =
          _filterFundType == null || e.fundType == _filterFundType;

      final matchesApproval =
          _filterApproval == null || e.approvalStatus == _filterApproval;

      return matchesSearch && matchesFundType && matchesApproval;
    }).toList()
      ..sort((a, b) {
        int cmp;
        switch (_sortField) {
          case _SortField.id:
            cmp = a.id.compareTo(b.id);
            break;
          case _SortField.title:
            cmp = a.title.compareTo(b.title);
            break;
          case _SortField.fundType:
            cmp = a.fundType.compareTo(b.fundType);
            break;
          case _SortField.year:
            cmp = a.year.compareTo(b.year);
            break;
          case _SortField.amount:
            cmp = a.amount.compareTo(b.amount);
            break;
          case _SortField.approvalStatus:
            cmp = a.approvalStatus.compareTo(b.approvalStatus);
            break;
          case _SortField.dueDate:
            final ad = a.dueDate ?? '';
            final bd = b.dueDate ?? '';
            cmp = ad.compareTo(bd);
            break;
        }
        return _sortAscending ? cmp : -cmp;
      });
  }

  List<WFPEntry> get _pagedEntries {
    final all   = _filtered;
    final start = _currentPage * _rowsPerPage;
    if (start >= all.length) return [];
    return all.sublist(start, (start + _rowsPerPage).clamp(0, all.length));
  }

  int get _totalPages {
    final n = _filtered.length;
    return n == 0 ? 1 : (n / _rowsPerPage).ceil();
  }

  // Distinct fund types from the full list for the filter dropdown
  List<String> get _distinctFundTypes {
    final types = _allEntries.map((e) => e.fundType).toSet().toList()..sort();
    return types;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  void _setSortField(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField     = field;
        _sortAscending = true;
      }
      _currentPage = 0;
    });
  }

  // ─── WFP Selection ──────────────────────────────────────────────────────────

  Future<void> _selectWFP(WFPEntry entry) async {
    setState(() {
      _selectedWFP       = entry;
      _loadingActivities = true;
      _activities        = [];
    });
    final acts = await widget.appState.loadActivitiesForReport(entry.id);
    if (mounted) {
      setState(() {
        _activities        = acts;
        _loadingActivities = false;
      });
    }
  }

  void _clearSelection() => setState(() {
    _selectedWFP = null;
    _activities  = [];
  });

  // ─── Export ─────────────────────────────────────────────────────────────────

  Future<void> _export() async {
    if (_selectedWFP == null) return;
    setState(() => _exporting = true);
    try {
      final path = await ReportExporter.exportSummaryReport(
        wfp:        _selectedWFP!,
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
    final folder = path.substring(0, path.lastIndexOf('\\').clamp(0, path.length));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
    ));
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final allEntries     = _allEntries;
        final filteredList   = _filtered;
        final pagedList      = _pagedEntries;
        final totalPages     = _totalPages;
        final hasEntries     = allEntries.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Left panel: selector + controls ──────────────────────────
              SizedBox(
                width: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Title
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
                      'Select a WFP entry to preview and export',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    if (!hasEntries)
                      _emptyEntriesNotice()
                    else ...[

                      // ── Search bar ────────────────────────────────────
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: 'Search entries…',
                          isDense: true,
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _currentPage = 0;
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (v) => setState(() {
                          _searchQuery = v;
                          _currentPage = 0;
                        }),
                      ),
                      const SizedBox(height: 10),

                      // ── Filter row ────────────────────────────────────
                      Row(
                        children: [
                          // Fund Type filter
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _filterFundType,
                              decoration: const InputDecoration(
                                labelText: 'Fund Type',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('All', style: TextStyle(color: Colors.grey)),
                                ),
                                ..._distinctFundTypes.map(
                                  (f) => DropdownMenuItem(value: f, child: Text(f)),
                                ),
                              ],
                              onChanged: (v) => setState(() {
                                _filterFundType = v;
                                _currentPage    = 0;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Approval filter
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _filterApproval,
                              decoration: const InputDecoration(
                                labelText: 'Approval',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('All', style: TextStyle(color: Colors.grey)),
                                ),
                                DropdownMenuItem(value: 'Pending',  child: Text('Pending')),
                                DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                                DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                              ],
                              onChanged: (v) => setState(() {
                                _filterApproval = v;
                                _currentPage    = 0;
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── Sort chips ────────────────────────────────────
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _SortField.values.map((field) {
                            final active = _sortField == field;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                avatar: Icon(
                                  field.icon,
                                  size: 13,
                                  color: active
                                      ? Colors.white
                                      : const Color(0xff2F3E46),
                                ),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      field.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: active ? Colors.white : const Color(0xff2F3E46),
                                      ),
                                    ),
                                    if (active) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        _sortAscending
                                            ? Icons.arrow_upward
                                            : Icons.arrow_downward,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ],
                                ),
                                selected: active,
                                selectedColor: const Color(0xff2F3E46),
                                backgroundColor: Colors.grey.shade100,
                                showCheckmark: false,
                                onSelected: (_) => _setSortField(field),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Results count + rows per page ─────────────────
                      Row(
                        children: [
                          Text(
                            '${filteredList.length} result${filteredList.length == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          const Spacer(),
                          Text('Show:', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          const SizedBox(width: 6),
                          DropdownButton<int>(
                            value: _rowsPerPage,
                            isDense: true,
                            underline: const SizedBox(),
                            style: const TextStyle(fontSize: 12, color: Color(0xff2F3E46)),
                            items: _pageSizeOptions.map((n) => DropdownMenuItem(
                              value: n,
                              child: Text('$n'),
                            )).toList(),
                            onChanged: (v) => setState(() {
                              _rowsPerPage = v!;
                              _currentPage = 0;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // ── Entry list ────────────────────────────────────
                      Expanded(
                        child: filteredList.isEmpty
                            ? _noResultsNotice()
                            : Card(
                                elevation: 2,
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListView.separated(
                                    padding: EdgeInsets.zero,
                                    itemCount: pagedList.length,
                                    separatorBuilder: (context, index) =>
                                        Divider(height: 1, color: Colors.grey.shade200),
                                    itemBuilder: (context, i) {
                                      final e          = pagedList[i];
                                      final isSelected = _selectedWFP?.id == e.id;
                                      return _entryTile(e, isSelected);
                                    },
                                  ),
                                ),
                              ),
                      ),

                      // ── Pagination bar ────────────────────────────────
                      if (filteredList.isNotEmpty)
                        _PaginationBar(
                          currentPage:   _currentPage,
                          totalPages:    totalPages,
                          totalItems:    filteredList.length,
                          rowsPerPage:   _rowsPerPage,
                          onPageChanged: (p) => setState(() => _currentPage = p),
                        ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 28),

              // ── Right panel: preview ──────────────────────────────────────
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

  // ─── Entry tile ───────────────────────────────────────────────────────────

  Widget _entryTile(WFPEntry e, bool isSelected) {
    final approvalColor = e.approvalStatus == 'Approved'
        ? Colors.green.shade600
        : e.approvalStatus == 'Rejected'
            ? Colors.red.shade600
            : Colors.orange.shade600;

    return InkWell(
      onTap: () => _selectWFP(e),
      child: Container(
        color: isSelected
            ? const Color(0xff2F3E46).withValues(alpha: 0.07)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Active indicator bar
            if (isSelected)
              Container(
                width: 3, height: 38,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: const Color(0xff2F3E46),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        e.id,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('•', style: TextStyle(color: Colors.grey.shade300, fontSize: 10)),
                      const SizedBox(width: 6),
                      // Fund Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xff2F3E46).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          e.fundType,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('•', style: TextStyle(color: Colors.grey.shade300, fontSize: 10)),
                      const SizedBox(width: 6),
                      Text(
                        '${e.year}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  if (e.dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          Icon(Icons.event_outlined, size: 10, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text(
                            'Due: ${e.dueDate}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(e.amount),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: approvalColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    e.approvalStatus,
                    style: TextStyle(
                      fontSize: 9,
                      color: approvalColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Notice widgets ──────────────────────────────────────────────────────────

  Widget _emptyEntriesNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No WFP entries yet. Add entries in WFP Management first.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noResultsNotice() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(
              'No entries match your filters.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Right panel widgets ─────────────────────────────────────────────────────

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
            child: Icon(Icons.summarize_outlined, size: 52, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          Text(
            'No WFP entry selected',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
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
    final wfp            = _selectedWFP!;
    final totalAR        = _activities.fold<double>(0, (s, a) => s + a.total);
    final totalProjected = _activities.fold<double>(0, (s, a) => s + a.projected);
    final totalDisbursed = _activities.fold<double>(0, (s, a) => s + a.disbursed);
    final totalBalance   = _activities.fold<double>(0, (s, a) => s + a.balance);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar
          Row(
            children: [
              const Text(
                'Report Preview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              OutlinedButton(onPressed: _clearSelection, child: const Text('Clear')),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff2F3E46),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                icon: _exporting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: Text(_exporting ? 'Exporting…' : 'Export to Excel'),
                onPressed: _exporting ? null : _export,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Report document
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

                // Header block
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(children: [
                        _headerRow('Operating Unit:', 'Department of Education'),
                        const SizedBox(height: 8),
                        _headerRow('Program:', wfp.title),
                        const SizedBox(height: 8),
                        _headerRow('Approval:', wfp.approvalStatus),
                        if (wfp.approvedDate != null) ...[
                          const SizedBox(height: 8),
                          _headerRow('Approved On:', wfp.approvedDate!),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(children: [
                        _headerRow('Type Fund:', wfp.fundType),
                        const SizedBox(height: 8),
                        _headerRow('Title:', wfp.title),
                        const SizedBox(height: 8),
                        _headerRow('Indicator:', wfp.indicator),
                        if (wfp.dueDate != null) ...[
                          const SizedBox(height: 8),
                          _headerRow('Due Date:', wfp.dueDate!),
                        ],
                      ]),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 16),

                // Financial summary
                if (_loadingActivities)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _summaryRow('Total AR Amount:', CurrencyFormatter.format(totalAR)),
                  const SizedBox(height: 8),
                  _summaryRow('Total AR Amount (Projected / Obligated):', CurrencyFormatter.format(totalProjected)),
                  const SizedBox(height: 8),
                  _summaryRow('Total AR Disbursed:', CurrencyFormatter.format(totalDisbursed)),
                  const SizedBox(height: 8),
                  _summaryRow(
                    'Total AR Balance:',
                    CurrencyFormatter.format(totalBalance),
                    valueColor: totalBalance >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),

                  const SizedBox(height: 24),
                  Divider(color: Colors.grey.shade300),
                  const SizedBox(height: 16),

                  // Activities label
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
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
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
                        7: FlexColumnWidth(1.8),
                      },
                      children: [
                        // Header
                        TableRow(
                          decoration: const BoxDecoration(color: Color(0xff2F3E46)),
                          children: [
                            'Activity ID', 'Activity Name', 'Total AR (₱)',
                            'Projected (₱)', 'Disbursed (₱)', 'Balance (₱)',
                            'Status', 'Target Date',
                          ].map((h) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                            child: Text(
                              h,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          )).toList(),
                        ),
                        // Data rows
                        ..._activities.asMap().entries.map((entry) {
                          final i = entry.key;
                          final a = entry.value;
                          return TableRow(
                            decoration: BoxDecoration(
                              color: i.isEven ? Colors.white : Colors.grey.shade50,
                            ),
                            children: [
                              a.id,
                              a.name,
                              CurrencyFormatter.format(a.total),
                              CurrencyFormatter.format(a.projected),
                              CurrencyFormatter.format(a.disbursed),
                              CurrencyFormatter.format(a.balance),
                              a.status,
                              a.targetDate ?? '—',
                            ].map((v) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Text(v, style: const TextStyle(fontSize: 10)),
                            )).toList(),
                          );
                        }),
                        // Totals
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey.shade100),
                          children: [
                            'TOTAL', '',
                            CurrencyFormatter.format(totalAR),
                            CurrencyFormatter.format(totalProjected),
                            CurrencyFormatter.format(totalDisbursed),
                            CurrencyFormatter.format(totalBalance),
                            '', '',
                          ].map((v) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                            child: Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                          )).toList(),
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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700),
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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
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

// ─── Pagination Bar ───────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int rowsPerPage;
  final void Function(int) onPageChanged;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.rowsPerPage,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final start = totalItems == 0 ? 0 : currentPage * rowsPerPage + 1;
    final end   = ((currentPage + 1) * rowsPerPage).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$start–$end of $totalItems',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
          ),
          ...List.generate(totalPages, (i) => i)
              .where((i) => i == 0 || i == totalPages - 1 || (i - currentPage).abs() <= 1)
              .fold<List<Widget>>([], (acc, i) {
                if (acc.isNotEmpty) {
                  final prev = acc.last is _PageChip
                      ? (_lastChipPage(acc))
                      : -999;
                  if (i - prev > 1) {
                    acc.add(
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text('…', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ),
                    );
                  }
                }
                acc.add(_PageChip(
                  page: i,
                  isActive: i == currentPage,
                  onTap: () => onPageChanged(i),
                ));
                return acc;
              }),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: currentPage < totalPages - 1 ? () => onPageChanged(currentPage + 1) : null,
          ),
        ],
      ),
    );
  }

  int _lastChipPage(List<Widget> acc) {
    for (int i = acc.length - 1; i >= 0; i--) {
      if (acc[i] is _PageChip) return (acc[i] as _PageChip).page;
    }
    return -999;
  }
}

class _PageChip extends StatelessWidget {
  final int page;
  final bool isActive;
  final VoidCallback onTap;

  const _PageChip({required this.page, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xff2F3E46) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive ? const Color(0xff2F3E46) : Colors.grey.shade300,
            ),
          ),
          child: Text(
            '${page + 1}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}