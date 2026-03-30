import '../models/budget_activity.dart';
import '../models/wfp_entry.dart';
import 'currency_formatter.dart';

class RecordValidator {
  static String normalizeText(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String? validateWfp({
    required String title,
    required String targetSize,
    required String indicator,
    required double? amount,
    required int year,
    required String fundType,
    required String viewSection,
    required String approvalStatus,
    required String? approvedDate,
    required String? dueDate,
    required Iterable<WFPEntry> existingEntries,
    String? editingId,
  }) {
    final normalizedTitle = normalizeText(title);
    if (normalizedTitle.isEmpty) {
      return 'Title cannot be empty.';
    }
    if (normalizeText(targetSize).isEmpty) {
      return 'Target size cannot be empty.';
    }
    if (normalizeText(indicator).isEmpty) {
      return 'Indicator cannot be empty.';
    }
    if (amount == null) {
      return 'Please enter a valid amount.';
    }
    if (amount < 0) {
      return 'Amount cannot be negative.';
    }

    final approved = _parseDate(approvedDate);
    final due = _parseDate(dueDate);
    if (approvedDate != null && approved == null) {
      return 'Approved date is invalid.';
    }
    if (dueDate != null && due == null) {
      return 'Due date is invalid.';
    }
    if (approvalStatus == 'Approved' && approved == null) {
      return 'Approved entries must have an approved date.';
    }
    if (approved != null && due != null && due.isBefore(approved)) {
      return 'Due date cannot be earlier than the approved date.';
    }

    final duplicate = existingEntries.any((entry) {
      if (entry.id == editingId) return false;
      return normalizeText(entry.title) == normalizedTitle &&
          entry.year == year &&
          entry.fundType == fundType &&
          entry.viewSection == viewSection;
    });
    if (duplicate) {
      return 'A matching WFP entry already exists for this year, fund type, and section.';
    }

    return null;
  }

  static String? validateActivity({
    required WFPEntry selectedWFP,
    required String name,
    required double? total,
    required double? projected,
    required double? disbursed,
    required String? targetDate,
    required Iterable<BudgetActivity> existingActivities,
    String? editingId,
  }) {
    if (!selectedWFP.isApproved) {
      return 'Cannot add activities. Approve the WFP entry first.';
    }
    if (normalizeText(name).isEmpty) {
      return 'Activity name cannot be empty.';
    }
    if (total == null || projected == null || disbursed == null) {
      return 'Please enter valid numeric values.';
    }
    if (total < 0 || projected < 0 || disbursed < 0) {
      return 'Amounts cannot be negative.';
    }

    final duplicate = existingActivities.any((activity) {
      if (activity.id == editingId) return false;
      return normalizeText(activity.name) == normalizeText(name);
    });
    if (duplicate) {
      return 'An activity with this name already exists for the selected WFP.';
    }

    final otherTotal = existingActivities
        .where((activity) => activity.id != editingId)
        .fold<double>(0, (sum, activity) => sum + activity.total);
    if (otherTotal + total > selectedWFP.amount) {
      final remaining = selectedWFP.amount - otherTotal;
      return 'Exceeds WFP ceiling. Remaining: ${CurrencyFormatter.format(remaining < 0 ? 0 : remaining)}';
    }

    final approved = _parseDate(selectedWFP.approvedDate);
    final due = _parseDate(selectedWFP.dueDate);
    final target = _parseDate(targetDate);
    if (targetDate != null && target == null) {
      return 'Target date is invalid.';
    }
    if (approved != null && target != null && target.isBefore(approved)) {
      return 'Target date cannot be earlier than the WFP approved date.';
    }
    if (due != null && target != null && target.isAfter(due)) {
      return 'Target date cannot be later than the WFP due date.';
    }

    return null;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}
