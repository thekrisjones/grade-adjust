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
    const controls = SizedBox.shrink();

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

  testWidgets('Pace controls render in the single-column layout',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => RouteAnalyzerScreen.buildPaceControls(
              context: context,
              selectedPaceSeconds: 240,
              estimatedTotalTimeMinutes: 95,
              distanceUnitLabel: 'km',
              formatPaceForDisplay: (seconds) => '04:00',
              formatTotalTime: (minutes) => '1h 35m 0s',
              minPaceSeconds: 165,
              maxPaceSeconds: 1200,
              onPaceChanged: (_) {},
              onDecreaseFive: () {},
              onDecreaseOne: () {},
              onIncreaseOne: () {},
              onIncreaseFive: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Grade Adjusted Pace: 04:00/km'), findsOneWidget);
    expect(find.text('-5s'), findsOneWidget);
    expect(find.text('+5s'), findsOneWidget);
    expect(find.text('Estimated Total Time: 1h 35m 0s'), findsOneWidget);
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

  test('Plan export payload includes all required route state', () {
    final payload = RouteAnalyzerScreen.buildPlanPayload(
      gpxXml: '<gpx><trk><trkseg><trkpt lat="1" lon="2"><ele>10</ele></trkpt></trkseg></trk></gpx>',
      routePoints: const [
        {'lat': 1.0, 'lon': 2.0},
        {'lat': 1.5, 'lon': 2.5},
      ],
      checkpointData: const [
        {'distance': 0.0, 'name': 'Start', 'pauseSeconds': 12.0, 'adjustmentFactor': 5.0},
        {'distance': 2.0, 'name': 'Finish', 'pauseSeconds': 0.0, 'adjustmentFactor': 0.0},
      ],
      useImperialUnits: true,
      useLinearPacing: true,
      pacingVariationPercent: 12.5,
      selectedPaceSeconds: 300.0,
      startTimeHours: 7,
      startTimeMinutes: 30,
      carbsPerHour: 90.0,
      gramsPerUnit: 45.0,
      fluidPerHour: 750.0,
      mlPerUnit: 500.0,
    );

    expect(payload['version'], 1);
    expect(payload['gpxXml'], isNotEmpty);
    expect(payload['routePoints'], isNotEmpty);
    expect(payload['checkpoints'], isNotEmpty);
    expect(payload['useImperialUnits'], true);
    expect(payload['useLinearPacing'], true);
    expect(payload['selectedPaceSeconds'], 300.0);
    expect(payload['startTime'], {'hour': 7, 'minute': 30});
  });

  test('Web plan uploads read from bytes when path is unavailable', () async {
    final text = await RouteAnalyzerScreen.readFileContents(
      path: null,
      bytes: const [80, 108, 97, 110, 32, 105, 109, 112, 111, 114, 116, 101, 100],
    );

    expect(text, 'Plan imported');
  });

}
