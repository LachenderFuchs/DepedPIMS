class WFPEntry {
  final String id;
  final String title;
  final String targetSize;
  final String indicator;
  final int year;
  final String fundType;
  final double amount;

  /// Approval lifecycle: 'Pending' | 'Approved' | 'Rejected'
  final String approvalStatus;

  /// ISO-8601 date string (yyyy-MM-dd) set when approvalStatus → 'Approved'.
  /// Null until approved.
  final String? approvedDate;

  /// ISO-8601 date string (yyyy-MM-dd) for this WFP's due/end date.
  /// Used for deadline notifications.
  final String? dueDate;

  const WFPEntry({
    required this.id,
    required this.title,
    required this.targetSize,
    required this.indicator,
    required this.year,
    required this.fundType,
    required this.amount,
    this.approvalStatus = 'Pending',
    this.approvedDate,
    this.dueDate,
  });

  /// True only when this entry has been explicitly approved.
  bool get isApproved => approvalStatus == 'Approved';

  /// Days until due date from today. Null if no due date set.
  int? get daysUntilDue {
    if (dueDate == null) return null;
    final due = DateTime.tryParse(dueDate!);
    if (due == null) return null;
    return due.difference(DateTime.now()).inDays;
  }

  WFPEntry copyWith({
    String? id,
    String? title,
    String? targetSize,
    String? indicator,
    int? year,
    String? fundType,
    double? amount,
    String? approvalStatus,
    String? approvedDate,
    String? dueDate,
    bool clearApprovedDate = false,
    bool clearDueDate = false,
  }) {
    return WFPEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      targetSize: targetSize ?? this.targetSize,
      indicator: indicator ?? this.indicator,
      year: year ?? this.year,
      fundType: fundType ?? this.fundType,
      amount: amount ?? this.amount,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      approvedDate: clearApprovedDate ? null : (approvedDate ?? this.approvedDate),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'targetSize': targetSize,
        'indicator': indicator,
        'year': year,
        'fundType': fundType,
        'amount': amount,
        'approvalStatus': approvalStatus,
        'approvedDate': approvedDate,
        'dueDate': dueDate,
      };

  factory WFPEntry.fromMap(Map<String, dynamic> map) => WFPEntry(
        id: map['id'] as String,
        title: map['title'] as String,
        targetSize: map['targetSize'] as String,
        indicator: map['indicator'] as String,
        year: map['year'] as int,
        fundType: map['fundType'] as String,
        amount: (map['amount'] as num).toDouble(),
        approvalStatus: (map['approvalStatus'] as String?) ?? 'Pending',
        approvedDate: map['approvedDate'] as String?,
        dueDate: map['dueDate'] as String?,
      );

  @override
  String toString() => 'WFPEntry($id, $title, $fundType, $year, $approvalStatus)';

  @override
  bool operator ==(Object other) => other is WFPEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}