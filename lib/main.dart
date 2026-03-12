import 'package:flutter/material.dart';
import 'pages/login_page.dart';

void main() {
  runApp(PIMSApp());
}

class PIMSApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PIMS DepED',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginPage(),
    );
  }
}