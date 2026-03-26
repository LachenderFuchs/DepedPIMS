import 'package:flutter/material.dart';
import '../utils/decimal_input_formatter.dart';
import 'package:data_table_2/data_table_2.dart';
import '../models/wfp_entry.dart';
import '../services/app_state.dart';
import '../utils/currency_formatter.dart';
import '../widgets/pagination_bar.dart';

// ScrollBehavior that prevents the framework from inserting any automatic
// platform scrollbars. We wrap the page with this so only our explicit
// page-edge scrollbar is visible.
class _NoScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

// ─── Reusable tooltip-wrapped label widget ────────────────────────────────────

class _HintLabel extends StatelessWidget {
  final String text;
  final String hint;
  final IconData? icon;

  const _HintLabel(this.text, {required this.hint, this.icon});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: hint,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF2F3E46),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
          ],
          Text(text),
          const SizedBox(width: 4),
          Icon(Icons.help_outline_rounded, size: 13, color: Colors.grey.shade400),
        ],
      ),
    );
  }
}

// ─── Tooltip-wrapped InputDecorator helper ────────────────────────────────────

class _TooltipField extends StatelessWidget {
  final String tooltip;
  final Widget child;

  const _TooltipField({required this.tooltip, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: const Color(0xFF2F3E46),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class WFPManagementPage extends StatefulWidget {
  final AppState appState;
  const WFPManagementPage({super.key, required this.appState});

  @override
  State<WFPManagementPage> createState() => WFPManagementPageState();
}

class WFPManagementPageState extends State<WFPManagementPage> {
  final _title       = TextEditingController();
  final _targetSize  = TextEditingController();
  final _indicator   = TextEditingController();
  final _amount      = TextEditingController();
  final _search      = TextEditingController();

  int    _selectedYear   = DateTime.now().year < 2026 ? 2026 : DateTime.now().year;
  String _fundType       = 'MODE';
  String _viewSection    = 'HRD';
  String _approvalStatus = 'Pending';
  String? _approvedDate;
  String? _dueDate;

  WFPEntry? _editingEntry;

  int  _sortColumnIndex = 0;
  bool _sortAscending   = true;
  int  _currentPage     = 0;
  int  _rowsPerPage     = 10;
  static const _rowsPerPageOptions = [10, 25, 50, 100];

  static const double _tableMinWidth = 1280.0;
  static const double _tableHeight   = 420.0;

  static const _fundTypes = [
    'MODE','GASS','HRTD','LSP','SBFP','PESS','Palaro',
    'BEFF-EAO','BFLP','DPRP','OPDNTP','BEFF-Repair','BEFF-Electric',
  ];
  static const _sections = ['HRD', 'SMME', 'PRS', 'YFB', 'SHNS', 'EFS', 'SMNS', 'Sports'];
  static const _approvalOptions = ['Pending', 'Approved', 'Rejected'];

  // Fund type descriptions for tooltips
  static const _fundTypeHints = <String, String>{
    'MODE':          'Miscellaneous Operating and Development Expenses',
    'GASS':          'General Administration and Support Services',
    'HRTD':          'Human Resource Training and Development',
    'LSP':           'Learning Support Program',
    'SBFP':          'School-Based Feeding Program',
    'PESS':          'Physical Education and School Sports',
    'Palaro':        'National/Regional Schools Press Conference & Athletic Meet',
    'BEFF-EAO':      'Basic Education Facilities Fund – Equipment & Apparatus',
    'BFLP':          'Basic and Further Learning Program',
    'DPRP':          'Disaster Preparedness and Response Program',
    'OPDNTP':        'Out-of-School Youth and Adult Learners Program',
    'BEFF-Repair':   'Basic Education Facilities Fund – Repair & Maintenance',
    'BEFF-Electric': 'Basic Education Facilities Fund – Electrical Works',
  };

  // Section descriptions for tooltips
  static const _sectionHints = <String, String>{
    'HRD':    'Human Resource Development Division',
    'SMME':   'School Management & Monitoring and Evaluation',
    'PRS':    'Planning and Research Section',
    'YFB':    'Youth Formation Bureau',
    'SHNS':   'School Health and Nutrition Section',
    'EFS':    'Education Facilities Section',
    'SMNS':   'Special Molave National School',
    'Sports': 'Sports Development and Programs',
  };

  // Zoom & scrolling
  double _zoom = 0.85;
  static const double _baselineZoom = 0.85;
  final ScrollController _hScrollController = ScrollController();
  final ScrollController _vScrollController = ScrollController();
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
      if (pos < 0)  _hScrollController.jumpTo(0.0);
    });
  }

  // ─── Filtering & Sorting ──────────────────────────────────────────────────

  List<WFPEntry> get _filtered {
    final q   = _search.text.toLowerCase();
    final all = widget.appState.wfpEntries;
    final filtered = q.isEmpty
        ? all.toList()
        : all.where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.id.toLowerCase().contains(q) ||
            e.fundType.toLowerCase().contains(q) ||
            e.year.toString().contains(q) ||
            e.targetSize.toLowerCase().contains(q) ||
            e.indicator.toLowerCase().contains(q) ||
            e.approvalStatus.toLowerCase().contains(q) ||
            e.viewSection.toLowerCase().contains(q),
          ).toList();

    filtered.sort((a, b) {
      int cmp;
      switch (_sortColumnIndex) {
        case 0: cmp = a.id.compareTo(b.id); break;
        case 1: cmp = a.title.compareTo(b.title); break;
        case 2: cmp = a.targetSize.compareTo(b.targetSize); break;
        case 3: cmp = a.fundType.compareTo(b.fundType); break;
        case 4: cmp = a.viewSection.compareTo(b.viewSection); break;
        case 5: cmp = a.year.compareTo(b.year); break;
        case 6: cmp = a.amount.compareTo(b.amount); break;
        case 7: cmp = a.approvalStatus.compareTo(b.approvalStatus); break;
        default: cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return filtered;
  }

  void _onSort(int col, bool asc) => setState(() {
    _sortColumnIndex = col; _sortAscending = asc; _currentPage = 0;
  });

  List<WFPEntry> get _pagedRows {
    final all   = _filtered;
    final start = _currentPage * _rowsPerPage;
    if (start >= all.length) return [];
    return all.sublist(start, (start + _rowsPerPage).clamp(0, all.length));
  }

  int get _totalPages {
    final total = _filtered.length;
    return total == 0 ? 1 : (total / _rowsPerPage).ceil();
  }

  void clearForm() => _clearForm();

  bool get hasUnsavedChanges =>
      _title.text.isNotEmpty ||
      _targetSize.text.isNotEmpty ||
      _indicator.text.isNotEmpty ||
      _amount.text.isNotEmpty ||
      _editingEntry != null;

  // ─── Form Helpers ─────────────────────────────────────────────────────────

  void _loadEntryIntoForm(WFPEntry entry) {
    _title.text      = entry.title;
    _targetSize.text = entry.targetSize;
    _indicator.text  = entry.indicator;
    _amount.text     = CurrencyFormatter.formatPlain(entry.amount);
    setState(() {
      _selectedYear   = entry.year;
      _fundType       = entry.fundType;
      _viewSection    = entry.viewSection;
      _approvalStatus = entry.approvalStatus;
      _approvedDate   = entry.approvedDate;
      _dueDate        = entry.dueDate;
      _editingEntry   = entry;
    });
  }

  void _clearForm() {
    _title.clear(); _targetSize.clear(); _indicator.clear(); _amount.clear();
    setState(() {
      _approvalStatus = 'Pending';
      _viewSection    = 'HRD';
      _approvedDate   = null;
      _dueDate        = null;
      _editingEntry   = null;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _targetSize.dispose();
    _indicator.dispose();
    _amount.dispose();
    _search.dispose();
    _hScrollController.dispose();
    _vScrollController.dispose();
    super.dispose();
  }

  // ─── Date Pickers ─────────────────────────────────────────────────────────

  Future<void> _pickDueDate() async {
    final initial = _dueDate != null
        ? DateTime.tryParse(_dueDate!) ?? DateTime.now()
        : DateTime.now();
    final picked = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(2020), lastDate: DateTime(2040),
      helpText: 'Select Due Date',
    );
    if (picked != null) setState(() => _dueDate = picked.toIso8601String().substring(0, 10));
  }

  Future<void> _pickApprovedDate() async {
    final initial = _approvedDate != null
        ? DateTime.tryParse(_approvedDate!) ?? DateTime.now()
        : DateTime.now();
    final picked = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(2020), lastDate: DateTime(2040),
      helpText: 'Select Approval Date',
    );
    if (picked != null) setState(() => _approvedDate = picked.toIso8601String().substring(0, 10));
  }

  // ─── Add / Update ─────────────────────────────────────────────────────────

  Future<void> _submitEntry() async {
    if (_title.text.trim().isEmpty) {
      _showSnack('Title cannot be empty.', isError: true); return;
    }
    final parsedAmount = double.tryParse(_amount.text.replaceAll(',', ''));
    if (parsedAmount == null || parsedAmount < 0) {
      _showSnack('Please enter a valid amount.', isError: true); return;
    }

    String? resolvedApprovedDate = _approvedDate;
    if (_approvalStatus == 'Approved' && resolvedApprovedDate == null) {
      resolvedApprovedDate = DateTime.now().toIso8601String().substring(0, 10);
    }
    if (_approvalStatus != 'Approved') resolvedApprovedDate = null;

    if (_editingEntry != null) {
      final updated = _editingEntry!.copyWith(
        title: _title.text.trim(), targetSize: _targetSize.text.trim(),
        indicator: _indicator.text.trim(), year: _selectedYear,
        fundType: _fundType, viewSection: _viewSection, amount: parsedAmount,
        approvalStatus: _approvalStatus, approvedDate: resolvedApprovedDate,
        clearApprovedDate: resolvedApprovedDate == null,
        dueDate: _dueDate, clearDueDate: _dueDate == null,
      );
      await widget.appState.updateWFP(updated);
      _showSnack('WFP entry updated successfully.');
    } else {
      final duplicate = widget.appState.wfpEntries.any(
        (e) => e.title.toLowerCase() == _title.text.trim().toLowerCase());
      if (duplicate) {
        _showSnack('A WFP entry with this title already exists.', isError: true);
        return;
      }
      final id = await widget.appState.generateWFPId(_selectedYear);
      final entry = WFPEntry(
        id: id, title: _title.text.trim(), targetSize: _targetSize.text.trim(),
        indicator: _indicator.text.trim(), year: _selectedYear,
        fundType: _fundType, viewSection: _viewSection, amount: parsedAmount,
        approvalStatus: _approvalStatus, approvedDate: resolvedApprovedDate,
        dueDate: _dueDate,
      );
      await widget.appState.addWFP(entry);
      _showSnack('WFP entry added: $id');
    }
    _clearForm();
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(WFPEntry entry) async {
    final activityCount = await widget.appState.getActivityCountForWFP(entry.id);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Recycle Bin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete "${entry.title}" (${entry.id})?'),
            const SizedBox(height: 12),
            if (activityCount > 0)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'This will also delete $activityCount linked budget '
                    '${activityCount == 1 ? 'activity' : 'activities'}. '
                    'The entry will be moved to the Recycle Bin.',
                    style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
                  )),
                ]),
              )
            else
              Text('This entry has no linked activities. It will be moved to the Recycle Bin.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Move to Bin'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.appState.softDeleteWFP(entry.id);
      if (mounted) _showSnack('Moved to Recycle Bin: ${entry.id}');
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
    ));
  }

  Color _approvalColor(String status) {
    switch (status) {
      case 'Approved': return Colors.green.shade600;
      case 'Rejected': return Colors.red.shade600;
      default:         return Colors.orange.shade600;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final isLoading = widget.appState.isLoading;

        return ScrollConfiguration(
          behavior: _NoScrollbarBehavior(),
          child: Scrollbar(
            controller: _vScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                controller: _vScrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Page header ──────────────────────────────────────
                    const Text('WFP Management',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                          color: Color(0xff2F3E46))),
                    const SizedBox(height: 4),
                    Text('Create, manage, and track Work and Financial Plan entries.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),

                    const SizedBox(height: 20),

                    // ── Form card ────────────────────────────────────────
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _editingEntry != null ? 'Edit WFP Entry' : 'Add WFP Entry',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: _editingEntry != null
                                      ? 'You are editing an existing WFP entry. Make changes and press "Save Changes" to confirm.'
                                      : 'Fill in the fields below and press "Add WFP Entry" to create a new Work and Financial Plan record.',
                                  preferBelow: false,
                                  waitDuration: const Duration(milliseconds: 300),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2F3E46),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                                  child: Icon(Icons.info_outline_rounded,
                                    size: 16, color: Colors.grey.shade400),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // ── Row 1: Title, Target Size, Indicator ─────
                            LayoutBuilder(builder: (context, c) {
                              final narrow = c.maxWidth < 600;

                              final titleField = _TooltipField(
                                tooltip: 'Enter the full official name of the program or project.\nExample: "Special Education Fund – Training"',
                                child: TextField(
                                  controller: _title,
                                  decoration: InputDecoration(
                                    labelText: 'Program Title *',
                                    hintText: 'e.g. In-Service Training for Teachers',
                                    helperText: 'Required. Must be unique across all WFP entries.',
                                    prefixIcon: const Icon(Icons.title_rounded, size: 18),
                                    suffixIcon: Tooltip(
                                      message: 'The official program or project title as it appears in the approved WFP document.',
                                      child: Icon(Icons.help_outline_rounded,
                                        size: 16, color: Colors.grey.shade400),
                                    ),
                                  ),
                                ),
                              );

                              final targetSizeField = _TooltipField(
                                tooltip: 'Specify the number or scope of beneficiaries/outputs.\nExamples: "500 Teachers", "3 Schools", "1 Batch"',
                                child: TextField(
                                  controller: _targetSize,
                                  decoration: InputDecoration(
                                    labelText: 'Target Size',
                                    hintText: 'e.g. 120 Teachers',
                                    helperText: 'Number of beneficiaries or output units.',
                                    prefixIcon: const Icon(Icons.group_outlined, size: 18),
                                    suffixIcon: Tooltip(
                                      message: 'How many people or units this program targets. Leave blank if not applicable.',
                                      child: Icon(Icons.help_outline_rounded,
                                        size: 16, color: Colors.grey.shade400),
                                    ),
                                  ),
                                ),
                              );

                              final indicatorField = _TooltipField(
                                tooltip: 'Describe the measurable outcome or success indicator.\nExample: "80% of trainees pass post-assessment"',
                                child: TextField(
                                  controller: _indicator,
                                  decoration: InputDecoration(
                                    labelText: 'Indicator / Details',
                                    hintText: 'e.g. No. of teachers trained',
                                    helperText: 'Performance indicator or relevant details.',
                                    prefixIcon: const Icon(Icons.track_changes_rounded, size: 18),
                                    suffixIcon: Tooltip(
                                      message: 'The performance indicator used to measure accomplishment of this program.',
                                      child: Icon(Icons.help_outline_rounded,
                                        size: 16, color: Colors.grey.shade400),
                                    ),
                                  ),
                                ),
                              );

                              if (narrow) {
                                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  titleField,
                                  const SizedBox(height: 10),
                                  targetSizeField,
                                  const SizedBox(height: 10),
                                  indicatorField,
                                ]);
                              }
                              return Row(children: [
                                Expanded(flex: 3, child: titleField),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: targetSizeField),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: indicatorField),
                              ]);
                            }),

                            const SizedBox(height: 14),

                            // ── Row 2: Year, Fund Type, Section, Amount ──
                            LayoutBuilder(builder: (context, c) {
                              final narrow = c.maxWidth < 600;

                              final yearDd = _TooltipField(
                                tooltip: 'Select the calendar year this WFP entry covers.\nFiscal years span two calendar years (e.g. FY 2026–2027).',
                                child: DropdownButtonFormField<int>(
                                  // ignore: deprecated_member_use
                                  value: _selectedYear,
                                  decoration: const InputDecoration(
                                    labelText: 'Year',
                                    prefixIcon: Icon(Icons.calendar_month_outlined, size: 18),
                                  ),
                                  items: List.generate(10, (i) {
                                    final y = 2026 + i;
                                    return DropdownMenuItem(value: y, child: Text(y.toString()));
                                  }),
                                  onChanged: (v) => setState(() => _selectedYear = v!),
                                ),
                              );

                              final fundDd = _TooltipField(
                                tooltip: _fundTypeHints[_fundType] ??
                                    'Select the budget fund source for this WFP entry.',
                                child: DropdownButtonFormField<String>(
                                  // ignore: deprecated_member_use
                                  value: _fundType,
                                  decoration: const InputDecoration(
                                    labelText: 'Fund Type',
                                    prefixIcon: Icon(Icons.account_balance_outlined, size: 18),
                                  ),
                                  items: _fundTypes.map((f) => DropdownMenuItem(
                                    value: f,
                                    child: Tooltip(
                                      message: _fundTypeHints[f] ?? f,
                                      preferBelow: false,
                                      waitDuration: const Duration(milliseconds: 300),
                                      child: Text(f),
                                    ),
                                  )).toList(),
                                  onChanged: (v) => setState(() => _fundType = v!),
                                ),
                              );

                              final sectionDd = _TooltipField(
                                tooltip: _sectionHints[_viewSection] ??
                                    'Select the division or section responsible for this program.',
                                child: DropdownButtonFormField<String>(
                                  // ignore: deprecated_member_use
                                  value: _viewSection,
                                  decoration: const InputDecoration(
                                    labelText: 'View Section',
                                    prefixIcon: Icon(Icons.domain_outlined, size: 18),
                                  ),
                                  items: _sections.map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Tooltip(
                                      message: _sectionHints[s] ?? s,
                                      preferBelow: false,
                                      waitDuration: const Duration(milliseconds: 300),
                                      child: Text(s),
                                    ),
                                  )).toList(),
                                  onChanged: (v) => setState(() => _viewSection = v!),
                                ),
                              );

                              final amountField = _TooltipField(
                                tooltip: 'Enter the total approved budget amount in Philippine Peso (₱).\nDo not include commas — they are formatted automatically.',
                                child: TextField(
                                  controller: _amount,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [MoneyInputFormatter(decimalRange: 2)],
                                  decoration: InputDecoration(
                                    labelText: 'Amount (₱) *',
                                    hintText: '0.00',
                                    helperText: 'Total approved budget in Philippine Peso.',
                                    prefixText: '₱ ',
                                    prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                                    suffixIcon: Tooltip(
                                      message: 'The total allotment or appropriation for this WFP entry. Required.',
                                      child: Icon(Icons.help_outline_rounded,
                                        size: 16, color: Colors.grey.shade400),
                                    ),
                                  ),
                                ),
                              );

                              if (narrow) {
                                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  Row(children: [
                                    Expanded(child: yearDd),
                                    const SizedBox(width: 12),
                                    Expanded(child: fundDd),
                                  ]),
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    Expanded(child: sectionDd),
                                    const SizedBox(width: 12),
                                    Expanded(child: amountField),
                                  ]),
                                ]);
                              }
                              return Row(children: [
                                Expanded(child: yearDd), const SizedBox(width: 12),
                                Expanded(child: fundDd), const SizedBox(width: 12),
                                Expanded(child: sectionDd), const SizedBox(width: 12),
                                Expanded(child: amountField),
                              ]);
                            }),

                            const SizedBox(height: 14),

                            // ── Row 3: Approval Status, Approved Date, Due Date ──
                            LayoutBuilder(builder: (context, c) {
                              final approvalDd = _TooltipField(
                                tooltip: 'Set the current approval lifecycle status of this WFP entry.\n'
                                    '• Pending – awaiting review\n'
                                    '• Approved – officially approved (sets approval date)\n'
                                    '• Rejected – not approved',
                                child: DropdownButtonFormField<String>(
                                  // ignore: deprecated_member_use
                                  value: _approvalStatus,
                                  decoration: InputDecoration(
                                    labelText: 'Approval Status',
                                    labelStyle: TextStyle(color: _approvalColor(_approvalStatus)),
                                    prefixIcon: Icon(
                                      _approvalStatus == 'Approved'
                                          ? Icons.check_circle_outline
                                          : _approvalStatus == 'Rejected'
                                              ? Icons.cancel_outlined
                                              : Icons.hourglass_empty_rounded,
                                      size: 18,
                                      color: _approvalColor(_approvalStatus),
                                    ),
                                  ),
                                  items: _approvalOptions.map((s) {
                                    final color = _approvalColor(s);
                                    return DropdownMenuItem(
                                      value: s,
                                      child: Tooltip(
                                        message: s == 'Pending'
                                            ? 'Awaiting review or approval from authorities.'
                                            : s == 'Approved'
                                                ? 'This WFP entry has been officially approved. Setting this will record today as the approval date.'
                                                : 'This WFP entry was reviewed and rejected.',
                                        preferBelow: false,
                                        waitDuration: const Duration(milliseconds: 300),
                                        child: Row(children: [
                                          Container(
                                            width: 10, height: 10,
                                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(s, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                                        ]),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (v) => setState(() {
                                    _approvalStatus = v!;
                                    if (v == 'Approved' && _approvedDate == null) {
                                      _approvedDate = DateTime.now().toIso8601String().substring(0, 10);
                                    }
                                    if (v != 'Approved') _approvedDate = null;
                                  }),
                                ),
                              );

                              final approvedDateField = Tooltip(
                                message: _approvalStatus == 'Approved'
                                    ? 'Tap to change the date this WFP entry was officially approved.\nDefaults to today when status is set to Approved.'
                                    : 'Approval date is only available when status is set to "Approved".',
                                preferBelow: false,
                                waitDuration: const Duration(milliseconds: 400),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2F3E46),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                                child: InkWell(
                                  onTap: _approvalStatus == 'Approved' ? _pickApprovedDate : null,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Approved Date',
                                      prefixIcon: Icon(
                                        Icons.event_available_outlined,
                                        size: 18,
                                        color: _approvalStatus == 'Approved'
                                            ? Colors.green.shade600
                                            : Colors.grey.shade400,
                                      ),
                                      suffixIcon: const Icon(Icons.calendar_today, size: 16),
                                      enabled: _approvalStatus == 'Approved',
                                    ),
                                    child: Text(
                                      _approvedDate ?? (_approvalStatus == 'Approved' ? 'Tap to set' : '—'),
                                      style: TextStyle(
                                        color: _approvalStatus == 'Approved'
                                            ? Colors.black87 : Colors.grey.shade400,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              );

                              final dueDateField = Tooltip(
                                message: 'Tap to set the deadline or end date for this WFP entry.\n'
                                    'Entries due within the warning window will appear in the Dashboard and Deadlines page.\n'
                                    'Click the × icon to clear the date.',
                                preferBelow: false,
                                waitDuration: const Duration(milliseconds: 400),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2F3E46),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                                child: InkWell(
                                  onTap: _pickDueDate,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Due Date',
                                      prefixIcon: Icon(Icons.event_outlined, size: 18),
                                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                                    ),
                                    child: Row(children: [
                                      Expanded(child: Text(
                                        _dueDate ?? 'Tap to set',
                                        style: TextStyle(
                                          color: _dueDate != null ? Colors.black87 : Colors.grey.shade400,
                                          fontSize: 14,
                                        ),
                                      )),
                                      if (_dueDate != null)
                                        Tooltip(
                                          message: 'Clear due date',
                                          child: GestureDetector(
                                            onTap: () => setState(() => _dueDate = null),
                                            child: Icon(Icons.clear, size: 16, color: Colors.grey.shade500),
                                          ),
                                        ),
                                    ]),
                                  ),
                                ),
                              );

                              if (c.maxWidth < 600) {
                                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  approvalDd, const SizedBox(height: 10),
                                  Row(children: [
                                    Expanded(child: approvedDateField),
                                    const SizedBox(width: 12),
                                    Expanded(child: dueDateField),
                                  ]),
                                ]);
                              }
                              return Row(children: [
                                Expanded(child: approvalDd), const SizedBox(width: 12),
                                Expanded(child: approvedDateField), const SizedBox(width: 12),
                                Expanded(child: dueDateField),
                              ]);
                            }),

                            const SizedBox(height: 16),

                            // ── Form action buttons ──────────────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (_editingEntry != null) ...[
                                  Tooltip(
                                    message: 'Discard all changes and reset the form.',
                                    child: OutlinedButton.icon(
                                      onPressed: _clearForm,
                                      icon: const Icon(Icons.cancel_outlined, size: 16),
                                      label: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Tooltip(
                                  message: _editingEntry != null
                                      ? 'Save all changes to this WFP entry.'
                                      : 'Validate and add this WFP entry to the system.',
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xff2F3E46),
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: Icon(_editingEntry != null ? Icons.save : Icons.add),
                                    label: Text(_editingEntry != null ? 'Save Changes' : 'Add WFP Entry'),
                                    onPressed: isLoading ? null : _submitEntry,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Search + Entries Per Page ────────────────────────
                    LayoutBuilder(builder: (context, c) {
                      final searchField = Tooltip(
                        message: 'Search across WFP ID, title, fund type, year, target size, indicator, section, and approval status.\nPress Enter or type to filter results instantly.',
                        preferBelow: false,
                        waitDuration: const Duration(milliseconds: 500),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F3E46),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                        child: TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Search entries…',
                            hintText: 'Title, ID, fund type, year, section, approval status…',
                          ),
                          onChanged: (_) => setState(() => _currentPage = 0),
                        ),
                      );

                      final paginationControls = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Show:', style: TextStyle(color: Colors.grey)),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Choose how many WFP entries are shown per page in the table below.',
                            preferBelow: false,
                            waitDuration: const Duration(milliseconds: 400),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2F3E46),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                            child: DropdownButton<int>(
                              value: _rowsPerPage,
                              items: _rowsPerPageOptions
                                  .map((n) => DropdownMenuItem(value: n, child: Text('$n entries')))
                                  .toList(),
                              onChanged: (v) => setState(() { _rowsPerPage = v!; _currentPage = 0; }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('${_filtered.length} result${_filtered.length == 1 ? '' : 's'}',
                            style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      );

                      if (c.maxWidth < 600) {
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          searchField, const SizedBox(height: 8), paginationControls,
                        ]);
                      }
                      return Row(children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 16),
                        paginationControls,
                      ]);
                    }),

                    const SizedBox(height: 16),

                    // ── Table toolbar (zoom controls) ─────────────────────
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      const Text('Zoom', style: TextStyle(color: Colors.grey)),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Zoom out – make the table smaller.',
                        child: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _zoom > _minZoom ? () {
                            setState(() => _zoom = (_zoom - _zoomStep).clamp(_minZoom, _maxZoom));
                            _clampHorizontalScroll();
                          } : null,
                        ),
                      ),
                      Tooltip(
                        message: 'Current zoom level (${(_zoom / _baselineZoom * 100).round()}%). Click the reset button to restore default.',
                        child: Text('${(_zoom / _baselineZoom * 100).round()}%'),
                      ),
                      Tooltip(
                        message: 'Reset zoom to default (100%).',
                        child: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () {
                            setState(() => _zoom = _baselineZoom);
                            _clampHorizontalScroll();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Zoom in – make the table larger. A horizontal scrollbar appears when zoomed in.',
                        child: IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: _zoom < _maxZoom ? () {
                            setState(() => _zoom = (_zoom + _zoomStep).clamp(_minZoom, _maxZoom));
                            _clampHorizontalScroll();
                          } : null,
                        ),
                      ),
                    ]),

                    // ── Data Table ───────────────────────────────────────
                    LayoutBuilder(builder: (context, constraints) {
                      final baseWidth = constraints.maxWidth < _tableMinWidth
                          ? _tableMinWidth
                          : constraints.maxWidth;

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
                          child: Builder(builder: (ctx) {
                            final useExpandedLayout = _zoom > _baselineZoom;

                            // Shared columns definition
                            final columns = <DataColumn2>[
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'Unique system-generated identifier for each WFP entry.\nFormat: WFP-YYYY-NNNN',
                                  child: _HintLabel('WFP ID', hint: 'Unique system-generated identifier'),
                                ),
                                size: ColumnSize.M,
                                onSort: _onSort,
                              ),
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'The official program or project title as recorded in the WFP.',
                                  child: _HintLabel('Title', hint: 'Program or project title'),
                                ),
                                size: ColumnSize.L,
                                onSort: _onSort,
                              ),
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'Number or scope of beneficiaries/outputs targeted by this program.',
                                  child: _HintLabel('Target Size', hint: 'Beneficiaries or output count'),
                                ),
                                size: ColumnSize.M,
                                onSort: _onSort,
                              ),
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'Budget fund source classification for this WFP entry.\nHover over a value in the table for its full name.',
                                  child: _HintLabel('Fund Type', hint: 'Budget fund source'),
                                ),
                                size: ColumnSize.S,
                                onSort: _onSort,
                              ),
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'The division or section responsible for implementing this program.',
                                  child: _HintLabel('Section', hint: 'Implementing division'),
                                ),
                                size: ColumnSize.S,
                                onSort: _onSort,
                              ),
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'Calendar year this WFP entry was planned for.',
                                  child: _HintLabel('Year', hint: 'Planning year'),
                                ),
                                size: ColumnSize.S,
                                numeric: true,
                                onSort: _onSort,
                              ),
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'Total approved budget allotment for this WFP entry in Philippine Peso (₱).',
                                  child: _HintLabel('Amount', hint: 'Approved budget in ₱'),
                                ),
                                size: ColumnSize.M,
                                numeric: true,
                                onSort: _onSort,
                              ),
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'Current approval lifecycle status:\n• Pending – under review\n• Approved – officially approved\n• Rejected – not approved',
                                  child: _HintLabel('Approval', hint: 'Approval lifecycle status'),
                                ),
                                size: ColumnSize.S,
                                onSort: _onSort,
                              ),
                              DataColumn2(
                                label: const Tooltip(
                                  message: 'Deadline or end date for this WFP entry.\nEntries due within the warning window are flagged with a ⚠ icon.',
                                  child: _HintLabel('Due Date', hint: 'Program deadline or end date'),
                                ),
                                size: ColumnSize.S,
                                onSort: _onSort,
                              ),
                              const DataColumn2(
                                label: Tooltip(
                                  message: 'Edit or delete this WFP entry.',
                                  child: Text('Actions'),
                                ),
                                size: ColumnSize.S,
                              ),
                            ];

                            // Shared row builder
                            List<DataRow2> buildRows() {
                              return _pagedRows.asMap().entries.map((entry) {
                                final i = entry.key;
                                final e = entry.value;
                                final isEditing = _editingEntry?.id == e.id;
                                final isPending = e.approvalStatus == 'Pending';
                                final approvalClr = _approvalColor(e.approvalStatus);
                                final daysUntil = e.daysUntilDue;

                                return DataRow2(
                                  color: WidgetStateProperty.resolveWith((_) {
                                    if (isEditing) return Colors.blue.shade50;
                                    if (isPending) return Colors.orange.shade50;
                                    return i.isEven ? Colors.white : Colors.grey.shade50;
                                  }),
                                  cells: [
                                    // WFP ID
                                    DataCell(Tooltip(
                                      message: 'WFP ID: ${e.id}',
                                      child: Row(children: [
                                        if (isPending)
                                          Tooltip(
                                            message: 'This entry is still pending approval.',
                                            child: Container(
                                              width: 3, height: 28,
                                              margin: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade400,
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                        Text(e.id,
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                      ]),
                                    )),

                                    // Title
                                    DataCell(Tooltip(
                                      message: e.title,
                                      child: Text(e.title),
                                    )),

                                    // Target Size
                                    DataCell(Tooltip(
                                      message: e.targetSize.isEmpty
                                          ? 'No target size specified.'
                                          : 'Target: ${e.targetSize}',
                                      child: Text(e.targetSize),
                                    )),

                                    // Fund Type
                                    DataCell(Tooltip(
                                      message: _fundTypeHints[e.fundType] ?? e.fundType,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xff2F3E46).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(e.fundType,
                                          style: const TextStyle(fontSize: 12)),
                                      ),
                                    )),

                                    // Section
                                    DataCell(Tooltip(
                                      message: _sectionHints[e.viewSection] ?? e.viewSection,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xff3A7CA5).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(e.viewSection,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xff3A7CA5),
                                            fontWeight: FontWeight.w600,
                                          )),
                                      ),
                                    )),

                                    // Year
                                    DataCell(Tooltip(
                                      message: 'Planning year: ${e.year}',
                                      child: Text(e.year.toString()),
                                    )),

                                    // Amount
                                    DataCell(Tooltip(
                                      message: 'Total budget: ${CurrencyFormatter.format(e.amount)}',
                                      child: Text(CurrencyFormatter.format(e.amount)),
                                    )),

                                    // Approval Status
                                    DataCell(Tooltip(
                                      message: e.approvalStatus == 'Approved'
                                          ? 'Approved on: ${e.approvedDate ?? "date not set"}'
                                          : e.approvalStatus == 'Rejected'
                                              ? 'This entry was rejected.'
                                              : 'Awaiting approval.',
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: approvalClr.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(e.approvalStatus,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: approvalClr,
                                            fontWeight: FontWeight.w600,
                                          )),
                                      ),
                                    )),

                                    // Due Date
                                    DataCell(e.dueDate == null
                                        ? Tooltip(
                                            message: 'No due date set for this entry.',
                                            child: Text('—',
                                              style: TextStyle(color: Colors.grey.shade400)),
                                          )
                                        : Tooltip(
                                            message: daysUntil == null
                                                ? 'Due: ${e.dueDate}'
                                                : daysUntil < 0
                                                    ? 'OVERDUE by ${-daysUntil} day${-daysUntil == 1 ? '' : 's'}!'
                                                    : daysUntil == 0
                                                        ? 'Due TODAY!'
                                                        : 'Due in $daysUntil day${daysUntil == 1 ? '' : 's'} (${e.dueDate})',
                                            child: Row(children: [
                                              if (daysUntil != null && daysUntil <= 7)
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 4),
                                                  child: Icon(Icons.warning_amber_rounded,
                                                    size: 14,
                                                    color: daysUntil < 0 ? Colors.red : Colors.orange),
                                                ),
                                              Text(e.dueDate!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: daysUntil != null && daysUntil < 0
                                                      ? Colors.red.shade600
                                                      : Colors.black87,
                                                )),
                                            ]),
                                          )),

                                    // Actions
                                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                      Tooltip(
                                        message: 'Edit this WFP entry — loads its data into the form above.',
                                        child: IconButton(
                                          icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                                          onPressed: () => _loadEntryIntoForm(e),
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Move this WFP entry to the Recycle Bin.\nLinked budget activities will also be removed.',
                                        child: IconButton(
                                          icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                                          onPressed: () => _confirmDelete(e),
                                        ),
                                      ),
                                    ])),
                                  ],
                                );
                              }).toList();
                            }

                            if (useExpandedLayout) {
                              return SizedBox(
                                width: baseWidth * _zoom,
                                height: _tableHeight * _zoom,
                                child: DataTable2(
                                  minWidth: _tableMinWidth,
                                  sortColumnIndex: _sortColumnIndex,
                                  sortAscending: _sortAscending,
                                  headingRowColor: WidgetStateProperty.all(const Color(0xff2F3E46)),
                                  headingTextStyle: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold),
                                  columnSpacing: 16,
                                  horizontalMargin: 12,
                                  columns: columns,
                                  rows: buildRows(),
                                ),
                              );
                            } else {
                              return SizedBox(
                                width: baseWidth,
                                height: _tableHeight,
                                child: Transform.scale(
                                  scale: _zoom,
                                  alignment: Alignment.topLeft,
                                  child: SizedBox(
                                    width: baseWidth,
                                    height: _tableHeight,
                                    child: DataTable2(
                                      minWidth: _tableMinWidth,
                                      sortColumnIndex: _sortColumnIndex,
                                      sortAscending: _sortAscending,
                                      headingRowColor: WidgetStateProperty.all(const Color(0xff2F3E46)),
                                      headingTextStyle: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.bold),
                                      columnSpacing: 16,
                                      horizontalMargin: 12,
                                      columns: columns,
                                      rows: buildRows(),
                                    ),
                                  ),
                                ),
                              );
                            }
                          }),
                        ),
                      );
                    }),

                    // ── Pagination ───────────────────────────────────────
                    PaginationBar(
                      currentPage:   _currentPage,
                      totalPages:    _totalPages,
                      totalItems:    _filtered.length,
                      rowsPerPage:   _rowsPerPage,
                      onPageChanged: (p) => setState(() => _currentPage = p),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}