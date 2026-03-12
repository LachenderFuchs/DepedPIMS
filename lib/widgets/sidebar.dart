import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {

  final int selectedIndex;
  final Function(int) onItemSelected;

  Sidebar({required this.selectedIndex, required this.onItemSelected});

  @override
  Widget build(BuildContext context) {

    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onItemSelected,
      labelType: NavigationRailLabelType.all,
      destinations: const [

        NavigationRailDestination(
          icon: Icon(Icons.dashboard),
          label: Text("WFP Management"),
        ),

        NavigationRailDestination(
          icon: Icon(Icons.attach_money),
          label: Text("Budget Overview"),
        ),
      ],
    );
  }
}