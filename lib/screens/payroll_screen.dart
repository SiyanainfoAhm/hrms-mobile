import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/app_drawer.dart';

class PayrollScreen extends StatelessWidget {
  const PayrollScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll')),
      drawer: AppDrawer(app: app),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Payroll (admin) — TODO: payroll periods/run'),
      ),
    );
  }
}

