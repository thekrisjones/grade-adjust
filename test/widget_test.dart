// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grade_adjust/screens/route_analyzer_screen.dart';

void main() {
  testWidgets('Route analyzer smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: RouteAnalyzerScreen()));

    // Verify that the upload button is present
    expect(find.text('Upload GPX File'), findsOneWidget);
  });
}
