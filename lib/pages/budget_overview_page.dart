import 'package:flutter/material.dart';
import '../models/budget_activity.dart';
import 'package:uuid/uuid.dart';

class BudgetOverviewPage extends StatefulWidget {

  @override
  State<BudgetOverviewPage> createState() => _BudgetOverviewPageState();
}

class _BudgetOverviewPageState extends State<BudgetOverviewPage> {

  final uuid = Uuid();

  List<BudgetActivity> activities = [];

  final total = TextEditingController();
  final projected = TextEditingController();
  final disbursed = TextEditingController();

  void addActivity(){

    final act = BudgetActivity(
      id: uuid.v4(),
      wfpId: "TEMP",
      totalAmount: double.parse(total.text),
      projectedAmount: double.parse(projected.text),
      disbursedAmount: double.parse(disbursed.text),
    );

    setState(()=> activities.add(act));
  }

  double get totalBalance {
    return activities.fold(0, (sum, a)=> sum + a.balance);
  }

  @override
  Widget build(BuildContext context){

    return Padding(
      padding: EdgeInsets.all(20),

      child: Column(

        children: [

          Text("Budget Overview Dashboard", style: TextStyle(fontSize:22)),

          Row(
            children: [

              Expanded(child: TextField(controller: total, decoration: InputDecoration(labelText:"Total Amount"))),

              Expanded(child: TextField(controller: projected, decoration: InputDecoration(labelText:"Projected"))),

              Expanded(child: TextField(controller: disbursed, decoration: InputDecoration(labelText:"Disbursed"))),
            ],
          ),

          SizedBox(height:10),

          ElevatedButton(
            onPressed: addActivity,
            child: Text("Add Activity"),
          ),

          SizedBox(height:20),

          Text("Total AR Balance: ₱$totalBalance", style: TextStyle(fontSize:18)),

          Expanded(
            child: ListView.builder(
              itemCount: activities.length,
              itemBuilder: (_,i){

                final a = activities[i];

                return ListTile(
                  title: Text("Activity ${i+1}"),
                  subtitle: Text("Balance: ${a.balance}"),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}