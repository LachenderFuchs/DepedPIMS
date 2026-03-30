import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../services/app_state.dart';
import '../services/bulk_import_service.dart';
import '../services/deadline_reminder_service.dart';
import '../theme/app_theme.dart';
import 'recycle_bin_page.dart';
import '../database/database_helper.dart';
import '../widgets/hint.dart';
import '../widgets/import_preview_dialog.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/settings_section_card.dart';

class SettingsPage extends StatefulWidget {
  final AppState appState;
  const SettingsPage({super.key, required this.appState});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _projectManagerLine = 'Project Manager: Ric Francis';
  static const _leadDeveloperLine = 'Lead Developer: Emanuel Melchor I. Sernal';
  static const _coDeveloperLine = 'Co-Developer: Basil Santos';
  static const _developerHandlesLine = 'Handles:';
  static const _developerContactsLine = 'Contacts:';
  static const _developedForLine = 'Developed for DepED SDO Naga City - SGOD';

  late final TextEditingController _operatingUnitCtrl;
  late final TextEditingController _currencyCtrl;
  late final TextEditingController _currentUsernameCtrl;
  late final TextEditingController _currentPasswordCtrl;
  late final TextEditingController _newUsernameCtrl;
  late final TextEditingController _newPasswordCtrl;
  late final TextEditingController _confirmPasswordCtrl;
  bool _savingUnit = false;
  bool _savingCurrency = false;
  bool _savingCredentials = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  int _recycleBinCount = 0;
  bool _archiving = false;
  String? _archiveResult;
  bool _archiveSuccess = false;
  int _archiveCount = 0;
  String _installDir = '';
  String _dataDir = '';
  String _dbPath = '';
  String _archiveDir = '';

  // Auto-backup status Ã¢â‚¬â€ polled every 5 seconds so the UI stays current
  Timer? _statusTimer;
  DateTime? _autoBackupTime;
  bool _autoBackupFailed = false;
  int _autoArchiveCount = 0;
  DeadlineReminderSettings _reminderSettings = const DeadlineReminderSettings(
    enabled: true,
    intervalMinutes: 60,
    urgencyDays: 1,
  );

  static const _autoBackupDelayOptions = [
    Duration(seconds: 30),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];
  static const _autoBackupRetentionOptions = [3, 5, 10, 20];

  @override
  void initState() {
    super.initState();
    _operatingUnitCtrl = TextEditingController(
      text: widget.appState.operatingUnit,
    );
    _currencyCtrl = TextEditingController(text: widget.appState.currencySymbol);
    _currentUsernameCtrl = TextEditingController();
    _currentPasswordCtrl = TextEditingController();
    _newUsernameCtrl = TextEditingController(
      text: widget.appState.loginUsername,
    );
    _newPasswordCtrl = TextEditingController();
    _confirmPasswordCtrl = TextEditingController();
    _loadStorageInfo();
    _refreshArchiveCount();
    _refreshAutoStatus();
    _refreshRecycleBinCount();
    _loadReminderSettings();
    // Poll auto-backup status every 5 s so the UI updates after a backup fires
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshAutoStatus();
    });
  }

  @override
  void dispose() {
    _operatingUnitCtrl.dispose();
    _currencyCtrl.dispose();
    _currentUsernameCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newUsernameCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
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

  Future<void> _saveLoginCredentials() async {
    final currentUsername = _currentUsernameCtrl.text.trim();
    final currentPassword = _currentPasswordCtrl.text;
    final newUsername = _newUsernameCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;

    if (currentUsername.isEmpty || currentPassword.isEmpty) {
      _showSnack(
        'Enter your current username and password first.',
        isError: true,
      );
      return;
    }
    if (!await widget.appState.validateCredentialsFresh(
      username: currentUsername,
      password: currentPassword,
    )) {
      _showSnack('Current username or password is incorrect.', isError: true);
      return;
    }
    if (newUsername.isEmpty) {
      _showSnack('New username cannot be empty.', isError: true);
      return;
    }
    if (newPassword.isEmpty) {
      _showSnack('New password cannot be empty.', isError: true);
      return;
    }
    if (newPassword != confirmPassword) {
      _showSnack('New password and confirmation do not match.', isError: true);
      return;
    }

    setState(() => _savingCredentials = true);
    try {
      await widget.appState.setLoginCredentials(
        username: newUsername,
        password: newPassword,
      );
      _currentUsernameCtrl.clear();
      _currentPasswordCtrl.clear();
      _newUsernameCtrl.text = widget.appState.loginUsername;
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      _showSnack('Login credentials updated.');
    } on ArgumentError catch (e) {
      _showSnack(
        e.message?.toString() ?? 'Invalid credentials.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _savingCredentials = false);
      }
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Archive helpers Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Future<void> _refreshArchiveCount() async {
    final files = await DatabaseHelper.listManualArchivesInfo();
    if (mounted) setState(() => _archiveCount = files.length);
  }

  Future<void> _refreshAutoStatus() async {
    final archives = await DatabaseHelper.listAutoArchivesInfo();
    if (!mounted) return;

    setState(() {
      _autoBackupTime =
          DatabaseHelper.lastAutoBackupTime ??
          (archives.isEmpty ? null : archives.first.modifiedAt);
      _autoBackupFailed = DatabaseHelper.lastAutoBackupFailed;
      _autoArchiveCount = archives.length;
    });
  }

  Future<void> _loadStorageInfo() async {
    final installDir = await DatabaseHelper.installDirectoryPath;
    final dataDir = await DatabaseHelper.dataDirectoryPath;
    final dbPath = await DatabaseHelper.databaseFilePath;
    final archiveDir = await DatabaseHelper.archivesDirectoryPath;
    if (!mounted) return;
    setState(() {
      _installDir = installDir;
      _dataDir = dataDir;
      _dbPath = dbPath;
      _archiveDir = archiveDir;
    });
  }

  Future<void> _refreshRecycleBinCount() async {
    final entries = await widget.appState.getRecycleBinEntries();
    if (mounted) setState(() => _recycleBinCount = entries.length);
  }

  Future<void> _loadReminderSettings() async {
    final settings = await DeadlineReminderService.instance.loadSettings();
    if (!mounted) return;
    setState(() => _reminderSettings = settings);
  }

  Future<String?> _promptForManualBackupName() async {
    final controller = TextEditingController();
    String? errorText;

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Name Manual Backup'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter a clear name for this manual backup before saving it.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Backup name',
                        hintText: 'e.g. Before April Updates',
                        errorText: errorText,
                      ),
                      onSubmitted: (_) {
                        final trimmed = controller.text.trim();
                        if (trimmed.isEmpty) {
                          setDialogState(
                            () => errorText = 'Backup name is required.',
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(trimmed);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final trimmed = controller.text.trim();
                    if (trimmed.isEmpty) {
                      setDialogState(
                        () => errorText = 'Backup name is required.',
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(trimmed);
                  },
                  child: const Text('Save Backup'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return value;
  }

  Future<void> _restoreArchiveAndRefresh(ArchiveSnapshotInfo archive) async {
    final restored = await DatabaseHelper.restoreFromArchivePath(archive.path);
    if (!restored) {
      _showSnack(
        'Failed to restore the selected backup. Integrity validation did not pass.',
        isError: true,
      );
      return;
    }

    widget.appState.clearSelectedWFP();
    await widget.appState.init();
    await _refreshArchiveCount();
    await _refreshAutoStatus();
    await _refreshRecycleBinCount();

    if (!mounted) return;
    _showSnack('Restored ${archive.displayName} and refreshed the live data.');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  Future<void> _updateReminderSettings(
    DeadlineReminderSettings settings,
  ) async {
    await DeadlineReminderService.instance.updateSettings(settings);
    if (!mounted) return;
    setState(() => _reminderSettings = settings);
  }

  Future<void> _checkRemindersNow() async {
    await DeadlineReminderService.instance.checkNow(force: true);
    if (!mounted) return;
    _showSnack('Desktop reminder check completed.');
  }

  Future<void> _createImportTemplate() async {
    try {
      final path = await BulkImportService.saveTemplate();
      if (path == null || !mounted) return;
      _showSnack('Import template saved: ${p.basename(path)}');
    } catch (e) {
      _showSnack('Failed to save template: $e', isError: true);
    }
  }

  Future<void> _pickWorkbookForImport() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        allowMultiple: false,
      );
      final path = picked?.files.single.path;
      if (path == null || path.isEmpty || !mounted) {
        return;
      }

      final preview = await BulkImportService.previewFromFile(
        sourcePath: path,
        appState: widget.appState,
      );
      if (!mounted) return;

      final imported = await showDialog<bool>(
        context: context,
        builder: (_) => ImportPreviewDialog(
          preview: preview,
          onImport: () async {
            final ok = await widget.appState.importWorkbookData(
              wfps: preview.wfps,
              activities: preview.activities,
              sourceLabel: p.basename(path),
            );
            if (ok) {
              await _refreshArchiveCount();
            }
            return ok;
          },
        ),
      );

      if (!mounted) return;
      if (imported == true) {
        _showSnack(
          'Workbook import completed: ${preview.wfps.length} WFP and ${preview.activities.length} activities.',
        );
      }
    } catch (e) {
      _showSnack('Import failed: $e', isError: true);
    }
  }

  Future<void> _createArchive() async {
    final label = await _promptForManualBackupName();
    if (label == null) return;

    setState(() {
      _archiving = true;
      _archiveResult = null;
    });
    try {
      final dest = await DatabaseHelper.createManualArchive(label: label);
      final modifiedAt = await File(dest).lastModified();

      await _refreshArchiveCount();
      if (mounted) {
        setState(() {
          _archiveResult =
              'Manual backup "$label" saved on ${_formatTime(modifiedAt)}.';
          _archiveSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _archiveResult = e.toString();
          _archiveSuccess = false;
        });
      }
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  Future<void> _openArchiveFolder() async {
    final archiveDir = await DatabaseHelper.archivesDirectoryPath;
    final dir = Directory(archiveDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final uri = Uri.file(archiveDir);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openSnapshotsDialog() async {
    var manualArchives = await DatabaseHelper.listManualArchivesInfo();
    var autoArchives = await DatabaseHelper.listAutoArchivesInfo();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var filter = '';
        var sortMode = 'newest';
        var activeGroup = 'manual';
        String? selectedPath;
        final integrity = <String, bool?>{};

        ArchiveSnapshotInfo? selectedArchiveFrom(
          List<ArchiveSnapshotInfo> archives,
        ) {
          if (selectedPath == null) return null;
          for (final archive in archives) {
            if (archive.path == selectedPath) {
              return archive;
            }
          }
          return null;
        }

        Future<void> refreshArchives(StateSetter setState2) async {
          manualArchives = await DatabaseHelper.listManualArchivesInfo();
          autoArchives = await DatabaseHelper.listAutoArchivesInfo();
          await _refreshArchiveCount();
          await _refreshAutoStatus();
          if (!ctx.mounted) return;

          final availablePaths = {
            ...manualArchives.map((archive) => archive.path),
            ...autoArchives.map((archive) => archive.path),
          };

          setState2(() {
            integrity.removeWhere((path, _) => !availablePaths.contains(path));
            if (selectedPath != null &&
                !availablePaths.contains(selectedPath)) {
              selectedPath = null;
            }
          });
        }

        Future<void> ensureIntegrity(
          ArchiveSnapshotInfo archive,
          StateSetter setState2,
        ) async {
          if (integrity.containsKey(archive.path)) return;
          setState2(() => integrity[archive.path] = null);
          final ok = await DatabaseHelper.validateArchive(archive.path);
          if (!ctx.mounted) return;
          setState2(() => integrity[archive.path] = ok);
        }

        return StatefulBuilder(
          builder: (ctx2, setState2) {
            final currentArchives = activeGroup == 'manual'
                ? manualArchives
                : autoArchives;
            final filterLower = filter.toLowerCase();
            final filtered =
                currentArchives.where((archive) {
                  final haystack = '${archive.displayName} ${archive.fileName}'
                      .toLowerCase();
                  return haystack.contains(filterLower);
                }).toList()..sort(
                  (a, b) => sortMode == 'newest'
                      ? b.modifiedAt.compareTo(a.modifiedAt)
                      : a.modifiedAt.compareTo(b.modifiedAt),
                );

            final selectedArchive = selectedArchiveFrom(filtered);

            Widget buildDetails(ArchiveSnapshotInfo archive) {
              final integrityState = integrity[archive.path];
              final integrityText = integrityState == null
                  ? 'Checking backup integrity...'
                  : integrityState
                  ? 'Integrity check passed'
                  : 'Integrity check failed';
              final integrityColor = integrityState == null
                  ? AppColors.textSecondary
                  : integrityState
                  ? AppColors.success
                  : AppColors.danger;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    archive.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    archive.fileName,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Saved: ${_formatTime(archive.modifiedAt)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type: ${archive.isAutoBackup ? 'Automatic backup' : 'Manual backup'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Size: ${_formatFileSize(archive.sizeBytes)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    integrityText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: integrityColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Path',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    archive.path,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Text('Manage Snapshots'),
                  const Spacer(),
                  Hint(
                    message: 'Rescan snapshots',
                    child: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        await refreshArchives(setState2);
                      },
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 800,
                height: 420,
                child: manualArchives.isEmpty && autoArchives.isEmpty
                    ? const Text('No manual or automatic backups found yet.')
                    : Row(
                        children: [
                          Flexible(
                            flex: 4,
                            child: Column(
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: Text(
                                        'Manual (${manualArchives.length})',
                                      ),
                                      selected: activeGroup == 'manual',
                                      onSelected: (_) {
                                        setState2(() {
                                          activeGroup = 'manual';
                                          selectedPath = null;
                                        });
                                      },
                                    ),
                                    ChoiceChip(
                                      label: Text(
                                        'Automatic (${autoArchives.length})',
                                      ),
                                      selected: activeGroup == 'auto',
                                      onSelected: (_) {
                                        setState2(() {
                                          activeGroup = 'auto';
                                          selectedPath = null;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.search),
                                    hintText: 'Filter backups by name...',
                                  ),
                                  onChanged: (v) => setState2(() => filter = v),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const SizedBox(width: 8),
                                    Hint(
                                      message: 'Show newest first',
                                      child: ChoiceChip(
                                        label: const Text('Newest'),
                                        selected: sortMode == 'newest',
                                        onSelected: (_) => setState2(
                                          () => sortMode = 'newest',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Hint(
                                      message: 'Show oldest first',
                                      child: ChoiceChip(
                                        label: const Text('Oldest'),
                                        selected: sortMode == 'oldest',
                                        onSelected: (_) => setState2(
                                          () => sortMode = 'oldest',
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${filtered.length} backup${filtered.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: filtered.isEmpty
                                      ? Center(
                                          child: Text(
                                            activeGroup == 'manual'
                                                ? 'No manual backups match this filter.'
                                                : 'No automatic backups match this filter.',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: filtered.length,
                                          separatorBuilder: (context, index) =>
                                              const SizedBox(height: 8),
                                          itemBuilder: (ctx3, i) {
                                            final archive = filtered[i];
                                            final isSelected =
                                                archive.path == selectedPath;
                                            return Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                onTap: () async {
                                                  setState2(
                                                    () => selectedPath =
                                                        archive.path,
                                                  );
                                                  await ensureIntegrity(
                                                    archive,
                                                    setState2,
                                                  );
                                                },
                                                child: Ink(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? AppColors.tint(
                                                            AppColors.primary,
                                                            0.10,
                                                          )
                                                        : Colors.white,
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? AppColors.primary
                                                          : AppColors.border,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        archive.isAutoBackup
                                                            ? Icons
                                                                  .schedule_outlined
                                                            : Icons
                                                                  .backup_outlined,
                                                        color: isSelected
                                                            ? AppColors.primary
                                                            : AppColors
                                                                  .textSecondary,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              archive
                                                                  .displayName,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(
                                                              _formatTime(
                                                                archive
                                                                    .modifiedAt,
                                                              ),
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: AppColors
                                                                    .textSecondary,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 16),

                          Flexible(
                            flex: 5,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: selectedArchive == null
                                  ? const Center(
                                      child: Text(
                                        'Select a backup to see details and actions.',
                                      ),
                                    )
                                  : buildDetails(selectedArchive),
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: selectedArchive == null
                      ? null
                      : () async {
                          final archive = selectedArchive;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Confirm Restore'),
                              content: Text(
                                'Restore "${archive.displayName}" from ${_formatTime(archive.modifiedAt)}? A pre-restore backup will be created automatically.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(c).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(c).pop(true),
                                  child: const Text('Restore'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            await _restoreArchiveAndRefresh(archive);
                          }
                        },
                  child: const Text('Restore'),
                ),
                TextButton(
                  onPressed: selectedArchive == null
                      ? null
                      : () async {
                          final archive = selectedArchive;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Confirm Delete'),
                              content: Text(
                                'Permanently delete "${archive.displayName}"? This cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(c).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(c).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            try {
                              final f = File(archive.path);
                              if (await f.exists()) await f.delete();
                              if (!ctx.mounted) return;
                              await refreshArchives(setState2);
                              _showSnack('Deleted: ${archive.displayName}');
                            } catch (e) {
                              _showSnack('Delete failed: $e', isError: true);
                            }
                          }
                        },
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  String _formatTime(DateTime t) {
    return DateFormat('MMM d, yyyy, h:mm:ss a').format(t);
  }

  String _formatDurationLabel(Duration duration) {
    if (duration.inSeconds == 30) return '30 seconds';
    if (duration.inMinutes < 60) return '${duration.inMinutes} minutes';
    if (duration.inHours == 1) return '1 hour';
    return '${duration.inHours} hours';
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required bool obscureText,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          tooltip: obscureText ? 'Show password' : 'Hide password',
          onPressed: onToggle,
        ),
      ),
    );
  }

  Widget _buildLoginCredentialsCard() {
    return _settingsCard(
      title: 'Login Credentials',
      icon: Icons.lock_outline,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 16),
          maintainState: true,
          title: const Text(
            'Change username and password',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Current username: ${widget.appState.loginUsername}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Default username and password are both "admin" until changed. '
                'Enter your current username and password before saving new credentials.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Verify Current Credentials',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _currentUsernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Current Username',
                hintText: 'Enter current username',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            _passwordField(
              controller: _currentPasswordCtrl,
              labelText: 'Current Password',
              hintText: 'Enter current password',
              obscureText: _obscureCurrentPassword,
              onToggle: () => setState(
                () => _obscureCurrentPassword = !_obscureCurrentPassword,
              ),
            ),
            const SizedBox(height: 18),
            Divider(color: Colors.grey.shade200, height: 1),
            const SizedBox(height: 18),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Set New Credentials',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newUsernameCtrl,
              decoration: const InputDecoration(
                labelText: 'New Username',
                hintText: 'Enter new username',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            _passwordField(
              controller: _newPasswordCtrl,
              labelText: 'New Password',
              hintText: 'Enter new password',
              obscureText: _obscureNewPassword,
              onToggle: () =>
                  setState(() => _obscureNewPassword = !_obscureNewPassword),
            ),
            const SizedBox(height: 12),
            _passwordField(
              controller: _confirmPasswordCtrl,
              labelText: 'Confirm New Password',
              hintText: 'Re-enter new password',
              obscureText: _obscureConfirmPassword,
              onToggle: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Hint(
                message: 'Save updated login credentials',
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _savingCredentials ? null : _saveLoginCredentials,
                  icon: _savingCredentials
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _savingCredentials ? 'Saving...' : 'Save Credentials',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final padding = ResponsiveLayout.pagePaddingForWidth(
              constraints.maxWidth,
            );

            return SingleChildScrollView(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'System preferences and configuration.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ Organization Settings Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      _buildLoginCredentialsCard(),

                      const SizedBox(height: 20),

                      _settingsCard(
                        title: 'Organization',
                        icon: Icons.business_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Operating Unit',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'This name appears in Excel and PDF report headers.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final input = Hint(
                                  message: 'Edit operating unit name',
                                  child: TextField(
                                    controller: _operatingUnitCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Operating Unit Name',
                                      hintText: 'Department of Education',
                                    ),
                                  ),
                                );
                                final saveButton = Hint(
                                  message: 'Save operating unit name',
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _savingUnit
                                        ? null
                                        : _saveOperatingUnit,
                                    child: _savingUnit
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Save'),
                                  ),
                                );

                                if (constraints.maxWidth < 640) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      input,
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: saveButton,
                                      ),
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(child: input),
                                    const SizedBox(width: 12),
                                    saveButton,
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Current: ${widget.appState.operatingUnit}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ Currency Settings Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      _settingsCard(
                        title: 'Currency',
                        icon: Icons.attach_money_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Currency Symbol',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Shown before all monetary values throughout the app.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                SizedBox(
                                  width: 120,
                                  child: Hint(
                                    message: 'Edit currency symbol',
                                    child: TextField(
                                      controller: _currencyCtrl,
                                      maxLength: 5,
                                      decoration: const InputDecoration(
                                        labelText: 'Symbol',
                                        hintText: '\u20B1',
                                        counterText: '',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Hint(
                                  message: 'Save currency symbol',
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _savingCurrency
                                        ? null
                                        : _saveCurrency,
                                    child: _savingCurrency
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Save'),
                                  ),
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
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Current: "${widget.appState.currencySymbol}"',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ Deadline Notifications Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      _settingsCard(
                        title: 'Deadline Notifications',
                        icon: Icons.schedule_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Warning Window',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Show a badge on the Deadlines sidebar item when a WFP due date '
                              'or activity target date is within this many days.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              children: [7, 14, 30].map((days) {
                                final selected =
                                    widget.appState.warningDays == days;
                                return Hint(
                                  message: 'Set warning window to $days days',
                                  child: ChoiceChip(
                                    label: Text('$days days'),
                                    selected: selected,
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onSelected: (_) =>
                                        widget.appState.setWarningDays(days),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Current: ${widget.appState.warningDays} days | '
                              '${widget.appState.deadlineWarningCount} item(s) flagged right now',
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.appState.deadlineWarningCount > 0
                                    ? Colors.red.shade600
                                    : Colors.green.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Divider(color: Colors.grey.shade200, height: 1),
                            const SizedBox(height: 18),
                            SwitchListTile(
                              value: _reminderSettings.enabled,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Desktop reminders',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: const Text(
                                'Send Windows desktop notifications for urgent due-today and overdue work while the app is running.',
                                style: TextStyle(fontSize: 12),
                              ),
                              onChanged: (value) => _updateReminderSettings(
                                _reminderSettings.copyWith(enabled: value),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 220,
                                  child: DropdownButtonFormField<int>(
                                    initialValue:
                                        _reminderSettings.intervalMinutes,
                                    decoration: const InputDecoration(
                                      labelText: 'Reminder interval',
                                      isDense: true,
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 15,
                                        child: Text('Every 15 minutes'),
                                      ),
                                      DropdownMenuItem(
                                        value: 60,
                                        child: Text('Every hour'),
                                      ),
                                      DropdownMenuItem(
                                        value: 240,
                                        child: Text('Every 4 hours'),
                                      ),
                                      DropdownMenuItem(
                                        value: 1440,
                                        child: Text('Once a day'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      _updateReminderSettings(
                                        _reminderSettings.copyWith(
                                          intervalMinutes: value,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _checkRemindersNow,
                                  icon: const Icon(Icons.notifications_active),
                                  label: const Text('Check now'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [0, 1, 3, 7].map((days) {
                                final selected =
                                    _reminderSettings.urgencyDays == days;
                                final label = days == 0
                                    ? 'Today / overdue'
                                    : 'Due within $days day${days == 1 ? '' : 's'}';
                                return ChoiceChip(
                                  label: Text(label),
                                  selected: selected,
                                  selectedColor: AppColors.primary,
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  onSelected: (_) => _updateReminderSettings(
                                    _reminderSettings.copyWith(
                                      urgencyDays: days,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ Archive / Backup Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      _settingsCard(
                        title: 'Archive & Backup',
                        icon: Icons.archive_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Database Backup',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Create named manual backups on demand and keep automatic '
                              'backups separate. Restoring a backup refreshes the live '
                              'data right away without changing the original backup file.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Ã¢â€â‚¬Ã¢â€â‚¬ Action row Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Hint(
                                  message:
                                      'Create a named manual backup of the database',
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: _archiving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.backup_outlined,
                                            size: 18,
                                          ),
                                    label: Text(
                                      _archiving
                                          ? 'Backing up...'
                                          : 'Create Manual Backup',
                                    ),
                                    onPressed: _archiving
                                        ? null
                                        : _createArchive,
                                  ),
                                ),
                                Hint(
                                  message:
                                      'Open the app data archives folder in file explorer',
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xff2F3E46),
                                      side: const BorderSide(
                                        color: Color(0xff2F3E46),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.folder_open_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Open Archives Folder'),
                                    onPressed: _openArchiveFolder,
                                  ),
                                ),
                                Hint(
                                  message:
                                      'Manage snapshot files (restore/delete)',
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xff2F3E46),
                                      side: const BorderSide(
                                        color: Color(0xff2F3E46),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.history_toggle_off,
                                      size: 18,
                                    ),
                                    label: const Text('Manage Snapshots'),
                                    onPressed: _openSnapshotsDialog,
                                  ),
                                ),
                              ],
                            ),

                            // Ã¢â€â‚¬Ã¢â€â‚¬ Result banner Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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

                            // Ã¢â€â‚¬Ã¢â€â‚¬ Manual archive count + path Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$_archiveCount manual backup${_archiveCount == 1 ? '' : 's'} available. '
                                    'Open Manage Snapshots to view file details.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            const Divider(height: 1),
                            const SizedBox(height: 20),

                            // Ã¢â€â‚¬Ã¢â€â‚¬ Auto-Backup section Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                            Row(
                              children: [
                                const Text(
                                  'Auto-Backup',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.tint(
                                      AppColors.success,
                                      0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Automatically backs up the database after a period of '
                              'inactivity following the last record change. The timer '
                              'resets on every write - backup fires only when activity '
                              'goes quiet.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Ã¢â€â‚¬Ã¢â€â‚¬ Delay selector Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                            Text(
                              'Backup delay after last activity',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              children: _autoBackupDelayOptions.map((delay) {
                                final selected =
                                    DatabaseHelper.autoBackupDelay == delay;
                                final label = _formatDurationLabel(delay);
                                return Hint(
                                  message: 'Set auto-backup delay to $label',
                                  child: ChoiceChip(
                                    label: Text(label),
                                    selected: selected,
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onSelected: (_) async {
                                      await DatabaseHelper.setAutoBackupDelay(
                                        delay,
                                      );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 14),
                            Text(
                              'Auto-backup retention',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              children: _autoBackupRetentionOptions.map((
                                count,
                              ) {
                                final selected =
                                    DatabaseHelper.autoBackupRetention == count;
                                return Hint(
                                  message:
                                      'Keep the latest $count auto-backups',
                                  child: ChoiceChip(
                                    label: Text('$count copies'),
                                    selected: selected,
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onSelected: (_) async {
                                      await DatabaseHelper.setAutoBackupRetention(
                                        count,
                                      );
                                      if (mounted) {
                                        _refreshAutoStatus();
                                        setState(() {});
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 14),

                            // Ã¢â€â‚¬Ã¢â€â‚¬ Last auto-backup status Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
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
                                        ? AppColors.danger
                                        : _autoBackupTime != null
                                        ? AppColors.success
                                        : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _autoBackupFailed
                                              ? 'Last auto-backup failed'
                                              : _autoBackupTime != null
                                              ? 'Last auto-backup: ${_formatTime(_autoBackupTime!)}'
                                              : 'No automatic backup created yet',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _autoBackupFailed
                                                ? AppColors.danger
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$_autoArchiveCount of ${DatabaseHelper.autoBackupRetention} automatic backup slots currently used.',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ Recycle Bin Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      _settingsCard(
                        title: 'Recycle Bin',
                        icon: Icons.delete_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Deleted WFP Entries',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'WFP entries and their activities moved to the bin can be '
                              'restored or permanently deleted here.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final openButton = Hint(
                                  message: 'Open the Recycle Bin',
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outlined,
                                      size: 18,
                                    ),
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
                                      _refreshRecycleBinCount();
                                    },
                                  ),
                                );
                                final badge = _recycleBinCount > 0
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.tint(
                                            AppColors.danger,
                                            0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: AppColors.tint(
                                              AppColors.danger,
                                              0.28,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              size: 14,
                                              color: AppColors.danger,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '$_recycleBinCount deleted item${_recycleBinCount == 1 ? '' : 's'} awaiting review',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.danger,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : null;

                                if (constraints.maxWidth < 760) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      openButton,
                                      if (badge != null) ...[
                                        const SizedBox(height: 12),
                                        badge,
                                      ],
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    openButton,
                                    if (badge != null) ...[
                                      const SizedBox(width: 12),
                                      Expanded(child: badge),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ App Info Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      _settingsCard(
                        title: 'Bulk Import',
                        icon: Icons.upload_file_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Excel Import Workflow',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Import WFP and activity data from an Excel workbook using the WFP and Activities sheets. '
                              'Every import is previewed and a rollback snapshot is created before records are written.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _pickWorkbookForImport,
                                  icon: const Icon(Icons.file_open_outlined),
                                  label: const Text('Import Workbook'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _createImportTemplate,
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Download Template'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Tip: keep IDs unique and use YYYY-MM-DD for dates to avoid validation errors in the preview.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      _settingsCard(
                        title: 'Application',
                        icon: Icons.info_outline,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow(
                              'System',
                              'PMIS DepED - Personnel Management Information System',
                            ),
                            const SizedBox(height: 8),
                            _infoRow('Agency', widget.appState.operatingUnit),
                            const SizedBox(height: 8),
                            _infoRow(
                              'Install Folder',
                              _installDir.isEmpty ? 'Loading...' : _installDir,
                            ),
                            const SizedBox(height: 8),
                            _infoRow(
                              'Data Folder',
                              _dataDir.isEmpty ? 'Loading...' : _dataDir,
                            ),
                            const SizedBox(height: 8),
                            _infoRow(
                              'Database',
                              _dbPath.isEmpty ? 'Loading...' : _dbPath,
                            ),
                            const SizedBox(height: 8),
                            _infoRow(
                              'Archives',
                              _archiveDir.isEmpty ? 'Loading...' : _archiveDir,
                            ),
                            const SizedBox(height: 8),
                            _infoRow(
                              'Currency',
                              widget.appState.currencySymbol,
                            ),
                            const SizedBox(height: 16),
                            Divider(color: Colors.grey.shade200, height: 1),
                            const SizedBox(height: 16),
                            const Text(
                              'Developer Details',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _detailLine(_projectManagerLine),
                            const SizedBox(height: 8),
                            _detailLine(_leadDeveloperLine),
                            const SizedBox(height: 8),
                            _detailLine(_coDeveloperLine),
                            const SizedBox(height: 8),
                            _detailLine(_developerHandlesLine),
                            const SizedBox(height: 8),
                            _detailLine(_developerContactsLine),
                            const SizedBox(height: 8),
                            _detailLine(_developedForLine),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return SettingsSectionCard(title: title, icon: icon, child: child);
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    );
  }

  Widget _detailLine(String text) {
    return Text(text, style: const TextStyle(fontSize: 12));
  }
}
