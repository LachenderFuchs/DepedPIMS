import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';
import '../database/database_helper.dart';
import '../utils/id_generator.dart';
import '../utils/currency_formatter.dart';

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
  List<WFPEntry> _wfpsDueSoon = [];
  List<BudgetActivity> _activitiesDueSoon = [];

  // ── App Settings ──────────────────────────────────────────────────────────
  String _operatingUnit  = 'Department of Education';
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
  List<BudgetActivity> get activitiesDueSoon => List.unmodifiable(_activitiesDueSoon);
  int get warningDays => _warningDays;
  String get operatingUnit  => _operatingUnit;
  String get currencySymbol => _currencySymbol;

  Future<void> init() async {
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _warningDays     = prefs.getInt('warningDays') ?? 7;
      _operatingUnit   = prefs.getString('operatingUnit')  ?? 'Department of Education';
      _currencySymbol  = prefs.getString('currencySymbol') ?? '₱';
      // Sync currency symbol to formatter
      CurrencyFormatter.symbol = _currencySymbol;
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      _totalActivityCount = await DatabaseHelper.countAllActivities();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _recycleBinCount = await DatabaseHelper.countRecycleBin();
      _error = null;
    } catch (e) {
      // Database unavailable — fall back to local SharedPreferences cache.
      _error = 'Database unavailable, using local cache: $e';
      try {
        _wfpEntries = await _loadWFPsFromPrefs();
      } catch (_) {
        _wfpEntries = [];
      }
    } finally {
      _setLoading(false);
    }
  }

  // ── Local cache helpers (fallback when DB is unavailable) ───────────────
  static const String _prefsWFPKey = 'wfps_temp';

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
    return decoded.map((m) => WFPEntry.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<void> setWarningDays(int days) async {
    _warningDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('warningDays', days);
    await _refreshDeadlines();
    notifyListeners();
  }

  Future<void> setOperatingUnit(String value) async {
    _operatingUnit = value.trim().isEmpty ? 'Department of Education' : value.trim();
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

  Future<void> _refreshDeadlines() async {
    _wfpsDueSoon = await DatabaseHelper.getWFPsDueSoon(_warningDays);
    _activitiesDueSoon = await DatabaseHelper.getActivitiesDueSoon(_warningDays);
    _deadlineWarningCount = _wfpsDueSoon.length + _activitiesDueSoon.length;
  }

  Future<String> generateWFPId(int year) async {
    try {
      int count = await DatabaseHelper.countWFPsByYear(year);
      String id;
      do { count++; id = IDGenerator.generateWFP(year, count); }
      while (await DatabaseHelper.wfpIdExists(id));
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
      await _refreshDeadlines();
      _error = null;
    } catch (e) {
      // Fallback to local cache
      try {
        _wfpEntries.add(entry);
        await _saveWFPsToPrefs();
        _error = null;
      } catch (err) {
        _error = 'Failed to add WFP entry: $e';
      }
    } finally { _setLoading(false); }
  }

  Future<void> updateWFP(WFPEntry entry) async {
    _setLoading(true);
    try {
      final before = await DatabaseHelper.getWFPById(entry.id);
      await DatabaseHelper.updateWFP(entry);
      await _logWFP('UPDATE', entry, before: before);
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      if (_selectedWFP?.id == entry.id) _selectedWFP = entry;
      await _refreshDeadlines();
      _error = null;
    } catch (e) {
      // Fallback: update in local cache
      try {
        final idx = _wfpEntries.indexWhere((w) => w.id == entry.id);
        if (idx != -1) _wfpEntries[idx] = entry;
        await _saveWFPsToPrefs();
        if (_selectedWFP?.id == entry.id) _selectedWFP = entry;
        _error = null;
      } catch (err) {
        _error = 'Failed to update WFP entry: $e';
      }
    } finally { _setLoading(false); }
  }

  /// Moves a WFP into the recycle bin (soft delete). Call this instead of
  /// the old deleteWFP everywhere — the recycle bin page handles hard deletes.
  Future<void> softDeleteWFP(String id) async {
    _setLoading(true);
    try {
      final wfp = await DatabaseHelper.getWFPById(id);
      if (wfp == null) { _error = 'WFP not found: $id'; return; }
      final acts = await DatabaseHelper.getActivitiesForWFP(id);
      await DatabaseHelper.softDeleteWFP(wfp, acts);
      await _logWFP('DELETE', wfp);
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      _totalActivityCount = await DatabaseHelper.countAllActivities();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _recycleBinCount = await DatabaseHelper.countRecycleBin();
      if (_selectedWFP?.id == id) { _selectedWFP = null; _activities = []; }
      _error = null;
    } catch (e, st) {
      _error = 'Failed to move WFP to recycle bin: $e';
      debugPrint('[RecycleBin] softDeleteWFP error: $e\n$st');
    } finally { _setLoading(false); }
  }

  // ─── Recycle Bin ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecycleBinEntries() =>
      DatabaseHelper.getRecycleBinEntries();

  /// Restores a WFP + activities from the bin back into live tables.
  /// Returns true on success, false if the ID already exists in live data.
  Future<bool> restoreFromBin(
    int binId,
    WFPEntry entry,
    List<BudgetActivity> activities,
  ) async {
    _setLoading(true);
    try {
      final ok = await DatabaseHelper.restoreWFPFromBin(binId, entry, activities);
      if (ok) {
        await _logWFP('CREATE', entry);
        _wfpEntries = await DatabaseHelper.getAllWFPs();
        _totalActivityCount = await DatabaseHelper.countAllActivities();
        _allActivities = await DatabaseHelper.getAllActivities();
        await _refreshDeadlines();
        _recycleBinCount = await DatabaseHelper.countRecycleBin();
        _error = null;
      }
      return ok;
    } catch (e) {
      _error = 'Failed to restore entry: $e';
      return false;
    } finally { _setLoading(false); }
  }

  Future<void> permanentlyDeleteFromBin(int binId) async {
    await DatabaseHelper.permanentlyDeleteFromBin(binId);
    _recycleBinCount = await DatabaseHelper.countRecycleBin();
    notifyListeners();
  }

  Future<void> emptyRecycleBin() async {
    await DatabaseHelper.emptyRecycleBin();
    _recycleBinCount = 0;
    notifyListeners();
  }

  Future<int> getActivityCountForWFP(String wfpId) =>
      DatabaseHelper.countActivitiesForWFP(wfpId);

  Future<List<BudgetActivity>> loadActivitiesForReport(String wfpId) =>
      DatabaseHelper.getActivitiesForWFP(wfpId);

  Future<void> selectWFP(WFPEntry entry) async {
    _selectedWFP = entry;
    _setLoading(true);
    try {
      _activities = await DatabaseHelper.getActivitiesForWFP(entry.id);
      _error = null;
    } catch (e) { _error = 'Failed to load activities: $e'; }
    finally { _setLoading(false); }
  }

  void clearSelectedWFP() {
    _selectedWFP = null; _activities = []; notifyListeners();
  }

  Future<String> generateActivityId(String wfpId) async {
    int count = await DatabaseHelper.countActivitiesForWFP(wfpId);
    String id;
    do { count++; id = IDGenerator.generateActivity(wfpId, count); }
    while (await DatabaseHelper.activityIdExists(id));
    return id;
  }

  Future<void> addActivity(BudgetActivity activity) async {
    _setLoading(true);
    try {
      await DatabaseHelper.insertActivity(activity);
      await _logActivity('CREATE', activity);
      if (_selectedWFP != null) _activities = await DatabaseHelper.getActivitiesForWFP(_selectedWFP!.id);
      _totalActivityCount = await DatabaseHelper.countAllActivities();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _error = null;
    } catch (e) { _error = 'Failed to add activity: $e'; }
    finally { _setLoading(false); }
  }

  Future<void> updateActivity(BudgetActivity activity) async {
    _setLoading(true);
    try {
      final acts = _allActivities.where((a) => a.id == activity.id).toList();
      final before = acts.isNotEmpty ? acts.first : null;
      await DatabaseHelper.updateActivity(activity);
      await _logActivity('UPDATE', activity, before: before);
      if (_selectedWFP != null) _activities = await DatabaseHelper.getActivitiesForWFP(_selectedWFP!.id);
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _error = null;
    } catch (e) { _error = 'Failed to update activity: $e'; }
    finally { _setLoading(false); }
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
        _activities = await DatabaseHelper.getActivitiesForWFP(_selectedWFP!.id);
      }
      _totalActivityCount = await DatabaseHelper.countAllActivities();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _recycleBinCount = await DatabaseHelper.countRecycleBin();
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
  Future<bool> restoreActivityFromBin(int binId, BudgetActivity activity) async {
    _setLoading(true);
    try {
      final ok = await DatabaseHelper.restoreActivityFromBin(binId, activity);
      if (ok) {
        await _logActivity('CREATE', activity);
        if (_selectedWFP?.id == activity.wfpId) {
          _activities = await DatabaseHelper.getActivitiesForWFP(activity.wfpId);
        }
        _totalActivityCount = await DatabaseHelper.countAllActivities();
        _allActivities = await DatabaseHelper.getAllActivities();
        await _refreshDeadlines();
        _recycleBinCount = await DatabaseHelper.countRecycleBin();
        _error = null;
      }
      return ok;
    } catch (e) {
      _error = 'Failed to restore activity: $e';
      return false;
    } finally { _setLoading(false); }
  }

  Future<Map<String, List<BudgetActivity>>> loadActivitiesMapForExport(List<String> wfpIds) =>
      DatabaseHelper.getActivitiesForWFPs(wfpIds);

  Future<List<int>> getDistinctYears() => DatabaseHelper.getDistinctYears();

  Future<List<WFPEntry>> getWFPsFiltered({int? year, String? approvalStatus}) =>
      DatabaseHelper.getWFPsFiltered(year: year, approvalStatus: approvalStatus);

  double get totalAR => _activities.fold(0, (s, a) => s + a.total);
  double get totalObligated => _activities.fold(0, (s, a) => s + a.projected);
  double get totalDisbursed => _activities.fold(0, (s, a) => s + a.disbursed);
  double get totalBalance => _activities.fold(0, (s, a) => s + a.balance);
  double get dashboardTotalDisbursed => _allActivities.fold(0, (s, a) => s + a.disbursed);
  double get dashboardTotalBalance => _allActivities.fold(0, (s, a) => s + a.balance);



  // ─── Audit Log public ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAuditLog({
    int limit = 200,
    String? entityType,
    String? entityId,
  }) => DatabaseHelper.getAuditLog(
    limit: limit, entityType: entityType, entityId: entityId);

  Future<void> clearAuditLog() => DatabaseHelper.clearAuditLog();

  // ─── Audit helpers ─────────────────────────────────────────────────────────

  Map<String, dynamic> _wfpSnapshot(WFPEntry e) => {
    'title': e.title, 'targetSize': e.targetSize, 'indicator': e.indicator,
    'year': e.year, 'fundType': e.fundType, 'amount': e.amount,
    'approvalStatus': e.approvalStatus, 'approvedDate': e.approvedDate,
    'dueDate': e.dueDate,
  };

  Map<String, dynamic> _activitySnapshot(BudgetActivity a) => {
    'name': a.name, 'total': a.total, 'projected': a.projected,
    'disbursed': a.disbursed, 'status': a.status, 'targetDate': a.targetDate,
  };

  Map<String, dynamic> _diff(Map<String, dynamic> before, Map<String, dynamic> after) {
    final diff = <String, dynamic>{};
    for (final key in after.keys) {
      if (before[key] != after[key]) {
        diff[key] = {'from': before[key], 'to': after[key]};
      }
    }
    return diff;
  }

  Future<void> _logWFP(String action, WFPEntry entry, {WFPEntry? before}) async {
    final diff = before != null
        ? _diff(_wfpSnapshot(before), _wfpSnapshot(entry))
        : _wfpSnapshot(entry);
    await DatabaseHelper.insertAuditLog(
      entityType: 'WFP', entityId: entry.id,
      action: action, diffJson: jsonEncode(diff));
  }

  Future<void> _logActivity(String action, BudgetActivity a, {BudgetActivity? before}) async {
    final diff = before != null
        ? _diff(_activitySnapshot(before), _activitySnapshot(a))
        : _activitySnapshot(a);
    await DatabaseHelper.insertAuditLog(
      entityType: 'Activity', entityId: a.id,
      action: action, diffJson: jsonEncode(diff));
  }

  void _setLoading(bool v) { _isLoading = v; notifyListeners(); }
  void clearError() { _error = null; notifyListeners(); }
}