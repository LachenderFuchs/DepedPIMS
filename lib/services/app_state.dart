import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';
import '../database/database_helper.dart';
import '../utils/id_generator.dart';
import '../utils/currency_formatter.dart';
import 'login_credentials_store.dart';

class AppState extends ChangeNotifier {
  List<WFPEntry> _wfpEntries = [];
  List<BudgetActivity> _activities = [];
  List<BudgetActivity> _allActivities = [];
  WFPEntry? _selectedWFP;
  bool _isLoading = false;
  String? _error;
  int _totalActivityCount = 0;
  int _warningDays = 7;
  int _deadlineWarningCount = 0;
  int _recycleBinCount = 0;
  String _currentActorName = '';
  String _currentActorRole = 'Admin';
  List<WFPEntry> _wfpsDueSoon = [];
  List<BudgetActivity> _activitiesDueSoon = [];
  List<Map<String, dynamic>> _cachedRecycleBinEntries = [];
  List<Map<String, dynamic>> _cachedAuditLogEntries = [];
  static const String _prefsWFPKey = 'wfps_temp';
  static const String _prefsActivitiesKey = 'activities_temp';
  static const String _prefsRecycleBinKey = 'recycle_bin_temp';
  static const String _prefsAuditLogKey = 'audit_log_temp';
  String _loginUsername = LoginCredentialsStore.defaultUsername;
  String _loginPasswordHash = LoginCredentialsStore.defaultPasswordHash;

  Future<void> _savePrimaryCacheToPrefs() async {
    await _saveWFPsToPrefs();
    await _saveActivitiesToPrefs();
  }

  // ── App Settings ──────────────────────────────────────────────────────────
  String _operatingUnit = 'Department of Education';
  String _currencySymbol = '₱';

  List<WFPEntry> get wfpEntries => List.unmodifiable(_wfpEntries);
  List<BudgetActivity> get activities => List.unmodifiable(_activities);
  WFPEntry? get selectedWFP => _selectedWFP;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalActivityCount => _totalActivityCount;
  List<BudgetActivity> get allActivities => List.unmodifiable(_allActivities);
  int get deadlineWarningCount => _deadlineWarningCount;
  int get recycleBinCount => _recycleBinCount;
  List<WFPEntry> get wfpsDueSoon => List.unmodifiable(_wfpsDueSoon);
  List<BudgetActivity> get activitiesDueSoon =>
      List.unmodifiable(_activitiesDueSoon);
  int get warningDays => _warningDays;
  String get operatingUnit => _operatingUnit;
  String get currencySymbol => _currencySymbol;
  String get currentActorName => _currentActorName;
  String get loginUsername => _loginUsername;
  bool get hasActiveSession => _currentActorName.trim().isNotEmpty;

  bool validateCredentials({
    required String username,
    required String password,
  }) {
    return username.trim() == _loginUsername &&
        LoginCredentialsStore.hashPassword(password) == _loginPasswordHash;
  }

  Future<void> reloadLoginCredentials({bool notify = false}) async {
    final previousUsername = _loginUsername;
    final storedCredentials = await LoginCredentialsStore.load(
      allowLegacyMigration: true,
    );
    final changed =
        storedCredentials.username != _loginUsername ||
        storedCredentials.passwordHash != _loginPasswordHash;

    _loginUsername = storedCredentials.username;
    _loginPasswordHash = storedCredentials.passwordHash;

    if (_currentActorName.trim() == previousUsername &&
        previousUsername != _loginUsername) {
      _currentActorName = _loginUsername;
    }

    if (notify && changed) {
      notifyListeners();
    }
  }

  Future<bool> validateCredentialsFresh({
    required String username,
    required String password,
  }) async {
    await reloadLoginCredentials();
    return validateCredentials(username: username, password: password);
  }

  void startSession({required String username}) {
    _currentActorName = username.trim();
    _currentActorRole = 'Admin';
    notifyListeners();
  }

  void endSession() {
    _currentActorName = '';
    _currentActorRole = 'Admin';
    notifyListeners();
  }

  Future<void> init() async {
    _setLoading(true);
    try {
      await reloadLoginCredentials();

      final prefs = await SharedPreferences.getInstance();
      _warningDays = prefs.getInt('warningDays') ?? 7;
      _operatingUnit =
          prefs.getString('operatingUnit') ?? 'Department of Education';
      _currencySymbol = prefs.getString('currencySymbol') ?? '₱';
      // Sync currency symbol to formatter
      CurrencyFormatter.symbol = _currencySymbol;
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      _totalActivityCount = await DatabaseHelper.countAllActivities();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _cachedRecycleBinEntries = await DatabaseHelper.getRecycleBinEntries();
      _cachedAuditLogEntries = await DatabaseHelper.getAuditLog(limit: 500);
      _recycleBinCount = _cachedRecycleBinEntries.length;
      await _savePrimaryCacheToPrefs();
      await _saveRecycleBinToPrefs(_cachedRecycleBinEntries);
      await _saveAuditLogToPrefs(_cachedAuditLogEntries);
      _error = null;
    } catch (e) {
      // Database unavailable — fall back to the latest local cache.
      _error = 'Database unavailable, using local cache: $e';
      try {
        _wfpEntries = await _loadWFPsFromPrefs();
        _allActivities = await _loadActivitiesFromPrefs();
        _totalActivityCount = _allActivities.length;
        _cachedRecycleBinEntries = await _loadRecycleBinFromPrefs();
        _cachedAuditLogEntries = await _loadAuditLogFromPrefs();
        _recycleBinCount = _cachedRecycleBinEntries.length;
        await _refreshDeadlines();
      } catch (_) {
        _wfpEntries = [];
        _allActivities = [];
        _cachedRecycleBinEntries = [];
        _cachedAuditLogEntries = [];
      }
    } finally {
      _setLoading(false);
    }
  }

  // ── Local cache helpers (fallback when DB is unavailable) ───────────────
  Future<void> _saveWFPsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _wfpEntries.map((e) => e.toMap()).toList();
    await prefs.setString(_prefsWFPKey, jsonEncode(list));
  }

  Future<List<WFPEntry>> _loadWFPsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsWFPKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((m) => WFPEntry.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> _saveActivitiesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _allActivities.map((activity) => activity.toMap()).toList();
    await prefs.setString(_prefsActivitiesKey, jsonEncode(list));
  }

  Future<List<BudgetActivity>> _loadActivitiesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsActivitiesKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((map) => BudgetActivity.fromMap(Map<String, dynamic>.from(map)))
        .toList();
  }

  Future<void> _saveRecycleBinToPrefs(
    List<Map<String, dynamic>> entries,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsRecycleBinKey, jsonEncode(entries));
  }

  Future<List<Map<String, dynamic>>> _loadRecycleBinFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsRecycleBinKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  Future<void> _saveAuditLogToPrefs(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAuditLogKey, jsonEncode(entries));
  }

  Future<List<Map<String, dynamic>>> _loadAuditLogFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsAuditLogKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  Future<void> setWarningDays(int days) async {
    _warningDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('warningDays', days);
    await _refreshDeadlines();
    notifyListeners();
  }

  Future<void> setOperatingUnit(String value) async {
    _operatingUnit = value.trim().isEmpty
        ? 'Department of Education'
        : value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('operatingUnit', _operatingUnit);
    notifyListeners();
  }

  Future<void> setCurrencySymbol(String value) async {
    _currencySymbol = value.trim().isEmpty ? '₱' : value.trim();
    CurrencyFormatter.symbol = _currencySymbol;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currencySymbol', _currencySymbol);
    notifyListeners();
  }

  Future<void> setLoginCredentials({
    required String username,
    required String password,
  }) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      throw ArgumentError('Username cannot be empty.');
    }
    if (password.isEmpty) {
      throw ArgumentError('Password cannot be empty.');
    }

    final previousUsername = _loginUsername;
    _loginUsername = trimmedUsername;
    _loginPasswordHash = LoginCredentialsStore.hashPassword(password);

    await LoginCredentialsStore.save(
      LoginCredentials(
        username: _loginUsername,
        passwordHash: _loginPasswordHash,
      ),
      syncLegacyPrefs: true,
    );

    if (_currentActorName.trim() == previousUsername) {
      _currentActorName = _loginUsername;
    }

    notifyListeners();
  }

  Future<void> refreshDeadlineWarnings() async {
    await _refreshDeadlines();
    notifyListeners();
  }

  Future<void> _refreshDeadlines() async {
    try {
      _wfpsDueSoon = await DatabaseHelper.getWFPsDueSoon(_warningDays);
      _activitiesDueSoon = await DatabaseHelper.getActivitiesDueSoon(
        _warningDays,
      );
    } catch (_) {
      _wfpsDueSoon = _localDueSoonWfps();
      _activitiesDueSoon = _localDueSoonActivities();
    }
    _deadlineWarningCount = _wfpsDueSoon.length + _activitiesDueSoon.length;
  }

  List<WFPEntry> _localDueSoonWfps() {
    return _wfpEntries.where((entry) {
      final days = entry.daysUntilDue;
      return days != null && days <= _warningDays;
    }).toList()..sort((a, b) {
      final aDays = a.daysUntilDue ?? 9999;
      final bDays = b.daysUntilDue ?? 9999;
      if (aDays != bDays) return aDays.compareTo(bDays);
      return a.id.compareTo(b.id);
    });
  }

  List<BudgetActivity> _localDueSoonActivities() {
    return _allActivities.where((activity) {
      final days = activity.daysUntilTarget;
      return days != null && days <= _warningDays;
    }).toList()..sort((a, b) {
      final aDays = a.daysUntilTarget ?? 9999;
      final bDays = b.daysUntilTarget ?? 9999;
      if (aDays != bDays) return aDays.compareTo(bDays);
      return a.id.compareTo(b.id);
    });
  }

  Future<void> _cachePrimaryState() async {
    _totalActivityCount = _allActivities.length;
    await _savePrimaryCacheToPrefs();
  }

  Future<void> _cacheRecycleBinState() async {
    try {
      _cachedRecycleBinEntries = await DatabaseHelper.getRecycleBinEntries();
      _recycleBinCount = _cachedRecycleBinEntries.length;
      await _saveRecycleBinToPrefs(_cachedRecycleBinEntries);
    } catch (_) {
      _recycleBinCount = _cachedRecycleBinEntries.length;
    }
  }

  Future<void> _cacheAuditState() async {
    try {
      _cachedAuditLogEntries = await DatabaseHelper.getAuditLog(limit: 500);
      await _saveAuditLogToPrefs(_cachedAuditLogEntries);
    } catch (_) {}
  }

  Future<String> generateWFPId(int year) async {
    try {
      int count = await DatabaseHelper.countWFPsByYear(year);
      String id;
      do {
        count++;
        id = IDGenerator.generateWFP(year, count);
      } while (await DatabaseHelper.wfpIdExists(id));
      return id;
    } catch (_) {
      // Fallback: use local list to generate id
      final yearCount = _wfpEntries.where((w) => w.year == year).length;
      final count = yearCount + 1;
      return IDGenerator.generateWFP(year, count);
    }
  }

  Future<void> addWFP(WFPEntry entry) async {
    _setLoading(true);
    try {
      await DatabaseHelper.insertWFP(entry);
      await _logWFP('CREATE', entry);
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      await _cachePrimaryState();
      await _refreshDeadlines();
      await _cacheAuditState();
      _error = null;
    } catch (e) {
      // Fallback to local cache
      try {
        _wfpEntries.add(entry);
        await _cachePrimaryState();
        await _refreshDeadlines();
        _error = null;
      } catch (err) {
        _error = 'Failed to add WFP entry: $e';
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateWFP(WFPEntry entry) async {
    _setLoading(true);
    try {
      final before = await DatabaseHelper.getWFPById(entry.id);
      await DatabaseHelper.updateWFP(entry);
      await _logWFP('UPDATE', entry, before: before);
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      if (_selectedWFP?.id == entry.id) _selectedWFP = entry;
      await _cachePrimaryState();
      await _refreshDeadlines();
      await _cacheAuditState();
      _error = null;
    } catch (e) {
      // Fallback: update in local cache
      try {
        final idx = _wfpEntries.indexWhere((w) => w.id == entry.id);
        if (idx != -1) _wfpEntries[idx] = entry;
        if (_selectedWFP?.id == entry.id) _selectedWFP = entry;
        await _cachePrimaryState();
        await _refreshDeadlines();
        _error = null;
      } catch (err) {
        _error = 'Failed to update WFP entry: $e';
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Moves a WFP into the recycle bin (soft delete). Call this instead of
  /// the old deleteWFP everywhere — the recycle bin page handles hard deletes.
  Future<void> softDeleteWFP(String id) async {
    _setLoading(true);
    try {
      final wfp = await DatabaseHelper.getWFPById(id);
      if (wfp == null) {
        _error = 'WFP not found: $id';
        return;
      }
      final acts = await DatabaseHelper.getActivitiesForWFP(id);
      await DatabaseHelper.softDeleteWFP(wfp, acts);
      await _logWFP('DELETE', wfp);
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _cachePrimaryState();
      await _refreshDeadlines();
      await _cacheRecycleBinState();
      await _cacheAuditState();
      if (_selectedWFP?.id == id) {
        _selectedWFP = null;
        _activities = [];
      }
      _error = null;
    } catch (e, st) {
      _error = 'Failed to move WFP to recycle bin: $e';
      debugPrint('[RecycleBin] softDeleteWFP error: $e\n$st');
    } finally {
      _setLoading(false);
    }
  }

  // ─── Recycle Bin ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecycleBinEntries() async {
    try {
      final entries = await DatabaseHelper.getRecycleBinEntries();
      _cachedRecycleBinEntries = entries;
      _recycleBinCount = entries.length;
      await _saveRecycleBinToPrefs(entries);
      return entries;
    } catch (_) {
      if (_cachedRecycleBinEntries.isNotEmpty) {
        return List<Map<String, dynamic>>.from(_cachedRecycleBinEntries);
      }
      _cachedRecycleBinEntries = await _loadRecycleBinFromPrefs();
      _recycleBinCount = _cachedRecycleBinEntries.length;
      return List<Map<String, dynamic>>.from(_cachedRecycleBinEntries);
    }
  }

  /// Restores a WFP + activities from the bin back into live tables.
  /// Returns true on success, false if the ID already exists in live data.
  Future<bool> restoreFromBin(
    int binId,
    WFPEntry entry,
    List<BudgetActivity> activities,
  ) async {
    _setLoading(true);
    try {
      final ok = await DatabaseHelper.restoreWFPFromBin(
        binId,
        entry,
        activities,
      );
      if (ok) {
        await _logWFP('RESTORE', entry);
        _wfpEntries = await DatabaseHelper.getAllWFPs();
        _allActivities = await DatabaseHelper.getAllActivities();
        await _cachePrimaryState();
        await _refreshDeadlines();
        await _cacheRecycleBinState();
        await _cacheAuditState();
        _error = null;
      }
      return ok;
    } catch (e) {
      _error = 'Failed to restore entry: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> permanentlyDeleteFromBin(int binId) async {
    await DatabaseHelper.permanentlyDeleteFromBin(binId);
    await _cacheRecycleBinState();
    notifyListeners();
  }

  Future<void> emptyRecycleBin() async {
    await DatabaseHelper.emptyRecycleBin();
    _cachedRecycleBinEntries = [];
    _recycleBinCount = 0;
    await _saveRecycleBinToPrefs(_cachedRecycleBinEntries);
    notifyListeners();
  }

  Future<int> getActivityCountForWFP(String wfpId) async {
    try {
      return await DatabaseHelper.countActivitiesForWFP(wfpId);
    } catch (_) {
      return _allActivities.where((activity) => activity.wfpId == wfpId).length;
    }
  }

  Future<List<BudgetActivity>> loadActivitiesForReport(String wfpId) async {
    try {
      return await DatabaseHelper.getActivitiesForWFP(wfpId);
    } catch (_) {
      return _allActivities
          .where((activity) => activity.wfpId == wfpId)
          .toList(growable: false);
    }
  }

  Future<void> selectWFP(WFPEntry entry) async {
    _selectedWFP = entry;
    _setLoading(true);
    try {
      _activities = await DatabaseHelper.getActivitiesForWFP(entry.id);
      _error = null;
    } catch (e) {
      _activities = _allActivities
          .where((activity) => activity.wfpId == entry.id)
          .toList(growable: false);
      _error = 'Failed to load activities from database, using cached data: $e';
    } finally {
      _setLoading(false);
    }
  }

  void clearSelectedWFP() {
    _selectedWFP = null;
    _activities = [];
    notifyListeners();
  }

  Future<String> generateActivityId(String wfpId) async {
    try {
      int count = await DatabaseHelper.countActivitiesForWFP(wfpId);
      String id;
      do {
        count++;
        id = IDGenerator.generateActivity(wfpId, count);
      } while (await DatabaseHelper.activityIdExists(id));
      return id;
    } catch (_) {
      final count =
          _allActivities.where((activity) => activity.wfpId == wfpId).length +
          1;
      return IDGenerator.generateActivity(wfpId, count);
    }
  }

  Future<void> addActivity(BudgetActivity activity) async {
    _setLoading(true);
    try {
      await DatabaseHelper.insertActivity(activity);
      await _logActivity('CREATE', activity);
      if (_selectedWFP != null) {
        _activities = await DatabaseHelper.getActivitiesForWFP(
          _selectedWFP!.id,
        );
      }
      _allActivities = await DatabaseHelper.getAllActivities();
      await _cachePrimaryState();
      await _refreshDeadlines();
      await _cacheAuditState();
      _error = null;
    } catch (e) {
      try {
        _allActivities.add(activity);
        if (_selectedWFP?.id == activity.wfpId) {
          _activities = _allActivities
              .where((item) => item.wfpId == activity.wfpId)
              .toList(growable: false);
        }
        await _cachePrimaryState();
        await _refreshDeadlines();
        _error = null;
      } catch (_) {
        _error = 'Failed to add activity: $e';
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateActivity(BudgetActivity activity) async {
    _setLoading(true);
    try {
      final acts = _allActivities.where((a) => a.id == activity.id).toList();
      final before = acts.isNotEmpty ? acts.first : null;
      await DatabaseHelper.updateActivity(activity);
      await _logActivity('UPDATE', activity, before: before);
      if (_selectedWFP != null) {
        _activities = await DatabaseHelper.getActivitiesForWFP(
          _selectedWFP!.id,
        );
      }
      _allActivities = await DatabaseHelper.getAllActivities();
      await _cachePrimaryState();
      await _refreshDeadlines();
      await _cacheAuditState();
      _error = null;
    } catch (e) {
      try {
        final idx = _allActivities.indexWhere((item) => item.id == activity.id);
        if (idx != -1) _allActivities[idx] = activity;
        if (_selectedWFP?.id == activity.wfpId) {
          _activities = _allActivities
              .where((item) => item.wfpId == activity.wfpId)
              .toList(growable: false);
        }
        await _cachePrimaryState();
        await _refreshDeadlines();
        _error = null;
      } catch (_) {
        _error = 'Failed to update activity: $e';
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteActivity(String id) async {
    _setLoading(true);
    try {
      final acts = _allActivities.where((a) => a.id == id).toList();
      if (acts.isEmpty) {
        _error = 'Activity not found: $id';
        return false;
      }
      final activity = acts.first;
      await DatabaseHelper.softDeleteActivity(activity);
      await _logActivity('DELETE', activity);
      if (_selectedWFP != null) {
        _activities = await DatabaseHelper.getActivitiesForWFP(
          _selectedWFP!.id,
        );
      }
      _allActivities = await DatabaseHelper.getAllActivities();
      await _cachePrimaryState();
      await _refreshDeadlines();
      await _cacheRecycleBinState();
      await _cacheAuditState();
      _error = null;
      return true;
    } catch (e) {
      _error = 'Failed to move activity to recycle bin: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Restores a single Activity from the recycle bin.
  /// Returns true on success, false if the parent WFP is gone or ID conflicts.
  Future<bool> restoreActivityFromBin(
    int binId,
    BudgetActivity activity,
  ) async {
    _setLoading(true);
    try {
      final ok = await DatabaseHelper.restoreActivityFromBin(binId, activity);
      if (ok) {
        await _logActivity('RESTORE', activity);
        if (_selectedWFP?.id == activity.wfpId) {
          _activities = await DatabaseHelper.getActivitiesForWFP(
            activity.wfpId,
          );
        }
        _allActivities = await DatabaseHelper.getAllActivities();
        await _cachePrimaryState();
        await _refreshDeadlines();
        await _cacheRecycleBinState();
        await _cacheAuditState();
        _error = null;
      }
      return ok;
    } catch (e) {
      _error = 'Failed to restore activity: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, List<BudgetActivity>>> loadActivitiesMapForExport(
    List<String> wfpIds,
  ) async {
    try {
      return await DatabaseHelper.getActivitiesForWFPs(wfpIds);
    } catch (_) {
      final ids = wfpIds.toSet();
      final grouped = <String, List<BudgetActivity>>{};
      for (final activity in _allActivities) {
        if (!ids.contains(activity.wfpId)) continue;
        grouped.putIfAbsent(activity.wfpId, () => []).add(activity);
      }
      return grouped;
    }
  }

  Future<List<int>> getDistinctYears() async {
    try {
      return await DatabaseHelper.getDistinctYears();
    } catch (_) {
      final years = _wfpEntries.map((entry) => entry.year).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      return years;
    }
  }

  Future<List<WFPEntry>> getWFPsFiltered({
    int? year,
    String? approvalStatus,
  }) async {
    try {
      return await DatabaseHelper.getWFPsFiltered(
        year: year,
        approvalStatus: approvalStatus,
      );
    } catch (_) {
      return _wfpEntries
          .where((entry) {
            final yearMatch = year == null || entry.year == year;
            final approvalMatch =
                approvalStatus == null ||
                entry.approvalStatus == approvalStatus;
            return yearMatch && approvalMatch;
          })
          .toList(growable: false);
    }
  }

  double get totalAR => _activities.fold(0, (s, a) => s + a.total);
  double get totalObligated => _activities.fold(0, (s, a) => s + a.projected);
  double get totalDisbursed => _activities.fold(0, (s, a) => s + a.disbursed);
  double get totalBalance => _activities.fold(0, (s, a) => s + a.balance);
  double get dashboardTotalDisbursed =>
      _allActivities.fold(0, (s, a) => s + a.disbursed);
  double get dashboardTotalBalance =>
      _allActivities.fold(0, (s, a) => s + a.balance);

  // ─── Audit Log public ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAuditLog({
    int limit = 200,
    String? entityType,
    String? entityId,
  }) async {
    try {
      final entries = await DatabaseHelper.getAuditLog(
        limit: limit,
        entityType: entityType,
        entityId: entityId,
      );
      _cachedAuditLogEntries = entries;
      await _saveAuditLogToPrefs(entries);
      return entries;
    } catch (_) {
      if (_cachedAuditLogEntries.isEmpty) {
        _cachedAuditLogEntries = await _loadAuditLogFromPrefs();
      }
      return _cachedAuditLogEntries
          .where((entry) {
            final typeMatch =
                entityType == null || entry['entityType'] == entityType;
            final idMatch = entityId == null || entry['entityId'] == entityId;
            return typeMatch && idMatch;
          })
          .take(limit)
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
  }

  Future<void> clearAuditLog() async {
    try {
      await DatabaseHelper.clearAuditLog();
    } finally {
      _cachedAuditLogEntries = [];
      await _saveAuditLogToPrefs(_cachedAuditLogEntries);
    }
  }

  // ─── Audit helpers ─────────────────────────────────────────────────────────

  Future<bool> importWorkbookData({
    required List<WFPEntry> wfps,
    required List<BudgetActivity> activities,
    String? sourceLabel,
  }) async {
    if (wfps.isEmpty && activities.isEmpty) {
      return false;
    }

    _setLoading(true);
    final comment = sourceLabel == null || sourceLabel.trim().isEmpty
        ? 'Bulk import'
        : 'Bulk import: $sourceLabel';

    String? rollbackArchive;
    try {
      rollbackArchive = await DatabaseHelper.createManualArchive();
      for (final entry in wfps) {
        await DatabaseHelper.insertWFP(entry);
        await _logWFP(
          'CREATE',
          entry,
          actorComment: comment,
          refreshCache: false,
        );
      }
      for (final activity in activities) {
        await DatabaseHelper.insertActivity(activity);
        await _logActivity(
          'CREATE',
          activity,
          actorComment: comment,
          refreshCache: false,
        );
      }

      _wfpEntries = await DatabaseHelper.getAllWFPs();
      _allActivities = await DatabaseHelper.getAllActivities();
      if (_selectedWFP != null) {
        _activities = await DatabaseHelper.getActivitiesForWFP(
          _selectedWFP!.id,
        );
      }
      await _cachePrimaryState();
      await _refreshDeadlines();
      await _cacheAuditState();
      _error = null;
      return true;
    } catch (e) {
      _error = 'Bulk import failed and will be rolled back: $e';
      if (rollbackArchive != null) {
        try {
          await DatabaseHelper.restoreFromArchivePath(rollbackArchive);
        } catch (_) {}
      }
      await init();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Map<String, dynamic> _wfpSnapshot(WFPEntry e) => {
    'title': e.title,
    'targetSize': e.targetSize,
    'indicator': e.indicator,
    'year': e.year,
    'fundType': e.fundType,
    'viewSection': e.viewSection,
    'amount': e.amount,
    'approvalStatus': e.approvalStatus,
    'approvedDate': e.approvedDate,
    'dueDate': e.dueDate,
  };

  Map<String, dynamic> _activitySnapshot(BudgetActivity a) => {
    'wfpId': a.wfpId,
    'name': a.name,
    'total': a.total,
    'projected': a.projected,
    'disbursed': a.disbursed,
    'status': a.status,
    'targetDate': a.targetDate,
  };

  Map<String, dynamic> _diff(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    final diff = <String, dynamic>{};
    for (final key in after.keys) {
      if (before[key] != after[key]) {
        diff[key] = {'from': before[key], 'to': after[key]};
      }
    }
    return diff;
  }

  Map<String, dynamic> _snapshotAsDiff(Map<String, dynamic> snapshot) {
    return {
      for (final entry in snapshot.entries)
        entry.key: {'from': null, 'to': entry.value},
    };
  }

  Future<void> _logWFP(
    String action,
    WFPEntry entry, {
    WFPEntry? before,
    String? actorComment,
    bool refreshCache = true,
  }) async {
    final snapshot = _wfpSnapshot(entry);
    final diff = action == 'UPDATE'
        ? {
            '_meta': {'title': entry.title, 'viewSection': entry.viewSection},
            'fields': before != null
                ? _diff(_wfpSnapshot(before), snapshot)
                : _snapshotAsDiff(snapshot),
          }
        : snapshot;
    await DatabaseHelper.insertAuditLog(
      entityType: 'WFP',
      entityId: entry.id,
      action: action,
      actorName: _auditActorName,
      actorRole: _auditActorRole,
      actorComment: actorComment,
      diffJson: jsonEncode(diff),
    );
    if (refreshCache) {
      await _cacheAuditState();
    }
  }

  Future<void> _logActivity(
    String action,
    BudgetActivity a, {
    BudgetActivity? before,
    String? actorComment,
    bool refreshCache = true,
  }) async {
    final snapshot = _activitySnapshot(a);
    final diff = action == 'UPDATE'
        ? {
            '_meta': {'name': a.name, 'wfpId': a.wfpId},
            'fields': before != null
                ? _diff(_activitySnapshot(before), snapshot)
                : _snapshotAsDiff(snapshot),
          }
        : snapshot;
    await DatabaseHelper.insertAuditLog(
      entityType: 'Activity',
      entityId: a.id,
      action: action,
      actorName: _auditActorName,
      actorRole: _auditActorRole,
      actorComment: actorComment,
      diffJson: jsonEncode(diff),
    );
    if (refreshCache) {
      await _cacheAuditState();
    }
  }

  String get _auditActorName =>
      _currentActorName.trim().isEmpty ? 'Unknown user' : _currentActorName;

  String get _auditActorRole =>
      _currentActorRole.trim().isEmpty ? 'Admin' : _currentActorRole;

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
