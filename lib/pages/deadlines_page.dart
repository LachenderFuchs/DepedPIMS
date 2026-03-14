import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';

class DeadlinesPage extends StatelessWidget {
  final AppState appState;

  const DeadlinesPage({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final wfps       = appState.wfpsDueSoon;
        final activities = appState.activitiesDueSoon;
        final total      = wfps.length + activities.length;

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Deadlines',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff2F3E46),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Items due within ${appState.warningDays} days',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '$total item${total == 1 ? '' : 's'} due soon',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 28),

              if (total == 0)
                Expanded(child: buildEmptyState())
              else
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: buildSection(
                          context: context,
                          icon: Icons.list_alt_outlined,
                          title: 'WFP Entries',
                          color: const Color(0xff3A7CA5),
                          isEmpty: wfps.isEmpty,
                          emptyMsg: 'No WFP entries due soon.',
                          children: wfps.map((e) => buildWfpCard(e)).toList(),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: buildSection(
                          context: context,
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Budget Activities',
                          color: const Color(0xff52B788),
                          isEmpty: activities.isEmpty,
                          emptyMsg: 'No activities due soon.',
                          children: activities.map((a) => buildActivityCard(a)).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_outline, size: 56, color: Colors.green.shade400),
          ),
          const SizedBox(height: 20),
          const Text(
            'All clear!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xff2F3E46),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No deadlines approaching within the warning window.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget buildSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required bool isEmpty,
    required String emptyMsg,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${children.length}',
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                emptyMsg,
                style: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          )
        else
          Expanded(
            child: ListView(children: children),
          ),
      ],
    );
  }

  Widget buildWfpCard(WFPEntry e) {
    final days = e.daysUntilDue;
    return buildDeadlineCard(
      id: e.id,
      title: e.title,
      subtitle: '${e.fundType}  •  ${e.year}',
      days: days,
      urgencyColor: urgencyColor(days),
      approvalBadge: e.approvalStatus,
    );
  }

  Widget buildActivityCard(BudgetActivity a) {
    final days = a.daysUntilTarget;
    return buildDeadlineCard(
      id: a.id,
      title: a.name,
      subtitle: 'WFP: ${a.wfpId}',
      days: days,
      urgencyColor: urgencyColor(days),
    );
  }

  Widget buildDeadlineCard({
    required String id,
    required String title,
    required String subtitle,
    required int? days,
    required Color urgencyColor,
    String? approvalBadge,
  }) {
    final daysLabel = days == null
        ? 'No date set'
        : days < 0
            ? 'Overdue by ${-days}d'
            : days == 0
                ? 'Due today'
                : 'Due in ${days}d';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: urgencyColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: urgencyColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  daysLabel,
                  style: TextStyle(
                    color: urgencyColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              if (approvalBadge != null) ...[
                const SizedBox(height: 5),
                buildApprovalChip(approvalBadge),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget buildApprovalChip(String status) {
    final color = status == 'Approved'
        ? Colors.green.shade600
        : status == 'Rejected'
            ? Colors.red.shade600
            : Colors.orange.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color urgencyColor(int? days) {
    if (days == null) return Colors.grey.shade400;
    if (days < 0)    return Colors.red.shade700;
    if (days <= 3)   return Colors.red.shade500;
    if (days <= 7)   return Colors.orange.shade600;
    return Colors.amber.shade600;
  }
}