import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../models/wfp_entry.dart';
import '../models/budget_activity.dart';
import '../widgets/sidebar.dart';
import '../widgets/summary_card.dart';
import 'wfp_management_page.dart';
import 'budget_overview_page.dart';
import 'reports_page.dart';
import 'deadlines_page.dart';
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
      DeadlinesPage(appState: widget.appState),
      SettingsPage(appState: widget.appState),
      const ProfilePage(),
    ];
  }

  void _onSidebarSelect(int index) {
    if (index == 7) {
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
          Sidebar(currentIndex: _pageIndex, onSelect: _onSidebarSelect, appState: widget.appState),
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

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 700;
            final cardGap = wide ? 16.0 : 8.0;

            Widget statCards = wide
                ? Column(children: [
                    Row(children: [
                      Expanded(child: SummaryCard(title: 'Total WFP Entries', value: entries.length.toString())),
                      SizedBox(width: cardGap),
                      Expanded(child: SummaryCard(title: 'Total WFP Budget', value: CurrencyFormatter.format(totalBudget))),
                      SizedBox(width: cardGap),
                      Expanded(child: SummaryCard(title: 'Fund Types Used', value: entries.map((e) => e.fundType).toSet().length.toString())),
                      SizedBox(width: cardGap),
                      Expanded(child: SummaryCard(title: 'Total Activities', value: appState.totalActivityCount.toString())),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: SummaryCard(title: 'Total Disbursed', value: CurrencyFormatter.format(appState.dashboardTotalDisbursed))),
                      SizedBox(width: cardGap),
                      Expanded(child: SummaryCard(title: 'Total Balance', value: CurrencyFormatter.format(appState.dashboardTotalBalance))),
                      SizedBox(width: cardGap),
                      const Expanded(child: SizedBox()),
                      SizedBox(width: cardGap),
                      const Expanded(child: SizedBox()),
                    ]),
                  ])
                : Wrap(
                    spacing: cardGap,
                    runSpacing: cardGap,
                    children: [
                      SizedBox(width: (constraints.maxWidth - cardGap) / 2 - 1,
                        child: SummaryCard(title: 'Total WFP Entries', value: entries.length.toString())),
                      SizedBox(width: (constraints.maxWidth - cardGap) / 2 - 1,
                        child: SummaryCard(title: 'Total WFP Budget', value: CurrencyFormatter.format(totalBudget))),
                      SizedBox(width: (constraints.maxWidth - cardGap) / 2 - 1,
                        child: SummaryCard(title: 'Fund Types Used', value: entries.map((e) => e.fundType).toSet().length.toString())),
                      SizedBox(width: (constraints.maxWidth - cardGap) / 2 - 1,
                        child: SummaryCard(title: 'Total Activities', value: appState.totalActivityCount.toString())),
                      SizedBox(width: (constraints.maxWidth - cardGap) / 2 - 1,
                        child: SummaryCard(title: 'Total Disbursed', value: CurrencyFormatter.format(appState.dashboardTotalDisbursed))),
                      SizedBox(width: (constraints.maxWidth - cardGap) / 2 - 1,
                        child: SummaryCard(title: 'Total Balance', value: CurrencyFormatter.format(appState.dashboardTotalBalance))),
                    ],
                  );

            // Charts always stacked vertically — bar chart on top, fund type below
            Widget chartsRow = entries.isEmpty
                ? const SizedBox()
                : Column(
                    children: [
                      _BudgetVsDisbursedChart(entries: entries, allActivities: allActivities),
                      const SizedBox(height: 16),
                      _FundTypeDistributionChart(entries: entries),
                    ],
                  );

            Widget panelsRow = wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(children: [
                        _PanelCard(icon: Icons.list_alt, title: 'WFP Management',
                          subtitle: '${entries.length} WFP entries recorded',
                          color: const Color(0xff2F3E46), onTap: () => onNavigate(1)),
                        const SizedBox(height: 8),
                        _WFPMiniList(entries: entries, onNavigate: onNavigate),
                      ])),
                      const SizedBox(width: 20),
                      Expanded(child: Column(children: [
                        _PanelCard(icon: Icons.account_balance_wallet, title: 'Budget Overview',
                          subtitle: 'Total: \${CurrencyFormatter.format(totalBudget)}',
                          color: const Color(0xff3A7CA5), onTap: () => onNavigate(2)),
                        const SizedBox(height: 8),
                        _ActivityMiniList(activities: allActivities),
                      ])),
                    ],
                  )
                : Column(children: [
                    _PanelCard(icon: Icons.list_alt, title: 'WFP Management',
                      subtitle: '${entries.length} WFP entries recorded',
                      color: const Color(0xff2F3E46), onTap: () => onNavigate(1)),
                    const SizedBox(height: 8),
                    _WFPMiniList(entries: entries, onNavigate: onNavigate),
                    const SizedBox(height: 16),
                    _PanelCard(icon: Icons.account_balance_wallet, title: 'Budget Overview',
                      subtitle: 'Total: \${CurrencyFormatter.format(totalBudget)}',
                      color: const Color(0xff3A7CA5), onTap: () => onNavigate(2)),
                    const SizedBox(height: 8),
                    _ActivityMiniList(activities: allActivities),
                  ]);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dashboard',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xff2F3E46))),
                  const SizedBox(height: 4),
                  Text('Welcome to PIMS DepED', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 24),
                  statCards,
                  const SizedBox(height: 28),
                  chartsRow,
                  if (entries.isNotEmpty) const SizedBox(height: 28),
                  panelsRow,
                ],
              ),
            );
          },
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
                Expanded(
                  child: Text(
                    e.title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xff2F3E46).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    e.fundType,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const SizedBox(width: 8),
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
      case 'Completed': return Colors.green.shade600;
      case 'Ongoing':   return Colors.blue.shade600;
      case 'At Risk':   return Colors.red.shade600;
      default:          return Colors.grey.shade500;
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
              Expanded(
                child: Text(
                  a.name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
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
              SizedBox(
                width: 100,
                child: Text(
                  CurrencyFormatter.format(a.total),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey.shade200,
            ),
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

class _BudgetVsDisbursedChart extends StatefulWidget {
  final List<WFPEntry> entries;
  final List<BudgetActivity> allActivities;

  const _BudgetVsDisbursedChart({
    required this.entries,
    required this.allActivities,
  });

  @override
  State<_BudgetVsDisbursedChart> createState() => _BudgetVsDisbursedChartState();
}

class _BudgetVsDisbursedChartState extends State<_BudgetVsDisbursedChart> {
  int? _hoveredIndex;

  String _compact(double v) {
    if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '₱${(v / 1000).toStringAsFixed(0)}K';
    return '₱${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final disbursedByWfp = <String, double>{};
    for (final a in widget.allActivities) {
      disbursedByWfp[a.wfpId] = (disbursedByWfp[a.wfpId] ?? 0) + a.disbursed;
    }

    final chartEntries = widget.entries.take(6).toList();

    final maxVal = chartEntries.fold<double>(1, (m, e) {
      final disbursed = disbursedByWfp[e.id] ?? 0;
      return [m, e.amount, disbursed].reduce((a, b) => a > b ? a : b);
    });

    const gridLines    = 4;
    final yStep        = maxVal / gridLines;
    const maxBarHeight = 120.0;
    const yAxisWidth   = 52.0;
    const xLabelHeight = 32.0;
    const tooltipH     = 100.0; // increased from 80 to prevent overflow
    const kChartBuffer = 10.0;  // safety threshold

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total AR Amount vs Disbursed',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Per WFP entry — most recent 6',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                _Legend(color: Color(0xff2F3E46), label: 'Total AR'),
                _Legend(color: Color(0xff3A7CA5), label: 'Disbursed'),
                _Legend(color: Color(0xff52B788), label: 'Balance'),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: tooltipH + maxBarHeight + xLabelHeight + kChartBuffer,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: yAxisWidth,
                    height: tooltipH + maxBarHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: List.generate(gridLines + 1, (i) {
                        final val   = yStep * (gridLines - i);
                        final topPx = tooltipH + (i / gridLines) * maxBarHeight;
                        return Positioned(
                          top: topPx - 6,
                          right: 6,
                          child: Text(
                            _compact(val),
                            style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
                            textAlign: TextAlign.right,
                          ),
                        );
                      }),
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: tooltipH + maxBarHeight + xLabelHeight + kChartBuffer,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                        ...List.generate(gridLines + 1, (i) {
                          final topPx = tooltipH + (i / gridLines) * maxBarHeight;
                          return Positioned(
                            top: topPx,
                            left: 0, right: 0,
                            child: Divider(height: 1, color: Colors.grey.shade200),
                          );
                        }),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: tooltipH + maxBarHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: chartEntries.asMap().entries.map((mapEntry) {
                              final idx       = mapEntry.key;
                              final e         = mapEntry.value;
                              final budget    = e.amount;
                              final disbursed = disbursedByWfp[e.id] ?? 0;
                              final balance   = (budget - disbursed).clamp(0.0, double.infinity) as double;
                              final isHovered = _hoveredIndex == idx;

                              final budgetH    = maxVal > 0 ? (budget    / maxVal * maxBarHeight).clamp(2.0, maxBarHeight) : 2.0;
                              final disbursedH = maxVal > 0 ? (disbursed / maxVal * maxBarHeight).clamp(0.0, maxBarHeight) : 0.0;
                              final balanceH   = maxVal > 0 ? (balance   / maxVal * maxBarHeight).clamp(0.0, maxBarHeight) : 0.0;

                              return Expanded(
                                child: MouseRegion(
                                  onEnter:  (_) => setState(() => _hoveredIndex = idx),
                                  onExit:   (_) => setState(() => _hoveredIndex = null),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      SizedBox(
                                        height: tooltipH,
                                        child: isHovered
                                            ? Align(
                                                alignment: Alignment.bottomCenter,
                                                child: Container(
                                                  margin: const EdgeInsets.only(bottom: 4),
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 7, vertical: 5,
                                                  ),
                                                  constraints: const BoxConstraints(maxWidth: 150),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xff2F3E46),
                                                    borderRadius: BorderRadius.circular(6),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.18),
                                                        blurRadius: 6,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        e.id,
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 8,
                                                          fontFamily: 'monospace',
                                                        ),
                                                      ),
                                                      Text(
                                                        e.title,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 9,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                      const SizedBox(height: 3),
                                                      _tooltipRow('Total AR',  budget,    const Color(0xff2F3E46)),
                                                      _tooltipRow('Disbursed', disbursed, const Color(0xff3A7CA5)),
                                                      _tooltipRow('Balance',   balance,   const Color(0xff52B788)),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _BarRect(height: budgetH,    color: const Color(0xff2F3E46), hovered: isHovered),
                                          const SizedBox(width: 2),
                                          _BarRect(height: disbursedH, color: const Color(0xff3A7CA5), hovered: isHovered),
                                          const SizedBox(width: 2),
                                          _BarRect(height: balanceH,   color: const Color(0xff52B788), hovered: isHovered),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        Positioned(
                          top: tooltipH + maxBarHeight,
                          left: 0,
                          right: 0,
                          height: xLabelHeight,
                          child: Row(
                            children: chartEntries.asMap().entries.map((mapEntry) {
                              final idx       = mapEntry.key;
                              final e         = mapEntry.value;
                              final isHovered = _hoveredIndex == idx;
                              final shortLabel = "${e.fundType}\n'${e.year.toString().substring(2)}";
                              return Expanded(
                                child: Center(
                                  child: Text(
                                    shortLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: isHovered ? const Color(0xff2F3E46) : Colors.grey.shade500,
                                      fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),  // SizedBox
                  ),  // Expanded
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tooltipRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '$label: ${_compact(value)}',
            style: const TextStyle(color: Colors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _BarRect extends StatelessWidget {
  final double height;
  final Color  color;
  final bool   hovered;

  const _BarRect({required this.height, required this.color, required this.hovered});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width:  hovered ? 13 : 11,
      height: height.clamp(2.0, double.infinity),
      decoration: BoxDecoration(
        color: hovered ? color : color.withValues(alpha: 0.85),
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
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
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
    final totals = <String, double>{};
    for (final e in entries) {
      totals[e.fundType] = (totals[e.fundType] ?? 0) + e.amount;
    }

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
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
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
                                valueColor: AlwaysStoppedAnimation<Color>(color),
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