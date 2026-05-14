// Smoke test only: full `HrmsApp` needs `RuntimeConfig` + `SupabaseApp.init()` (see `lib/main.dart`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Material shell smoke', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      title: 'HRMS',
      home: Scaffold(body: Text('HRMS')),
    ));
    expect(find.text('HRMS'), findsWidgets);
  });
}
