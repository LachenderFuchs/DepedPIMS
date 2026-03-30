import '../models/budget_activity.dart';
import '../models/wfp_entry.dart';

class DashboardSnapshot {
  final List<WFPEntry> entries;
  final List<BudgetActivity> activities;
  final List<int> fiscalYearStarts;
  final double totalBudget;
  final double totalDisbursed;
  final double activityBalance;
  final double totalityBalance;
  final int fundTypeCount;
  final int totalActivityCount;

  const DashboardSnapshot({
    required this.entries,
    required this.activities,
    required this.fiscalYearStarts,
    required this.totalBudget,
    required this.totalDisbursed,
    required this.activityBalance,
    required this.totalityBalance,
    required this.fundTypeCount,
    required this.totalActivityCount,
  });

  factory DashboardSnapshot.build({
    required List<WFPEntry> allEntries,
    required List<BudgetActivity> allActivities,
    required int? fiscalYearStart,
  }) {
    final fiscalYearStarts = _distinctFiscalYearStarts(allEntries);
    final entries = fiscalYearStart == null
        ? List<WFPEntry>.from(allEntries)
        : allEntries
              .where((entry) => _inFiscalYear(entry, fiscalYearStart))
              .toList(growable: false);
    final selectedWfpIds = entries.map((entry) => entry.id).toSet();
    final activities = fiscalYearStart == null
        ? List<BudgetActivity>.from(allActivities)
        : allActivities
              .where((activity) => selectedWfpIds.contains(activity.wfpId))
              .toList(growable: false);

    final totalBudget = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.amount,
    );
    final totalDisbursed = activities.fold<double>(
      0,
      (sum, activity) => sum + activity.disbursed,
    );
    final activityBalance = activities.fold<double>(
      0,
      (sum, activity) => sum + activity.balance,
    );

    return DashboardSnapshot(
      entries: entries,
      activities: activities,
      fiscalYearStarts: fiscalYearStarts,
      totalBudget: totalBudget,
      totalDisbursed: totalDisbursed,
      activityBalance: activityBalance,
      totalityBalance: totalBudget - totalDisbursed,
      fundTypeCount: entries.map((entry) => entry.fundType).toSet().length,
      totalActivityCount: activities.length,
    );
  }

  static bool _inFiscalYear(WFPEntry entry, int startYear) =>
      entry.year == startYear || entry.year == startYear + 1;

  static List<int> _distinctFiscalYearStarts(List<WFPEntry> entries) {
    final years = entries.map((entry) => entry.year).toSet();
    final fyStarts = <int>{};
    for (final year in years) {
      fyStarts.add(year - 1);
      fyStarts.add(year);
    }
    return fyStarts.toList()..sort((a, b) => b.compareTo(a));
  }
}
