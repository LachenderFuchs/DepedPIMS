import 'package:flutter/material.dart';

import '../models/budget_activity.dart';
import '../models/wfp_entry.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';

class DeadlinesPage extends StatelessWidget {
  final AppState appState;
  final Future<void> Function(String)? onOpenWFP;
  final Future<void> Function(String)? onOpenActivity;

  const DeadlinesPage({
    super.key,
    required this.appState,
    this.onOpenWFP,
    this.onOpenActivity,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final wfps = appState.wfpsDueSoon;
        final activities = appState.activitiesDueSoon;
        final total = wfps.length + activities.length;

        return LayoutBuilder(
          builder: (context, constraints) {
            final padding = ResponsiveLayout.pagePaddingForWidth(
              constraints.maxWidth,
            );
            final splitSections = constraints.maxWidth >= 960;

            return SingleChildScrollView(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (constraints.maxWidth < 780)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Deadlines',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Items due within ${appState.warningDays} days',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            if (total > 0) ...[
                              const SizedBox(height: 16),
                              _summaryBadge(total),
                            ],
                          ],
                        )
                      else
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
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Items due within ${appState.warningDays} days',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            if (total > 0) _summaryBadge(total),
                          ],
                        ),
                      const SizedBox(height: 28),
                      if (total == 0)
                        buildEmptyState()
                      else if (splitSections)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: buildSection(
                                icon: Icons.list_alt_outlined,
                                title: 'WFP Entries',
                                color: AppColors.primary,
                                isEmpty: wfps.isEmpty,
                                emptyMsg: 'No WFP entries due soon.',
                                children: wfps.map(buildWfpCard).toList(),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: buildSection(
                                icon: Icons.account_balance_wallet_outlined,
                                title: 'Budget Activities',
                                color: AppColors.success,
                                isEmpty: activities.isEmpty,
                                emptyMsg: 'No activities due soon.',
                                children: activities
                                    .map(buildActivityCard)
                                    .toList(),
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            buildSection(
                              icon: Icons.list_alt_outlined,
                              title: 'WFP Entries',
                              color: AppColors.primary,
                              isEmpty: wfps.isEmpty,
                              emptyMsg: 'No WFP entries due soon.',
                              children: wfps.map(buildWfpCard).toList(),
                            ),
                            const SizedBox(height: 20),
                            buildSection(
                              icon: Icons.account_balance_wallet_outlined,
                              title: 'Budget Activities',
                              color: AppColors.success,
                              isEmpty: activities.isEmpty,
                              emptyMsg: 'No activities due soon.',
                              children: activities
                                  .map(buildActivityCard)
                                  .toList(),
                            ),
                          ],
                        ),
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

  Widget _summaryBadge(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.tint(AppColors.warning, 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.tint(AppColors.warning, 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Text(
            '$total item${total == 1 ? '' : 's'} due soon',
            style: TextStyle(
              color: AppColors.warning,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.tint(AppColors.success, 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 56,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'All clear!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No deadlines approaching within the warning window.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSection({
    required IconData icon,
    required String title,
    required Color color,
    required bool isEmpty,
    required String emptyMsg,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
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
          const SizedBox(height: 14),
          if (isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Text(
                  emptyMsg,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            Column(children: children),
        ],
      ),
    );
  }

  Widget buildWfpCard(WFPEntry entry) {
    final days = entry.daysUntilDue;
    return buildDeadlineCard(
      id: entry.id,
      title: entry.title,
      subtitle: '${entry.fundType}  •  ${entry.year}',
      days: days,
      urgencyColor: urgencyColor(days),
      approvalBadge: entry.approvalStatus,
      onTap: onOpenWFP == null
          ? null
          : () {
              onOpenWFP!(entry.id);
            },
    );
  }

  Widget buildActivityCard(BudgetActivity activity) {
    final days = activity.daysUntilTarget;
    return buildDeadlineCard(
      id: activity.id,
      title: activity.name,
      subtitle: 'WFP: ${activity.wfpId}',
      days: days,
      urgencyColor: urgencyColor(days),
      onTap: onOpenActivity == null
          ? null
          : () {
              onOpenActivity!(activity.id);
            },
    );
  }

  Widget buildDeadlineCard({
    required String id,
    required String title,
    required String subtitle,
    required int? days,
    required Color urgencyColor,
    String? approvalBadge,
    VoidCallback? onTap,
  }) {
    final daysLabel = days == null
        ? 'No date set'
        : days < 0
        ? 'Overdue by ${-days}d'
        : days == 0
        ? 'Due today'
        : 'Due in ${days}d';

    final shell = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: urgencyColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final metaColumn = Column(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
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
              if (onTap != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Open record',
                  style: TextStyle(
                    fontSize: 10,
                    color: urgencyColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                metaColumn,
              ],
            );
          }

          return Row(
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
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              metaColumn,
            ],
          );
        },
      ),
    );

    if (onTap == null) return shell;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: shell,
      ),
    );
  }

  Widget buildApprovalChip(String status) {
    final color = status == 'Approved'
        ? AppColors.success
        : status == 'Rejected'
        ? AppColors.danger
        : AppColors.warning;
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
    if (days == null) return AppColors.textSecondary.withValues(alpha: 0.65);
    if (days < 0) return AppColors.danger;
    if (days <= 3) return AppColors.danger;
    if (days <= 7) return AppColors.warning;
    return AppColors.info;
  }
}
