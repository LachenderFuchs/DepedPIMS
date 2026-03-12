import 'package:flutter/material.dart';
import 'dashboard_page.dart';

class LoginPage extends StatelessWidget {

  final username = TextEditingController();
  final password = TextEditingController();

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 350,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              Text("PIMS DepED Login", style: TextStyle(fontSize: 24)),

              TextField(
                controller: username,
                decoration: InputDecoration(labelText: "Username"),
              ),

              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(labelText: "Password"),
              ),

              SizedBox(height:20),

              ElevatedButton(
                child: Text("Login"),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => DashboardPage()),
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}