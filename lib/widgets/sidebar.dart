import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  final Function(int) onSelect;
  final int currentIndex;

  const Sidebar({super.key, required this.onSelect, this.currentIndex = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: const Color(0xff2F3E46),
      child: Column(
        children: [
          const SizedBox(height: 40),

          const Text(
            'PIMS DepED',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'DepED Management System',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          _item(Icons.dashboard_outlined, 'Dashboard', 0),
          _item(Icons.list_alt_outlined, 'WFP Management', 1),
          _item(Icons.account_balance_wallet_outlined, 'Budget Overview', 2),
          _item(Icons.summarize_outlined, 'Reports', 3),
          _item(Icons.settings_outlined, 'Settings', 4),
          _item(Icons.person_outline, 'Profile', 5),

          const Spacer(),

          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 8),

          _item(Icons.logout, 'Log Out', 6),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String title, int index) {
    final isActive = currentIndex == index;
    // Log Out never shows as "active"
    final showActive = isActive && index != 6;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: showActive
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          color: showActive ? Colors.white : Colors.white70,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: showActive ? Colors.white : Colors.white70,
            fontWeight: showActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        onTap: () => onSelect(index),
      ),
    );
  }
}
