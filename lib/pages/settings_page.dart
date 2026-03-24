import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../services/app_state.dart';
import 'recycle_bin_page.dart';
import '../database/database_helper.dart';

class SettingsPage extends StatefulWidget {
  final AppState appState;
  const SettingsPage({super.key, required this.appState});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _operatingUnitCtrl;
  late final TextEditingController _currencyCtrl;
  bool _savingUnit     = false;
  bool _savingCurrency = false;
  int  _recycleBinCount = 0;
  bool _archiving      = false;
  String? _archiveResult;
  bool _archiveSuccess = false;
  int  _archiveCount   = 0;
  

  // Auto-backup status — polled every 5 seconds so the UI stays current
  Timer? _statusTimer;
  DateTime? _autoBackupTime;
  String?   _autoBackupPath;
  bool      _autoBackupFailed = false;
  int       _autoArchiveCount = 0;

  @override
  void initState() {
    super.initState();
    _operatingUnitCtrl = TextEditingController(text: widget.appState.operatingUnit);
    _currencyCtrl      = TextEditingController(text: widget.appState.currencySymbol);
    _refreshArchiveCount();
    _refreshAutoStatus();
    _refreshRecycleBinCount();
    // Poll auto-backup status every 5 s so the UI updates after a backup fires
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshAutoStatus();
    });
  }

  @override
  void dispose() {
    _operatingUnitCtrl.dispose();
    _currencyCtrl.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }


  Future<void> _saveOperatingUnit() async {
    setState(() => _savingUnit = true);
    await widget.appState.setOperatingUnit(_operatingUnitCtrl.text);
    if (mounted) {
      setState(() => _savingUnit = false);
      _showSnack('Operating unit saved.');
    }
  }

  Future<void> _saveCurrency() async {
    if (_currencyCtrl.text.trim().isEmpty) {
      _showSnack('Currency symbol cannot be empty.', isError: true);
      return;
    }
    setState(() => _savingCurrency = true);
    await widget.appState.setCurrencySymbol(_currencyCtrl.text);
    if (mounted) {
      setState(() => _savingCurrency = false);
      _showSnack('Currency symbol saved.');
    }
  }

  // ─── Archive helpers ─────────────────────────────────────────────────────

  String get _exeDir => File(Platform.resolvedExecutable).parent.path;
  String get _dbPath  => p.join(_exeDir, 'pims_deped.db');
  String get _archiveDir => p.join(_exeDir, 'archives');

  Future<void> _refreshArchiveCount() async {
    final dir = Directory(_archiveDir);
    if (!await dir.exists()) { setState(() => _archiveCount = 0); return; }
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.db'))
        .length;
    if (mounted) setState(() => _archiveCount = files);
  }

  void _refreshAutoStatus() {
    if (!mounted) return;
    final autoDir = Directory(p.join(_archiveDir, 'auto'));
    autoDir.exists().then((exists) async {
      int count = 0;
      if (exists) {
        count = await autoDir
            .list()
            .where((e) => e is File && e.path.endsWith('.db'))
            .length;
      }
      if (mounted) {
        setState(() {
        _autoBackupTime   = DatabaseHelper.lastAutoBackupTime;
        _autoBackupPath   = DatabaseHelper.lastAutoBackupPath;
        _autoBackupFailed = DatabaseHelper.lastAutoBackupFailed;
        _autoArchiveCount = count;
      });
      }
    });
  }

  Future<void> _refreshRecycleBinCount() async {
    final entries = await widget.appState.getRecycleBinEntries();
    if (mounted) setState(() => _recycleBinCount = entries.length);
  }

  Future<void> _createArchive() async {
    setState(() { _archiving = true; _archiveResult = null; });
    try {
      final src = File(_dbPath);
      if (!await src.exists()) throw Exception('Database file not found at $_dbPath');

      final dir = Directory(_archiveDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4,'0')}'
          '${now.month.toString().padLeft(2,'0')}'
          '${now.day.toString().padLeft(2,'0')}_'
          '${now.hour.toString().padLeft(2,'0')}'
          '${now.minute.toString().padLeft(2,'0')}'
          '${now.second.toString().padLeft(2,'0')}';
      final dest = p.join(_archiveDir, 'pims_deped_$stamp.db');
      await src.copy(dest);

      await _refreshArchiveCount();
      if (mounted) setState(() { _archiveResult = dest; _archiveSuccess = true; });
    } catch (e) {
      if (mounted) setState(() { _archiveResult = e.toString(); _archiveSuccess = false; });
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  Future<void> _openArchiveFolder() async {
    final dir = Directory(_archiveDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final uri = Uri.file(_archiveDir);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openSnapshotsDialog() async {
    final archives = await DatabaseHelper.listArchives();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        String filter = '';
        String sortMode = 'newest'; // or 'oldest'
        int? selectedIdx;
        Map<String, bool?> integrity = {};

        Future<void> _checkIntegrityFor(String path) async {
          final ok = await DatabaseHelper.validateArchive(path);
          integrity[path] = ok;
        }

        return StatefulBuilder(builder: (ctx2, setState2) {
          final filtered = archives
              .where((p) => p.toLowerCase().contains(filter.toLowerCase()))
              .toList();
          filtered.sort((a, b) => sortMode == 'newest' ? b.compareTo(a) : a.compareTo(b));

          Widget detailsFor(String path) {
            final f = File(path);
            final name = p.basename(path);
            String sizeTxt = '—';
            String mtime = '—';
            try {
              if (f.existsSync()) {
                sizeTxt = '${(f.lengthSync() / 1024).toStringAsFixed(1)} KB';
                mtime = f.lastModifiedSync().toString();
              }
            } catch (_) {}
            final integrityStatus = integrity.containsKey(path)
                ? (integrity[path] == true ? 'OK' : 'Invalid')
                : 'Unknown';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('Path: $path', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text('Size: $sizeTxt  •  Modified: $mtime', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Text('Integrity: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(integrityStatus, style: TextStyle(color: integrityStatus == 'OK' ? Colors.green.shade700 : Colors.red.shade700)),
                ]),
              ],
            );
          }

          return AlertDialog(
            title: Row(children: [const Text('Manage Snapshots'), const Spacer(), IconButton(icon: const Icon(Icons.refresh), onPressed: () async {
              // Re-scan archives and re-run integrity checks for visible items
              final newList = await DatabaseHelper.listArchives();
              archives.clear();
              archives.addAll(newList);
              setState2(() {});
            })]),
            content: SizedBox(
              width: 800,
              height: 420,
              child: archives.isEmpty
                  ? const Text('No snapshots found in archives.')
                  : Row(children: [
                      // Left: list and controls
                      Flexible(
                        flex: 4,
                        child: Column(children: [
                          TextField(
                            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter snapshots by name...'),
                            onChanged: (v) => setState2(() => filter = v),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            const SizedBox(width: 6),
                            ChoiceChip(label: const Text('Newest'), selected: sortMode == 'newest', onSelected: (_) => setState2(() => sortMode = 'newest')),
                            const SizedBox(width: 8),
                            ChoiceChip(label: const Text('Oldest'), selected: sortMode == 'oldest', onSelected: (_) => setState2(() => sortMode = 'oldest')),
                            const Spacer(),
                            Text('${filtered.length} snapshot${filtered.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.grey)),
                          ]),
                          const SizedBox(height: 8),
                          Expanded(child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx3, i) {
                              final path = filtered[i];
                              final name = p.basename(path);
                              final sel = selectedIdx == i;
                              final integrityFlag = integrity.containsKey(path) ? integrity[path] : null;
                              return RadioListTile<int>(
                                value: i,
                                groupValue: selectedIdx,
                                onChanged: (v) async {
                                  setState2(() => selectedIdx = v);
                                  if (!integrity.containsKey(path)) {
                                    setState2(() => integrity[path] = null);
                                    final ok = await DatabaseHelper.validateArchive(path);
                                    setState2(() => integrity[path] = ok);
                                  }
                                },
                                title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
                                subtitle: Text(path, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                secondary: integrityFlag == null ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(integrityFlag ? Icons.check_circle_outline : Icons.error_outline, color: integrityFlag ? Colors.green : Colors.red),
                              );
                            },
                          )),
                        ]),
                      ),

                      const SizedBox(width: 16),

                      // Right: details + actions
                      Flexible(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
                          child: selectedIdx == null
                              ? const Center(child: Text('Select a snapshot to see details and actions.'))
                              : detailsFor(filtered[selectedIdx!]),
                        ),
                      ),
                    ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
              TextButton(
                onPressed: selectedIdx == null ? null : () async {
                  final path = filtered[selectedIdx!];
                  final name = p.basename(path);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Confirm Restore'),
                      content: Text('Restore snapshot "$name"? A pre-restore backup will be created automatically.'),
                      actions: [TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Restore'))],
                    ),
                  );
                  if (ok == true) {
                    Navigator.of(ctx).pop();
                    final restored = await DatabaseHelper.restoreFromArchivePath(path);
                    if (restored) {
                      _showSnack('Restored snapshot: $name');
                      await _refreshArchiveCount();
                      _refreshAutoStatus();
                    } else {
                      _showSnack('Failed to restore snapshot (integrity check failed).', isError: true);
                    }
                  }
                },
                child: const Text('Restore'),
              ),
              TextButton(
                onPressed: selectedIdx == null ? null : () async {
                  final path = filtered[selectedIdx!];
                  final name = p.basename(path);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Confirm Delete'),
                      content: Text('Permanently delete snapshot "$name"? This cannot be undone.'),
                      actions: [TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete'))],
                    ),
                  );
                  if (ok == true) {
                    try {
                      final f = File(path);
                      if (await f.exists()) await f.delete();
                      await _refreshArchiveCount();
                      setState(() {});
                      _showSnack('Deleted: $name');
                    } catch (e) {
                      _showSnack('Delete failed: $e', isError: true);
                    }
                  }
                },
                child: const Text('Delete'),
              ),
            ],
          );
        });
      },
    );
  }

  // Database normalization is a manual design activity (schema normalization,
  // deduplication, and integrity constraints). The app provides integrity
  // checks, migrations, and VACUUM/ANALYZE helpers, and automatic backups, but
  // full normalization requires review and planned schema changes. Users may
  // restore from snapshots before applying structural changes.

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
    ));
  }

  String _formatTime(DateTime t) {
    final h   = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    final sec = t.second.toString().padLeft(2, '0');
    final d   = '${t.month}/${t.day}/${t.year}';
    return '$d  $h:$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Settings',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                    color: Color(0xff2F3E46))),
              const SizedBox(height: 4),
              Text('System preferences and configuration.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 32),

              // ── Organization Settings ─────────────────────────────────
              _settingsCard(
                title: 'Organization',
                icon: Icons.business_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Operating Unit',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'This name appears in Excel and PDF report headers.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _operatingUnitCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Operating Unit Name',
                            hintText: 'Department of Education',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff2F3E46),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _savingUnit ? null : _saveOperatingUnit,
                        child: _savingUnit
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save'),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('Current: ${widget.appState.operatingUnit}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Currency Settings ─────────────────────────────────────
              _settingsCard(
                title: 'Currency',
                icon: Icons.attach_money_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Currency Symbol',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'Shown before all monetary values throughout the app.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _currencyCtrl,
                          maxLength: 5,
                          decoration: const InputDecoration(
                            labelText: 'Symbol',
                            hintText: '₱',
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff2F3E46),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _savingCurrency ? null : _saveCurrency,
                        child: _savingCurrency
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save'),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Preview: ${widget.appState.currencySymbol}1,234,567.89',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff2F3E46),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('Current: "${widget.appState.currencySymbol}"',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Deadline Notifications ────────────────────────────────
              _settingsCard(
                title: 'Deadline Notifications',
                icon: Icons.schedule_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Warning Window',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text(
                      'Show a badge on the Deadlines sidebar item when a WFP due date '
                      'or activity target date is within this many days.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      children: [7, 14, 30].map((days) {
                        final selected = widget.appState.warningDays == days;
                        return ChoiceChip(
                          label: Text('$days days'),
                          selected: selected,
                          selectedColor: const Color(0xff2F3E46),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : const Color(0xff2F3E46),
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => widget.appState.setWarningDays(days),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Current: ${widget.appState.warningDays} days  •  '
                      '${widget.appState.deadlineWarningCount} item(s) flagged right now',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.appState.deadlineWarningCount > 0
                            ? Colors.red.shade600 : Colors.green.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Archive / Backup ──────────────────────────────────────
              _settingsCard(
                title: 'Archive & Backup',
                icon: Icons.archive_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Database Backup',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'Creates a timestamped copy of pims_deped.db inside the '
                      '"archives" folder next to the application. Backups are '
                      'independent — the live database continues unchanged.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    // ── Action row ──────────────────────────────────────
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff2F3E46),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                          ),
                          icon: _archiving
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.backup_outlined, size: 18),
                          label: Text(_archiving ? 'Backing up…' : 'Create Backup'),
                          onPressed: _archiving ? null : _createArchive,
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xff2F3E46),
                            side: const BorderSide(color: Color(0xff2F3E46)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                          icon: const Icon(Icons.folder_open_outlined, size: 18),
                          label: const Text('Open Archives Folder'),
                          onPressed: _openArchiveFolder,
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xff2F3E46),
                            side: const BorderSide(color: Color(0xff2F3E46)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                          icon: const Icon(Icons.history_toggle_off, size: 18),
                          label: const Text('Manage Snapshots'),
                          onPressed: _openSnapshotsDialog,
                        ),
                        
                      ],
                    ),

                    // ── Result banner ───────────────────────────────────
                    if (_archiveResult != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _archiveSuccess
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _archiveSuccess
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _archiveSuccess
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              size: 18,
                              color: _archiveSuccess
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _archiveSuccess
                                        ? 'Backup created successfully'
                                        : 'Backup failed',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: _archiveSuccess
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _archiveResult!,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: _archiveSuccess
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // ── Manual archive count + path ─────────────────────
                    Row(children: [
                      Icon(Icons.folder_outlined,
                          size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        '$_archiveCount manual backup${_archiveCount == 1 ? '' : 's'} '
                        'stored in: $_archiveDir',
                        style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                      )),
                    ]),

                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 20),

                    // ── Auto-Backup section ─────────────────────────────
                    Row(children: [
                      const Text('Auto-Backup',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5EE),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text('Active',
                          style: TextStyle(fontSize: 10, color: Color(0xFF2D6A4F),
                              fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Automatically backs up the database after a period of '
                      'inactivity following the last record change. The timer '
                      'resets on every write — backup fires only when activity '
                      'goes quiet.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 14),

                    // ── Delay selector ──────────────────────────────────
                    Text('Backup delay after last activity',
                      style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: [
                        const Duration(seconds: 30),
                        const Duration(hours: 1),
                      ].map((d) {
                        final selected = DatabaseHelper.autoBackupDelay == d;
                        final label = d.inSeconds == 30 ? '30 seconds' : '1 hour';
                        return ChoiceChip(
                          label: Text(label),
                          selected: selected,
                          selectedColor: const Color(0xff2F3E46),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : const Color(0xff2F3E46),
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) {
                            DatabaseHelper.setAutoBackupDelay(d);
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 14),

                    // ── Last auto-backup status ─────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _autoBackupFailed
                                ? Icons.error_outline
                                : _autoBackupTime != null
                                    ? Icons.check_circle_outline
                                    : Icons.info_outline,
                            size: 16,
                            color: _autoBackupFailed
                                ? Colors.red.shade400
                                : _autoBackupTime != null
                                    ? Colors.green.shade600
                                    : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _autoBackupFailed
                                    ? 'Last auto-backup failed'
                                    : _autoBackupTime != null
                                        ? 'Last auto-backup: ${_formatTime(_autoBackupTime!)}'
                                        : 'No auto-backup yet this session',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _autoBackupFailed
                                      ? Colors.red.shade700
                                      : Colors.grey.shade700,
                                ),
                              ),
                              if (_autoBackupPath != null && !_autoBackupFailed) ...[
                                const SizedBox(height: 2),
                                Text(_autoBackupPath!,
                                  style: TextStyle(
                                    fontSize: 10, fontFamily: 'monospace',
                                    color: Colors.grey.shade500),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                '$_autoArchiveCount / 5 auto-backups stored  ·  '
                                'folder: ${p.join(_archiveDir, 'auto')}',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                              ),
                            ],
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),


              // ── Recycle Bin ───────────────────────────────────────────
              _settingsCard(
                title: 'Recycle Bin',
                icon: Icons.delete_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Deleted WFP Entries',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'WFP entries and their activities moved to the bin can be '
                      'restored or permanently deleted here.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff2F3E46),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                          ),
                          icon: const Icon(Icons.delete_outlined, size: 18),
                          label: Text(
                            _recycleBinCount > 0
                                ? 'Open Recycle Bin ($_recycleBinCount item${_recycleBinCount == 1 ? '' : 's'})'
                                : 'Open Recycle Bin',
                          ),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RecycleBinPage(
                                  appState: widget.appState,
                                ),
                              ),
                            );
                            // Refresh count when returning from the bin page
                            _refreshRecycleBinCount();
                          },
                        ),
                        if (_recycleBinCount > 0) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(children: [
                              Icon(Icons.info_outline,
                                  size: 14, color: Colors.red.shade600),
                              const SizedBox(width: 6),
                              Text(
                                '$_recycleBinCount deleted item${_recycleBinCount == 1 ? '' : 's'} awaiting review',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.red.shade700),
                              ),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── App Info ──────────────────────────────────────────────
              _settingsCard(
                title: 'Application',
                icon: Icons.info_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('System', 'PIMS DepED — Personnel Information Management System'),
                    const SizedBox(height: 8),
                    _infoRow('Agency', widget.appState.operatingUnit),
                    const SizedBox(height: 8),
                    _infoRow('Database', _dbPath),
                    const SizedBox(height: 8),
                    _infoRow('Currency', widget.appState.currencySymbol),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _settingsCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: const Color(0xff2F3E46), size: 20),
              const SizedBox(width: 10),
              Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 15, color: Color(0xff2F3E46))),
            ]),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 90,
        child: Text(label,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12,
              color: Colors.grey.shade600))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
    ]);
  }
}