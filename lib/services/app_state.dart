import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';
import '../database/database_helper.dart';
import '../utils/id_generator.dart';

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
  List<WFPEntry> _wfpsDueSoon = [];
  List<BudgetActivity> _activitiesDueSoon = [];

  List<WFPEntry> get wfpEntries => List.unmodifiable(_wfpEntries);
  List<BudgetActivity> get activities => List.unmodifiable(_activities);
  WFPEntry? get selectedWFP => _selectedWFP;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalActivityCount => _totalActivityCount;
  List<BudgetActivity> get allActivities => List.unmodifiable(_allActivities);
  int get deadlineWarningCount => _deadlineWarningCount;
  List<WFPEntry> get wfpsDueSoon => List.unmodifiable(_wfpsDueSoon);
  List<BudgetActivity> get activitiesDueSoon => List.unmodifiable(_activitiesDueSoon);
  int get warningDays => _warningDays;

  Future<void> init() async {
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _warningDays = prefs.getInt('warningDays') ?? 7;
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      _totalActivityCount = await DatabaseHelper.countAllActivities();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _error = null;
    } catch (e) {
      _error = 'Failed to load data: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> setWarningDays(int days) async {
    _warningDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('warningDays', days);
    await _refreshDeadlines();
    notifyListeners();
  }

  Future<void> _refreshDeadlines() async {
    _wfpsDueSoon = await DatabaseHelper.getWFPsDueSoon(_warningDays);
    _activitiesDueSoon = await DatabaseHelper.getActivitiesDueSoon(_warningDays);
    _deadlineWarningCount = _wfpsDueSoon.length + _activitiesDueSoon.length;
  }

  Future<String> generateWFPId(int year) async {
    int count = await DatabaseHelper.countWFPsByYear(year);
    String id;
    do { count++; id = IDGenerator.generateWFP(year, count); }
    while (await DatabaseHelper.wfpIdExists(id));
    return id;
  }

  Future<void> addWFP(WFPEntry entry) async {
    _setLoading(true);
    try {
      await DatabaseHelper.insertWFP(entry);
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      await _refreshDeadlines();
      _error = null;
    } catch (e) { _error = 'Failed to add WFP entry: $e'; }
    finally { _setLoading(false); }
  }

  Future<void> updateWFP(WFPEntry entry) async {
    _setLoading(true);
    try {
      await DatabaseHelper.updateWFP(entry);
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      if (_selectedWFP?.id == entry.id) _selectedWFP = entry;
      await _refreshDeadlines();
      _error = null;
    } catch (e) { _error = 'Failed to update WFP entry: $e'; }
    finally { _setLoading(false); }
  }

  Future<void> deleteWFP(String id) async {
    _setLoading(true);
    try {
      await DatabaseHelper.deleteWFP(id);
      _wfpEntries = await DatabaseHelper.getAllWFPs();
      _totalActivityCount = await DatabaseHelper.countAllActivities();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      if (_selectedWFP?.id == id) { _selectedWFP = null; _activities = []; }
      _error = null;
    } catch (e) { _error = 'Failed to delete WFP entry: $e'; }
    finally { _setLoading(false); }
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
      await DatabaseHelper.updateActivity(activity);
      if (_selectedWFP != null) _activities = await DatabaseHelper.getActivitiesForWFP(_selectedWFP!.id);
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _error = null;
    } catch (e) { _error = 'Failed to update activity: $e'; }
    finally { _setLoading(false); }
  }

  Future<void> deleteActivity(String id) async {
    _setLoading(true);
    try {
      await DatabaseHelper.deleteActivity(id);
      if (_selectedWFP != null) _activities = await DatabaseHelper.getActivitiesForWFP(_selectedWFP!.id);
      _totalActivityCount = await DatabaseHelper.countAllActivities();
      _allActivities = await DatabaseHelper.getAllActivities();
      await _refreshDeadlines();
      _error = null;
    } catch (e) { _error = 'Failed to delete activity: $e'; }
    finally { _setLoading(false); }
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

  void _setLoading(bool v) { _isLoading = v; notifyListeners(); }
  void clearError() { _error = null; notifyListeners(); }
}