import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import 'wfp_management_page.dart';
import 'budget_overview_page.dart';

class DashboardPage extends StatefulWidget {
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {

  int index = 0;

  final pages = [
    WFPManagementPage(),
    BudgetOverviewPage()
  ];

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: Row(
        children: [

          Sidebar(
            selectedIndex: index,
            onItemSelected: (i){
              setState(()=> index = i);
            },
          ),

          Expanded(child: pages[index])
        ],
      ),
    );
  }
}