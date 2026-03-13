import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';
import '../widgets/sidebar.dart';
import '../widgets/summary_card.dart';
import 'wfp_management_page.dart';
import 'budget_overview_page.dart';
import 'reports_page.dart';
import 'settings_page.dart';
import 'profile_page.dart';
import 'login_page.dart';
import '../utils/currency_formatter.dart';

class DashboardPage extends StatefulWidget {
  final AppState appState;

  const DashboardPage({super.key, required this.appState});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _pageIndex = 0;

  // ── IMPORTANT: pages are created ONCE here, not inside build().
  // IndexedStack keeps all three widgets alive in the tree at all times,
  // so their State objects (and local controllers) are never destroyed
  // when the user switches between sections.
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      _DashboardHome(
        appState: widget.appState,
        onNavigate: (i) => setState(() => _pageIndex = i),
      ),
      WFPManagementPage(appState: widget.appState),
      BudgetOverviewPage(appState: widget.appState),
      ReportsPage(appState: widget.appState),
      const SettingsPage(),
      const ProfilePage(),
    ];
  }

  void _onSidebarSelect(int index) {
    if (index == 6) {
      _confirmLogout();
      return;
    }
    setState(() => _pageIndex = index);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      widget.appState.clearSelectedWFP();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginPage(appState: widget.appState)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Sidebar(currentIndex: _pageIndex, onSelect: _onSidebarSelect),
          // IndexedStack renders all pages but only shows the active one.
          // This keeps each page's State alive — no resets on tab switch.
          Expanded(
            child: IndexedStack(index: _pageIndex, children: _pages),
          ),
        ],
      ),
    );
  }
}

// ─── Dashboard Home ───────────────────────────────────────────────────────────

class _DashboardHome extends StatelessWidget {
  final AppState appState;
  final void Function(int) onNavigate;

  const _DashboardHome({required this.appState, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final entries = appState.wfpEntries;
        final allActivities = appState.allActivities;
        final totalBudget = entries.fold<double>(0, (s, e) => s + e.amount);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ──────────────────────────────────────────────────
              const Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff2F3E46),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Welcome to PIMS DepED',
                style: TextStyle(color: Colors.grey.shade600),
              ),

              const SizedBox(height: 24),

              // ── Stat cards ─────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      title: 'Total WFP Entries',
                      value: entries.length.toString(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SummaryCard(
                      title: 'Total WFP Budget',
                      value: CurrencyFormatter.format(totalBudget),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SummaryCard(
                      title: 'Fund Types Used',
                      value: entries
                          .map((e) => e.fundType)
                          .toSet()
                          .length
                          .toString(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SummaryCard(
                      title: 'Total Activities',
                      value: appState.totalActivityCount.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      title: 'Total Disbursed',
                      value: CurrencyFormatter.format(
                        appState.dashboardTotalDisbursed,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SummaryCard(
                      title: 'Total Balance',
                      value: CurrencyFormatter.format(
                        appState.dashboardTotalBalance,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(child: SizedBox()),
                  const SizedBox(width: 16),
                  const Expanded(child: SizedBox()),
                ],
              ),

              const SizedBox(height: 28),

              // ── Charts row ─────────────────────────────────────────────
              if (entries.isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bar chart: Budget vs Disbursed per WFP
                    Expanded(
                      flex: 3,
                      child: _BudgetVsDisbursedChart(
                        entries: entries,
                        allActivities: allActivities,
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Bar/pie: Fund type distribution by total amount
                    Expanded(
                      flex: 2,
                      child: _FundTypeDistributionChart(entries: entries),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],

              // ── Panel cards + mini-lists ────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WFP panel
                  Expanded(
                    child: Column(
                      children: [
                        _PanelCard(
                          icon: Icons.list_alt,
                          title: 'WFP Management',
                          subtitle: '${entries.length} WFP entries recorded',
                          color: const Color(0xff2F3E46),
                          onTap: () => onNavigate(1),
                        ),
                        const SizedBox(height: 8),
                        _WFPMiniList(entries: entries, onNavigate: onNavigate),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Budget panel
                  Expanded(
                    child: Column(
                      children: [
                        _PanelCard(
                          icon: Icons.account_balance_wallet,
                          title: 'Budget Overview',
                          subtitle:
                              'Total: ${CurrencyFormatter.format(totalBudget)}',
                          color: const Color(0xff3A7CA5),
                          onTap: () => onNavigate(2),
                        ),
                        const SizedBox(height: 8),
                        _ActivityMiniList(activities: allActivities),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── WFP Mini List ────────────────────────────────────────────────────────────

class _WFPMiniList extends StatelessWidget {
  final List<WFPEntry> entries;
  final void Function(int) onNavigate;

  const _WFPMiniList({required this.entries, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _emptyMiniList('No WFP entries yet.');
    }
    return _MiniListCard(
      children: entries.map((e) {
        return InkWell(
          onTap: () => onNavigate(1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                // ID
                SizedBox(
                  width: 110,
                  child: Text(
                    e.id,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Color(0xff2F3E46),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Title
                Expanded(
                  child: Text(
                    e.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Fund Type badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff2F3E46).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(e.fundType, style: const TextStyle(fontSize: 10)),
                ),
                const SizedBox(width: 8),
                // Amount
                SizedBox(
                  width: 100,
                  child: Text(
                    CurrencyFormatter.format(e.amount),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff2F3E46),
                    ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Year
                SizedBox(
                  width: 36,
                  child: Text(
                    e.year.toString(),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Activity Mini List ───────────────────────────────────────────────────────

class _ActivityMiniList extends StatelessWidget {
  final List<BudgetActivity> activities;

  const _ActivityMiniList({required this.activities});

  Color _statusColor(String status) {
    switch (status) {
      case 'Completed':
        return Colors.green.shade600;
      case 'Ongoing':
        return Colors.blue.shade600;
      case 'At Risk':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return _emptyMiniList('No budget activities yet.');
    }
    return _MiniListCard(
      children: activities.map((a) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              // Activity ID
              SizedBox(
                width: 110,
                child: Text(
                  a.id,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Color(0xff3A7CA5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Name
              Expanded(
                child: Text(
                  a.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(a.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  a.status,
                  style: TextStyle(
                    fontSize: 10,
                    color: _statusColor(a.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Total AR Amount
              SizedBox(
                width: 100,
                child: Text(
                  CurrencyFormatter.format(a.total),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Shared mini-list card container with scrollable body ─────────────────────

class _MiniListCard extends StatelessWidget {
  final List<Widget> children;

  const _MiniListCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        height: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: children.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ),
    );
  }
}

Widget _emptyMiniList(String message) {
  return Card(
    elevation: 2,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: SizedBox(
      height: 220,
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        ),
      ),
    ),
  );
}

// ─── Budget vs Disbursed Bar Chart ────────────────────────────────────────────

class _BudgetVsDisbursedChart extends StatelessWidget {
  final List<WFPEntry> entries;
  final List<BudgetActivity> allActivities;

  const _BudgetVsDisbursedChart({
    required this.entries,
    required this.allActivities,
  });

  @override
  Widget build(BuildContext context) {
    // Compute disbursed per WFP from allActivities
    final disbursedByWfp = <String, double>{};
    for (final a in allActivities) {
      disbursedByWfp[a.wfpId] = (disbursedByWfp[a.wfpId] ?? 0) + a.disbursed;
    }

    // Take the most recent 6 entries to keep the chart readable
    final chartEntries = entries.length > 6
        ? entries.sublist(entries.length - 6)
        : entries;

    final maxVal = chartEntries.fold<double>(0, (m, e) {
      final budget = e.amount;
      final disbursed = disbursedByWfp[e.id] ?? 0;
      return [m, budget, disbursed].reduce((a, b) => a > b ? a : b);
    });

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Budget vs Disbursed per WFP',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _Legend(color: const Color(0xff2F3E46), label: 'Budget'),
                const SizedBox(width: 16),
                _Legend(color: const Color(0xff3A7CA5), label: 'Disbursed'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: chartEntries.map((e) {
                  final budget = e.amount;
                  final disbursed = disbursedByWfp[e.id] ?? 0;
                  final budgetRatio = maxVal > 0 ? budget / maxVal : 0.0;
                  final disbursedRatio = maxVal > 0 ? disbursed / maxVal : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _Bar(
                                ratio: budgetRatio,
                                color: const Color(0xff2F3E46),
                                maxHeight: 140,
                              ),
                              const SizedBox(width: 3),
                              _Bar(
                                ratio: disbursedRatio,
                                color: const Color(0xff3A7CA5),
                                maxHeight: 140,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            e.id.replaceFirst('WFP-', ''),
                            style: const TextStyle(fontSize: 9),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double ratio;
  final Color color;
  final double maxHeight;

  const _Bar({
    required this.ratio,
    required this.color,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final height = (ratio * maxHeight).clamp(2.0, maxHeight);
    return Container(
      width: 14,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ─── Fund Type Distribution Chart ────────────────────────────────────────────

class _FundTypeDistributionChart extends StatelessWidget {
  final List<WFPEntry> entries;

  const _FundTypeDistributionChart({required this.entries});

  // Consistent color palette for up to 13 fund types
  static const _palette = [
    Color(0xff2F3E46),
    Color(0xff3A7CA5),
    Color(0xff52B788),
    Color(0xffE76F51),
    Color(0xff9B5DE5),
    Color(0xffF4A261),
    Color(0xff2EC4B6),
    Color(0xffE63946),
    Color(0xff457B9D),
    Color(0xff6A994E),
    Color(0xffF77F00),
    Color(0xff8338EC),
    Color(0xff06D6A0),
  ];

  @override
  Widget build(BuildContext context) {
    // Aggregate total amount per fund type
    final totals = <String, double>{};
    for (final e in entries) {
      totals[e.fundType] = (totals[e.fundType] ?? 0) + e.amount;
    }

    // Sort descending by amount
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final grandTotal = sorted.fold<double>(0, (s, e) => s + e.value);
    final maxVal = sorted.isEmpty ? 1.0 : sorted.first.value;

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fund Type Distribution',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Total budget by fund type',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            if (sorted.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'No entries yet.',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
              )
            else
              ...sorted.asMap().entries.map((mapEntry) {
                final idx = mapEntry.key;
                final fundEntry = mapEntry.value;
                final color = _palette[idx % _palette.length];
                final barRatio = maxVal > 0 ? fundEntry.value / maxVal : 0.0;
                final pct = grandTotal > 0
                    ? (fundEntry.value / grandTotal * 100).toStringAsFixed(1)
                    : '0.0';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              fundEntry.key,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const SizedBox(width: 14),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: barRatio,
                                minHeight: 7,
                                backgroundColor: Colors.grey.shade100,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  color,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: Text(
                              CurrencyFormatter.format(fundEntry.value),
                              style: const TextStyle(fontSize: 10),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ─── Panel Card ───────────────────────────────────────────────────────────────

class _PanelCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PanelCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
