import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';
import '../utils/currency_formatter.dart';

// ─── Sort options ──────────────────────────────────────────────────────────────
enum _SortField { deletedAt, title, year, amount, fundType, activityCount }

class RecycleBinPage extends StatefulWidget {
  final AppState appState;
  const RecycleBinPage({super.key, required this.appState});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  // ── Data ────────────────────────────────────────────────────────────────────
  List<_BinEntry> _entries = [];
  bool _loading = true;
  String? _loadError;

  // ── Search / filter ─────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _filterFundType;
  String? _filterSection;

  // ── Sort ────────────────────────────────────────────────────────────────────
  _SortField _sortField = _SortField.deletedAt;
  bool _sortAsc = false; // newest-first by default

  // ── Pagination ──────────────────────────────────────────────────────────────
  int _page = 0;
  int _rowsPerPage = 10;
  static const List<int> _perPageOptions = [5, 10, 25, 50];

  // ── Expanded card ids ────────────────────────────────────────────────────────
  final Set<int> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final raw = await widget.appState.getRecycleBinEntries();
      final parsed = <_BinEntry>[];
      for (final row in raw) {
        final entry = _BinEntry.tryParse(row);
        if (entry != null) parsed.add(entry);
      }
      if (mounted) setState(() { _entries = parsed; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _loading = false; });
    }
  }

  // ─── Derived lists ────────────────────────────────────────────────────────

  List<_BinEntry> get _filtered {
    final q = _search.toLowerCase();
    return _entries.where((e) {
      final matchSearch = q.isEmpty ||
          e.displayId.toLowerCase().contains(q) ||
          e.displayTitle.toLowerCase().contains(q) ||
          e.displayFundType.toLowerCase().contains(q) ||
          (e.isWFP ? (e.wfp?.viewSection ?? '').toLowerCase().contains(q) : false) ||
          (e.isActivity ? (e.parentWfpId ?? '').toLowerCase().contains(q) : false) ||
          e.displayYear.toString().contains(q);
      final matchFund = _filterFundType == null ||
          (e.isWFP && e.wfp?.fundType == _filterFundType) ||
          e.isActivity;
      final matchSection = _filterSection == null ||
          (e.isWFP && e.wfp?.viewSection == _filterSection) ||
          e.isActivity;
      return matchSearch && matchFund && matchSection;
    }).toList()
      ..sort(_compare);
  }

  int _compare(_BinEntry a, _BinEntry b) {
    int cmp;
    switch (_sortField) {
      case _SortField.deletedAt:     cmp = a.deletedAt.compareTo(b.deletedAt); break;
      case _SortField.title:         cmp = a.displayTitle.compareTo(b.displayTitle); break;
      case _SortField.year:          cmp = a.displayYear.compareTo(b.displayYear); break;
      case _SortField.amount:        cmp = a.displayAmount.compareTo(b.displayAmount); break;
      case _SortField.fundType:      cmp = a.displayFundType.compareTo(b.displayFundType); break;
      case _SortField.activityCount: cmp = a.activities.length.compareTo(b.activities.length); break;
    }
    return _sortAsc ? cmp : -cmp;
  }

  List<_BinEntry> get _paged {
    final all   = _filtered;
    final start = _page * _rowsPerPage;
    if (start >= all.length) return [];
    return all.sublist(start, (start + _rowsPerPage).clamp(0, all.length));
  }

  int get _totalPages {
    final n = _filtered.length;
    return n == 0 ? 1 : (n / _rowsPerPage).ceil();
  }

  List<String> get _allFundTypes {
    final s = _entries
        .where((e) => e.isWFP && e.wfp != null)
        .map((e) => e.wfp!.fundType)
        .toSet()
        .toList()..sort();
    return s;
  }

  List<String> get _allSections {
    final s = _entries
        .where((e) => e.isWFP && e.wfp != null)
        .map((e) => e.wfp!.viewSection)
        .toSet()
        .toList()..sort();
    return s;
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _restore(_BinEntry entry) async {
    if (entry.isActivity) {
      await _restoreActivity(entry);
    } else {
      await _restoreWFP(entry);
    }
  }

  Future<void> _restoreWFP(_BinEntry entry) async {
    final wfp      = entry.wfp!;
    final actCount = entry.activities.length;
    final confirmed = await _showConfirm(
      title: 'Restore WFP Entry',
      icon: Icons.restore,
      iconColor: const Color(0xff2F3E46),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Restore "${wfp.title}"?',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _infoBox(
            color: const Color(0xff3A7CA5),
            icon: Icons.info_outline,
            text: actCount > 0
                ? 'This will also restore $actCount linked budget '
                  '${actCount == 1 ? 'activity' : 'activities'}.'
                : 'This entry has no linked activities.',
          ),
        ],
      ),
      confirmLabel: 'Restore',
      confirmColor: const Color(0xff2F3E46),
    );
    if (confirmed != true) return;

    final ok = await widget.appState.restoreFromBin(
        entry.binId, wfp, entry.activities);
    if (!mounted) return;
    if (ok) {
      _showSnack('Restored: ${wfp.id}', isSuccess: true);
      _expandedIds.remove(entry.binId);
      _load();
    } else {
      _showSnack(
        'Cannot restore — an entry with ID ${wfp.id} already exists in the live data.',
        isError: true,
      );
    }
  }

  Future<void> _restoreActivity(_BinEntry entry) async {
    final act = entry.activity!;
    final confirmed = await _showConfirm(
      title: 'Restore Activity',
      icon: Icons.restore,
      iconColor: const Color(0xff2F3E46),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Restore "${act.name}"?',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _infoBox(
            color: const Color(0xff3A7CA5),
            icon: Icons.info_outline,
            text: 'This activity will be restored under WFP: ${act.wfpId}.',
          ),
        ],
      ),
      confirmLabel: 'Restore',
      confirmColor: const Color(0xff2F3E46),
    );
    if (confirmed != true) return;

    final ok = await widget.appState.restoreActivityFromBin(entry.binId, act);
    if (!mounted) return;
    if (ok) {
      _showSnack('Restored: ${act.id}', isSuccess: true);
      _expandedIds.remove(entry.binId);
      _load();
    } else {
      _showSnack(
        'Cannot restore — either the parent WFP (${act.wfpId}) no longer exists '
        'or an activity with ID ${act.id} already exists.',
        isError: true,
      );
    }
  }

  Future<void> _permanentDelete(_BinEntry entry) async {
    final confirmed = await _showConfirm(
      title: 'Delete Forever',
      icon: Icons.delete_forever,
      iconColor: Colors.red.shade600,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Permanently delete "${entry.displayTitle}"?',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _infoBox(
            color: Colors.red.shade600,
            icon: Icons.warning_amber_rounded,
            text: 'This cannot be undone. All data will be gone forever.',
          ),
        ],
      ),
      confirmLabel: 'Delete Forever',
      confirmColor: Colors.red.shade600,
    );
    if (confirmed != true) return;
    await widget.appState.permanentlyDeleteFromBin(entry.binId);
    if (mounted) {
      _showSnack('Permanently deleted.');
      _expandedIds.remove(entry.binId);
      _load();
    }
  }

  Future<void> _emptyBin() async {
    if (_entries.isEmpty) return;
    final confirmed = await _showConfirm(
      title: 'Empty Recycle Bin',
      icon: Icons.delete_sweep_outlined,
      iconColor: Colors.red.shade600,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Permanently delete all ${_entries.length} '
            'item${_entries.length == 1 ? '' : 's'} in the bin?',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _infoBox(
            color: Colors.red.shade600,
            icon: Icons.warning_amber_rounded,
            text: 'This cannot be undone.',
          ),
        ],
      ),
      confirmLabel: 'Empty Bin',
      confirmColor: Colors.red.shade600,
    );
    if (confirmed != true) return;
    await widget.appState.emptyRecycleBin();
    if (mounted) { _showSnack('Recycle bin emptied.'); _load(); }
  }

  Future<bool?> _showConfirm({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget body,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16)),
        ]),
        content: body,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError
          ? Colors.red.shade600
          : isSuccess
              ? Colors.green.shade600
              : const Color(0xff2F3E46),
    ));
  }

  void _setSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = field != _SortField.deletedAt;
      }
      _page = 0;
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total    = filtered.length;
    final start    = total == 0 ? 0 : _page * _rowsPerPage + 1;
    final end      = ((_page + 1) * _rowsPerPage).clamp(0, total);
    final paged    = _paged;

    return Scaffold(
      backgroundColor: const Color(0xffF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xff2F3E46),
        leading: const BackButton(),
        title: Row(children: [
          const Text('Recycle Bin',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color(0xff2F3E46))),
          if (_entries.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text('${_entries.length}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade600)),
            ),
          ],
        ]),
        actions: [
          if (!_loading && _entries.isNotEmpty)
            Tooltip(
              message: 'Empty the recycle bin (permanently delete all items)',
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('Empty Bin'),
                onPressed: _emptyBin,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _errorState()
              : _entries.isEmpty
                  ? _emptyState()
                  : Column(
                      children: [
                        _buildToolbar(),
                        _buildStatsBar(start, end, total),
                        Expanded(
                          child: paged.isEmpty
                              ? _noResultsState()
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                                  itemCount: paged.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, i) => _binCard(paged[i]),
                                ),
                        ),
                        _buildPagination(total),
                      ],
                    ),
    );
  }

  // ─── Toolbar ──────────────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: search + filters
          Row(children: [
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Search by ID, title, fund type, section…',
                    isDense: true,
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() { _search = ''; _page = 0; });
                            })
                        : null,
                  ),
                  onChanged: (v) => setState(() { _search = v; _page = 0; }),
                ),
              ),
            ),
              if (_allFundTypes.length > 1) ...[
              const SizedBox(width: 10),
              _filterDropdown<String?>(
                value: _filterFundType,
                hint: 'Fund Type',
                items: [
                  const DropdownMenuItem(value: null, child: Text('All fund types')),
                  ..._allFundTypes.map((f) =>
                      DropdownMenuItem(value: f, child: Text(f))),
                ],
                onChanged: (v) => setState(() { _filterFundType = v; _page = 0; }),
              ),
            ],
              if (_allSections.length > 1) ...[
              const SizedBox(width: 10),
              _filterDropdown<String?>(
                value: _filterSection,
                hint: 'Section',
                items: [
                  const DropdownMenuItem(value: null, child: Text('All sections')),
                  ..._allSections.map((s) =>
                      DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (v) => setState(() { _filterSection = v; _page = 0; }),
              ),
            ],
          ]),

          const SizedBox(height: 10),

          // Row 2: sort chips
          Row(children: [
            Text('Sort by:',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            _sortChip('Date Deleted', _SortField.deletedAt),
            _sortChip('Title',        _SortField.title),
            _sortChip('Year',         _SortField.year),
            _sortChip('Amount',       _SortField.amount),
            _sortChip('Fund Type',    _SortField.fundType),
            _sortChip('Activities',   _SortField.activityCount),
          ]),
        ],
      ),
    );
  }

  Widget _filterDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: Tooltip(
          message: 'Filter: $hint',
          child: DropdownButton<T>(
            value: value,
            hint: Text(hint, style: const TextStyle(fontSize: 13)),
            isDense: true,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, _SortField field) {
    final active = _sortField == field;
    return Tooltip(
      message: 'Sort by $label',
      child: GestureDetector(
        onTap: () => _setSort(field),
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? const Color(0xff2F3E46) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? const Color(0xff2F3E46) : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.grey.shade600,
                )),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 11, color: Colors.white,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Stats bar ────────────────────────────────────────────────────────────

  Widget _buildStatsBar(int start, int end, int total) {
    final f           = _filtered;
    final wfpEntries  = f.where((e) => e.isWFP).toList();
    final actEntries  = f.where((e) => e.isActivity).toList();
    final totalAmount = wfpEntries.fold<double>(0, (s, e) => s + (e.wfp?.amount ?? 0));
    final totalActs   = wfpEntries.fold<int>(0, (s, e) => s + e.activities.length)
                      + actEntries.length;

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(children: [
        Text('Showing $start–$end of $total item${total == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(width: 16),
        Icon(Icons.account_balance_wallet_outlined,
            size: 13, color: const Color(0xff3A7CA5)),
        const SizedBox(width: 4),
        Text(CurrencyFormatter.format(totalAmount),
          style: const TextStyle(
              fontSize: 12,
              color: Color(0xff3A7CA5),
              fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        Icon(Icons.task_outlined, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text('$totalActs activit${totalActs == 1 ? 'y' : 'ies'}',
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500)),
        const Spacer(),
        Text('Per page:',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(width: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _rowsPerPage,
            isDense: true,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            items: _perPageOptions.map((n) =>
                DropdownMenuItem(value: n, child: Text('$n'))).toList(),
            onChanged: (v) {
              if (v != null) setState(() { _rowsPerPage = v; _page = 0; });
            },
          ),
        ),
      ]),
    );
  }

  // ─── Pagination ───────────────────────────────────────────────────────────

  Widget _buildPagination(int total) {
    final totalPgs = _totalPages;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page), iconSize: 20,
            tooltip: 'First page',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _page > 0 ? () => setState(() => _page = 0) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left), iconSize: 20,
            tooltip: 'Previous page',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _page > 0 ? () => setState(() => _page--) : null,
          ),
          const SizedBox(width: 4),
          ..._buildPageChips(totalPgs),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.chevron_right), iconSize: 20,
            tooltip: 'Next page',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _page < totalPgs - 1
                ? () => setState(() => _page++)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page), iconSize: 20,
            tooltip: 'Last page',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _page < totalPgs - 1
                ? () => setState(() => _page = totalPgs - 1)
                : null,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageChips(int totalPgs) {
    final chips   = <Widget>[];
    bool  gapped  = false;
    for (int i = 0; i < totalPgs; i++) {
      final near = (i - _page).abs() <= 1;
      final edge = i == 0 || i == totalPgs - 1;
      if (!near && !edge) {
        if (!gapped) {
          chips.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('…',
              style: TextStyle(color: Colors.grey.shade500))));
          gapped = true;
        }
        continue;
      }
      gapped = false;
      final active = i == _page;
      chips.add(
        GestureDetector(
          onTap: () => setState(() => _page = i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? const Color(0xff2F3E46) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: active
                    ? const Color(0xff2F3E46)
                    : Colors.grey.shade300),
            ),
            child: Text('${i + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade700,
              )),
          ),
        ),
      );
    }
    return chips;
  }

  // ─── Bin card ─────────────────────────────────────────────────────────────

  Widget _binCard(_BinEntry entry) {
    return entry.isActivity
        ? _buildActivityBinCard(entry)
        : _buildWfpBinCard(entry);
  }

  // ── Shared card shell ─────────────────────────────────────────────────────

  Widget _buildCardShell({
    required _BinEntry entry,
    required Color accentColor,
    required IconData icon,
    required Widget headerContent,
    required Widget expandedContent,
  }) {
    final isExpanded = _expandedIds.contains(entry.binId);
    final daysAgo   = DateTime.now().difference(entry.deletedAt).inDays;
    final daysLabel = daysAgo == 0
        ? 'Today'
        : daysAgo == 1 ? 'Yesterday' : '$daysAgo days ago';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.grey.shade100, blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            onTap: () => setState(() => isExpanded
                ? _expandedIds.remove(entry.binId)
                : _expandedIds.add(entry.binId)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                // Left accent bar
                Container(
                  width: 4, height: 52,
                  decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 14),
                // Icon badge
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 14),
                // Main content
                Expanded(child: headerContent),
                const SizedBox(width: 12),
                // Right: timestamp + action buttons
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(children: [
                      Icon(Icons.schedule, size: 11,
                          color: Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Text(daysLabel,
                          style: TextStyle(fontSize: 11,
                              color: Colors.grey.shade500)),
                    ]),
                    const SizedBox(height: 2),
                    Text(_formatDateTime(entry.deletedAt),
                        style: TextStyle(fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.grey.shade400)),
                    const SizedBox(height: 10),
                    Row(children: [
                      _actionBtn(
                        label: 'Restore',
                        icon: Icons.restore,
                        color: const Color(0xff2F3E46),
                        onTap: () => _restore(entry),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: Icon(Icons.delete_forever,
                            size: 18, color: Colors.red.shade300),
                        tooltip: 'Delete Forever',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 28, minHeight: 28),
                        onPressed: () => _permanentDelete(entry),
                      ),
                    ]),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.grey.shade400, size: 20,
                ),
              ]),
            ),
          ),
          if (isExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12)),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: expandedContent,
            ),
        ],
      ),
    );
  }

  // ── WFP bin card ──────────────────────────────────────────────────────────

  Widget _buildWfpBinCard(_BinEntry entry) {
    final wfp        = entry.wfp!;
    final activities = entry.activities;

    final approvalColor = wfp.approvalStatus == 'Approved'
        ? Colors.green.shade600
        : wfp.approvalStatus == 'Rejected'
            ? Colors.red.shade600
            : Colors.orange.shade600;

    return _buildCardShell(
      entry: entry,
      accentColor: const Color(0xff2F3E46),
      icon: Icons.list_alt_outlined,
      headerContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(wfp.id,
                style: const TextStyle(fontFamily: 'monospace',
                    fontSize: 10, color: Colors.grey)),
            const SizedBox(width: 8),
            _chip(wfp.approvalStatus, approvalColor),
          ]),
          const SizedBox(height: 3),
          Text(wfp.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Wrap(spacing: 5, runSpacing: 4, children: [
            _chip(wfp.fundType,           const Color(0xff2F3E46)),
            _chip(wfp.viewSection,        const Color(0xff3A7CA5)),
            _chip(wfp.year.toString(),    Colors.grey.shade600),
            _chip(CurrencyFormatter.format(wfp.amount),
                const Color(0xff52B788)),
            if (activities.isNotEmpty)
              _chip(
                '${activities.length} '
                '${activities.length == 1 ? 'activity' : 'activities'}',
                Colors.purple.shade400),
          ]),
        ],
      ),
      expandedContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('WFP Details'),
          const SizedBox(height: 10),
          Wrap(spacing: 24, runSpacing: 10, children: [
            _detailItem('Amount',      CurrencyFormatter.format(wfp.amount)),
            _detailItem('Fund Type',   wfp.fundType),
            _detailItem('Section',     wfp.viewSection),
            _detailItem('Year',        wfp.year.toString()),
            _detailItem('Status',      wfp.approvalStatus),
            _detailItem('Approved',    wfp.approvedDate ?? '—'),
            _detailItem('Due Date',    wfp.dueDate ?? '—'),
            _detailItem('Target Size', wfp.targetSize),
          ]),
          const SizedBox(height: 10),
          _detailItemWide('Indicator', wfp.indicator),
          if (activities.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 12),
            _sectionLabel(
              '${activities.length} Budget '
              '${activities.length == 1 ? 'Activity' : 'Activities'}'),
            const SizedBox(height: 8),
            ...activities.map(_activityRow),
          ] else ...[
            const SizedBox(height: 10),
            Text('No linked budget activities.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
        ],
      ),
    );
  }

  // ── Activity bin card ─────────────────────────────────────────────────────

  Widget _buildActivityBinCard(_BinEntry entry) {
    final act = entry.activity!;

    final statusColor = act.status == 'Completed'
        ? Colors.green.shade600
        : act.status == 'Ongoing'
            ? Colors.blue.shade600
            : act.status == 'At Risk'
                ? Colors.red.shade600
                : Colors.grey.shade500;

    return _buildCardShell(
      entry: entry,
      accentColor: const Color(0xff3A7CA5),
      icon: Icons.account_balance_wallet_outlined,
      headerContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(act.id,
                style: const TextStyle(fontFamily: 'monospace',
                    fontSize: 10, color: Colors.grey)),
            const SizedBox(width: 8),
            _chip('Activity', const Color(0xff3A7CA5)),
            const SizedBox(width: 4),
            _chip(act.status, statusColor),
          ]),
          const SizedBox(height: 3),
          Text(act.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Wrap(spacing: 5, runSpacing: 4, children: [
            _chip('WFP: ${act.wfpId}', Colors.grey.shade600),
            _chip(CurrencyFormatter.format(act.total),
                const Color(0xff52B788)),
            if (act.targetDate != null)
              _chip('Target: ${act.targetDate}', Colors.orange.shade600),
          ]),
        ],
      ),
      expandedContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Activity Details'),
          const SizedBox(height: 10),
          Wrap(spacing: 24, runSpacing: 10, children: [
            _detailItem('Activity ID',  act.id),
            _detailItem('Parent WFP',   act.wfpId),
            _detailItem('Total AR',     CurrencyFormatter.format(act.total)),
            _detailItem('Projected',    CurrencyFormatter.format(act.projected)),
            _detailItem('Disbursed',    CurrencyFormatter.format(act.disbursed)),
            _detailItem('Balance',      CurrencyFormatter.format(act.balance)),
            _detailItem('Status',       act.status),
            _detailItem('Target Date',  act.targetDate ?? '—'),
          ]),
          const SizedBox(height: 10),
          _detailItemWide('Name', act.name),
          const SizedBox(height: 10),
          _infoBox(
            color: const Color(0xff3A7CA5),
            icon: Icons.info_outline,
            text: 'Restoring this activity requires its parent WFP '
                '(${act.wfpId}) to still exist in the live data.',
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
          ]),
        ),
      ),
    );
  }

  Widget _activityRow(BudgetActivity a) {
    final statusColor = a.status == 'Completed'
        ? Colors.green.shade600
        : a.status == 'Ongoing'
            ? Colors.blue.shade600
            : Colors.grey.shade500;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.id,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(a.name,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        )),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(CurrencyFormatter.format(a.total),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(a.status,
              style: TextStyle(
                  fontSize: 10,
                  color: statusColor,
                  fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }

  // ─── Empty / error states ─────────────────────────────────────────────────

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
                color: Colors.grey.shade100, shape: BoxShape.circle),
            child: Icon(Icons.delete_outline,
                size: 56, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          const Text('Recycle bin is empty',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xff2F3E46))),
          const SizedBox(height: 8),
          Text('Deleted WFP entries will appear here.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _noResultsState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No entries match your filters.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _search = ''; _searchCtrl.clear();
              _filterFundType = null; _filterSection = null; _page = 0;
            }),
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 16),
          const Text('Failed to load recycle bin',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: Color(0xff2F3E46))),
          const SizedBox(height: 6),
          Text(_loadError ?? '',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff2F3E46),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  // ─── Small helpers ────────────────────────────────────────────────────────

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _sectionLabel(String label) => Text(label,
    style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade500,
        letterSpacing: 0.5));

  Widget _detailItem(String label, String value) {
    return SizedBox(
      width: 148,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
          style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _detailItemWide(String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 80,
        child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
    ]);
  }

  Widget _infoBox({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
          style: TextStyle(fontSize: 12, color: color))),
      ]),
    );
  }

  String _formatDateTime(DateTime dt) {
    final y  = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d  = dt.day.toString().padLeft(2, '0');
    final h  = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d  $h:$mi';
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────

enum _BinEntryType { wfp, activity }

class _BinEntry {
  final int                  binId;
  final _BinEntryType        type;
  final DateTime             deletedAt;

  // WFP-type fields
  final WFPEntry?            wfp;
  final List<BudgetActivity> activities;

  // Activity-type fields
  final BudgetActivity?      activity;
  final String?              parentWfpId;

  const _BinEntry._({
    required this.binId,
    required this.type,
    required this.deletedAt,
    this.wfp,
    this.activities = const [],
    this.activity,
    this.parentWfpId,
  });

  bool get isWFP      => type == _BinEntryType.wfp;
  bool get isActivity => type == _BinEntryType.activity;

  /// Display title used in cards and sort/search.
  String get displayTitle =>
      isWFP ? (wfp?.title ?? '') : (activity?.name ?? '');

  String get displayId =>
      isWFP ? (wfp?.id ?? '') : (activity?.id ?? '');

  String get displayFundType =>
      isWFP ? (wfp?.fundType ?? '') : '';

  int get displayYear =>
      isWFP ? (wfp?.year ?? 0) : 0;

  double get displayAmount =>
      isWFP ? (wfp?.amount ?? 0) : (activity?.total ?? 0);

  static _BinEntry? tryParse(Map<String, dynamic> row) {
    try {
      final entryTypeRaw = (row['entryType'] as String?) ?? 'WFP';
      final entryType = entryTypeRaw.toLowerCase() == 'activity'
          ? _BinEntryType.activity
          : _BinEntryType.wfp;
      final deletedAt = DateTime.tryParse(row['deletedAt'] as String) ?? DateTime.now();
      final binId     = row['id'] as int;

      if (entryType == _BinEntryType.activity) {
        final actJson = row['activityJson'] as String?;
        if (actJson == null || actJson.isEmpty) {
          // Legacy fallback: maybe activity is stored in wfpJson with type label
          return null;
        }
        final activity = BudgetActivity.fromMap(
            jsonDecode(actJson) as Map<String, dynamic>);
        return _BinEntry._(
          binId:       binId,
          type:        _BinEntryType.activity,
          deletedAt:   deletedAt,
          activity:    activity,
          parentWfpId: row['wfpId'] as String?,
        );
      } else {
        final wfpJsonStr = row['wfpJson'] as String?;
        if (wfpJsonStr == null || wfpJsonStr.isEmpty) return null;
        final wfp = WFPEntry.fromMap(
            jsonDecode(wfpJsonStr) as Map<String, dynamic>);
        final actsJson = row['activitiesJson'] as String? ?? '[]';
        final acts = (jsonDecode(actsJson) as List<dynamic>)
            .map((m) => BudgetActivity.fromMap(m as Map<String, dynamic>))
            .toList();
        return _BinEntry._(
          binId:      binId,
          type:       _BinEntryType.wfp,
          deletedAt:  deletedAt,
          wfp:        wfp,
          activities: acts,
        );
      }
    } catch (_) {
      return null;
    }
  }
}