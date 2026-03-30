import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import '../models/budget_activity.dart';
import '../models/wfp_entry.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/decimal_input_formatter.dart';
import '../utils/record_validator.dart';
import '../widgets/pagination_bar.dart';

class _TableHeaderText extends StatelessWidget {
  final String text;

  const _TableHeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }
}

class BudgetOverviewPage extends StatefulWidget {
  final AppState appState;
  const BudgetOverviewPage({super.key, required this.appState});
  @override
  State<BudgetOverviewPage> createState() => BudgetOverviewPageState();
}

class BudgetOverviewPageState extends State<BudgetOverviewPage> {
  final _activityName = TextEditingController();
  final _total = TextEditingController();
  final _projected = TextEditingController();
  final _disbursed = TextEditingController();
  final _activitySearch = TextEditingController();
  final _wfpSearch = TextEditingController();

  String _status = 'Not Started';
  String? _suggestedStatus;
  String? _targetDate;
  BudgetActivity? _editingActivity;

  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  int _currentPage = 0;
  int _rowsPerPage = 10;
  static const _rowsPerPageOptions = [10, 25, 50, 100];

  int _wfpSortCol = 0;
  bool _wfpSortAsc = true;

  final _scrollController = ScrollController();
  final _activitySectionKey = GlobalKey();

  static const _statusOptions = [
    'Not Started',
    'Ongoing',
    'Completed',
    'At Risk',
  ];
  static const double _compactChipMaxWidth = 96.0;
  static const double _dateCellMaxWidth = 122.0;
  static const double _activityTableHeight = 420.0;
  static const double _tableMinWidth = 900.0;

  // ─── Zoom & horizontal scroll (activity table) ────────────────────────────
  double _zoom = 0.85;
  static const double _baselineZoom = 0.85;
  final ScrollController _hScrollController = ScrollController();
  static const double _minZoom = 0.6;
  static const double _maxZoom = 1.6;
  static const double _zoomStep = 0.1;

  void _clampHorizontalScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hScrollController.hasClients) return;
      if (_zoom <= _baselineZoom) {
        _hScrollController.jumpTo(0.0);
        return;
      }
      final max = _hScrollController.position.maxScrollExtent;
      final pos = _hScrollController.offset;
      if (pos > max) _hScrollController.jumpTo(max.clamp(0.0, double.infinity));
      if (pos < 0) _hScrollController.jumpTo(0.0);
    });
  }

  @override
  void dispose() {
    _activityName.dispose();
    _total.dispose();
    _projected.dispose();
    _disbursed.dispose();
    _activitySearch.dispose();
    _wfpSearch.dispose();
    _scrollController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  // ─── WFP filtering + sort ─────────────────────────────────────────────────

  List<WFPEntry> get _filteredWFP {
    final q = _wfpSearch.text.toLowerCase();
    final all = widget.appState.wfpEntries;
    final filtered = q.isEmpty
        ? all.toList()
        : all
              .where(
                (e) =>
                    e.id.toLowerCase().contains(q) ||
                    e.title.toLowerCase().contains(q) ||
                    e.fundType.toLowerCase().contains(q) ||
                    e.year.toString().contains(q) ||
                    e.approvalStatus.toLowerCase().contains(q),
              )
              .toList();
    filtered.sort((a, b) {
      int cmp;
      switch (_wfpSortCol) {
        case 0:
          cmp = a.id.compareTo(b.id);
          break;
        case 1:
          cmp = a.title.compareTo(b.title);
          break;
        case 2:
          cmp = a.fundType.compareTo(b.fundType);
          break;
        case 3:
          cmp = a.year.compareTo(b.year);
          break;
        case 4:
          cmp = a.amount.compareTo(b.amount);
          break;
        case 5:
          cmp = a.approvalStatus.compareTo(b.approvalStatus);
          break;
        case 6:
          cmp = (a.dueDate ?? '').compareTo(b.dueDate ?? '');
          break;
        default:
          cmp = 0;
      }
      return _wfpSortAsc ? cmp : -cmp;
    });
    return filtered;
  }

  void _onWFPSort(int col, bool asc) => setState(() {
    _wfpSortCol = col;
    _wfpSortAsc = asc;
  });

  // ─── Select WFP + scroll ──────────────────────────────────────────────────

  Future<void> _selectWFP(WFPEntry e) async {
    await widget.appState.selectWFP(e);
    _clearForm();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activitySectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // ─── Activity filtering & sort ────────────────────────────────────────────

  List<BudgetActivity> get _filteredActivities {
    final q = _activitySearch.text.toLowerCase();
    final all = widget.appState.activities;
    final filtered = q.isEmpty
        ? all.toList()
        : all
              .where(
                (a) =>
                    a.id.toLowerCase().contains(q) ||
                    a.name.toLowerCase().contains(q) ||
                    a.status.toLowerCase().contains(q),
              )
              .toList();
    filtered.sort((a, b) {
      int cmp;
      switch (_sortColumnIndex) {
        case 0:
          cmp = a.id.compareTo(b.id);
          break;
        case 1:
          cmp = a.name.compareTo(b.name);
          break;
        case 2:
          cmp = a.total.compareTo(b.total);
          break;
        case 3:
          cmp = a.projected.compareTo(b.projected);
          break;
        case 4:
          cmp = a.disbursed.compareTo(b.disbursed);
          break;
        case 5:
          cmp = a.balance.compareTo(b.balance);
          break;
        case 6:
          cmp = a.status.compareTo(b.status);
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return filtered;
  }

  void _onActivitySort(int col, bool asc) => setState(() {
    _sortColumnIndex = col;
    _sortAscending = asc;
    _currentPage = 0;
  });

  List<BudgetActivity> get _pagedRows {
    final all = _filteredActivities;
    final start = _currentPage * _rowsPerPage;
    if (start >= all.length) return [];
    return all.sublist(start, (start + _rowsPerPage).clamp(0, all.length));
  }

  int get _totalPages {
    final total = _filteredActivities.length;
    return total == 0 ? 1 : (total / _rowsPerPage).ceil();
  }

  void clearForm() => _clearForm();

  bool get hasUnsavedChanges =>
      _activityName.text.isNotEmpty ||
      _total.text.isNotEmpty ||
      _projected.text.isNotEmpty ||
      _disbursed.text.isNotEmpty ||
      _editingActivity != null;

  Future<void> openActivityById(String activityId) async {
    final activityIndex = widget.appState.allActivities.indexWhere(
      (item) => item.id == activityId,
    );
    if (activityIndex == -1) return;
    final activity = widget.appState.allActivities[activityIndex];

    final parentIndex = widget.appState.wfpEntries.indexWhere(
      (item) => item.id == activity.wfpId,
    );
    if (parentIndex == -1) return;
    final parent = widget.appState.wfpEntries[parentIndex];

    _wfpSearch.text = parent.id;
    _activitySearch.text = activity.id;
    await _selectWFP(parent);
    _loadActivityIntoForm(activity);
    setState(() => _currentPage = 0);
  }

  // ─── Form helpers ─────────────────────────────────────────────────────────

  void _loadActivityIntoForm(BudgetActivity a) {
    _activityName.text = a.name;
    _total.text = CurrencyFormatter.formatPlain(a.total);
    _projected.text = CurrencyFormatter.formatPlain(a.projected);
    _disbursed.text = CurrencyFormatter.formatPlain(a.disbursed);
    setState(() {
      _status = a.status;
      _suggestedStatus = null;
      _targetDate = a.targetDate;
      _editingActivity = a;
    });
  }

  void _clearForm() {
    _activityName.clear();
    _total.clear();
    _projected.clear();
    _disbursed.clear();
    setState(() {
      _status = 'Not Started';
      _suggestedStatus = null;
      _targetDate = null;
      _editingActivity = null;
    });
  }

  String? _computeSuggestedStatus() {
    final total = double.tryParse(_total.text.replaceAll(',', '')) ?? 0;
    final projected = double.tryParse(_projected.text.replaceAll(',', '')) ?? 0;
    final disbursed = double.tryParse(_disbursed.text.replaceAll(',', '')) ?? 0;

    String suggested;
    if (total <= 0 && disbursed <= 0) {
      suggested = 'Not Started';
    } else if (projected > total && total > 0) {
      suggested = 'At Risk';
    } else if (disbursed >= total && total > 0) {
      suggested = 'Completed';
    } else if (disbursed > 0) {
      suggested = 'Ongoing';
    } else {
      suggested = 'Not Started';
    }

    return suggested == _status ? null : suggested;
  }

  void _onAmountChanged() {
    final suggestion = _computeSuggestedStatus();
    if (suggestion != _suggestedStatus) {
      setState(() => _suggestedStatus = suggestion);
    }
  }

  Future<void> _pickTargetDate() async {
    final initial = _targetDate != null
        ? DateTime.tryParse(_targetDate!) ?? DateTime.now()
        : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      helpText: 'Select Target Date',
    );
    if (picked != null) {
      setState(() => _targetDate = picked.toIso8601String().substring(0, 10));
    }
  }

  // ─── Submit Activity ──────────────────────────────────────────────────────

  Future<void> _submitActivity() async {
    final selectedWFP = widget.appState.selectedWFP;
    if (selectedWFP == null) return;
    final totalVal = double.tryParse(_total.text.replaceAll(',', ''));
    final projectedVal = double.tryParse(_projected.text.replaceAll(',', ''));
    final disbursedVal = double.tryParse(_disbursed.text.replaceAll(',', ''));
    final validationError = RecordValidator.validateActivity(
      selectedWFP: selectedWFP,
      name: _activityName.text,
      total: totalVal,
      projected: projectedVal,
      disbursed: disbursedVal,
      targetDate: _targetDate,
      existingActivities: widget.appState.activities,
      editingId: _editingActivity?.id,
    );
    if (validationError != null) {
      _showSnack(
        selectedWFP.isApproved
            ? validationError
            : 'Cannot add activities — this WFP is "${selectedWFP.approvalStatus}". Approve it first.',
        isError: true,
      );
      return;
    }
    if (_editingActivity != null) {
      await widget.appState.updateActivity(
        _editingActivity!.copyWith(
          name: _activityName.text.trim(),
          total: totalVal!,
          projected: projectedVal!,
          disbursed: disbursedVal!,
          status: _status,
          targetDate: _targetDate,
          clearTargetDate: _targetDate == null,
        ),
      );
      _showSnack('Activity updated.');
    } else {
      final id = await widget.appState.generateActivityId(selectedWFP.id);
      await widget.appState.addActivity(
        BudgetActivity(
          id: id,
          wfpId: selectedWFP.id,
          name: _activityName.text.trim(),
          total: totalVal!,
          projected: projectedVal!,
          disbursed: disbursedVal!,
          status: _status,
          targetDate: _targetDate,
        ),
      );
      _showSnack('Activity added: $id');
    }
    _clearForm();
  }

  // ─── Delete Activity ──────────────────────────────────────────────────────

  Future<void> _confirmDeleteActivity(BudgetActivity a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move Activity to Recycle Bin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Move "${a.name}" (${a.id}) to the Recycle Bin?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade600,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The activity can be restored from the Recycle Bin in Settings.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            onPressed: () => Navigator.of(ctx).pop(true),
            label: const Text('Move to Bin'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await widget.appState.deleteActivity(a.id);
      if (ok) {
        _showSnack('Activity moved to Recycle Bin.');
        if (_editingActivity?.id == a.id) _clearForm();
      } else {
        _showSnack(
          widget.appState.error ?? 'Failed to move activity to Recycle Bin.',
          isError: true,
        );
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Completed':
        return AppColors.success;
      case 'Ongoing':
        return AppColors.info;
      case 'At Risk':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _approvalColor(String s) {
    switch (s) {
      case 'Approved':
        return AppColors.success;
      case 'Rejected':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  double _responsiveColumnWidth(
    double availableWidth, {
    required double fraction,
    required double min,
    required double max,
  }) {
    return (availableWidth * fraction).clamp(min, max).toDouble();
  }

  Widget _buildCompactChip({
    required String text,
    required String tooltip,
    required Color backgroundColor,
    Color? textColor,
    FontWeight fontWeight = FontWeight.w600,
    double maxWidth = _compactChipMaxWidth,
  }) {
    return Tooltip(
      message: tooltip,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              color: textColor,
              fontWeight: fontWeight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDueDateCell(
    WFPEntry entry, {
    double maxWidth = _dateCellMaxWidth,
  }) {
    final daysUntil = entry.daysUntilDue;
    if (entry.dueDate == null) {
      return Tooltip(
        message: 'No due date set',
        child: Text(
          '-',
          style: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    final message = daysUntil == null
        ? 'Due: ${entry.dueDate}'
        : daysUntil < 0
        ? 'Overdue by ${-daysUntil} day${-daysUntil == 1 ? '' : 's'}'
        : daysUntil == 0
        ? 'Due today!'
        : 'Due in $daysUntil day${daysUntil == 1 ? '' : 's'} (${entry.dueDate})';

    return Tooltip(
      message: message,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (daysUntil != null && daysUntil <= 7) ...[
              Icon(
                Icons.warning_amber_rounded,
                size: 13,
                color: daysUntil < 0 ? AppColors.danger : AppColors.warning,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                entry.dueDate!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  color: daysUntil != null && daysUntil < 0
                      ? AppColors.danger
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final selectedWFP = widget.appState.selectedWFP;
        final isLoading = widget.appState.isLoading;
        final wfpEntries = _filteredWFP;
        final allWFP = widget.appState.wfpEntries;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ─────────────────────────────────────────────
                Row(
                  children: [
                    const Text(
                      'Budget Overview',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (isLoading)
                      const Tooltip(
                        message: 'Saving changes…',
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a WFP entry below to manage its budget activities.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 20),

                // ── WFP Table ──────────────────────────────────────────
                Card(
                  elevation: 2,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final titleRow = Row(
                              children: [
                                const Text(
                                  'WFP Entries',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: 'Total number of WFP entries',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xff2F3E46,
                                      ).withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${allWFP.length}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                            final searchField = SizedBox(
                              height: 38,
                              child: Tooltip(
                                message:
                                    'Filter WFP entries by ID, title, fund type, year, or approval status',
                                child: TextField(
                                  controller: _wfpSearch,
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 18,
                                    ),
                                    hintText:
                                        'ID, title, fund type, year, or approval status',
                                    hintStyle: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade400,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            );
                            if (c.maxWidth < 600) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  titleRow,
                                  const SizedBox(height: 8),
                                  searchField,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                titleRow,
                                const SizedBox(width: 16),
                                Expanded(child: searchField),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: allWFP.isEmpty ? 100 : 320,
                        child: allWFP.isEmpty
                            ? Center(
                                child: Text(
                                  'No WFP entries yet. Add entries in WFP Management.',
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : wfpEntries.isEmpty
                            ? Center(
                                child: Text(
                                  'No results for "${_wfpSearch.text}"',
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final tableWidth =
                                      constraints.maxWidth < _tableMinWidth
                                      ? _tableMinWidth
                                      : constraints.maxWidth;
                                  final wfpIdWidth = _responsiveColumnWidth(
                                    tableWidth,
                                    fraction: 0.15,
                                    min: 122,
                                    max: 154,
                                  );
                                  final fundTypeWidth = _responsiveColumnWidth(
                                    tableWidth,
                                    fraction: 0.11,
                                    min: 84,
                                    max: 114,
                                  );
                                  final yearWidth = _responsiveColumnWidth(
                                    tableWidth,
                                    fraction: 0.08,
                                    min: 72,
                                    max: 88,
                                  );
                                  final amountWidth = _responsiveColumnWidth(
                                    tableWidth,
                                    fraction: 0.14,
                                    min: 118,
                                    max: 152,
                                  );
                                  final approvalWidth = _responsiveColumnWidth(
                                    tableWidth,
                                    fraction: 0.11,
                                    min: 96,
                                    max: 126,
                                  );
                                  final dueDateWidth = _responsiveColumnWidth(
                                    tableWidth,
                                    fraction: 0.13,
                                    min: 110,
                                    max: 138,
                                  );
                                  final actionsWidth = _responsiveColumnWidth(
                                    tableWidth,
                                    fraction: 0.15,
                                    min: 122,
                                    max: 154,
                                  );

                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: tableWidth,
                                      child: DataTable2(
                                        minWidth: _tableMinWidth,
                                        sortColumnIndex: _wfpSortCol,
                                        sortAscending: _wfpSortAsc,
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                              AppColors.primary,
                                            ),
                                        headingTextStyle: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        columnSpacing: 14,
                                        horizontalMargin: 12,
                                        columns: [
                                          DataColumn2(
                                            label: Tooltip(
                                              message:
                                                  'Unique WFP identifier — click to sort',
                                              child: const _TableHeaderText(
                                                'WFP ID',
                                              ),
                                            ),
                                            fixedWidth: wfpIdWidth,
                                            onSort: _onWFPSort,
                                          ),
                                          DataColumn2(
                                            label: Tooltip(
                                              message:
                                                  'WFP program title — click to sort',
                                              child: const _TableHeaderText(
                                                'Title',
                                              ),
                                            ),
                                            size: ColumnSize.L,
                                            onSort: _onWFPSort,
                                          ),
                                          DataColumn2(
                                            label: Tooltip(
                                              message:
                                                  'Source of funds (e.g. GAA, RLIP) — click to sort',
                                              child: const _TableHeaderText(
                                                'Fund Type',
                                              ),
                                            ),
                                            fixedWidth: fundTypeWidth,
                                            onSort: _onWFPSort,
                                          ),
                                          DataColumn2(
                                            label: Tooltip(
                                              message:
                                                  'Fiscal year this WFP covers — click to sort',
                                              child: const _TableHeaderText(
                                                'Year',
                                              ),
                                            ),
                                            fixedWidth: yearWidth,
                                            numeric: true,
                                            onSort: _onWFPSort,
                                          ),
                                          DataColumn2(
                                            label: Tooltip(
                                              message:
                                                  'Total approved budget ceiling — click to sort',
                                              child: const _TableHeaderText(
                                                'Amount',
                                              ),
                                            ),
                                            fixedWidth: amountWidth,
                                            numeric: true,
                                            onSort: _onWFPSort,
                                          ),
                                          DataColumn2(
                                            label: Tooltip(
                                              message:
                                                  'Current approval status (Approved / Pending / Rejected) — click to sort',
                                              child: const _TableHeaderText(
                                                'Approval',
                                              ),
                                            ),
                                            fixedWidth: approvalWidth,
                                            onSort: _onWFPSort,
                                          ),
                                          DataColumn2(
                                            label: Tooltip(
                                              message:
                                                  'Deadline for this WFP — turns red when overdue — click to sort',
                                              child: const _TableHeaderText(
                                                'Due Date',
                                              ),
                                            ),
                                            fixedWidth: dueDateWidth,
                                            onSort: _onWFPSort,
                                          ),
                                          DataColumn2(
                                            label: Tooltip(
                                              message:
                                                  'Select a WFP to begin adding or editing its budget activities',
                                              child: const _TableHeaderText(
                                                'Actions',
                                              ),
                                            ),
                                            fixedWidth: actionsWidth,
                                          ),
                                        ],
                                        rows: wfpEntries.asMap().entries.map((
                                          entry,
                                        ) {
                                          final i = entry.key;
                                          final e = entry.value;
                                          final isSelected =
                                              selectedWFP?.id == e.id;
                                          final approvalClr = _approvalColor(
                                            e.approvalStatus,
                                          );
                                          return DataRow2(
                                            color:
                                                WidgetStateProperty.resolveWith(
                                                  (_) {
                                                    if (isSelected) {
                                                      return AppColors.selected;
                                                    }
                                                    return i.isEven
                                                        ? AppColors.surface
                                                        : AppColors.background;
                                                  },
                                                ),
                                            cells: [
                                              DataCell(
                                                Tooltip(
                                                  message: 'WFP ID: ${e.id}',
                                                  child: Text(
                                                    e.id,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 12,
                                                      fontWeight: isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                      color: isSelected
                                                          ? AppColors
                                                                .textPrimary
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Row(
                                                  children: [
                                                    if (isSelected)
                                                      Container(
                                                        width: 3,
                                                        height: 20,
                                                        margin:
                                                            const EdgeInsets.only(
                                                              right: 6,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              AppColors.primary,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                2,
                                                              ),
                                                        ),
                                                      ),
                                                    Expanded(
                                                      child: Tooltip(
                                                        message: e.title,
                                                        child: Text(
                                                          e.title,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                isSelected
                                                                ? FontWeight
                                                                      .w600
                                                                : FontWeight
                                                                      .normal,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              DataCell(
                                                _buildCompactChip(
                                                  text: e.fundType,
                                                  tooltip:
                                                      'Fund type: ${e.fundType}',
                                                  backgroundColor:
                                                      AppColors.tint(
                                                        AppColors.textPrimary,
                                                        0.1,
                                                      ),
                                                  textColor:
                                                      AppColors.textPrimary,
                                                  maxWidth: fundTypeWidth,
                                                ),
                                              ),
                                              DataCell(
                                                Tooltip(
                                                  message:
                                                      'Fiscal year: ${e.year}',
                                                  child: Text(
                                                    e.year.toString(),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Tooltip(
                                                  message:
                                                      'Total budget ceiling: ${CurrencyFormatter.format(e.amount)}',
                                                  child: Text(
                                                    CurrencyFormatter.format(
                                                      e.amount,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                _buildCompactChip(
                                                  text: e.approvalStatus,
                                                  tooltip:
                                                      'Approval status: ${e.approvalStatus}',
                                                  backgroundColor: approvalClr
                                                      .withValues(alpha: 0.1),
                                                  textColor: approvalClr,
                                                  maxWidth: approvalWidth,
                                                ),
                                              ),
                                              DataCell(
                                                e.dueDate == null
                                                    ? Tooltip(
                                                        message:
                                                            'No due date set',
                                                        child: Text(
                                                          '—',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey
                                                                .shade400,
                                                          ),
                                                        ),
                                                      )
                                                    : _buildDueDateCell(
                                                        e,
                                                        maxWidth: dueDateWidth,
                                                      ),
                                              ),
                                              DataCell(
                                                isSelected
                                                    ? Tooltip(
                                                        message:
                                                            'Currently working on this WFP',
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                const Color(
                                                                  0xff2F3E46,
                                                                ).withValues(
                                                                  alpha: 0.08,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  6,
                                                                ),
                                                          ),
                                                          child: const Text(
                                                            'Selected',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Color(
                                                                0xff2F3E46,
                                                              ),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    : Tooltip(
                                                        message:
                                                            'Select this WFP to add or manage its budget activities',
                                                        child: TextButton.icon(
                                                          style: TextButton.styleFrom(
                                                            backgroundColor:
                                                                const Color(
                                                                  0xff2F3E46,
                                                                ),
                                                            foregroundColor:
                                                                Colors.white,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 4,
                                                                ),
                                                            minimumSize:
                                                                Size.zero,
                                                            tapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            textStyle:
                                                                const TextStyle(
                                                                  fontSize: 11,
                                                                ),
                                                          ),
                                                          icon: const Icon(
                                                            Icons.add,
                                                            size: 13,
                                                          ),
                                                          label: const Text(
                                                            'Add Activity',
                                                          ),
                                                          onPressed: () =>
                                                              _selectWFP(e),
                                                        ),
                                                      ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Activity Section ───────────────────────────────────
                if (selectedWFP != null) ...[
                  SizedBox(key: _activitySectionKey, height: 0),

                  // Context banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.tint(AppColors.primary, 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.tint(AppColors.primary, 0.28),
                      ),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _contextChip('ID', selectedWFP.id),
                        _contextChip('Title', selectedWFP.title),
                        _contextChip('Fund Type', selectedWFP.fundType),
                        _contextChip(
                          'WFP Amount',
                          CurrencyFormatter.format(selectedWFP.amount),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  _buildSummaryHeader(),
                  const SizedBox(height: 20),

                  // ── Activity form ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _editingActivity != null
                              ? 'Edit Activity: ${_editingActivity!.id}'
                              : 'Add New Activity',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!selectedWFP.isApproved)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  color: Colors.orange.shade700,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'This WFP is "${selectedWFP.approvalStatus}" — '
                                    'activities cannot be added until it is Approved.',
                                    style: TextStyle(
                                      color: Colors.orange.shade800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        LayoutBuilder(
                          builder: (context, c) {
                            // ── Name field ──────────────────────────────
                            final nameField = Tooltip(
                              message:
                                  'Enter a clear, descriptive name for this budget activity',
                              child: TextField(
                                controller: _activityName,
                                decoration: const InputDecoration(
                                  labelText: 'Activity Name *',
                                  hintText: 'e.g. Community Outreach Program',
                                  helperText:
                                      'Short description of the budget activity',
                                  prefixIcon: Icon(
                                    Icons.label_outline,
                                    size: 18,
                                  ),
                                ),
                              ),
                            );

                            // ── Total field ─────────────────────────────
                            final totalField = Tooltip(
                              message:
                                  'Total Allotted Release (AR) — the approved budget ceiling for this activity.\n'
                                  'Cannot exceed the remaining WFP amount.',
                              child: TextField(
                                controller: _total,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  MoneyInputFormatter(decimalRange: 2),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Total Amount (₱)',
                                  hintText: 'e.g. 1,000,000.00',
                                  helperText: 'Approved budget ceiling (AR)',
                                  prefixIcon: Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 18,
                                  ),
                                ),
                                onChanged: (_) => _onAmountChanged(),
                              ),
                            );

                            // ── Projected / Obligated field ─────────────
                            final projField = Tooltip(
                              message:
                                  'Projected / Obligated — amount committed or encumbered.\n'
                                  'A value exceeding Total will flag this activity as "At Risk".',
                              child: TextField(
                                controller: _projected,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  MoneyInputFormatter(decimalRange: 2),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Projected / Obligated (₱)',
                                  hintText: 'e.g. 800,000.00',
                                  helperText: 'Amount committed so far',
                                  prefixIcon: Icon(
                                    Icons.trending_up_outlined,
                                    size: 18,
                                  ),
                                ),
                                onChanged: (_) => _onAmountChanged(),
                              ),
                            );

                            // ── Disbursed field ─────────────────────────
                            final disbField = Tooltip(
                              message:
                                  'Disbursed — amount actually paid out.\n'
                                  'When this equals Total, the activity is auto-suggested as "Completed".',
                              child: TextField(
                                controller: _disbursed,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  MoneyInputFormatter(decimalRange: 2),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Disbursed (₱)',
                                  hintText: 'e.g. 500,000.00',
                                  helperText: 'Amount actually paid out',
                                  prefixIcon: Icon(
                                    Icons.payments_outlined,
                                    size: 18,
                                  ),
                                ),
                                onChanged: (_) => _onAmountChanged(),
                              ),
                            );

                            // ── Status dropdown ─────────────────────────
                            final statusDd = Tooltip(
                              message:
                                  'Activity status:\n'
                                  '• Not Started — no funds disbursed yet\n'
                                  '• Ongoing — partially disbursed\n'
                                  '• Completed — fully disbursed\n'
                                  '• At Risk — obligated amount exceeds total',
                              child: DropdownButton<String>(
                                value: _status,
                                items: _statusOptions
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  _status = v!;
                                  _suggestedStatus = _computeSuggestedStatus();
                                }),
                              ),
                            );

                            // ── Suggestion chip ─────────────────────────
                            final suggestionChip = _suggestedStatus != null
                                ? Tooltip(
                                    message:
                                        'Based on the amounts you entered, "$_suggestedStatus" '
                                        'is the recommended status. Click to apply.',
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _status = _suggestedStatus!;
                                        _suggestedStatus = null;
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue.shade300,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.auto_fix_high,
                                              size: 13,
                                              color: Colors.blue.shade700,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Suggest: $_suggestedStatus',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue.shade700,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.check,
                                              size: 12,
                                              color: Colors.blue.shade700,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : null;

                            final statusControls = Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [statusDd, ?suggestionChip],
                            );

                            // ── Target date field ───────────────────────
                            final targetDateField = Tooltip(
                              message:
                                  'Optional deadline for completing this activity.\n'
                                  'Used for deadline notifications and overdue tracking.',
                              child: InkWell(
                                onTap: _pickTargetDate,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Target Date',
                                    helperText: 'Optional completion deadline',
                                    suffixIcon: Tooltip(
                                      message: 'Open date picker',
                                      child: Icon(
                                        Icons.calendar_today,
                                        size: 14,
                                      ),
                                    ),
                                    isDense: true,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _targetDate ?? 'Set date',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _targetDate != null
                                                ? Colors.black87
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                      ),
                                      if (_targetDate != null)
                                        Tooltip(
                                          message: 'Clear target date',
                                          child: GestureDetector(
                                            onTap: () => setState(
                                              () => _targetDate = null,
                                            ),
                                            child: Icon(
                                              Icons.clear,
                                              size: 14,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );

                            // ── Action buttons ──────────────────────────
                            final actionBtns = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_editingActivity != null) ...[
                                  Tooltip(
                                    message:
                                        'Discard changes and return to add-new mode',
                                    child: OutlinedButton(
                                      onPressed: _clearForm,
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Tooltip(
                                  message: _editingActivity != null
                                      ? 'Save changes to activity ${_editingActivity!.id}'
                                      : 'Add this new activity to the selected WFP',
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: Icon(
                                      _editingActivity != null
                                          ? Icons.save
                                          : Icons.add,
                                    ),
                                    label: Text(
                                      _editingActivity != null
                                          ? 'Save'
                                          : 'Add Activity',
                                    ),
                                    onPressed: isLoading
                                        ? null
                                        : _submitActivity,
                                  ),
                                ),
                              ],
                            );

                            if (c.maxWidth < 700) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  nameField,
                                  const SizedBox(height: 8),
                                  totalField,
                                  const SizedBox(height: 8),
                                  projField,
                                  const SizedBox(height: 8),
                                  disbField,
                                  const SizedBox(height: 8),
                                  statusControls,
                                  const SizedBox(height: 8),
                                  targetDateField,
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: actionBtns,
                                  ),
                                ],
                              );
                            }
                            if (c.maxWidth < 1150) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 2, child: nameField),
                                      const SizedBox(width: 10),
                                      Expanded(child: totalField),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: projField),
                                      const SizedBox(width: 10),
                                      Expanded(child: disbField),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 150,
                                        child: targetDateField,
                                      ),
                                      statusControls,
                                      actionBtns,
                                    ],
                                  ),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 2, child: nameField),
                                    const SizedBox(width: 10),
                                    Expanded(child: totalField),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 150,
                                      child: targetDateField,
                                    ),
                                    const SizedBox(width: 10),
                                    actionBtns,
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: projField),
                                    const SizedBox(width: 10),
                                    Expanded(child: disbField),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: statusControls,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Search + pagination controls ───────────────────────
                  LayoutBuilder(
                    builder: (context, c) {
                      final searchField = Tooltip(
                        message: 'Filter activities by ID, name, or status',
                        child: TextField(
                          controller: _activitySearch,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Search activities…',
                            hintText: 'ID, name, or status',
                          ),
                          onChanged: (_) => setState(() => _currentPage = 0),
                        ),
                      );
                      final controls = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Show:',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message:
                                'Number of activity rows to display per page',
                            child: DropdownButton<int>(
                              value: _rowsPerPage,
                              items: _rowsPerPageOptions
                                  .map(
                                    (n) => DropdownMenuItem(
                                      value: n,
                                      child: Text('$n entries'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _rowsPerPage = v!;
                                _currentPage = 0;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message:
                                'Total number of activities matching your current search filter',
                            child: Text(
                              '${_filteredActivities.length} activit${_filteredActivities.length == 1 ? 'y' : 'ies'}',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      );
                      if (c.maxWidth < 600) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            searchField,
                            const SizedBox(height: 8),
                            controls,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: 16),
                          controls,
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // ── Zoom toolbar ─────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: 'Adjust the table zoom level',
                        child: const Text(
                          'Zoom',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Zoom out - make the table smaller.',
                        icon: const Icon(Icons.remove_circle_outline),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: _zoom > _minZoom
                            ? () {
                                setState(
                                  () => _zoom = (_zoom - _zoomStep).clamp(
                                    _minZoom,
                                    _maxZoom,
                                  ),
                                );
                                _clampHorizontalScroll();
                              }
                            : null,
                      ),
                      Tooltip(
                        message:
                            'Current zoom level (${(_zoom / _baselineZoom * 100).round()}%). '
                            'Click the reset button to restore default.',
                        child: Text(
                          '${(_zoom / _baselineZoom * 100).round()}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reset zoom to default (100%).',
                        icon: const Icon(Icons.refresh),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() => _zoom = _baselineZoom);
                          _clampHorizontalScroll();
                        },
                      ),
                      IconButton(
                        tooltip:
                            'Zoom in - make the table larger. A horizontal scrollbar appears when zoomed in.',
                        icon: const Icon(Icons.add_circle_outline),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: _zoom < _maxZoom
                            ? () {
                                setState(
                                  () => _zoom = (_zoom + _zoomStep).clamp(
                                    _minZoom,
                                    _maxZoom,
                                  ),
                                );
                                _clampHorizontalScroll();
                              }
                            : null,
                      ),
                    ],
                  ),

                  // ── Activities table (with zoom) ──────────────────────
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final baseWidth = constraints.maxWidth < _tableMinWidth
                          ? _tableMinWidth
                          : constraints.maxWidth;
                      final tableWidth = _zoom > _baselineZoom
                          ? baseWidth * _zoom
                          : baseWidth;
                      final activityIdWidth = _responsiveColumnWidth(
                        tableWidth,
                        fraction: 0.16,
                        min: 134,
                        max: 170,
                      );
                      final statusWidth = _responsiveColumnWidth(
                        tableWidth,
                        fraction: 0.11,
                        min: 92,
                        max: 122,
                      );
                      final actionsWidth = _responsiveColumnWidth(
                        tableWidth,
                        fraction: 0.12,
                        min: 112,
                        max: 142,
                      );

                      final tableRows = _pagedRows.asMap().entries.map((entry) {
                        final i = entry.key;
                        final a = entry.value;
                        final isEditing = _editingActivity?.id == a.id;
                        return DataRow2(
                          color: WidgetStateProperty.resolveWith((_) {
                            if (isEditing) return AppColors.selected;
                            return i.isEven
                                ? AppColors.surface
                                : AppColors.background;
                          }),
                          cells: [
                            DataCell(
                              Tooltip(
                                message: 'Activity ID: ${a.id}',
                                child: Text(
                                  a.id,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Tooltip(
                                message: a.name,
                                child: Text(
                                  a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ),
                            DataCell(
                              Tooltip(
                                message:
                                    'Total AR: ${CurrencyFormatter.format(a.total)}',
                                child: Text(
                                  CurrencyFormatter.format(a.total),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ),
                            DataCell(
                              Tooltip(
                                message:
                                    'Projected / Obligated: ${CurrencyFormatter.format(a.projected)}',
                                child: Text(
                                  CurrencyFormatter.format(a.projected),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ),
                            DataCell(
                              Tooltip(
                                message:
                                    'Disbursed: ${CurrencyFormatter.format(a.disbursed)}',
                                child: Text(
                                  CurrencyFormatter.format(a.disbursed),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ),
                            DataCell(
                              Tooltip(
                                message:
                                    'Balance = Total − Disbursed: ${CurrencyFormatter.format(a.balance)}'
                                    '${a.balance < 0 ? "\n⚠ Negative balance — disbursements exceed total AR" : ""}',
                                child: Text(
                                  CurrencyFormatter.format(a.balance),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: a.balance >= 0
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              _buildCompactChip(
                                text: a.status,
                                tooltip: 'Status: ${a.status}',
                                backgroundColor: _statusColor(
                                  a.status,
                                ).withValues(alpha: 0.12),
                                textColor: _statusColor(a.status),
                                maxWidth: statusWidth,
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: Colors.blueGrey,
                                    ),
                                    tooltip:
                                        'Edit "${a.name}" - loads data into the form above',
                                    onPressed: () => _loadActivityIntoForm(a),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red.shade400,
                                    ),
                                    tooltip:
                                        'Move "${a.name}" to the Recycle Bin',
                                    onPressed: () => _confirmDeleteActivity(a),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList();

                      List<DataColumn2> buildColumns() => [
                        DataColumn2(
                          label: Tooltip(
                            message:
                                'Auto-generated activity ID — click to sort',
                            child: const _TableHeaderText('Activity ID'),
                          ),
                          fixedWidth: activityIdWidth,
                          onSort: _onActivitySort,
                        ),
                        DataColumn2(
                          label: Tooltip(
                            message:
                                'Name of the budget activity — click to sort',
                            child: const _TableHeaderText('Activity Name'),
                          ),
                          size: ColumnSize.L,
                          onSort: _onActivitySort,
                        ),
                        DataColumn2(
                          label: Tooltip(
                            message:
                                'Total Allotted Release amount — click to sort',
                            child: const Text('Total AR (₱)'),
                          ),
                          size: ColumnSize.M,
                          numeric: true,
                          onSort: _onActivitySort,
                        ),
                        DataColumn2(
                          label: Tooltip(
                            message:
                                'Amount obligated / projected to be spent — click to sort',
                            child: const Text('Projected (₱)'),
                          ),
                          size: ColumnSize.M,
                          numeric: true,
                          onSort: _onActivitySort,
                        ),
                        DataColumn2(
                          label: Tooltip(
                            message: 'Amount actually paid out — click to sort',
                            child: const Text('Disbursed (₱)'),
                          ),
                          size: ColumnSize.M,
                          numeric: true,
                          onSort: _onActivitySort,
                        ),
                        DataColumn2(
                          label: Tooltip(
                            message:
                                'Remaining balance (Total − Disbursed) — red when negative — click to sort',
                            child: const Text('Balance (₱)'),
                          ),
                          size: ColumnSize.M,
                          numeric: true,
                          onSort: _onActivitySort,
                        ),
                        DataColumn2(
                          label: Tooltip(
                            message: 'Current activity status — click to sort',
                            child: const _TableHeaderText('Status'),
                          ),
                          fixedWidth: statusWidth,
                          onSort: _onActivitySort,
                        ),
                        DataColumn2(
                          label: Tooltip(
                            message: 'Edit or delete this activity',
                            child: const _TableHeaderText('Actions'),
                          ),
                          fixedWidth: actionsWidth,
                        ),
                      ];

                      return Scrollbar(
                        controller: _hScrollController,
                        thumbVisibility: _zoom > _baselineZoom,
                        trackVisibility: _zoom > _baselineZoom,
                        child: SingleChildScrollView(
                          physics: _zoom <= _baselineZoom
                              ? const NeverScrollableScrollPhysics()
                              : const ClampingScrollPhysics(),
                          controller: _hScrollController,
                          scrollDirection: Axis.horizontal,
                          child: _zoom > _baselineZoom
                              ? SizedBox(
                                  width: baseWidth * _zoom,
                                  height: _activityTableHeight * _zoom,
                                  child: DataTable2(
                                    minWidth: _tableMinWidth,
                                    sortColumnIndex: _sortColumnIndex,
                                    sortAscending: _sortAscending,
                                    headingRowColor: WidgetStateProperty.all(
                                      AppColors.primary,
                                    ),
                                    headingTextStyle: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    columnSpacing: 12,
                                    horizontalMargin: 12,
                                    columns: buildColumns(),
                                    rows: tableRows,
                                  ),
                                )
                              : SizedBox(
                                  width: baseWidth,
                                  height: _activityTableHeight,
                                  child: Transform.scale(
                                    scale: _zoom,
                                    alignment: Alignment.topLeft,
                                    child: SizedBox(
                                      width: baseWidth,
                                      height: _activityTableHeight,
                                      child: DataTable2(
                                        minWidth: _tableMinWidth,
                                        sortColumnIndex: _sortColumnIndex,
                                        sortAscending: _sortAscending,
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                              AppColors.primary,
                                            ),
                                        headingTextStyle: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        columnSpacing: 12,
                                        horizontalMargin: 12,
                                        columns: buildColumns(),
                                        rows: tableRows,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),

                  PaginationBar(
                    currentPage: _currentPage,
                    totalPages: _totalPages,
                    totalItems: _filteredActivities.length,
                    rowsPerPage: _rowsPerPage,
                    onPageChanged: (p) => setState(() => _currentPage = p),
                  ),

                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Summary widgets ──────────────────────────────────────────────────────

  String _aggregateStatus(List<BudgetActivity> activities) {
    if (activities.isEmpty) return 'Not Started';
    const severity = {
      'At Risk': 3,
      'Ongoing': 2,
      'Not Started': 1,
      'Completed': 0,
    };
    return activities
        .map((a) => a.status)
        .reduce((a, b) => (severity[a] ?? 0) >= (severity[b] ?? 0) ? a : b);
  }

  Color _aggregateStatusColor(String status) {
    switch (status) {
      case 'At Risk':
        return Colors.red.shade700;
      case 'Ongoing':
        return Colors.blue.shade700;
      case 'Completed':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  Widget _buildSummaryHeader() {
    final s = widget.appState;
    final overallStatus = _aggregateStatus(s.activities);
    return Row(
      children: [
        _summaryTile(
          'Current Status',
          overallStatus,
          tooltip:
              'Overall status derived from the highest-severity activity.\n'
              'At Risk > Ongoing > Not Started > Completed.',
          color: _aggregateStatusColor(overallStatus),
        ),
        const SizedBox(width: 12),
        _summaryTile(
          'Total AR Amount',
          CurrencyFormatter.format(s.totalAR),
          tooltip:
              'Sum of all Total AR amounts across all activities under this WFP.',
        ),
        const SizedBox(width: 12),
        _summaryTile(
          'Total Obligated AR',
          CurrencyFormatter.format(s.totalObligated),
          tooltip:
              'Sum of all Projected / Obligated amounts across all activities.',
        ),
        const SizedBox(width: 12),
        _summaryTile(
          'Disbursement Amount',
          CurrencyFormatter.format(s.totalDisbursed),
          tooltip:
              'Total amount actually paid out across all activities under this WFP.',
        ),
        const SizedBox(width: 12),
        _summaryTile(
          'Total AR Balance',
          CurrencyFormatter.format(s.totalBalance),
          tooltip:
              'Remaining balance = Total AR − Total Disbursed.\n'
              'Turns red when negative (over-disbursed).',
          color: s.totalBalance >= 0
              ? Colors.green.shade700
              : Colors.red.shade700,
          bold: true,
        ),
      ],
    );
  }

  Widget _summaryTile(
    String label,
    String value, {
    String? tooltip,
    Color? color,
    bool bold = false,
  }) {
    final tile = Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade100,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color ?? const Color(0xff2F3E46),
              ),
            ),
          ],
        ),
      ),
    );

    if (tooltip == null) return tile;
    return Expanded(
      child: Tooltip(message: tooltip, child: tile.child),
    );
  }

  Widget _contextChip(String label, String value) {
    return Tooltip(
      message: '$label: $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Pagination Bar ───────────────────────────────────────────────────────────

// ignore: unused_element
class _PaginationBar extends StatelessWidget {
  final int currentPage, totalPages, totalItems, rowsPerPage;
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
    final end = ((currentPage + 1) * rowsPerPage).clamp(0, totalItems);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Showing entries $start to $end out of $totalItems total',
            child: Text(
              'Showing $start–$end of $totalItems entries',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.first_page),
            tooltip: 'Go to first page',
            iconSize: 20,
            onPressed: currentPage > 0 ? () => onPageChanged(0) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Go to previous page',
            iconSize: 20,
            onPressed: currentPage > 0
                ? () => onPageChanged(currentPage - 1)
                : null,
          ),
          ...List.generate(totalPages, (i) => i)
              .where(
                (i) =>
                    i == 0 ||
                    i == totalPages - 1 ||
                    (i - currentPage).abs() <= 1,
              )
              .fold<List<Widget>>([], (acc, i) {
                if (acc.isNotEmpty) {
                  final prev =
                      int.tryParse(
                        (acc.last as dynamic)?.key?.toString() ?? '',
                      ) ??
                      -999;
                  if (i - prev > 1) {
                    acc.add(
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '…',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    );
                  }
                }
                final isActive = i == currentPage;
                acc.add(
                  Padding(
                    key: ValueKey(i),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: isActive
                          ? 'Current page: ${i + 1}'
                          : 'Go to page ${i + 1}',
                      child: InkWell(
                        onTap: () => onPageChanged(i),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xff2F3E46)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xff2F3E46)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? Colors.white
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                return acc;
              }),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Go to next page',
            iconSize: 20,
            onPressed: currentPage < totalPages - 1
                ? () => onPageChanged(currentPage + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            tooltip: 'Go to last page',
            iconSize: 20,
            onPressed: currentPage < totalPages - 1
                ? () => onPageChanged(totalPages - 1)
                : null,
          ),
        ],
      ),
    );
  }
}
