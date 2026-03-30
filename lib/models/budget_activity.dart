class BudgetActivity {
  final String id;
  final String wfpId;
  final String name;
  final double total;
  final double projected;
  final double disbursed;
  final String status;

  /// ISO-8601 date string (yyyy-MM-dd) for when this activity should be completed.
  /// Used for deadline notifications.
  final String? targetDate;

  const BudgetActivity({
    required this.id,
    required this.wfpId,
    required this.name,
    required this.total,
    required this.projected,
    required this.disbursed,
    required this.status,
    this.targetDate,
  });

  /// Auto-calculated: Total Amount minus Disbursed Amount.
  double get balance => total - disbursed;

  /// Days until target date from today. Null if no target date set.
  int? get daysUntilTarget {
    if (targetDate == null) return null;
    final target = DateTime.tryParse(targetDate!);
    if (target == null) return null;
    final today = DateTime.now();
    final targetDateOnly = DateTime(target.year, target.month, target.day);
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    return targetDateOnly.difference(todayDateOnly).inDays;
  }

  BudgetActivity copyWith({
    String? id,
    String? wfpId,
    String? name,
    double? total,
    double? projected,
    double? disbursed,
    String? status,
    String? targetDate,
    bool clearTargetDate = false,
  }) {
    return BudgetActivity(
      id: id ?? this.id,
      wfpId: wfpId ?? this.wfpId,
      name: name ?? this.name,
      total: total ?? this.total,
      projected: projected ?? this.projected,
      disbursed: disbursed ?? this.disbursed,
      status: status ?? this.status,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'wfpId': wfpId,
    'name': name,
    'total': total,
    'projected': projected,
    'disbursed': disbursed,
    'status': status,
    'targetDate': targetDate,
  };

  factory BudgetActivity.fromMap(Map<String, dynamic> map) => BudgetActivity(
    id: map['id'] as String,
    wfpId: map['wfpId'] as String,
    name: map['name'] as String,
    total: (map['total'] as num).toDouble(),
    projected: (map['projected'] as num).toDouble(),
    disbursed: (map['disbursed'] as num).toDouble(),
    status: map['status'] as String,
    targetDate: map['targetDate'] as String?,
  );

  @override
  bool operator ==(Object other) => other is BudgetActivity && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
