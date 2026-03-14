import 'package:flutter/material.dart';
import '../services/app_state.dart';

class SettingsPage extends StatelessWidget {
  final AppState appState;

  const SettingsPage({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff2F3E46),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'System preferences and configuration.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 32),

              // ── Deadline Settings Card ───────────────────────────────────
              _settingsCard(
                title: 'Deadline Notifications',
                icon: Icons.schedule_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Warning Window',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Show a badge on the Deadlines sidebar item when a WFP due date or activity target date is within this many days.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      children: [7, 14, 30].map((days) {
                        final selected = appState.warningDays == days;
                        return ChoiceChip(
                          label: Text('$days days'),
                          selected: selected,
                          selectedColor: const Color(0xff2F3E46),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : const Color(0xff2F3E46),
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => appState.setWarningDays(days),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Current setting: ${appState.warningDays} days  •  '
                      '${appState.deadlineWarningCount} item(s) flagged right now',
                      style: TextStyle(
                        fontSize: 12,
                        color: appState.deadlineWarningCount > 0
                            ? Colors.red.shade600
                            : Colors.green.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Placeholder for future settings ──────────────────────────
              _settingsCard(
                title: 'Application',
                icon: Icons.info_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('System', 'PIMS DepED — Personnel Information Management System'),
                    const SizedBox(height: 8),
                    _infoRow('Agency', 'Department of Education'),
                    const SizedBox(height: 8),
                    _infoRow('Database', 'Documents/pims_deped.db (SQLite)'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _settingsCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xff2F3E46), size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xff2F3E46),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}