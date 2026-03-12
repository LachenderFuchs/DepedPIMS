class BudgetActivity {

  String id;
  String wfpId;

  double totalAmount;
  double projectedAmount;
  double disbursedAmount;

  BudgetActivity({
    required this.id,
    required this.wfpId,
    required this.totalAmount,
    required this.projectedAmount,
    required this.disbursedAmount
  });

  double get balance => totalAmount - disbursedAmount;
}