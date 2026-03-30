import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'brand_mark.dart';

class Sidebar extends StatelessWidget {
  final Function(int) onSelect;
  final int currentIndex;
  final AppState appState;
  final bool compact;

  const Sidebar({
    super.key,
    required this.onSelect,
    required this.appState,
    this.currentIndex = 0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final topSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BrandMark(image: AssetImage('assets/images/logo.png')),
            const SizedBox(height: 16),
            const Text(
              'PMIS DepED',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.sidebarText,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'DepED Management System',
              style: TextStyle(color: AppColors.sidebarMutedText, fontSize: 10),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _item(Icons.dashboard_outlined, 'Dashboard', 0),
            _item(Icons.list_alt_outlined, 'WFP Management', 1),
            _item(Icons.account_balance_wallet_outlined, 'Budget Overview', 2),
            _item(Icons.summarize_outlined, 'Reports', 3),
            _badgeItem(
              Icons.schedule_outlined,
              'Deadlines',
              4,
              appState.deadlineWarningCount,
            ),
            _item(Icons.settings_outlined, 'Settings', 5),
            _item(Icons.history, 'Audit Log', 6),
          ],
        );

        final bottomSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (appState.hasActiveSession) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.primary, 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.sidebarText.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appState.currentActorName,
                      style: const TextStyle(
                        color: AppColors.sidebarText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
            Divider(
              color: AppColors.sidebarText.withValues(alpha: 0.12),
              height: 1,
            ),
            const SizedBox(height: 8),
            _item(Icons.logout, 'Log Out', 7),
          ],
        );

        return Container(
          width: compact ? null : 220,
          color: AppColors.sidebar,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final verticalPadding = compact ? 12.0 : 24.0;
                final minHeight = constraints.maxHeight.isFinite
                    ? (constraints.maxHeight - (verticalPadding + 24)).clamp(
                        0.0,
                        double.infinity,
                      )
                    : 0.0;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(10, verticalPadding, 10, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        topSection,
                        const SizedBox(height: 24),
                        bottomSection,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _item(IconData icon, String label, int index) {
    final active = currentIndex == index && index != 7;
    return _tile(icon, label, index, active, null);
  }

  Widget _badgeItem(IconData icon, String label, int index, int count) {
    final active = currentIndex == index;
    return _tile(icon, label, index, active, count > 0 ? count : null);
  }

  Widget _tile(
    IconData icon,
    String label,
    int index,
    bool active,
    int? badge,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: active ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          color: active ? Colors.white : AppColors.sidebarMutedText,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.sidebarText,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () => onSelect(index),
      ),
    );
  }
}
