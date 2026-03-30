import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/responsive_layout.dart';

class AuditLogPage extends StatefulWidget {
  final AppState appState;

  const AuditLogPage({super.key, required this.appState});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  static const Map<String, String> _fieldLabels = {
    'title': 'Program Title',
    'name': 'Activity Name',
    'wfpId': 'Parent WFP',
    'targetSize': 'Target Size',
    'indicator': 'Indicator / Details',
    'year': 'Year',
    'fundType': 'Fund Type',
    'viewSection': 'View Section',
    'amount': 'Amount',
    'total': 'Total AR',
    'projected': 'Projected / Obligated',
    'disbursed': 'Disbursed',
    'approvalStatus': 'Approval Status',
    'status': 'Status',
    'approvedDate': 'Approved Date',
    'dueDate': 'Due Date',
    'targetDate': 'Target Date',
  };

  static const List<String> _fieldOrder = [
    'title',
    'name',
    'wfpId',
    'targetSize',
    'indicator',
    'fundType',
    'viewSection',
    'year',
    'amount',
    'total',
    'projected',
    'disbursed',
    'approvalStatus',
    'status',
    'approvedDate',
    'dueDate',
    'targetDate',
  ];

  static const Set<String> _currencyFields = {
    'amount',
    'total',
    'projected',
    'disbursed',
  };

  static const Set<String> _dateFields = {
    'approvedDate',
    'dueDate',
    'targetDate',
  };

  static const Set<String> _statusFields = {'approvalStatus', 'status'};

  static const Set<String> _monospaceFields = {'wfpId'};

  static final DateFormat _timeFormat = DateFormat('MMM d, y - h:mm a');
  static final DateFormat _dateFormat = DateFormat('MMM d, y');

  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String _search = '';
  String? _filterType;
  String? _filterAction;
  final _searchCtrl = TextEditingController();

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

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await widget.appState.getAuditLog(limit: 500);
    if (mounted) {
      setState(() {
        _entries = all;
        _loading = false;
      });
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Audit Log'),
        content: const Text(
          'This will permanently delete all audit log entries. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.appState.clearAuditLog();
      _load();
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _entries.where((entry) {
      final action = entry['action'] as String? ?? '';
      final matchesAction = _filterAction == null || action == _filterAction;
      final matchesType =
          _filterType == null || entry['entityType'] == _filterType;
      final matchesSearch = q.isEmpty || _searchText(entry).contains(q);
      return matchesAction && matchesType && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = ResponsiveLayout.pagePaddingForWidth(
          constraints.maxWidth,
        );
        final compact = constraints.maxWidth < 760;

        return Padding(
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Audit Log',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Track who created, edited, restored, or deleted records with readable field values.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${filtered.length} of ${_entries.length} entries',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Audit Log',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Track who created, edited, restored, or deleted records with readable field values.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${filtered.length} of ${_entries.length} entries',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: BorderSide(
                              color: AppColors.tint(AppColors.danger, 0.35),
                            ),
                          ),
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            size: 16,
                          ),
                          label: const Text('Clear Log'),
                          onPressed: _loading ? null : _confirmClear,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh entries',
                          onPressed: _load,
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  if (compact) ...[
                    _buildSearchField(),
                    const SizedBox(height: 12),
                    _buildFilterDropdown<String?>(
                      value: _filterType,
                      hint: 'Entity',
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All types')),
                        DropdownMenuItem(value: 'WFP', child: Text('WFP')),
                        DropdownMenuItem(
                          value: 'Activity',
                          child: Text('Activity'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filterType = v),
                    ),
                    const SizedBox(height: 12),
                    _buildFilterDropdown<String?>(
                      value: _filterAction,
                      hint: 'Action',
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('All actions'),
                        ),
                        DropdownMenuItem(
                          value: 'CREATE',
                          child: Text('Created'),
                        ),
                        DropdownMenuItem(
                          value: 'UPDATE',
                          child: Text('Edited'),
                        ),
                        DropdownMenuItem(
                          value: 'RESTORE',
                          child: Text('Restored'),
                        ),
                        DropdownMenuItem(
                          value: 'DELETE',
                          child: Text('Deleted'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filterAction = v),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(flex: 3, child: _buildSearchField()),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 180,
                          child: _buildFilterDropdown<String?>(
                            value: _filterType,
                            hint: 'Entity',
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('All types'),
                              ),
                              DropdownMenuItem(
                                value: 'WFP',
                                child: Text('WFP'),
                              ),
                              DropdownMenuItem(
                                value: 'Activity',
                                child: Text('Activity'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _filterType = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 180,
                          child: _buildFilterDropdown<String?>(
                            value: _filterAction,
                            hint: 'Action',
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('All actions'),
                              ),
                              DropdownMenuItem(
                                value: 'CREATE',
                                child: Text('Created'),
                              ),
                              DropdownMenuItem(
                                value: 'UPDATE',
                                child: Text('Edited'),
                              ),
                              DropdownMenuItem(
                                value: 'RESTORE',
                                child: Text('Restored'),
                              ),
                              DropdownMenuItem(
                                value: 'DELETE',
                                child: Text('Deleted'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _filterAction = v),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : filtered.isEmpty
                        ? _emptyState()
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 14),
                            itemBuilder: (_, i) => _logCard(filtered[i]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, size: 18),
        hintText: 'Search by ID, action, or field value...',
        isDense: true,
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                tooltip: 'Clear search',
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
              )
            : null,
      ),
      onChanged: (v) => setState(() => _search = v),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _entries.isEmpty
                ? 'No audit log entries yet.'
                : 'No entries match your filters.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logCard(Map<String, dynamic> rawEntry) {
    final action = rawEntry['action'] as String? ?? 'UPDATE';
    final entityType = rawEntry['entityType'] as String? ?? 'Unknown';
    final entityId = rawEntry['entityId'] as String? ?? 'Unknown';
    final payload = _decodePayload(rawEntry['diffJson'] as String?);
    final meta = _entryMeta(payload);
    final fields = _entryFields(payload, action);
    final hasStructuredDiffs =
        action == 'UPDATE' && _hasStructuredDiffs(fields);
    final style = _actionStyle(action);
    final title = _displayTitle(entityType, meta, fields) ?? entityId;
    final contextLine = _contextLine(entityType, meta, fields);
    final summary = _summaryText(
      action,
      fields.length,
      hasStructuredDiffs: hasStructuredDiffs,
    );
    final preview = _previewText(
      entityType,
      fields,
      action,
      hasStructuredDiffs: hasStructuredDiffs,
    );
    final actorLine = _actorSummaryLine(rawEntry);
    final actorComment = _actorComment(rawEntry);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, size: 20, color: style.color),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _labelChip(entityType, _entityColor(entityType)),
                  _labelChip(style.label, style.color),
                  _neutralChip(summary),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (title != entityId) ...[
                const SizedBox(height: 3),
                Text(
                  entityId,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (contextLine != null) ...[
                const SizedBox(height: 5),
                Text(
                  contextLine,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatTimestamp(rawEntry['timestamp'] as String?),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (actorLine != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          actorLine,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (actorComment != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          actorComment,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          children: [
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            _actionBanner(
              action,
              entityType,
              style.color,
              hasStructuredDiffs: hasStructuredDiffs,
            ),
            const SizedBox(height: 14),
            action == 'UPDATE' && hasStructuredDiffs
                ? _renderDiff(entityType, fields)
                : _renderSnapshot(entityType, fields, action),
          ],
        ),
      ),
    );
  }

  Widget _actionBanner(
    String action,
    String entityType,
    Color color, {
    bool hasStructuredDiffs = false,
  }) {
    final subject = entityType == 'WFP' ? 'WFP entry' : 'budget activity';
    final text = switch (action) {
      'CREATE' =>
        'A new $subject was created. The recorded values at creation time are shown below.',
      'RESTORE' =>
        'This $subject was restored from the Recycle Bin. The restored values are shown below.',
      'DELETE' =>
        'This snapshot was captured before the $subject was moved to the Recycle Bin.',
      _ =>
        hasStructuredDiffs
            ? 'This $subject was edited. The field-level changes are shown below.'
            : 'This $subject was edited, but this older entry only stored the recorded values. Those values are shown below.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _renderDiff(String entityType, Map<String, dynamic> diff) {
    if (diff.isEmpty) {
      return Text(
        'No field changes were recorded for this edit.',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _orderedEntries(diff).map((entry) {
        final change =
            _coerceChangeMap(entry.value) ?? {'from': null, 'to': entry.value};
        final from = change['from'];
        final to = change['to'];

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _fieldLabel(entry.key),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _neutralChip(_changeLabel(from, to)),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 640;
                  final before = _valuePanel(
                    title: 'Before',
                    fieldKey: entry.key,
                    value: from,
                    background: Colors.red.shade50,
                    border: Colors.red.shade200,
                    foreground: Colors.red.shade700,
                    strikeThrough: true,
                  );
                  final after = _valuePanel(
                    title: 'After',
                    fieldKey: entry.key,
                    value: to,
                    background: Colors.green.shade50,
                    border: Colors.green.shade200,
                    foreground: Colors.green.shade700,
                  );

                  if (compact) {
                    return Column(
                      children: [
                        before,
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ),
                        after,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: before),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ),
                      Expanded(child: after),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _renderSnapshot(
    String entityType,
    Map<String, dynamic> snapshot,
    String action,
  ) {
    final entries = _orderedEntries(
      snapshot,
    ).where((entry) => !_isEmptyValue(entry.value)).toList();
    if (entries.isEmpty) {
      return Text(
        action == 'DELETE'
            ? 'No snapshot values were captured before deletion.'
            : 'No values were recorded for this action.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final cardWidth = wide
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: entries.map((entry) {
            return SizedBox(
              width: cardWidth,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fieldLabel(entry.key),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _valueView(entry.key, entry.value),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _valuePanel({
    required String title,
    required String fieldKey,
    required dynamic value,
    required Color background,
    required Color border,
    required Color foreground,
    bool strikeThrough = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _valueView(
            fieldKey,
            value,
            textColor: foreground,
            strikeThrough: strikeThrough,
          ),
        ],
      ),
    );
  }

  Widget _valueView(
    String fieldKey,
    dynamic value, {
    Color? textColor,
    bool strikeThrough = false,
  }) {
    if (_isEmptyValue(value)) {
      return Text(
        'Not set',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade500,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (_statusFields.contains(fieldKey)) {
      return _statusChip(fieldKey, value.toString());
    }

    return Text(
      _formatValue(fieldKey, value),
      style: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: textColor ?? const Color(0xff1C2B33),
        fontFamily: _monospaceFields.contains(fieldKey) ? 'monospace' : null,
        decoration: strikeThrough
            ? TextDecoration.lineThrough
            : TextDecoration.none,
      ),
    );
  }

  Widget _statusChip(String fieldKey, String value) {
    final color = _statusColor(fieldKey, value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _labelChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _neutralChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _searchText(Map<String, dynamic> rawEntry) {
    final entityType = rawEntry['entityType'] as String? ?? '';
    final entityId = rawEntry['entityId'] as String? ?? '';
    final action = rawEntry['action'] as String? ?? '';
    final payload = _decodePayload(rawEntry['diffJson'] as String?);
    final meta = _entryMeta(payload);
    final fields = _entryFields(payload, action);
    final buffer = StringBuffer()
      ..write('$entityType $entityId $action ${_actionStyle(action).label} ');
    buffer.write(
      '${rawEntry['actorName'] ?? ''} ${rawEntry['actorComment'] ?? ''} ',
    );

    for (final entry in meta.entries) {
      buffer.write('${entry.key} ${entry.value ?? ''} ');
    }
    for (final entry in fields.entries) {
      buffer.write('${entry.key} ${_fieldLabel(entry.key)} ');
      final change = _coerceChangeMap(entry.value);
      if (change != null) {
        buffer.write('${change['from'] ?? ''} ${change['to'] ?? ''} ');
      } else {
        buffer.write('${entry.value ?? ''} ');
      }
    }
    return buffer.toString().toLowerCase();
  }

  Map<String, dynamic> _decodePayload(String? diffJson) {
    if (diffJson == null || diffJson.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(diffJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return {};
  }

  Map<String, dynamic> _entryMeta(Map<String, dynamic> payload) {
    final meta = payload['_meta'];
    if (meta is Map<String, dynamic>) {
      return meta;
    }
    if (meta is Map) {
      return Map<String, dynamic>.from(meta);
    }
    return {};
  }

  Map<String, dynamic> _entryFields(
    Map<String, dynamic> payload,
    String action,
  ) {
    if (action == 'UPDATE') {
      final fields = payload['fields'];
      if (fields is Map<String, dynamic>) {
        return fields;
      }
      if (fields is Map) {
        return Map<String, dynamic>.from(fields);
      }
    }
    return Map<String, dynamic>.from(payload)
      ..remove('_meta')
      ..remove('fields');
  }

  List<MapEntry<String, dynamic>> _orderedEntries(Map<String, dynamic> fields) {
    final entries = fields.entries.toList();
    entries.sort((a, b) {
      final aIndex = _fieldOrder.indexOf(a.key);
      final bIndex = _fieldOrder.indexOf(b.key);
      if (aIndex == -1 && bIndex == -1) {
        return a.key.compareTo(b.key);
      }
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });
    return entries;
  }

  String _fieldLabel(String key) => _fieldLabels[key] ?? key;

  String? _displayTitle(
    String entityType,
    Map<String, dynamic> meta,
    Map<String, dynamic> fields,
  ) {
    if (entityType == 'WFP') {
      return _currentString(meta['title'] ?? fields['title']);
    }
    return _currentString(meta['name'] ?? fields['name']);
  }

  String? _contextLine(
    String entityType,
    Map<String, dynamic> meta,
    Map<String, dynamic> fields,
  ) {
    if (entityType == 'WFP') {
      final section = _currentString(
        meta['viewSection'] ?? fields['viewSection'],
      );
      return section == null ? null : 'Section: $section';
    }
    final wfpId = _currentString(meta['wfpId'] ?? fields['wfpId']);
    return wfpId == null ? null : 'Parent WFP: $wfpId';
  }

  String _summaryText(
    String action,
    int count, {
    required bool hasStructuredDiffs,
  }) {
    if (action == 'UPDATE' && hasStructuredDiffs) {
      return count == 1 ? '1 change' : '$count changes';
    }
    return count == 1 ? '1 value' : '$count values';
  }

  String _previewText(
    String entityType,
    Map<String, dynamic> fields,
    String action, {
    required bool hasStructuredDiffs,
  }) {
    final labels = _orderedEntries(
      fields,
    ).map((entry) => _fieldLabel(entry.key)).toList();
    if (labels.isEmpty) {
      return action == 'UPDATE' && hasStructuredDiffs
          ? 'No field-level changes were captured.'
          : 'No values were recorded for this action.';
    }
    final preview = labels.take(3).join(', ');
    final extra = labels.length > 3 ? ' +${labels.length - 3} more' : '';
    return action == 'UPDATE' && hasStructuredDiffs
        ? 'Changed: $preview$extra'
        : 'Recorded values: $preview$extra';
  }

  String _formatTimestamp(String? timestamp) {
    final parsed = DateTime.tryParse(timestamp ?? '');
    if (parsed == null) {
      return timestamp ?? '';
    }
    return _timeFormat.format(parsed);
  }

  String? _actorSummaryLine(Map<String, dynamic> rawEntry) {
    return _nonEmptyText(rawEntry['actorName']);
  }

  String? _actorComment(Map<String, dynamic> rawEntry) {
    return _nonEmptyText(rawEntry['actorComment']);
  }

  String _formatValue(String fieldKey, dynamic value) {
    if (_isEmptyValue(value)) {
      return 'Not set';
    }
    if (_currencyFields.contains(fieldKey)) {
      final amount = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (amount != null) {
        return CurrencyFormatter.format(amount);
      }
    }
    if (_dateFields.contains(fieldKey)) {
      final parsed = DateTime.tryParse('$value');
      if (parsed != null) {
        return _dateFormat.format(parsed);
      }
    }
    if (value is bool) {
      return value ? 'Yes' : 'No';
    }
    if (value is num) {
      final number = value.toDouble();
      return number == number.roundToDouble()
          ? number.toInt().toString()
          : value.toString();
    }
    if (value is List || value is Map) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return value.toString();
  }

  String _changeLabel(dynamic from, dynamic to) {
    if (_isEmptyValue(from) && !_isEmptyValue(to)) {
      return 'Set';
    }
    if (!_isEmptyValue(from) && _isEmptyValue(to)) {
      return 'Cleared';
    }
    return 'Changed';
  }

  String? _currentString(dynamic source) {
    if (source is Map) {
      final to = source['to'];
      if (!_isEmptyValue(to)) return '$to';
      final from = source['from'];
      if (!_isEmptyValue(from)) return '$from';
      return null;
    }
    if (_isEmptyValue(source)) {
      return null;
    }
    return '$source';
  }

  String? _nonEmptyText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  bool _hasStructuredDiffs(Map<String, dynamic> fields) {
    return fields.values.any((value) => _coerceChangeMap(value) != null);
  }

  Map<String, dynamic>? _coerceChangeMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value.containsKey('from') || value.containsKey('to')
          ? value
          : null;
    }
    if (value is Map) {
      final mapped = Map<String, dynamic>.from(value);
      return mapped.containsKey('from') || mapped.containsKey('to')
          ? mapped
          : null;
    }
    return null;
  }

  bool _isEmptyValue(dynamic value) {
    return value == null || (value is String && value.trim().isEmpty);
  }

  Color _entityColor(String entityType) {
    return entityType == 'WFP' ? AppColors.textPrimary : AppColors.primary;
  }

  Color _statusColor(String fieldKey, String value) {
    if (fieldKey == 'approvalStatus') {
      switch (value) {
        case 'Approved':
          return AppColors.success;
        case 'Rejected':
          return AppColors.danger;
        default:
          return AppColors.warning;
      }
    }
    switch (value) {
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

  _AuditActionStyle _actionStyle(String action) {
    switch (action) {
      case 'CREATE':
        return _AuditActionStyle(
          label: 'Created',
          color: AppColors.success,
          icon: Icons.add_circle_outline,
        );
      case 'DELETE':
        return _AuditActionStyle(
          label: 'Deleted',
          color: AppColors.danger,
          icon: Icons.delete_outline,
        );
      case 'RESTORE':
        return _AuditActionStyle(
          label: 'Restored',
          color: AppColors.info,
          icon: Icons.restore_rounded,
        );
      default:
        return _AuditActionStyle(
          label: 'Edited',
          color: AppColors.primary,
          icon: Icons.edit_outlined,
        );
    }
  }
}

class _AuditActionStyle {
  final String label;
  final Color color;
  final IconData icon;

  const _AuditActionStyle({
    required this.label,
    required this.color,
    required this.icon,
  });
}
