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

  testWidgets('Route analyzer includes a distance/elevation unit toggle',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RouteAnalyzerScreen()));

    expect(find.text('km / m'), findsOneWidget);
    expect(find.text('mi / ft'), findsOneWidget);
  });

  testWidgets('Responsive route analysis layout resolves the supported breakpoint modes',
      (WidgetTester tester) async {
    final controls = const SizedBox.shrink();

    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveRouteAnalysisLayout(
          layoutMode: RouteLayoutMode.narrow,
          mapAndElevation: controls,
          histograms: controls,
          splitsTable: controls,
        ),
      ),
    );

    expect(
      tester.widget<ResponsiveRouteAnalysisLayout>(
        find.byType(ResponsiveRouteAnalysisLayout),
      ).layoutMode,
      RouteLayoutMode.narrow,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveRouteAnalysisLayout(
          layoutMode: RouteLayoutMode.medium,
          mapAndElevation: controls,
          histograms: controls,
          splitsTable: controls,
        ),
      ),
    );

    expect(
      tester.widget<ResponsiveRouteAnalysisLayout>(
        find.byType(ResponsiveRouteAnalysisLayout),
      ).layoutMode,
      RouteLayoutMode.medium,
    );
  });

  test('Rounded histogram bins stay readable and provide at least five buckets', () {
    final elevation = RouteAnalyzerScreen.buildRoundedHistogramBoundaries(
      minValue: 32,
      maxValue: 140,
      stepOptions: const [200, 100, 50, 25, 10],
      minimumBins: 5,
      forceZeroStart: true,
    );

    expect(elevation.length >= 6, isTrue);
    expect(elevation.first, 0.0);
    expect(elevation.contains(50.0), isTrue);
    expect(elevation.contains(100.0), isTrue);

    final pace = RouteAnalyzerScreen.buildRoundedHistogramBoundaries(
      minValue: 280,
      maxValue: 480,
      stepOptions: const [300, 180, 120, 60, 30],
      minimumBins: 5,
      forceZeroStart: false,
    );

    expect(pace.length >= 6, isTrue);
    expect(pace.first, 270.0);
    expect(pace.contains(300.0), isTrue);
    expect(pace.contains(420.0), isTrue);
  });

  test('Manual pace adjustment is capped at +/-30 s/km', () {
    expect(RouteAnalyzerScreen.maxAdjustmentSeconds, 30.0);
  });

}
