import 'package:flutter/material.dart';
import '../models/wfp_entry.dart';
import 'package:uuid/uuid.dart';
import 'package:data_table_2/data_table_2.dart';

class WFPManagementPage extends StatefulWidget {

  @override
  State<WFPManagementPage> createState() => _WFPManagementPageState();
}

class _WFPManagementPageState extends State<WFPManagementPage> {

  final uuid = Uuid();

  List<WFPEntry> entries = [];

  final title = TextEditingController();
  final target = TextEditingController();
  final indicator = TextEditingController();
  final amount = TextEditingController();

  int year = 2026;
  String fundType = "MODE";

  void addEntry(){

    final newEntry = WFPEntry(
      id: uuid.v4(),
      title: title.text,
      targetSize: target.text,
      indicator: indicator.text,
      year: year,
      fundType: fundType,
      amount: double.parse(amount.text),
    );

    setState(() {
      entries.add(newEntry);
    });
  }

  @override
  Widget build(BuildContext context){

    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [

          Text("WFP Management Dashboard", style: TextStyle(fontSize: 22)),

          Row(
            children: [

              Expanded(child: TextField(controller: title, decoration: InputDecoration(labelText:"Title"))),

              SizedBox(width:10),

              Expanded(child: TextField(controller: amount, decoration: InputDecoration(labelText:"Amount")))
            ],
          ),

          SizedBox(height:10),

          ElevatedButton(
            onPressed: addEntry,
            child: Text("Add Entry"),
          ),

          SizedBox(height:20),

          Expanded(
        child: DataTable2(
            columnSpacing: 20,
            horizontalMargin: 12,
            minWidth: 600,
            columns: const [
            DataColumn(label: Text("ID")),
            DataColumn(label: Text("Title")),
            DataColumn(label: Text("Fund Type")),
            DataColumn(label: Text("Amount")),
            DataColumn(label: Text("Year")),
            ],
            rows: entries.map((entry) {
            return DataRow(
                cells: [
                DataCell(Text(entry.id.substring(0, 8))),
                DataCell(Text(entry.title)),
                DataCell(Text(entry.fundType)),
                DataCell(Text(entry.amount.toString())),
                DataCell(Text(entry.year.toString())),
                ],
            );
            }).toList(),
        ),
        )
        ],
      ),
    );
  }
}