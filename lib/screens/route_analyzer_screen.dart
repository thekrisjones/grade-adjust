import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gpx/gpx.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
// Add specific math imports required by analyzer indirectly
import 'dart:math' show max, min, Point, pow, sin, cos, atan2, sqrt, exp;
import 'dart:async';
import 'dart:convert';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart' show kIsWeb;

// Import new files
import '../models/checkpoint_data.dart';
import '../utils/platform_file_helper.dart';
import '../models/chart_data.dart';

// Class to store checkpoint data - MOVED to lib/models/checkpoint_data.dart
// class CheckpointData { ... }

// Class to store chart data for the summary section - MOVED to lib/models/chart_data.dart
// class ChartData { ... }

enum RouteLayoutMode {
  narrow,
  medium,
}

class ResponsiveRouteAnalysisLayout extends StatelessWidget {
  const ResponsiveRouteAnalysisLayout({
    super.key,
    required this.layoutMode,
    required this.mapAndElevation,
    required this.histograms,
    required this.splitsTable,
  });

  final RouteLayoutMode layoutMode;
  final Widget mapAndElevation;
  final Widget histograms;
  final Widget splitsTable;

  @override
  Widget build(BuildContext context) {
    switch (layoutMode) {
      case RouteLayoutMode.narrow:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mapAndElevation,
            const SizedBox(height: 12),
            histograms,
            const SizedBox(height: 12),
            splitsTable,
          ],
        );
      case RouteLayoutMode.medium:
        return LayoutBuilder(
          builder: (context, constraints) {
            const double columnGap = 12.0;
            final double equalColumnWidth =
                ((constraints.maxWidth - columnGap) / 2).clamp(400.0, double.infinity);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: equalColumnWidth, child: mapAndElevation),
                    const SizedBox(width: columnGap),
                    SizedBox(width: equalColumnWidth, child: histograms),
                  ],
                ),
                const SizedBox(height: 12),
                splitsTable,
              ],
            );
          },
        );
    }
  }
}

class RouteAnalyzerScreen extends StatefulWidget {
  const RouteAnalyzerScreen({super.key});

  static const double maxAdjustmentSeconds = 30.0; // ±30 s/km

  static Map<String, dynamic> buildPlanPayload({
    String? gpxXml = '',
    List<Map<String, double>> routePoints = const [],
    List<Map<String, dynamic>> checkpointData = const [],
    List<Map<String, double>> elevationPoints = const [],
    bool useImperialUnits = false,
    bool useLinearPacing = false,
    double pacingVariationPercent = 15.0,
    double selectedPaceSeconds = 240.0,
    int? startTimeHours,
    int? startTimeMinutes,
    double carbsPerHour = 0.0,
    double gramsPerUnit = 0.0,
    double fluidPerHour = 0.0,
    double mlPerUnit = 0.0,
    bool showCheckpoints = false,
    List<double> pacingVector = const [],
    List<double> pacingMultipliers = const [],
    List<double> smoothedGradients = const [],
    double cumulativeDistance = 0.0,
  }) {
    return {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'gpxXml': gpxXml ?? '',
      'routePoints': routePoints,
      'elevationPoints': elevationPoints,
      'checkpoints': checkpointData,
      'useImperialUnits': useImperialUnits,
      'useLinearPacing': useLinearPacing,
      'pacingVariationPercent': pacingVariationPercent,
      'selectedPaceSeconds': selectedPaceSeconds,
      'startTime': startTimeHours != null && startTimeMinutes != null
          ? {'hour': startTimeHours, 'minute': startTimeMinutes}
          : null,
      'carbsPerHour': carbsPerHour,
      'gramsPerUnit': gramsPerUnit,
      'fluidPerHour': fluidPerHour,
      'mlPerUnit': mlPerUnit,
      'showCheckpoints': showCheckpoints,
      'pacingVector': pacingVector,
      'pacingMultipliers': pacingMultipliers,
      'smoothedGradients': smoothedGradients,
      'cumulativeDistance': cumulativeDistance,
    };
  }

  static Future<String> readFileContents({
    String? path,
    List<int>? bytes,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      return String.fromCharCodes(bytes);
    }

    if (path != null && path.isNotEmpty) {
      return await readTextFile(path: path);
    }

    throw const FormatException('No file content available to read');
  }

  static List<double> buildRoundedHistogramBoundaries({
    required double minValue,
    required double maxValue,
    required List<double> stepOptions,
    required int minimumBins,
    bool forceZeroStart = false,
  }) {
    if (maxValue <= minValue) {
      return [minValue, maxValue];
    }

    double chosenStep = stepOptions.firstWhere(
      (step) => (maxValue - minValue) / minimumBins <= step,
      orElse: () => stepOptions.last,
    );

    double lowerBound = forceZeroStart
        ? 0.0
        : (minValue / chosenStep).floorToDouble() * chosenStep;
    double upperBound = (maxValue / chosenStep).ceilToDouble() * chosenStep;

    if ((upperBound - lowerBound) / chosenStep < minimumBins) {
      for (final step in stepOptions) {
        if (step < chosenStep) {
          chosenStep = step;
          lowerBound = forceZeroStart
              ? 0.0
              : (minValue / chosenStep).floorToDouble() * chosenStep;
          upperBound = (maxValue / chosenStep).ceilToDouble() * chosenStep;
          if ((upperBound - lowerBound) / chosenStep >= minimumBins) {
            break;
          }
        }
      }
    }

    final boundaries = <double>[];
    for (double boundary = lowerBound;
        boundary <= upperBound + 0.0000001;
        boundary += chosenStep) {
      boundaries.add(boundary);
    }

    if (boundaries.length < minimumBins + 1) {
      final fallbackStep = stepOptions.first;
      boundaries.clear();
      final fallbackLower = forceZeroStart
          ? 0.0
          : (minValue / fallbackStep).floorToDouble() * fallbackStep;
      final fallbackUpper = (maxValue / fallbackStep).ceilToDouble() * fallbackStep;
      for (double boundary = fallbackLower;
          boundary <= fallbackUpper + 0.0000001;
          boundary += fallbackStep) {
        boundaries.add(boundary);
      }
    }

    return boundaries;
  }

  @override
  State<RouteAnalyzerScreen> createState() => _RouteAnalyzerScreenState();
}

class _RouteAnalyzerScreenState extends State<RouteAnalyzerScreen> {
  Gpx? gpxData;
  String gpxXmlData = '';
  List<LatLng> routePoints = [];
  List<FlSpot> elevationPoints = [];
  List<FlSpot> timePoints = []; // Points for time graph
  List<FlSpot> pacePoints = []; // Points for pace graph
  List<double> cumulativeElevationGain =
      []; // Track cumulative elevation gain at each point
  List<double> cumulativeElevationLoss =
      []; // Track cumulative elevation loss at each point
  double? maxElevation;
  double? minElevation;
  double cumulativeDistance = 0.0;
  int? hoveredPointIndex;
  double? hoveredDistance;
  FlSpot? hoveredSpot; // Add this to track the exact hovered spot
  Timer? _mapDebounceTimer; // Separate timer for map marker
  Timer? _chartDebounceTimer; // Separate timer for chart marker
  Timer? _checkpointUpdateTimer; // Timer for debouncing checkpoint updates
  final mapController = MapController();
  List<double> smoothedGradients = [];

  // Add state for start time
  TimeOfDay? startTime;

  // Add state for pending checkpoint creation
  bool _isPendingCheckpointCreation = false;
  double? _pendingCheckpointDistance;

  // Add state for showing map
  bool showMap = true;

  // Checkpoint-related state
  bool showCheckpoints = false;
  List<CheckpointData> checkpoints = [];
  // Add state to track which fields are being edited
  String? _editingCheckpointId;
  bool _isEditingName = false;
  bool _isEditingDistance = false;
  // Add focus nodes for the text fields - make them nullable
  final List<FocusNode> _nameFocusNodes = [];
  final List<FocusNode> _distanceFocusNodes = [];
  // Add a flag to prevent web-related focus errors
  final bool _isWeb = kIsWeb;
  bool useImperialUnits = false;

  static const double _kilometersPerMile = 1.609344;
  static const double _metersPerFoot = 3.28084;
  static const double _milesPerKilometer = 0.621371;

  String get distanceUnitLabel => useImperialUnits ? 'mi' : 'km';
  String get elevationUnitLabel => useImperialUnits ? 'ft' : 'm';

  double convertDistanceToDisplay(double kilometers) {
    return useImperialUnits ? kilometers * _milesPerKilometer : kilometers;
  }

  double convertElevationToDisplay(double meters) {
    return useImperialUnits ? meters * _metersPerFoot : meters;
  }

  double convertDistanceFromDisplay(double value) {
    return useImperialUnits ? value / _milesPerKilometer : value;
  }

  double convertPaceToDisplayUnit(double secondsPerKilometer) {
    return useImperialUnits ? secondsPerKilometer * _kilometersPerMile : secondsPerKilometer;
  }

  String formatDistanceValue(double kilometers, {int decimals = 1}) {
    return '${convertDistanceToDisplay(kilometers).toStringAsFixed(decimals)} $distanceUnitLabel';
  }

  String formatElevationValue(double meters, {int decimals = 0}) {
    return '${convertElevationToDisplay(meters).toStringAsFixed(decimals)} $elevationUnitLabel';
  }

  String formatPaceForDisplay(double secondsPerKilometer) {
    return formatPace(convertPaceToDisplayUnit(secondsPerKilometer));
  }

  // Pace-related state
  double selectedPaceSeconds = 240; // Default 4:00 (240 seconds)
  static const double minPaceSeconds = 165; // 2:45
  static const double maxPaceSeconds = 1200; // 20:00
  // Add minimum allowed segment pace (2:00 min/km)
  static const double minSegmentPace = 120; // 2:00 min/km
  static const double paceAdjustmentStep = 5.0; // 5 s/km per button press

  // Manual pace adjustment constants
  static const double minAllowedPaceSeconds = 160; // 2:40 min/km
  static const double maxAllowedPaceSeconds = 2400; // 40:00 min/km
  static const double adjustmentIncrement = 5; // 5 s/km increments
  // Remove the flag to show adjusted pace column

  // Linear pacing strategy variables
  bool useLinearPacing = false;
  double pacingVariationPercent =
      15.0; // Default 15% variation from start to finish (range: -10% to +30%)
  List<double> pacingMultipliers = []; // Multipliers for each segment

  // Pacing vector - single source of truth for all segment paces (in seconds/km)
  List<double> pacingVector =
      []; // One pace value per segment, includes all adjustments

  // Add state variables for min/max pace for chart scaling & color
  double _minPace = 90; // Y-axis min (clamped)
  double _maxPace = 1200; // Y-axis max (clamped)
  double _minRawPace = 90; // For color scaling (unclamped)
  double _maxRawPace = 1200; // For color scaling (unclamped)

  // Add carbs calculation variables
  double carbsPerHour = 0.0;
  double gramsPerUnit = 0.0;

  // Add fluid calculation variables
  double fluidPerHour = 0.0;
  double mlPerUnit = 0.0;

  String formatPace(double seconds) {
    int mins = (seconds / 60).floor();
    int secs = (seconds % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  double calculateGradeAdjustment(double gradientPercent) {
    // Clamp gradient to ±45%
    double g = gradientPercent.clamp(-45.0, 45.0);
    // Updated to 4th-order polynomial as per target algorithm
    return (-0.000000447713 * pow(g, 4)) +
        (-0.000003068688 * pow(g, 3)) +
        (0.001882643005 * pow(g, 2)) +
        (0.030457306268 * g) +
        1.0;
  }

  /// Generates linear pacing multipliers that maintain the overall average pace
  /// while varying from fast to slow (or slow to fast) across the route
  /// Range: -10% (speeding up during race) to +30% (slowing down during race)
  void generateLinearPacingMultipliers() {
    if (elevationPoints.isEmpty) {
      pacingMultipliers = [];
      return;
    }

    int segmentCount = elevationPoints.length;
    pacingMultipliers = List.filled(segmentCount, 1.0);

    if (!useLinearPacing || pacingVariationPercent == 0) {
      return; // Use uniform pacing (all multipliers = 1.0)
    }

    // Calculate the range of multipliers
    // For positive values (slowing down): start faster, end slower
    // For negative values (speeding up): start slower, end faster
    double halfVariation = pacingVariationPercent.abs() /
        200.0; // Divide by 200 to get half percentage as decimal

    double startMultiplier, endMultiplier;
    if (pacingVariationPercent > 0) {
      // Positive: slow down during race (start fast, end slow)
      startMultiplier = 1.0 - halfVariation;
      endMultiplier = 1.0 + halfVariation;
    } else {
      // Negative: speed up during race (start slow, end fast)
      startMultiplier = 1.0 + halfVariation;
      endMultiplier = 1.0 - halfVariation;
    }

    // Generate linear progression from start to end
    for (int i = 0; i < segmentCount; i++) {
      double progress = segmentCount > 1 ? i / (segmentCount - 1) : 0.0;
      pacingMultipliers[i] =
          startMultiplier + (progress * (endMultiplier - startMultiplier));
    }

    // Normalize so the average multiplier equals 1.0 (maintains overall average pace)
    double sum = pacingMultipliers.reduce((a, b) => a + b);
    double average = sum / segmentCount;
    if (average > 0) {
      for (int i = 0; i < segmentCount; i++) {
        pacingMultipliers[i] = pacingMultipliers[i] / average;
      }
    }
  }

  /// Updates the pacing vector with base pace + linear adjustments + manual adjustments
  /// This is the single source of truth for all segment paces
  void updatePacingVector() {
    if (elevationPoints.isEmpty) {
      pacingVector = [];
      return;
    }

    int segmentCount = elevationPoints.length;

    // Step 1: Initialize with base average pace for all segments
    pacingVector = List.filled(segmentCount, selectedPaceSeconds);

    // Step 2: Apply linear pacing adjustments if enabled
    if (useLinearPacing && pacingMultipliers.length == segmentCount) {
      for (int i = 0; i < segmentCount; i++) {
        pacingVector[i] = pacingVector[i] * pacingMultipliers[i];
      }
    }

    // Step 3: Apply manual adjustments from checkpoints
    // Map checkpoint adjustments to the correct pacing vector segments
    for (int checkpointIndex = 0;
        checkpointIndex < checkpoints.length;
        checkpointIndex++) {
      if (checkpoints[checkpointIndex].adjustmentFactor != 0) {
        // Find the segment that this checkpoint defines
        double segmentStartDistance = checkpointIndex > 0
            ? checkpoints[checkpointIndex - 1].distance
            : 0.0;
        double segmentEndDistance = checkpoints[checkpointIndex].distance;

        // Apply the manual adjustment to ALL elevation points in this segment
        for (int i = 0; i < elevationPoints.length; i++) {
          double pointDistance = elevationPoints[i].x;

          // Check if this elevation point is within the segment
          if (pointDistance > segmentStartDistance &&
              pointDistance <= segmentEndDistance) {
            // Apply manual adjustment in seconds per kilometer
            pacingVector[i] =
                pacingVector[i] + checkpoints[checkpointIndex].adjustmentFactor;

            // Validate the adjusted pace is within limits
            pacingVector[i] = pacingVector[i]
                .clamp(minAllowedPaceSeconds, maxAllowedPaceSeconds);
          }
        }
      }
    }
  }

  /// Validates if a pace adjustment is within allowed limits
  bool isValidPaceAdjustment(double basePaceSeconds, double adjustmentSeconds) {
    double adjustedPace = basePaceSeconds + adjustmentSeconds;
    return adjustedPace >= minAllowedPaceSeconds &&
        adjustedPace <= maxAllowedPaceSeconds &&
        adjustmentSeconds.abs() <= RouteAnalyzerScreen.maxAdjustmentSeconds;
  }

  /// Validates if the overall average pace would remain within limits
  bool isValidAveragePace(double proposedAveragePaceSeconds) {
    return proposedAveragePaceSeconds >= minAllowedPaceSeconds &&
        proposedAveragePaceSeconds <= maxAllowedPaceSeconds;
  }

  /// Redistributes time across non-manually-adjusted segments to maintain average pace
  /// Returns true if redistribution was successful, false if impossible
  bool redistributeAdjustmentTime(int adjustedSegmentIndex, double timeChange) {
    if (checkpoints.isEmpty || elevationPoints.isEmpty) return false;

    // Calculate total distance and time to determine target average pace
    double totalDistance = elevationPoints.last.x; // Total route distance
    double totalTargetTime =
        (totalDistance * selectedPaceSeconds) / 60.0; // Target time in minutes

    // Calculate current total time from the timePoints
    double currentTotalTime = timePoints.isNotEmpty ? timePoints.last.y : 0.0;

    // Calculate how much time we need to redistribute
    double timeDifference = currentTotalTime - totalTargetTime;

    if (timeDifference.abs() < 0.01) {
      // Already very close to target, no redistribution needed
      return true;
    }

    // Find all non-manually-adjusted segments
    List<int> adjustableSegments = [];
    double adjustableDistance = 0.0;

    for (int i = 0; i < checkpoints.length; i++) {
      if (checkpoints[i].adjustmentFactor == 0) {
        // This segment can be adjusted to compensate
        double segmentStartDistance = i > 0 ? checkpoints[i - 1].distance : 0.0;
        double segmentEndDistance = checkpoints[i].distance;
        double segmentDistance = segmentEndDistance - segmentStartDistance;

        adjustableSegments.add(i);
        adjustableDistance += segmentDistance;
      }
    }

    if (adjustableSegments.isEmpty || adjustableDistance <= 0) {
      return false;
    }

    // Calculate the pace adjustment needed per kilometer of adjustable segments
    double adjustmentPerKm =
        -(timeDifference * 60.0) / adjustableDistance; // Convert to s/km

    // Limit the adjustment to prevent extreme paces
    double maxAutoAdjustment = 30.0; // Max 30 s/km auto adjustment
    if (adjustmentPerKm.abs() > maxAutoAdjustment) {
      adjustmentPerKm = adjustmentPerKm.sign * maxAutoAdjustment;
    }

    // Apply the adjustment to all adjustable segments
    for (int segmentIndex in adjustableSegments) {
      // Apply adjustment to all elevation points in this segment
      double segmentStartDistance =
          segmentIndex > 0 ? checkpoints[segmentIndex - 1].distance : 0.0;
      double segmentEndDistance = checkpoints[segmentIndex].distance;

      for (int i = 0; i < elevationPoints.length; i++) {
        double pointDistance = elevationPoints[i].x;
        if (pointDistance > segmentStartDistance &&
            pointDistance <= segmentEndDistance) {
          pacingVector[i] = (pacingVector[i] + adjustmentPerKm)
              .clamp(minAllowedPaceSeconds, maxAllowedPaceSeconds);
        }
      }
    }

    return true;
  }

  /// Resets all manual pace adjustments to zero
  void resetAllManualAdjustments() {
    for (var checkpoint in checkpoints) {
      checkpoint.adjustmentFactor = 0;
    }
    // Recalculate without manual adjustments
    _recalculatePacingAndCheckpoints();
  }

  void calculateTimePoints() {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty) return;

    // Generate linear pacing multipliers if strategy is enabled
    generateLinearPacingMultipliers();

    // Update the unified pacing vector with all adjustments
    updatePacingVector();

    List<FlSpot> newTimePoints = [];
    List<FlSpot> newPacePoints = []; // <-- Add this
    double cumulativeTime = 0;
    double minCalculatedPace =
        double.infinity; // Track min/max pace for chart scaling
    double maxCalculatedPace = double.negativeInfinity;

    // Get segment boundaries based on checkpoints
    List<double> segmentBoundaries = [];
    if (checkpoints.isNotEmpty) {
      segmentBoundaries = checkpoints.map((cp) => cp.distance).toList();
      segmentBoundaries.sort();
    }

    // First, calculate the base grade-adjusted pace for each segment
    // Note: These values will be overridden in _calculateCheckpointMetrics
    // but are needed for time calculation
    if (checkpoints.isNotEmpty) {
      // Calculate for start to first checkpoint
      checkpoints[0].baseGradeAdjustedPace =
          getSegmentBaseGradeAdjustedPace(0, checkpoints[0].distance);

      // Calculate for checkpoint to checkpoint segments
      for (int i = 1; i < checkpoints.length; i++) {
        double startDist = checkpoints[i - 1].distance;
        double endDist = checkpoints[i].distance;
        checkpoints[i].baseGradeAdjustedPace =
            getSegmentBaseGradeAdjustedPace(startDist, endDist);
      }
    }

    for (int i = 0; i < elevationPoints.length; i++) {
      if (i == 0) {
        newTimePoints.add(const FlSpot(0, 0));
        // Skip pace point for index 0, calculate starting from first segment
        continue;
      }

      // Calculate distance segment in kilometers
      double segmentDistance = elevationPoints[i].x - elevationPoints[i - 1].x;

      // Get grade adjustment factor for this segment
      // Ensure gradient index is valid
      int gradientIndex = i.clamp(0, smoothedGradients.length - 1);
      double adjustment =
          calculateGradeAdjustment(smoothedGradients[gradientIndex]);

      // Get pace from pacing vector (already includes base pace + linear + manual adjustments)
      double basePace = i < pacingVector.length
          ? pacingVector[i]
          : selectedPaceSeconds; // Fallback to average if vector not ready

      // Apply grade adjustment to get final pace
      double gradePace = basePace * adjustment;

      // Ensure pace doesn't go below minimum allowed pace (2:00 min/km)
      gradePace = max(gradePace, minSegmentPace);

      // Calculate time for this segment
      double segmentTime =
          (segmentDistance * gradePace) / 60; // Convert to minutes
      cumulativeTime += segmentTime;

      newTimePoints.add(FlSpot(elevationPoints[i].x, cumulativeTime));

      // --- Calculate Real Pace ---
      double realPace = basePace * adjustment;

      // Clamp real pace between 2:00 (120s) and 20:00 (1200s)
      realPace = realPace.clamp(120.0, 1200.0);

      newPacePoints
          .add(FlSpot(elevationPoints[i].x, realPace)); // Add pace point

      // Update min/max calculated pace
      minCalculatedPace = min(minCalculatedPace, realPace);
      maxCalculatedPace = max(maxCalculatedPace, realPace);
    }

    // Add a starting pace point (equal to the first segment's pace)
    if (newPacePoints.isNotEmpty) {
      newPacePoints.insert(0, FlSpot(0, newPacePoints.first.y));
      // Update min/max again in case the first point is the extreme
      minCalculatedPace = min(minCalculatedPace, newPacePoints.first.y);
      maxCalculatedPace = max(maxCalculatedPace, newPacePoints.first.y);
    } else {
      // Handle case with only one elevation point
      if (elevationPoints.length == 1) {
        double initialAdjustment =
            calculateGradeAdjustment(0); // Assume flat start
        double initialPace = selectedPaceSeconds;
        if (initialAdjustment.abs() > 0.01) {
          initialPace = selectedPaceSeconds / initialAdjustment;
        }
        initialPace = initialPace.clamp(90.0, 1200.0);
        newPacePoints.add(FlSpot(0, initialPace));
        minCalculatedPace = initialPace;
        maxCalculatedPace = initialPace;
      }
    }

    setState(() {
      timePoints = newTimePoints;
      pacePoints = newPacePoints; // <-- Update state
      // Update state variables for min/max pace
      _minPace = minCalculatedPace.isFinite ? minCalculatedPace : 90;
      _maxPace = maxCalculatedPace.isFinite ? maxCalculatedPace : 1200;
      // Ensure summary data is updated when pace changes
      if (mounted) {
        // Using a post-frame callback to avoid setState inside another setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {}); // Force rebuild for summary charts
          }
        });
      }
    });
  }

  // Separate function to calculate pace points for the chart
  void calculatePacePoints() {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty) return;

    List<FlSpot> newPacePoints = [];
    double minClampedPace = double.infinity; // For Y-axis scaling
    double maxClampedPace = double.negativeInfinity;
    double minRawPace = double.infinity; // For color scaling
    double maxRawPace = double.negativeInfinity;
    double totalSegmentDistance = 0; // To calculate average spacing
    int segmentCount = 0; // To calculate average spacing

    double basePace = selectedPaceSeconds;

    for (int i = 0; i < elevationPoints.length; i++) {
      // Need adjustment factor even for the first point (index 0)
      int gradientIndex = i.clamp(0, smoothedGradients.length - 1);
      double adjustment =
          calculateGradeAdjustment(smoothedGradients[gradientIndex]);

      // Calculate raw real pace: base pace * adjustment factor
      double realPace = basePace * adjustment;

      // Update raw min/max for color scaling *before* clamping
      minRawPace = min(minRawPace, realPace);
      maxRawPace = max(maxRawPace, realPace);

      // Clamp real pace between 1:30 (90s) and 20:00 (1200s)
      realPace = realPace.clamp(90.0, 1200.0);

      newPacePoints
          .add(FlSpot(elevationPoints[i].x, realPace)); // Add pace point

      // Update clamped min/max for Y-axis scaling
      minClampedPace = min(minClampedPace, realPace);
      maxClampedPace = max(maxClampedPace, realPace);

      // Track segment distance for average spacing calculation
      if (i > 0) {
        double segmentDist =
            elevationPoints[i].x - elevationPoints[i - 1].x; // in km
        if (segmentDist > 0) {
          totalSegmentDistance += segmentDist * 1000; // convert to meters
          segmentCount++;
        }
      }
    }

    // Ensure pacePoints has at least one point if elevationPoints has one
    if (elevationPoints.length == 1 && newPacePoints.isEmpty) {
      // This case was handled inside the loop now, but double-check
      int gradientIndex = 0.clamp(0, smoothedGradients.length - 1);
      double adjustment =
          calculateGradeAdjustment(smoothedGradients[gradientIndex]);
      double realPace = basePace * adjustment;
      realPace = realPace.clamp(90.0, 1200.0);
      newPacePoints.add(FlSpot(elevationPoints[0].x, realPace));
      minClampedPace = realPace;
      maxClampedPace = realPace;
      minRawPace = realPace;
      maxRawPace = realPace;
    }

    // Calculate adaptive window size for smoothing (~200m)
    double avgSpacingMeters = segmentCount > 0
        ? totalSegmentDistance / segmentCount
        : 10; // Default 10m if no segments
    int pointWindowSize = (200 / avgSpacingMeters).round();
    // Ensure window size is odd and within reasonable bounds (e.g., 3 to 21)
    pointWindowSize = (pointWindowSize ~/ 2 * 2 + 1); // Make odd
    pointWindowSize = pointWindowSize.clamp(3, 21); // Clamp between 3 and 21

    // Smooth the calculated pace data using the adaptive window size
    List<FlSpot> smoothedPacePoints =
        _smoothData(newPacePoints, pointWindowSize);

    setState(() {
      pacePoints = smoothedPacePoints; // Use smoothed data
      // Update state variables for min/max pace (clamped for axis, raw for color)
      _minPace = minClampedPace.isFinite ? minClampedPace : 90;
      _maxPace = maxClampedPace.isFinite ? maxClampedPace : 1200;
      _minRawPace = minRawPace.isFinite ? minRawPace : 90;
      _maxRawPace = maxRawPace.isFinite ? maxRawPace : 1200;
    });
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    // Convert degrees to radians
    double lat1Rad = lat1 * pi / 180;
    double lon1Rad = lon1 * pi / 180;
    double lat2Rad = lat2 * pi / 180;
    double lon2Rad = lon2 * pi / 180;

    // Differences in coordinates
    double dLat = lat2Rad - lat1Rad;
    double dLon = lon2Rad - lon1Rad;

    // Haversine formula
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c; // Distance in meters
  }

  Future<void> pickGPXFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );

    if (result != null) {
      try {
        final fileContent = String.fromCharCodes(result.files.first.bytes!);

        try {
          gpxData = GpxReader().fromString(fileContent);

          gpxXmlData = fileContent;

          // Verify that the GPX data contains valid tracks
          if (gpxData?.trks.isEmpty ?? true) {
            throw const FormatException('No track data found in the GPX file');
          }

          // Verify at least one track segment has points
          bool hasPoints = false;
          for (var track in gpxData!.trks) {
            for (var segment in track.trksegs) {
              if (segment.trkpts.isNotEmpty) {
                hasPoints = true;
                break;
              }
            }
            if (hasPoints) break;
          }

          if (!hasPoints) {
            throw const FormatException(
                'No track points found in the GPX file');
          }

          processGpxData();
        } on FormatException catch (e) {
          debugPrint('GPX format error: $e');
          // Show error message to user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error parsing GPX file: ${e.message}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error reading GPX file: $e');
        // Show error message to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading GPX file: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Resamples GPX points to uniform 10m (0.01km) increments
  /// Interpolates latitude, longitude, and elevation data
  List<Map<String, double>> resampleToUniform10mIncrements(List<Wpt> points) {
    if (points.length < 2) return [];

    List<Map<String, double>> resampledPoints = [];
    double targetIncrement = 0.01; // 10m in kilometers
    double cumulativeDistance = 0.0;
    double nextTargetDistance = 0.0;

    // Add first point
    resampledPoints.add({
      'distance': 0.0,
      'lat': points[0].lat!,
      'lon': points[0].lon!,
      'elevation': points[0].ele ?? 0.0,
    });

    for (int i = 1; i < points.length; i++) {
      double prevLat = points[i - 1].lat!;
      double prevLon = points[i - 1].lon!;
      double prevEle = points[i - 1].ele ?? 0.0;

      double currLat = points[i].lat!;
      double currLon = points[i].lon!;
      double currEle = points[i].ele ?? 0.0;

      // Calculate segment distance in kilometers
      double segmentDistance =
          calculateDistance(prevLat, prevLon, currLat, currLon) / 1000.0;

      // Skip extremely short segments to avoid issues
      if (segmentDistance < 0.001) continue; // Less than 1 meter

      double segmentEndDistance = cumulativeDistance + segmentDistance;

      // Interpolate points at 10m intervals within this segment
      while (nextTargetDistance < segmentEndDistance) {
        nextTargetDistance += targetIncrement;

        if (nextTargetDistance <= segmentEndDistance) {
          // Calculate interpolation ratio
          double ratio = segmentDistance > 0
              ? (nextTargetDistance - cumulativeDistance) / segmentDistance
              : 0.0;

          // Clamp ratio to prevent issues
          ratio = ratio.clamp(0.0, 1.0);

          // Interpolate coordinates and elevation
          double interpLat = prevLat + ratio * (currLat - prevLat);
          double interpLon = prevLon + ratio * (currLon - prevLon);
          double interpEle = prevEle + ratio * (currEle - prevEle);

          resampledPoints.add({
            'distance': nextTargetDistance,
            'lat': interpLat,
            'lon': interpLon,
            'elevation': interpEle,
          });
        }
      }

      cumulativeDistance = segmentEndDistance;
    }

    // Ensure we have at least one point
    if (resampledPoints.isEmpty) {
      resampledPoints.add({
        'distance': 0.0,
        'lat': points[0].lat!,
        'lon': points[0].lon!,
        'elevation': points[0].ele ?? 0.0,
      });
    }

    return resampledPoints;
  }

  void processGpxData() {
    if (gpxData == null) return;

    // Get points from tracks
    List<Wpt> points = [];
    for (var track in gpxData!.trks) {
      for (var segment in track.trksegs) {
        points.addAll(segment.trkpts);
      }
    }

    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The GPX file contains no valid track points'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if file has elevation data
    bool hasElevationData = points.any((pt) => pt.ele != null);
    if (!hasElevationData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'The GPX file does not contain elevation data. Using 0m as default elevation.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }

    setState(() {
      // Reset all data
      routePoints = [];
      elevationPoints = [];
      timePoints = [];
      pacePoints = []; // <-- Reset pace points
      smoothedGradients = [];
      cumulativeDistance = 0.0;
      cumulativeElevationGain = [];
      cumulativeElevationLoss = [];
      maxElevation = null;
      minElevation = null;
      hoveredPointIndex = null;
      hoveredDistance = null;
      _minPace = 90; // <-- Reset min/max pace
      _maxPace = 1200;

      // Reset checkpoints
      checkpoints = [];
      showCheckpoints = false;

      // Clear focus nodes to prevent index out of range errors
      for (var node in _nameFocusNodes) {
        node.dispose();
      }
      for (var node in _distanceFocusNodes) {
        node.dispose();
      }
      _nameFocusNodes.clear();
      _distanceFocusNodes.clear();

      // Resample to uniform 10m increments
      List<Map<String, double>> resampledData =
          resampleToUniform10mIncrements(points);

      if (resampledData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to resample GPX data'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Keep the map line dense enough to preserve detail without dropping the
      // route below a 10m sampling interval. The GPX data is already resampled to
      // 10m increments, so retaining the resampled points preserves trace detail
      // while avoiding the much sparser 100m gaps from the old sampling strategy.
      routePoints = resampledData
          .map((point) => LatLng(point['lat']!, point['lon']!))
          .toList();

      // Process elevation points using all resampled data
      double totalElevationGain = 0;
      double totalElevationLoss = 0;

      for (int i = 0; i < resampledData.length; i++) {
        var point = resampledData[i];
        double elevation = point['elevation']!;
        double distance = point['distance']!;

        // Calculate elevation change for gain/loss tracking
        if (i > 0) {
          double elevationChange =
              elevation - resampledData[i - 1]['elevation']!;
          if (elevationChange > 0) {
            totalElevationGain += elevationChange;
          } else {
            totalElevationLoss += -elevationChange;
          }
        }

        // Add elevation point
        elevationPoints.add(FlSpot(distance, elevation));
        cumulativeElevationGain.add(totalElevationGain);
        cumulativeElevationLoss.add(totalElevationLoss);
      }

      // Set cumulative distance to the total route distance
      cumulativeDistance =
          resampledData.isNotEmpty ? resampledData.last['distance']! : 0.0;

      // Calculate elevation bounds
      if (elevationPoints.isNotEmpty) {
        maxElevation =
            elevationPoints.map((p) => p.y).reduce((a, b) => max(a, b));
        minElevation =
            elevationPoints.map((p) => p.y).reduce((a, b) => min(a, b));
      }

      // Calculate gradients with uniform 10m spacing - use smaller window for smoothing
      List<double> gradients = calculateGradients(elevationPoints);
      smoothedGradients =
          smoothGradients(gradients, 5); // Fixed window size for 10m data

      // Calculate initial time and pace points
      calculateTimePoints();
      calculatePacePoints(); // <-- Call new function

      // Process waypoints from GPX file
      processWaypoints();

      // Add a default finish checkpoint
      if (elevationPoints.isNotEmpty) {
        final finishCheckpoint =
            CheckpointData(distance: elevationPoints.last.x);
        finishCheckpoint.id = 'finish';
        finishCheckpoint.name = 'Finish';

        // Add the checkpoint
        checkpoints.add(finishCheckpoint);

        // Update checkpoint metrics for initial data
        _calculateCheckpointMetrics(startIndex: 0);

        // Add new focus nodes for this checkpoint - with web platform handling
        final nameNode = FocusNode();
        final distanceNode = FocusNode();

        // Add focus listeners only if not on web
        if (!_isWeb) {
          try {
            nameNode.addListener(_onFocusChange);
            distanceNode.addListener(_onFocusChange);
          } catch (e) {
            // Silently handle any focus node errors
          }
        }

        _nameFocusNodes.add(nameNode);
        _distanceFocusNodes.add(distanceNode);

        // Recalculate metrics for all checkpoints to ensure consistency
        _calculateCheckpointMetrics(startIndex: 0);
      }

      // Fit map bounds to show the entire route
      Future.delayed(const Duration(milliseconds: 100), () {
        mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(routePoints),
            padding: const EdgeInsets.all(20.0),
          ),
        );
      });
    });
  }

  // Process waypoints from GPX file and add them as checkpoints
  void processWaypoints() {
    if (gpxData == null || gpxData!.wpts.isEmpty || routePoints.isEmpty) return;

    // Create a list to store valid waypoints
    List<CheckpointData> waypointCheckpoints = [];

    // Process each waypoint
    for (var waypoint in gpxData!.wpts) {
      if (waypoint.lat == null || waypoint.lon == null) continue;

      // Find closest point on route
      double minDistance = double.infinity;
      int closestPointIndex = -1;

      for (int i = 0; i < routePoints.length; i++) {
        final routePoint = routePoints[i];
        final distance = calculateDistance(waypoint.lat!, waypoint.lon!,
            routePoint.latitude, routePoint.longitude);

        if (distance < minDistance) {
          minDistance = distance;
          closestPointIndex = i;
        }
      }

      // Skip waypoints more than 100m from the route
      if (minDistance > 100) continue;

      // Find the distance along the route to this point
      double distanceAlongRoute = 0.0;

      // Map route point index to corresponding elevation point
      double routeDistance;

      if (closestPointIndex == 0) {
        routeDistance = 0.0;
      } else if (elevationPoints.length == routePoints.length) {
        // Direct mapping if arrays have the same length
        routeDistance = elevationPoints[closestPointIndex].x;
      } else {
        // Otherwise use proportional mapping
        double ratio = elevationPoints.length / routePoints.length;
        int elevationIndex = (closestPointIndex * ratio).round();
        elevationIndex = elevationIndex.clamp(0, elevationPoints.length - 1);
        routeDistance = elevationPoints[elevationIndex].x;
      }

      // Create a new checkpoint
      final checkpoint = CheckpointData(distance: routeDistance);

      // Use waypoint name if available
      // Set waypoint name as a property on the checkpoint (we need to add this field)
      checkpoint.name =
          waypoint.name ?? 'Waypoint ${waypointCheckpoints.length + 1}';

      // Add to our list
      waypointCheckpoints.add(checkpoint);
    }

    // If we found any valid waypoints, enable checkpoints and add them
    if (waypointCheckpoints.isNotEmpty) {
      checkpoints = waypointCheckpoints;
      showCheckpoints = true;

      // Calculate metrics for the checkpoints
      _calculateCheckpointMetrics(startIndex: 0);
    }
  }

  int findClosestRoutePoint(Offset localPosition, BoxConstraints constraints) {
    if (routePoints.isEmpty) return -1;

    // Convert screen coordinates to lat/lng
    final point = mapController.camera
        .pointToLatLng(Point(localPosition.dx, localPosition.dy));

    // Find closest point on route using a more efficient approach
    double minDistance = double.infinity;
    int closestIndex = -1;

    // Use a step size to check fewer points for better performance
    // For very large routes, check every Nth point first, then refine
    int stepSize = routePoints.length > 1000 ? 10 : 1;

    // First pass with step size
    for (int i = 0; i < routePoints.length; i += stepSize) {
      final routePoint = routePoints[i];
      final distance = (point.latitude - routePoint.latitude) *
              (point.latitude - routePoint.latitude) +
          (point.longitude - routePoint.longitude) *
              (point.longitude - routePoint.longitude);

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    // Second pass to refine if we used a step size
    if (stepSize > 1 && closestIndex >= 0) {
      int start = max(0, closestIndex - stepSize);
      int end = min(routePoints.length - 1, closestIndex + stepSize);

      for (int i = start; i <= end; i++) {
        if (i % stepSize == 0) continue; // Skip points we already checked

        final routePoint = routePoints[i];
        final distance = (point.latitude - routePoint.latitude) *
                (point.latitude - routePoint.latitude) +
            (point.longitude - routePoint.longitude) *
                (point.longitude - routePoint.longitude);

        if (distance < minDistance) {
          minDistance = distance;
          closestIndex = i;
        }
      }
    }

    return closestIndex;
  }

  Color getGradientColor(double gradient) {
    const maxGradient = 25.0; // Maximum gradient percentage to consider
    double normalizedGradient = (gradient / maxGradient).clamp(-1.0, 1.0);

    if (gradient > 0) {
      // Uphill: Yellow (60) to Red (0)
      double hue = 60.0 * (1.0 - normalizedGradient);
      return HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
    } else {
      // Downhill: Blue (240) to Cyan (180)
      double hue = 240.0 - (normalizedGradient.abs() * 60.0);
      return HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
    }
  }

  List<double> calculateGradients(List<FlSpot> points) {
    List<double> grads = [];

    // Calculate minimum distance between points to handle varying densities
    double minDistance = double.infinity;
    for (int i = 1; i < points.length; i++) {
      double distance = points[i].x - points[i - 1].x;
      if (distance > 0 && distance < minDistance) {
        minDistance = distance;
      }
    }

    // Use this for gradient calculation
    for (int i = 1; i < points.length; i++) {
      final dx = (points[i].x - points[i - 1].x) * 1000; // Convert to meters
      final dy = points[i].y - points[i - 1].y;

      // Skip extremely short segments that might cause extreme gradients
      if (dx < 1.0) {
        // Use previous gradient or 0 if first point
        grads.add(grads.isEmpty ? 0.0 : grads.last);
        continue;
      }

      // Calculate gradient percentage
      final gradient = (dy / dx) * 100;

      // Clamp extreme values that might be due to GPS errors
      final clampedGradient = gradient.clamp(-45.0, 45.0);
      grads.add(clampedGradient);
    }

    // Add first gradient to start of list to match points length
    if (grads.isNotEmpty) {
      grads.insert(0, grads[0]);
    }
    return grads;
  }

  List<double> smoothGradients(List<double> gradients, int windowSize) {
    List<double> smoothed = List.filled(gradients.length, 0);

    for (int i = 0; i < gradients.length; i++) {
      double sum = 0;
      double weightSum = 0;

      // Use a larger window for sparse data
      int effectiveWindow = windowSize;
      if (i > 0 && i < gradients.length - 1) {
        // Check if we have sparse data by looking at gradient changes
        double prevDiff = (gradients[i] - gradients[i - 1]).abs();
        double nextDiff = (gradients[i + 1] - gradients[i]).abs();
        if (prevDiff > 10 || nextDiff > 10) {
          effectiveWindow =
              windowSize * 2; // Double window size for sparse data
        }
      }

      // Calculate window bounds
      int windowStart = max(0, i - effectiveWindow ~/ 2);
      int windowEnd = min(gradients.length, i + effectiveWindow ~/ 2 + 1);

      // Calculate weighted average based on distance from center point
      for (int j = windowStart; j < windowEnd; j++) {
        // Use gaussian-like weighting
        double distance = (j - i).abs().toDouble();
        double weight = exp(-distance *
            distance /
            (2 * (effectiveWindow / 4) * (effectiveWindow / 4)));

        sum += gradients[j] * weight;
        weightSum += weight;
      }

      if (weightSum > 0) {
        smoothed[i] = sum / weightSum;
      }
    }

    return smoothed;
  }

  // Optimize the map marker update method
  void _updateMapMarker(int? pointIndex) {
    // Skip update if the point hasn't changed
    if (pointIndex == hoveredPointIndex) return;

    // Cancel previous timer if it exists
    _mapDebounceTimer?.cancel();

    // Update immediately without debounce for better responsiveness
    if (mounted) {
      setState(() {
        hoveredPointIndex = pointIndex;
      });
    }
  }

  // Optimize the hover point update method
  void _updateHoveredPoint(int? pointIndex, double? distance) {
    // Skip update if the distance hasn't changed
    if (distance == hoveredDistance) return;

    // Cancel previous timer if it exists
    _chartDebounceTimer?.cancel();

    // When hovering over the map or chart, update immediately without debounce
    if (distance != null) {
      setState(() {
        hoveredDistance = distance;
        hoveredSpot = findClosestElevationPoint(distance);
      });
    } else {
      // For exit events, update immediately
      setState(() {
        hoveredDistance = null;
        hoveredSpot = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // ... existing code ...
  }

  @override
  void dispose() {
    _mapDebounceTimer?.cancel();
    _chartDebounceTimer?.cancel();
    _checkpointUpdateTimer?.cancel();
    // Dispose all focus nodes - with null safety check
    if (!_isWeb) {
      for (var node in _nameFocusNodes) {
        try {
          node.removeListener(_onFocusChange);
          node.dispose();
        } catch (e) {
          // Silently handle any disposal errors
        }
      }
      for (var node in _distanceFocusNodes) {
        try {
          node.removeListener(_onFocusChange);
          node.dispose();
        } catch (e) {
          // Silently handle any disposal errors
        }
      }
    }
    super.dispose();
  }

  // Handle focus changes to update the table when clicking away - with web safety
  void _onFocusChange() {
    if (_isWeb) return; // Skip focus change handling on web platforms

    if (_isEditingName && !_nameFocusNodes.any((node) => node.hasFocus)) {
      setState(() {
        _isEditingName = false;
        _editingCheckpointId = null;
      });
      _processCheckpointChanges();
    }

    if (_isEditingDistance &&
        !_distanceFocusNodes.any((node) => node.hasFocus)) {
      setState(() {
        _isEditingDistance = false;
        _editingCheckpointId = null;
      });
      _processCheckpointChanges();
    }
  }

  RouteLayoutMode _getRouteLayoutMode(BuildContext context) {
    const double mediumLayoutMinWidth = 824.0;
    final double width = MediaQuery.sizeOf(context).width;

    if (width < mediumLayoutMinWidth) {
      return RouteLayoutMode.narrow;
    }

    return RouteLayoutMode.medium;
  }

  bool get canExportPlan => routePoints.isNotEmpty || checkpoints.isNotEmpty || gpxXmlData.isNotEmpty;

  Map<String, dynamic> _buildPlanPayload() {
    return RouteAnalyzerScreen.buildPlanPayload(
      gpxXml: gpxXmlData,
      routePoints: routePoints
          .map((point) => {'lat': point.latitude, 'lon': point.longitude})
          .toList(),
      checkpointData: checkpoints
          .map((checkpoint) => {
                'distance': checkpoint.distance,
                'name': checkpoint.name ?? '',
                'elevation': checkpoint.elevation,
                'elevationGain': checkpoint.elevationGain,
                'elevationLoss': checkpoint.elevationLoss,
                'cumulativeTime': checkpoint.cumulativeTime,
                'timeFromPrevious': checkpoint.timeFromPrevious,
                'pauseSeconds': checkpoint.pauseSeconds,
                'id': checkpoint.id,
                'baseGradeAdjustedPace': checkpoint.baseGradeAdjustedPace,
                'gradeAdjustedDistance': checkpoint.gradeAdjustedDistance,
                'cumulativeGradeAdjustedDistance':
                    checkpoint.cumulativeGradeAdjustedDistance,
                'adjustmentFactor': checkpoint.adjustmentFactor,
                'legUnits': checkpoint.legUnits,
                'cumulativeUnits': checkpoint.cumulativeUnits,
                'legFluidUnits': checkpoint.legFluidUnits,
                'cumulativeFluidUnits': checkpoint.cumulativeFluidUnits,
              })
          .toList(),
      elevationPoints: elevationPoints
          .map((spot) => {'distance': spot.x, 'elevation': spot.y})
          .toList(),
      useImperialUnits: useImperialUnits,
      useLinearPacing: useLinearPacing,
      pacingVariationPercent: pacingVariationPercent,
      selectedPaceSeconds: selectedPaceSeconds,
      startTimeHours: startTime?.hour,
      startTimeMinutes: startTime?.minute,
      carbsPerHour: carbsPerHour,
      gramsPerUnit: gramsPerUnit,
      fluidPerHour: fluidPerHour,
      mlPerUnit: mlPerUnit,
      showCheckpoints: showCheckpoints,
      pacingVector: pacingVector,
      pacingMultipliers: pacingMultipliers,
      smoothedGradients: smoothedGradients,
      cumulativeDistance: cumulativeDistance,
    );
  }

  Future<void> exportPlanFile() async {
    if (!canExportPlan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available to export')),
      );
      return;
    }

    try {
      final payload = _buildPlanPayload();
      final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
      const String defaultFileName = 'route_plan.json';

      final savedPath = await saveTextFile(defaultFileName, jsonString);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan exported to your Downloads folder.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting plan: $e')),
      );
    }
  }

  Future<void> loadPlanFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final filePath = kIsWeb ? null : file.path;
      final jsonString = await RouteAnalyzerScreen.readFileContents(
        path: filePath,
        bytes: file.bytes,
      );

      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Plan file is not a JSON object');
      }

      final rawGpxXml = decoded['gpxXml'];
      final routePointData = decoded['routePoints'] as List? ?? const [];
      final elevationData = decoded['elevationPoints'] as List? ?? const [];
      final checkpointData = decoded['checkpoints'] as List? ?? const [];

      setState(() {
        gpxXmlData = rawGpxXml is String ? rawGpxXml : '';
        if (gpxXmlData.isNotEmpty) {
          try {
            gpxData = GpxReader().fromString(gpxXmlData);
          } catch (_) {
            gpxData = null;
          }
        }

        useImperialUnits = decoded['useImperialUnits'] == true;
        useLinearPacing = decoded['useLinearPacing'] == true;
        pacingVariationPercent = (decoded['pacingVariationPercent'] ?? 15.0)
            .toDouble();
        selectedPaceSeconds = (decoded['selectedPaceSeconds'] ?? 240.0)
            .toDouble();
        carbsPerHour = (decoded['carbsPerHour'] ?? 0.0).toDouble();
        gramsPerUnit = (decoded['gramsPerUnit'] ?? 0.0).toDouble();
        fluidPerHour = (decoded['fluidPerHour'] ?? 0.0).toDouble();
        mlPerUnit = (decoded['mlPerUnit'] ?? 0.0).toDouble();
        showCheckpoints = decoded['showCheckpoints'] == true;
        cumulativeDistance = (decoded['cumulativeDistance'] ?? 0.0).toDouble();

        if (decoded['startTime'] is Map) {
          final timeMap = decoded['startTime'] as Map;
          startTime = TimeOfDay(
            hour: (timeMap['hour'] ?? 0) as int,
            minute: (timeMap['minute'] ?? 0) as int,
          );
        } else {
          startTime = null;
        }

        routePoints = routePointData.map<LatLng>((entry) {
          final map = entry as Map;
          return LatLng(
            (map['lat'] as num).toDouble(),
            (map['lon'] as num).toDouble(),
          );
        }).toList();

        elevationPoints = elevationData.map<FlSpot>((entry) {
          final map = entry as Map;
          return FlSpot(
            (map['distance'] as num).toDouble(),
            (map['elevation'] as num).toDouble(),
          );
        }).toList();

        checkpoints = checkpointData.map<CheckpointData>((entry) {
          final map = entry as Map;
          final checkpoint = CheckpointData(
            distance: (map['distance'] as num).toDouble(),
          );
          checkpoint.id = (map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString()).toString();
          checkpoint.name = map['name']?.toString();
          checkpoint.elevation = (map['elevation'] ?? 0.0).toDouble();
          checkpoint.elevationGain = (map['elevationGain'] ?? 0.0).toDouble();
          checkpoint.elevationLoss = (map['elevationLoss'] ?? 0.0).toDouble();
          checkpoint.cumulativeTime = (map['cumulativeTime'] ?? 0.0).toDouble();
          checkpoint.timeFromPrevious = (map['timeFromPrevious'] ?? 0.0).toDouble();
          checkpoint.pauseSeconds = (map['pauseSeconds'] ?? 0.0).toDouble();
          checkpoint.baseGradeAdjustedPace =
              (map['baseGradeAdjustedPace'] ?? 0.0).toDouble();
          checkpoint.gradeAdjustedDistance =
              (map['gradeAdjustedDistance'] ?? 0.0).toDouble();
          checkpoint.cumulativeGradeAdjustedDistance =
              (map['cumulativeGradeAdjustedDistance'] ?? 0.0).toDouble();
          checkpoint.adjustmentFactor =
              (map['adjustmentFactor'] ?? 0.0).toDouble();
          checkpoint.legUnits = (map['legUnits'] ?? 0) as int;
          checkpoint.cumulativeUnits = (map['cumulativeUnits'] ?? 0) as int;
          checkpoint.legFluidUnits = (map['legFluidUnits'] ?? 0) as int;
          checkpoint.cumulativeFluidUnits = (map['cumulativeFluidUnits'] ?? 0) as int;
          return checkpoint;
        }).toList();

        pacingVector = (decoded['pacingVector'] as List? ?? const [])
            .map<double>((value) => (value as num).toDouble())
            .toList();
        pacingMultipliers = (decoded['pacingMultipliers'] as List? ?? const [])
            .map<double>((value) => (value as num).toDouble())
            .toList();
        smoothedGradients = (decoded['smoothedGradients'] as List? ?? const [])
            .map<double>((value) => (value as num).toDouble())
            .toList();
      });

      if (checkpoints.isNotEmpty) {
        setState(() {
          checkpoints.sort((a, b) => a.distance.compareTo(b.distance));
          _recalculatePacingAndCheckpoints();
        });
      }

      if (routePoints.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 100), () {
          mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(routePoints),
              padding: const EdgeInsets.all(20.0),
            ),
          );
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan loaded')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading plan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Race Planner')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: pickGPXFile,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Upload GPX File'),
                      ),
                      ElevatedButton.icon(
                        onPressed: loadPlanFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Upload Plan'),
                      ),
                      if (canExportPlan)
                        ElevatedButton.icon(
                          onPressed: exportPlanFile,
                          icon: const Icon(Icons.download),
                          label: const Text('Export Plan'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ToggleButtons(
                    isSelected: [!useImperialUnits, useImperialUnits],
                    onPressed: (index) {
                      setState(() {
                        useImperialUnits = index == 1;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    selectedBorderColor: Theme.of(context).primaryColor,
                    selectedColor: Colors.white,
                    fillColor: Theme.of(context).primaryColor,
                    color: Colors.black87,
                    constraints: const BoxConstraints(
                      minHeight: 36,
                      minWidth: 88,
                    ),
                    children: const [
                      Text('km / m'),
                      Text('mi / ft'),
                    ],
                  ),
                ],
              ),
            ),
            if (routePoints.isNotEmpty) ...[
              Builder(
                builder: (context) {
                  final routeLayoutMode = _getRouteLayoutMode(context);

                  final paceControls = Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                                'Grade Adjusted Pace: ${formatPaceForDisplay(selectedPaceSeconds)}/$distanceUnitLabel'),
                            Expanded(
                              child: Slider(
                                value: selectedPaceSeconds,
                                min: minPaceSeconds,
                                max: maxPaceSeconds,
                                onChanged: (value) {
                                  setState(() {
                                    selectedPaceSeconds = value;
                                    _recalculatePacingAndCheckpoints();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedPaceSeconds =
                                      max(minPaceSeconds, selectedPaceSeconds - 5);
                                  _recalculatePacingAndCheckpoints();
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                minimumSize: const Size(40, 36),
                              ),
                              child: const Text('-5s', style: TextStyle(fontSize: 14)),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedPaceSeconds =
                                      max(minPaceSeconds, selectedPaceSeconds - 1);
                                  _recalculatePacingAndCheckpoints();
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                minimumSize: const Size(40, 36),
                              ),
                              child: const Text('-1s', style: TextStyle(fontSize: 14)),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedPaceSeconds =
                                      min(maxPaceSeconds, selectedPaceSeconds + 1);
                                  _recalculatePacingAndCheckpoints();
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                minimumSize: const Size(40, 36),
                              ),
                              child: const Text('+1s', style: TextStyle(fontSize: 14)),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedPaceSeconds =
                                      min(maxPaceSeconds, selectedPaceSeconds + 5);
                                  _recalculatePacingAndCheckpoints();
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                minimumSize: const Size(40, 36),
                              ),
                              child: const Text('+5s', style: TextStyle(fontSize: 14)),
                            ),
                          ],
                        ),
                        if (timePoints.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Estimated Total Time: ${_formatTotalTime(_estimatedTotalTimeMinutes)}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );

                  final mapAndElevation = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (routeLayoutMode == RouteLayoutMode.medium) ...[
                        paceControls,
                        const SizedBox(height: 8),
                      ],
                      // Map toggle button
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 6.0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              showMap = !showMap;
                            });
                          },
                          icon: Icon(
                              showMap ? Icons.visibility_off : Icons.visibility),
                          label: Text(showMap ? 'Hide Map' : 'Show Map'),
                        ),
                      ),
                      // Map container
                      if (showMap)
                        SizedBox(
                          height: 360,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final screenWidth = constraints.maxWidth;
                              final double horizontalPadding =
                                  screenWidth > 600 ? 40.0 : 0.0;
                              final double containerWidth =
                                  screenWidth - (horizontalPadding * 2);

                              return Center(
                                child: Container(
                                  width: containerWidth,
                                  decoration: BoxDecoration(
                                    border: screenWidth > 600
                                        ? Border.all(
                                            color: Colors.grey.shade300, width: 1)
                                        : null,
                                    borderRadius: screenWidth > 600
                                        ? BorderRadius.circular(8)
                                        : null,
                                  ),
                                  child: Stack(
                                    children: [
                                      LayoutBuilder(
                                        builder: (context, mapConstraints) {
                                          return MouseRegion(
                                            cursor: hoveredDistance != null
                                                ? SystemMouseCursors.click
                                                : SystemMouseCursors.basic,
                                            onHover: (event) {
                                              if (_mapDebounceTimer?.isActive ?? false) return;
                                              final RenderBox? box =
                                                  context.findRenderObject() as RenderBox?;
                                              if (box == null) return;

                                              try {
                                                final localPosition =
                                                    box.globalToLocal(event.position);
                                                final closestIndex =
                                                    findClosestRoutePoint(
                                                        localPosition,
                                                        mapConstraints);
                                                if (closestIndex >= 0 &&
                                                    closestIndex < routePoints.length) {
                                                  int elevationIndex;
                                                  if (routePoints.length ==
                                                      elevationPoints.length) {
                                                    elevationIndex = closestIndex;
                                                  } else {
                                                    final double ratio =
                                                        elevationPoints.length /
                                                            routePoints.length;
                                                    elevationIndex =
                                                        (closestIndex * ratio).round();
                                                    elevationIndex = elevationIndex.clamp(
                                                        0,
                                                        elevationPoints.length - 1,
                                                    );
                                                  }

                                                  if (elevationIndex >= 0 &&
                                                      elevationIndex <
                                                          elevationPoints.length &&
                                                      mounted) {
                                                    setState(() {
                                                      hoveredPointIndex = closestIndex;
                                                      _closestElevationPointIndex =
                                                          elevationIndex;
                                                      hoveredDistance =
                                                          elevationPoints[elevationIndex].x;
                                                      hoveredSpot =
                                                          elevationPoints[elevationIndex];
                                                    });
                                                  }
                                                  _mapDebounceTimer = Timer(
                                                    const Duration(milliseconds: 5),
                                                    () {},
                                                  );
                                                }
                                              } catch (_) {}
                                            },
                                            onExit: (_) {
                                              if (mounted) {
                                                setState(() {
                                                  hoveredPointIndex = null;
                                                  hoveredDistance = null;
                                                  hoveredSpot = null;
                                                  _closestElevationPointIndex = -1;
                                                });
                                              }
                                            },
                                            child: FlutterMap(
                                              mapController: mapController,
                                              options: MapOptions(
                                                onTap: (tapPosition, point) {
                                                  _handleMapTap(point);
                                                },
                                                initialCameraFit: CameraFit.bounds(
                                                  bounds: LatLngBounds.fromPoints(routePoints),
                                                  padding: const EdgeInsets.all(20.0),
                                                ),
                                              ),
                                              children: [
                                                TileLayer(
                                                  urlTemplate:
                                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                                  userAgentPackageName:
                                                      'com.example.app',
                                                  tileProvider:
                                                      CancellableNetworkTileProvider(),
                                                ),
                                                PolylineLayer(
                                                  polylines: [
                                                    Polyline(
                                                      points: routePoints,
                                                      color: Colors.blue,
                                                      strokeWidth: 3,
                                                    ),
                                                  ],
                                                ),
                                                if (hoveredPointIndex != null &&
                                                    hoveredPointIndex! < routePoints.length)
                                                  MarkerLayer(
                                                    markers: [
                                                      Marker(
                                                        point: routePoints[hoveredPointIndex!],
                                                        child: Container(
                                                          width: 3,
                                                          height: 3,
                                                          decoration: BoxDecoration(
                                                            color: Colors.blue,
                                                            shape: BoxShape.circle,
                                                            border: Border.all(
                                                              color: Colors.white,
                                                              width: 1,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                MarkerLayer(
                                                  markers: [
                                                    if (showCheckpoints)
                                                      ...checkpoints.map((checkpoint) {
                                                        final int routePointIndex =
                                                            _findRoutePointIndexForDistance(
                                                                checkpoint.distance);
                                                        if (routePointIndex < 0 ||
                                                            routePointIndex >= routePoints.length) {
                                                          return Marker(
                                                            point: const LatLng(0, 0),
                                                            width: 0,
                                                            height: 0,
                                                            child: Container(),
                                                          );
                                                        }

                                                        return Marker(
                                                          point: routePoints[routePointIndex],
                                                          child: Container(
                                                            width: 3,
                                                            height: 3,
                                                            decoration: BoxDecoration(
                                                              color: Colors.red.withOpacity(0.7),
                                                              shape: BoxShape.circle,
                                                              border: Border.all(
                                                                color: Colors.white,
                                                                width: 2,
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      }),
                                                    if (_isPendingCheckpointCreation &&
                                                        _pendingCheckpointDistance != null)
                                                      ..._getPendingCheckpointMarker(),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );

                  final mapAndElevationChart = Container(
                    height: 260,
                    padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        double minElevRounded =
                            max(minElevation! / 200.floor() * 200, 0);
                        double maxElevRounded = maxElevation! / 200.ceil() * 200;

                        return GestureDetector(
                          onTapUp: (details) => _handleElevationChartTap(
                              details.localPosition, constraints),
                          child: MouseRegion(
                            cursor: hoveredDistance != null
                                ? SystemMouseCursors.click
                                : SystemMouseCursors.basic,
                            onHover: (event) {
                              if (elevationPoints.isEmpty) return;
                              final RenderBox? box =
                                  context.findRenderObject() as RenderBox?;
                              if (box == null) return;

                              try {
                                final localPosition = box.globalToLocal(event.position);
                                const double leftOffset = 56;
                                const double rightOffset = 0;
                                final double chartAreaWidth =
                                    constraints.maxWidth - leftOffset - rightOffset;
                                double normalizedX =
                                    (localPosition.dx - leftOffset) / chartAreaWidth;
                                normalizedX = normalizedX.clamp(0.0, 1.0);

                                final double hoverDistance =
                                    normalizedX * elevationPoints.last.x;
                                final FlSpot hoveredPoint =
                                    findClosestElevationPoint(hoverDistance);
                                final int elevationIndex = _closestElevationPointIndex;

                                if (elevationIndex < 0) return;

                                int routePointIndex =
                                    _findRoutePointIndexForDistance(hoveredPoint.x);

                                if (routePointIndex < 0 ||
                                    routePointIndex >= routePoints.length) return;

                                if (mounted) {
                                  setState(() {
                                    hoveredPointIndex = routePointIndex;
                                    hoveredDistance = hoveredPoint.x;
                                    hoveredSpot = hoveredPoint;
                                  });
                                }
                              } catch (_) {}
                            },
                            onExit: (_) {
                              if (mounted) {
                                setState(() {
                                  hoveredPointIndex = null;
                                  hoveredDistance = null;
                                  hoveredSpot = null;
                                  _closestElevationPointIndex = -1;
                                });
                              }
                            },
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: 200,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: Colors.grey.shade300,
                                    strokeWidth: 1,
                                  ),
                                ),
                                borderData: FlBorderData(
                                  show: true,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    axisNameWidget: Padding(
                                      padding: const EdgeInsets.only(top: 12.0),
                                      child: Text(
                                        'Distance ($distanceUnitLabel)',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      interval: (elevationPoints.last.x / 10)
                                          .clamp(1, double.infinity),
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          convertDistanceToDisplay(value).toStringAsFixed(
                                              value < 1 ? 1 : 0),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    axisNameWidget: const SizedBox.shrink(),
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      interval: useImperialUnits ? 650 : 200,
                                      getTitlesWidget: (value, meta) {
                                        final double intervalValue =
                                            useImperialUnits ? 650.0 : 200.0;
                                        if ((value % intervalValue) > 0.001) {
                                          return Container();
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 8.0),
                                          child: Text(
                                            convertElevationToDisplay(value).toStringAsFixed(0),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: elevationPoints,
                                    isCurved: true,
                                    gradient: LinearGradient(
                                      colors: List.generate(
                                        smoothedGradients.length,
                                        (i) => getGradientColor(smoothedGradients[i]),
                                      ),
                                      stops: List.generate(
                                        smoothedGradients.length,
                                        (i) => elevationPoints[i].x / elevationPoints.last.x,
                                      ),
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    barWidth: 2,
                                    dotData: FlDotData(
                                      show: true,
                                      checkToShowDot: (spot, barData) {
                                        if (hoveredSpot != null &&
                                            (spot.x - hoveredSpot!.x).abs() < 0.05 &&
                                            spot.y == hoveredSpot!.y) {
                                          return true;
                                        }

                                        if (showCheckpoints) {
                                          for (var checkpoint in checkpoints) {
                                            final FlSpot elevSpot =
                                                findClosestElevationPoint(
                                                    checkpoint.distance);
                                            if ((spot.x - elevSpot.x).abs() < 0.05 &&
                                                spot.y == elevSpot.y) {
                                              return true;
                                            }
                                          }
                                        }
                                        return false;
                                      },
                                      getDotPainter: (spot, percent, barData, index) {
                                        bool isCheckpoint = false;
                                        if (showCheckpoints) {
                                          for (var checkpoint in checkpoints) {
                                            final FlSpot elevSpot =
                                                findClosestElevationPoint(
                                                    checkpoint.distance);
                                            if ((spot.x - elevSpot.x).abs() < 0.05 &&
                                                spot.y == elevSpot.y) {
                                              isCheckpoint = true;
                                              break;
                                            }
                                          }
                                        }

                                        return FlDotCirclePainter(
                                          radius: 6,
                                          color: isCheckpoint ? Colors.red : Colors.blue,
                                          strokeWidth: 2,
                                          strokeColor: Colors.white,
                                        );
                                      },
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: List.generate(
                                          smoothedGradients.length,
                                          (i) => getGradientColor(smoothedGradients[i])
                                              .withOpacity(0.2),
                                        ),
                                        stops: List.generate(
                                          smoothedGradients.length,
                                          (i) => elevationPoints[i].x / elevationPoints.last.x,
                                        ),
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                    ),
                                  ),
                                ],
                                minY: minElevRounded,
                                maxY: maxElevRounded,
                                minX: 0,
                                maxX: elevationPoints.last.x,
                                lineTouchData: const LineTouchData(enabled: false),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );

                  final histograms = Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route Summary',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return Wrap(
                              spacing: 8.0,
                              runSpacing: 8.0,
                              alignment: WrapAlignment.center,
                              children: [
                                SizedBox(
                                  width: constraints.maxWidth > 800
                                      ? (constraints.maxWidth - 40) / 6
                                      : (constraints.maxWidth - 8) / 2,
                                  child: _buildStatCard(
                                    'Total Distance',
                                    elevationPoints.isNotEmpty
                                        ? formatDistanceValue(elevationPoints.last.x)
                                        : '0 $distanceUnitLabel',
                                    Icons.straighten,
                                    Colors.blue,
                                  ),
                                ),
                                SizedBox(
                                  width: constraints.maxWidth > 800
                                      ? (constraints.maxWidth - 40) / 6
                                      : (constraints.maxWidth - 8) / 2,
                                  child: _buildStatCard(
                                    'Grade Adj. Distance',
                                    checkpoints.isNotEmpty
                                        ? formatDistanceValue(
                                            checkpoints.last.cumulativeGradeAdjustedDistance)
                                        : '0 $distanceUnitLabel',
                                    Icons.terrain,
                                    Colors.purple,
                                  ),
                                ),
                                SizedBox(
                                  width: constraints.maxWidth > 800
                                      ? (constraints.maxWidth - 40) / 6
                                      : (constraints.maxWidth - 8) / 2,
                                  child: _buildStatCard(
                                    'Elevation Gain',
                                    cumulativeElevationGain.isNotEmpty
                                        ? formatElevationValue(cumulativeElevationGain.last)
                                        : '0 $elevationUnitLabel',
                                    Icons.trending_up,
                                    Colors.green,
                                  ),
                                ),
                                SizedBox(
                                  width: constraints.maxWidth > 800
                                      ? (constraints.maxWidth - 40) / 6
                                      : (constraints.maxWidth - 8) / 2,
                                  child: _buildStatCard(
                                    'Elevation Loss',
                                    cumulativeElevationLoss.isNotEmpty
                                        ? formatElevationValue(cumulativeElevationLoss.last)
                                        : '0 $elevationUnitLabel',
                                    Icons.trending_down,
                                    Colors.red,
                                  ),
                                ),
                                SizedBox(
                                  width: constraints.maxWidth > 800
                                      ? (constraints.maxWidth - 40) / 6
                                      : (constraints.maxWidth - 8) / 2,
                                  child: _buildStatCard(
                                    'Estimated Time',
                                    timePoints.isNotEmpty
                                        ? _formatTotalTime(_estimatedTotalTimeMinutes)
                                        : '0m',
                                    Icons.timer,
                                    Colors.orange,
                                  ),
                                ),
                                SizedBox(
                                  width: constraints.maxWidth > 800
                                      ? (constraints.maxWidth - 40) / 6
                                      : (constraints.maxWidth - 8) / 2,
                                  child: _buildStatCard(
                                    'Average Pace',
                                    timePoints.isNotEmpty
                                        ? '${formatPaceAxisLabel((timePoints.last.y * 60) / elevationPoints.last.x)} min/$distanceUnitLabel'
                                        : '0 min/$distanceUnitLabel',
                                    Icons.speed,
                                    Colors.cyan,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildBarChart(
                              'Time at Elevation',
                              calculateRouteSummaryData()['elevation'] ?? [],
                              Colors.blue,
                            ),
                            const SizedBox(height: 12),
                            _buildBarChart(
                              'Time at Gradient',
                              calculateRouteSummaryData()['gradient'] ?? [],
                              Colors.red,
                            ),
                            const SizedBox(height: 12),
                            _buildBarChart(
                              'Time at Pace (min/$distanceUnitLabel)',
                              calculateRouteSummaryData()['pace'] ?? [],
                              Colors.green,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );

                  final splitsTable = Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              showCheckpoints = !showCheckpoints;
                              if (showCheckpoints && checkpoints.isEmpty) {
                                addDefaultFinishCheckpoint();
                              }
                            });
                          },
                          icon: Icon(showCheckpoints ? Icons.visibility_off : Icons.visibility),
                          label: Text(showCheckpoints ? 'Hide Checkpoints' : 'Add Checkpoints'),
                        ),
                        if (showCheckpoints) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final screenWidth = MediaQuery.of(context).size.width;
                                    final bool isWideScreen = screenWidth > 800;

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (!isWideScreen) ...[
                                          Wrap(
                                            spacing: 8,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              const Text('Start Time: '),
                                              TextButton(
                                                onPressed: () async {
                                                  final TimeOfDay? time = await showTimePicker(
                                                    context: context,
                                                    initialTime: startTime ?? TimeOfDay.now(),
                                                    builder: (BuildContext context, Widget? child) {
                                                      return MediaQuery(
                                                        data: MediaQuery.of(context).copyWith(
                                                          alwaysUse24HourFormat: true,
                                                        ),
                                                        child: child!,
                                                      );
                                                    },
                                                  );
                                                  if (time != null && mounted) {
                                                    setState(() {
                                                      startTime = time;
                                                    });
                                                  }
                                                },
                                                child: Text(
                                                  startTime != null
                                                      ? '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}'
                                                      : 'Set Time',
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        Wrap(
                                          spacing: 16,
                                          runSpacing: 8,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            if (isWideScreen)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Text('Start Time: '),
                                                  TextButton(
                                                    onPressed: () async {
                                                      final TimeOfDay? time = await showTimePicker(
                                                        context: context,
                                                        initialTime: startTime ?? TimeOfDay.now(),
                                                        builder: (BuildContext context, Widget? child) {
                                                          return MediaQuery(
                                                            data: MediaQuery.of(context).copyWith(
                                                              alwaysUse24HourFormat: true,
                                                            ),
                                                            child: child!,
                                                          );
                                                        },
                                                      );
                                                      if (time != null && mounted) {
                                                        setState(() {
                                                          startTime = time;
                                                        });
                                                      }
                                                    },
                                                    child: Text(
                                                      startTime != null
                                                          ? '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}'
                                                          : 'Set Time',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            const SizedBox(height: 16),
                                            Wrap(
                                              spacing: 16,
                                              runSpacing: 8,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Checkbox(
                                                      value: useLinearPacing,
                                                      onChanged: (value) {
                                                        setState(() {
                                                          useLinearPacing = value ?? false;
                                                          _recalculatePacingAndCheckpoints();
                                                        });
                                                      },
                                                    ),
                                                    const Text('Linear Pacing Strategy'),
                                                  ],
                                                ),
                                                ElevatedButton.icon(
                                                  onPressed: exportCheckpointsToExcel,
                                                  icon: const Icon(Icons.download),
                                                  label: const Text('Download Excel'),
                                                ),
                                                ElevatedButton.icon(
                                                  onPressed: () {
                                                    setState(() {
                                                      resetAllManualAdjustments();
                                                    });
                                                  },
                                                  icon: const Icon(Icons.refresh),
                                                  label: const Text('Reset Pace Adjustments'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.orange.shade100,
                                                    foregroundColor: Colors.orange.shade800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (useLinearPacing) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(() {
                                                      if (pacingVariationPercent == 0) {
                                                        return 'Variation: 0% (uniform pace)';
                                                      }
                                                      final double halfVariation =
                                                          pacingVariationPercent.abs() / 200.0;
                                                      double startMultiplier;
                                                      double endMultiplier;
                                                      if (pacingVariationPercent > 0) {
                                                        startMultiplier = 1.0 - halfVariation;
                                                        endMultiplier = 1.0 + halfVariation;
                                                      } else {
                                                        startMultiplier = 1.0 + halfVariation;
                                                        endMultiplier = 1.0 - halfVariation;
                                                      }
                                                      final String startPace =
                                                          formatPace(selectedPaceSeconds * startMultiplier);
                                                      final String endPace =
                                                          formatPace(selectedPaceSeconds * endMultiplier);
                                                      final String direction =
                                                          pacingVariationPercent > 0
                                                              ? 'slowing down'
                                                              : 'speeding up';
                                                      return 'Variation: ${pacingVariationPercent.toStringAsFixed(0)}% ($direction: $startPace → $endPace)';
                                                    }()),
                                                  ),
                                                ],
                                              ),
                                              Slider(
                                                value: pacingVariationPercent,
                                                min: -10.0,
                                                max: 30.0,
                                                divisions: 40,
                                                label: '${pacingVariationPercent.toStringAsFixed(0)}%',
                                                onChanged: (value) {
                                                  setState(() {
                                                    pacingVariationPercent = value;
                                                    _recalculatePacingAndCheckpoints();
                                                  });
                                                },
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 16,
                                              runSpacing: 8,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Text('Carbs per hour: '),
                                                    SizedBox(
                                                      width: 45,
                                                      child: TextField(
                                                        keyboardType: TextInputType.number,
                                                        decoration: const InputDecoration(
                                                          hintText: '90',
                                                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                                        ),
                                                        onChanged: (value) {
                                                          final double? newValue = double.tryParse(value);
                                                          if (newValue != null) {
                                                            setState(() {
                                                              carbsPerHour = newValue;
                                                              calculateCarbsUnits();
                                                            });
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                    const Text('g/hour'),
                                                  ],
                                                ),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Text('Carb unit: '),
                                                    SizedBox(
                                                      width: 45,
                                                      child: TextField(
                                                        keyboardType: TextInputType.number,
                                                        decoration: const InputDecoration(
                                                          hintText: '45',
                                                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                                        ),
                                                        onChanged: (value) {
                                                          final double? newValue = double.tryParse(value);
                                                          if (newValue != null) {
                                                            setState(() {
                                                              gramsPerUnit = newValue;
                                                              calculateCarbsUnits();
                                                            });
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                    const Text('g'),
                                                  ],
                                                ),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Text('Fluid per hour: '),
                                                    SizedBox(
                                                      width: 45,
                                                      child: TextField(
                                                        keyboardType: TextInputType.number,
                                                        decoration: const InputDecoration(
                                                          hintText: '750',
                                                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                                        ),
                                                        onChanged: (value) {
                                                          final double? newValue = double.tryParse(value);
                                                          if (newValue != null) {
                                                            setState(() {
                                                              fluidPerHour = newValue;
                                                              calculateFluidUnits();
                                                            });
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                    const Text('ml/h'),
                                                  ],
                                                ),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Text('Fluid unit: '),
                                                    SizedBox(
                                                      width: 45,
                                                      child: TextField(
                                                        keyboardType: TextInputType.number,
                                                        decoration: const InputDecoration(
                                                          hintText: '500',
                                                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                                        ),
                                                        onChanged: (value) {
                                                          final double? newValue = double.tryParse(value);
                                                          if (newValue != null) {
                                                            setState(() {
                                                              mlPerUnit = newValue;
                                                              calculateFluidUnits();
                                                            });
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                    const Text('ml'),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 1200),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        topRight: Radius.circular(8),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 120, child: Text('Name', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 110, child: Text('Total Distance\n($distanceUnitLabel)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 110, child: Text('Segment Dist.\n($distanceUnitLabel)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 110, child: Text('Segment Pace\n(min/$distanceUnitLabel)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 110, child: Text('Grade Adj. Dist.\n($distanceUnitLabel)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 110, child: Text('Elevation\n($elevationUnitLabel)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 110, child: Text('Elev. Gain\n($elevationUnitLabel)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 110, child: Text('Elev. Loss\n($elevationUnitLabel)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 100, child: Text('Total Time', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 100, child: Text('Segment Time', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 100, child: Text('Pause (s)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        SizedBox(width: 120, child: Text('Pace Adj.', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        if (carbsPerHour > 0 && gramsPerUnit > 0) SizedBox(width: 100, child: Text('Carb units', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        if (fluidPerHour > 0 && mlPerUnit > 0) SizedBox(width: 100, child: Text('Fluid units', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        if (startTime != null) SizedBox(width: 100, child: Text('Real Time', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                                        const SizedBox(width: 180),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: const BorderRadius.only(
                                        bottomLeft: Radius.circular(8),
                                        bottomRight: Radius.circular(8),
                                      ),
                                    ),
                                    child: Column(
                                      children: List.generate(checkpoints.length, (index) {
                                        final checkpoint = checkpoints[index];
                                        return Container(
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: index < checkpoints.length - 1
                                                  ? BorderSide(color: Colors.grey.shade300)
                                                  : BorderSide.none,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 120,
                                                child: TextFormField(
                                                  key: ValueKey('checkpoint_name_${checkpoint.id}'),
                                                  focusNode: index < _nameFocusNodes.length ? _nameFocusNodes[index] : null,
                                                  initialValue: checkpoint.name ?? '',
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                    border: OutlineInputBorder(),
                                                    hintText: 'Enter name',
                                                  ),
                                                  onChanged: (value) {
                                                    setState(() {
                                                      checkpoint.name = value;
                                                    });
                                                  },
                                                  onTap: () {
                                                    setState(() {
                                                      _editingCheckpointId = checkpoint.id;
                                                      _isEditingName = true;
                                                    });
                                                  },
                                                  onFieldSubmitted: (_) {
                                                    setState(() {
                                                      _isEditingName = false;
                                                      _editingCheckpointId = null;
                                                    });
                                                    _processCheckpointChanges();
                                                  },
                                                  onEditingComplete: () {
                                                    setState(() {
                                                      _isEditingName = false;
                                                      _editingCheckpointId = null;
                                                    });
                                                    _processCheckpointChanges();
                                                  },
                                                ),
                                              ),
                                              SizedBox(
                                                width: 110,
                                                child: TextFormField(
                                                  key: ValueKey('checkpoint_${checkpoint.id}'),
                                                  focusNode: index < _distanceFocusNodes.length ? _distanceFocusNodes[index] : null,
                                                  initialValue: checkpoint.distance > 0
                                                      ? convertDistanceToDisplay(checkpoint.distance).toStringAsFixed(1)
                                                      : '',
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                    border: const OutlineInputBorder(),
                                                    hintText: 'Enter $distanceUnitLabel',
                                                  ),
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  onChanged: (value) {
                                                    final double? distance = double.tryParse(value);
                                                    if (distance != null) {
                                                      updateCheckpointDistance(
                                                        index,
                                                        convertDistanceFromDisplay(distance),
                                                      );
                                                    }
                                                  },
                                                  onTap: () {
                                                    setState(() {
                                                      _editingCheckpointId = checkpoint.id;
                                                      _isEditingDistance = true;
                                                    });
                                                  },
                                                  onFieldSubmitted: (_) {
                                                    setState(() {
                                                      _isEditingDistance = false;
                                                      _editingCheckpointId = null;
                                                    });
                                                    _processCheckpointChanges();
                                                  },
                                                  onEditingComplete: () {
                                                    setState(() {
                                                      _isEditingDistance = false;
                                                      _editingCheckpointId = null;
                                                    });
                                                    _processCheckpointChanges();
                                                  },
                                                ),
                                              ),
                                              SizedBox(
                                                width: 110,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    convertDistanceToDisplay(_getSegmentDistance(index)).toStringAsFixed(1),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 110,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(_getSegmentPace(index)),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 110,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    convertDistanceToDisplay(
                                                            checkpoint.gradeAdjustedDistance)
                                                        .toStringAsFixed(1),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 110,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    convertElevationToDisplay(
                                                            checkpoint.elevation)
                                                        .toStringAsFixed(0),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 110,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    convertElevationToDisplay(
                                                            checkpoint.elevationGain)
                                                        .toStringAsFixed(0),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 110,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    convertElevationToDisplay(
                                                            checkpoint.elevationLoss)
                                                        .toStringAsFixed(0),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 100,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    _formatClockTime(checkpoint.cumulativeTime),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 100,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    _formatClockTime(checkpoint.timeFromPrevious),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 100,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: TextFormField(
                                                    initialValue: checkpoint.pauseSeconds.toStringAsFixed(0),
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                                                    textAlign: TextAlign.center,
                                                    decoration: const InputDecoration(
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                                      border: OutlineInputBorder(),
                                                    ),
                                                    onChanged: (value) {
                                                      final parsed = double.tryParse(value);
                                                      final safeValue = parsed == null || parsed < 0 ? 0.0 : parsed;
                                                      _adjustPauseTime(index, safeValue);
                                                    },
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 150,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        visualDensity: VisualDensity.compact,
                                                        onPressed: () => _adjustSegmentPace(index, -1),
                                                        icon: const Icon(Icons.remove),
                                                      ),
                                                      Flexible(
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            '${checkpoint.adjustmentFactor.round()}s',
                                                            textAlign: TextAlign.center,
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        visualDensity: VisualDensity.compact,
                                                        onPressed: () => _adjustSegmentPace(index, 1),
                                                        icon: const Icon(Icons.add),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              if (carbsPerHour > 0 && gramsPerUnit > 0)
                                                SizedBox(
                                                  width: 100,
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    child: Text(checkpoint.legUnits.toString()),
                                                  ),
                                                ),
                                              if (fluidPerHour > 0 && mlPerUnit > 0)
                                                SizedBox(
                                                  width: 100,
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    child: Text(checkpoint.legFluidUnits.toString()),
                                                  ),
                                                ),
                                              if (startTime != null)
                                                SizedBox(
                                                  width: 100,
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    child: Text(
                                                      _formatRealTime(checkpoint.cumulativeTime),
                                                    ),
                                                  ),
                                                ),
                                              const SizedBox(width: 180),
                                            ],
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );

                  return ResponsiveRouteAnalysisLayout(
                    layoutMode: routeLayoutMode,
                    mapAndElevation: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        mapAndElevation,
                        mapAndElevationChart,
                      ],
                    ),
                    histograms: histograms,
                    splitsTable: splitsTable,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTotalTime(double totalMinutes) {
    final totalSeconds = (totalMinutes * 60).round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  String _formatClockTime(double totalMinutes) {
    final totalSeconds = (totalMinutes * 60).round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double get _estimatedTotalTimeMinutes {
    final movingTime = timePoints.isNotEmpty ? timePoints.last.y : 0.0;
    final pausedTime = checkpoints.fold<double>(
      0.0,
      (total, checkpoint) => total + max(0, checkpoint.pauseSeconds) / 60.0,
    );
    return movingTime + pausedTime;
  }

  int _findRoutePointIndexForDistance(double distance) {
    int closestElevationIndex = -1;
    double minDist = double.infinity;

    for (int i = 0; i < elevationPoints.length; i++) {
      double dist = (elevationPoints[i].x - distance).abs();
      if (dist < minDist) {
        minDist = dist;
        closestElevationIndex = i;
      }
    }

    // If we couldn't find a close elevation point, return -1
    if (closestElevationIndex < 0) return -1;

    // Now map this elevation point index to a route point index
    // Since both arrays might have different lengths, we need to map proportionally

    // If the arrays have the same length, we can use a direct mapping
    if (elevationPoints.length == routePoints.length) {
      return closestElevationIndex;
    }

    // Otherwise, use a proportional mapping
    double ratio = routePoints.length / elevationPoints.length;
    int estimatedRouteIndex = (closestElevationIndex * ratio).round();

    // Ensure the index is within bounds
    return estimatedRouteIndex.clamp(0, routePoints.length - 1);
  }

  int findClosestPointIndex(double targetDistance) {
    return elevationPoints.indexWhere((point) => point.x >= targetDistance);
  }

  // Optimize this method to find the closest elevation point to a given distance
  FlSpot findClosestElevationPoint(double distance) {
    if (elevationPoints.isEmpty) return const FlSpot(0, 0);

    // Use binary search for better performance when finding the closest point
    int low = 0;
    int high = elevationPoints.length - 1;

    // If distance is beyond the range, return the first or last point
    if (distance <= elevationPoints.first.x) {
      _closestElevationPointIndex = 0;
      return elevationPoints.first;
    }
    if (distance >= elevationPoints.last.x) {
      _closestElevationPointIndex = elevationPoints.length - 1;
      return elevationPoints.last;
    }

    // Binary search to find the closest point
    while (low <= high) {
      int mid = (low + high) ~/ 2;

      if (elevationPoints[mid].x < distance) {
        low = mid + 1;
      } else if (elevationPoints[mid].x > distance) {
        high = mid - 1;
      } else {
        // Exact match found
        _closestElevationPointIndex = mid;
        return elevationPoints[mid];
      }
    }

    // At this point, low > high
    // The closest point is either at index high or low
    int closestIndex;
    if (high < 0) {
      closestIndex = 0;
    } else if (low >= elevationPoints.length) {
      closestIndex = elevationPoints.length - 1;
    } else {
      double distLow = (elevationPoints[low].x - distance).abs();
      double distHigh = (elevationPoints[high].x - distance).abs();
      closestIndex = distLow < distHigh ? low : high;
    }

    _closestElevationPointIndex = closestIndex;
    return elevationPoints[closestIndex];
  }

  // Add a field to track the index of the closest elevation point
  int _closestElevationPointIndex = -1;

  // Add a new checkpoint with the given distance
  void addCheckpoint() {
    // Create a new checkpoint with a unique ID and timestamp to ensure uniqueness
    final newCheckpoint = CheckpointData(distance: 0.0);
    newCheckpoint.id = DateTime.now().millisecondsSinceEpoch.toString();

    setState(() {
      // Add the checkpoint
      checkpoints.add(newCheckpoint);

      // Add new focus nodes for this checkpoint - with web platform handling
      final nameNode = FocusNode();
      final distanceNode = FocusNode();

      // Add focus listeners only if not on web
      if (!_isWeb) {
        try {
          nameNode.addListener(_onFocusChange);
          distanceNode.addListener(_onFocusChange);
        } catch (e) {
          // Silently handle any focus node errors
        }
      }

      _nameFocusNodes.add(nameNode);
      _distanceFocusNodes.add(distanceNode);

      // Sort checkpoints by distance
      checkpoints.sort((a, b) => a.distance.compareTo(b.distance));

      // Recalculate metrics for all checkpoints to ensure consistency
      _calculateCheckpointMetrics(startIndex: 0);

      // Recalculate carbs and fluid units for all checkpoints if values are set
      if (carbsPerHour > 0 && gramsPerUnit > 0) {
        calculateCarbsUnits();
      }
      if (fluidPerHour > 0 && mlPerUnit > 0) {
        calculateFluidUnits();
      }
    });
  }

  // Add a default 'Finish' checkpoint
  void addDefaultFinishCheckpoint() {
    if (elevationPoints.isEmpty) return;

    setState(() {
      // Create a new checkpoint at the end of the route
      final finishCheckpoint = CheckpointData(distance: elevationPoints.last.x);
      finishCheckpoint.id = 'finish';
      finishCheckpoint.name = 'Finish';

      // Add the checkpoint
      checkpoints.add(finishCheckpoint);

      // Add new focus nodes for this checkpoint - with web platform handling
      final nameNode = FocusNode();
      final distanceNode = FocusNode();

      // Add focus listeners only if not on web
      if (!_isWeb) {
        try {
          nameNode.addListener(_onFocusChange);
          distanceNode.addListener(_onFocusChange);
        } catch (e) {
          // Silently handle any focus node errors
        }
      }

      _nameFocusNodes.add(nameNode);
      _distanceFocusNodes.add(distanceNode);

      // Recalculate metrics for all checkpoints to ensure consistency
      _calculateCheckpointMetrics(startIndex: 0);
    });
  }

  // Update the distance of a checkpoint
  void updateCheckpointDistance(int index, double newDistance) {
    if (index < 0 || index >= checkpoints.length) return;

    // Ensure distance is not negative
    newDistance = max(0, newDistance);

    // Ensure distance is not beyond the route length
    if (elevationPoints.isNotEmpty) {
      newDistance = min(newDistance, elevationPoints.last.x);
    }

    // Update the distance immediately
    setState(() {
      checkpoints[index].distance = newDistance;
    });
  }

  double _segmentDistanceInKm(int checkpointIndex) {
    if (checkpointIndex < 0 || checkpointIndex >= checkpoints.length) return 0;
    if (checkpointIndex == 0) {
      return checkpoints[0].distance / 1000.0;
    }
    return (checkpoints[checkpointIndex].distance -
            checkpoints[checkpointIndex - 1].distance) /
        1000.0;
  }

  void _applyTimeBalanceToOtherSegments(
    int changedCheckpointIndex, {
    double paceDeltaSecondsPerKm = 0,
    double pauseDeltaSeconds = 0,
  }) {
    if (checkpoints.length < 2) return;

    double timeDeltaSeconds = 0;
    if (paceDeltaSecondsPerKm != 0) {
      final double segmentDistanceKm = _segmentDistanceInKm(changedCheckpointIndex);
      timeDeltaSeconds += paceDeltaSecondsPerKm * segmentDistanceKm;
    }
    if (pauseDeltaSeconds != 0) {
      timeDeltaSeconds += pauseDeltaSeconds;
    }

    if (timeDeltaSeconds.abs() < 0.001) return;

    double totalOtherDistanceKm = 0.0;
    for (int i = 0; i < checkpoints.length; i++) {
      if (i != changedCheckpointIndex) {
        totalOtherDistanceKm += _segmentDistanceInKm(i);
      }
    }

    if (totalOtherDistanceKm <= 0) return;

    final double compensationPerKm = -(timeDeltaSeconds / totalOtherDistanceKm);

    for (int i = 0; i < checkpoints.length; i++) {
      if (i == changedCheckpointIndex) continue;
      final double current = checkpoints[i].adjustmentFactor;
      checkpoints[i].adjustmentFactor =
          (current + compensationPerKm).clamp(
        -RouteAnalyzerScreen.maxAdjustmentSeconds,
        RouteAnalyzerScreen.maxAdjustmentSeconds,
      );
    }
  }

  void _adjustSegmentPace(int checkpointIndex, int stepCount) {
    if (checkpointIndex < 0 || checkpointIndex >= checkpoints.length) return;

    final double delta = stepCount * paceAdjustmentStep;
    final double currentAdjustment = checkpoints[checkpointIndex].adjustmentFactor;
    final double nextAdjustment = (currentAdjustment + delta).clamp(
      -RouteAnalyzerScreen.maxAdjustmentSeconds,
      RouteAnalyzerScreen.maxAdjustmentSeconds,
    );

    setState(() {
      checkpoints[checkpointIndex].adjustmentFactor = nextAdjustment;
      _applyTimeBalanceToOtherSegments(
        checkpointIndex,
        paceDeltaSecondsPerKm: delta,
      );
      _calculateCheckpointMetrics(startIndex: 0);
    });

    _recalculatePacingAndCheckpoints();
  }

  void _adjustPauseTime(int checkpointIndex, double newPauseSeconds) {
    if (checkpointIndex < 0 || checkpointIndex >= checkpoints.length) return;

    final double clampedPause = max(0, newPauseSeconds);

    setState(() {
      checkpoints[checkpointIndex].pauseSeconds = clampedPause;
      _calculateCheckpointMetrics(startIndex: 0);
    });

    _recalculatePacingAndCheckpoints();
  }

  void updateCheckpointPause(int index, double pauseSeconds) {
    if (index < 0 || index >= checkpoints.length) return;

    setState(() {
      checkpoints[index].pauseSeconds = max(0, pauseSeconds);
      _calculateCheckpointMetrics(startIndex: 0);
    });

    if (carbsPerHour > 0 && gramsPerUnit > 0) {
      calculateCarbsUnits();
    }
    if (fluidPerHour > 0 && mlPerUnit > 0) {
      calculateFluidUnits();
    }
  }

  // Process checkpoint changes when editing is complete
  void _processCheckpointChanges() {
    setState(() {
      // Sort checkpoints by distance
      checkpoints.sort((a, b) => a.distance.compareTo(b.distance));

      // Recalculate metrics for all checkpoints to ensure consistency
      _calculateCheckpointMetrics(startIndex: 0);
    });
  }

  // Remove a checkpoint at the given index
  void removeCheckpoint(int index) {
    if (index < 0 || index >= checkpoints.length) return;

    setState(() {
      // Remove the focus nodes - with web platform handling
      if (!_isWeb && index < _nameFocusNodes.length) {
        try {
          _nameFocusNodes[index].removeListener(_onFocusChange);
          _nameFocusNodes[index].dispose();
        } catch (e) {
          // Silently handle any focus node errors
        }
        _nameFocusNodes.removeAt(index);
      }

      if (!_isWeb && index < _distanceFocusNodes.length) {
        try {
          _distanceFocusNodes[index].removeListener(_onFocusChange);
          _distanceFocusNodes[index].dispose();
        } catch (e) {
          // Silently handle any focus node errors
        }
        _distanceFocusNodes.removeAt(index);
      }

      // Remove the checkpoint
      checkpoints.removeAt(index);

      // Recalculate metrics for all checkpoints to ensure consistency
      if (checkpoints.isNotEmpty) {
        _calculateCheckpointMetrics(startIndex: 0);
      }
    });
  }

  /// Comprehensive recalculation of pacing and checkpoint data
  /// Call this whenever pacing parameters change to ensure consistency
  void _recalculatePacingAndCheckpoints() {
    // Step 1: Regenerate linear pacing multipliers
    generateLinearPacingMultipliers();

    // Step 2: Update the unified pacing vector
    updatePacingVector();

    // Step 3: Recalculate time points based on updated pacing
    calculateTimePoints();

    // Step 4: Update checkpoint metrics
    if (checkpoints.isNotEmpty) {
      _calculateCheckpointMetrics(startIndex: 0);
    }
  }

  // Calculate metrics for all checkpoints
  void _calculateCheckpointMetrics({int startIndex = 0}) {
    if (elevationPoints.isEmpty || timePoints.isEmpty) return;

    // Always recalculate all checkpoints for consistency
    startIndex = 0;

    // First, ensure all checkpoints have valid distances
    for (int i = 0; i < checkpoints.length; i++) {
      final checkpoint = checkpoints[i];

      // Ensure distance is not negative
      checkpoint.distance = max(0, checkpoint.distance);

      // Ensure distance is not beyond the route length
      if (elevationPoints.isNotEmpty) {
        checkpoint.distance = min(checkpoint.distance, elevationPoints.last.x);
      }

      // Always recalculate base grade adjusted pace when pacing parameters change
      double startDistance = 0;
      if (i > 0) {
        startDistance = checkpoints[i - 1].distance;
      }
      // Recalculate the base grade adjusted pace to reflect current pacing settings
      checkpoint.baseGradeAdjustedPace =
          getSegmentBaseGradeAdjustedPace(startDistance, checkpoint.distance);

      // Calculate grade adjusted distance for this segment
      checkpoint.gradeAdjustedDistance =
          calculateGradeAdjustedDistance(startDistance, checkpoint.distance);
    }

    // Re-sort checkpoints by distance to ensure correct order
    checkpoints.sort((a, b) => a.distance.compareTo(b.distance));

    double accumulatedPauseMinutes = 0;

    // Process all checkpoints to ensure consistency
    for (int i = 0; i < checkpoints.length; i++) {
      final checkpoint = checkpoints[i];

      // Find the closest elevation point to this distance
      FlSpot elevationSpot = findClosestElevationPoint(checkpoint.distance);
      int elevationIndex = _closestElevationPointIndex;

      // Set elevation
      checkpoint.elevation = elevationSpot.y;

      // Set cumulative elevation gain/loss
      if (elevationIndex >= 0 &&
          elevationIndex < cumulativeElevationGain.length) {
        checkpoint.elevationGain = cumulativeElevationGain[elevationIndex];
        checkpoint.elevationLoss = cumulativeElevationLoss[elevationIndex];
      }

      // Calculate cumulative grade adjusted distance
      if (i == 0) {
        checkpoint.cumulativeGradeAdjustedDistance =
            checkpoint.gradeAdjustedDistance;
      } else {
        checkpoint.cumulativeGradeAdjustedDistance =
            checkpoints[i - 1].cumulativeGradeAdjustedDistance +
                checkpoint.gradeAdjustedDistance;
      }

      // Calculate cumulative time
      double cumulativeTime = 0;

      // Find the closest time points and interpolate
      FlSpot? prevPoint;
      FlSpot? nextPoint;

      for (int j = 0; j < timePoints.length - 1; j++) {
        if (timePoints[j].x <= checkpoint.distance &&
            timePoints[j + 1].x >= checkpoint.distance) {
          prevPoint = timePoints[j];
          nextPoint = timePoints[j + 1];
          break;
        }
      }

      if (prevPoint != null && nextPoint != null) {
        // Interpolate between the two points
        double timeDiff = nextPoint.y - prevPoint.y;
        double distDiff = nextPoint.x - prevPoint.x;
        if (distDiff > 0) {
          // Avoid division by zero
          double ratio = (checkpoint.distance - prevPoint.x) / distDiff;
          cumulativeTime = prevPoint.y + (timeDiff * ratio);
        } else {
          cumulativeTime = prevPoint.y;
        }
      } else if (checkpoint.distance <= 0) {
        // At start of route
        cumulativeTime = 0;
      } else if (checkpoint.distance >= timePoints.last.x) {
        // At or beyond end of route
        cumulativeTime = timePoints.last.y;
      } else {
        // Fallback to the closest point
        for (var timePoint in timePoints) {
          if (timePoint.x <= checkpoint.distance) {
            cumulativeTime = timePoint.y;
          } else {
            break;
          }
        }
      }

      checkpoint.pauseSeconds = max(0, checkpoint.pauseSeconds);
      checkpoint.cumulativeTime = cumulativeTime + accumulatedPauseMinutes;

      // Calculate time from previous checkpoint
      if (i > 0) {
        checkpoint.timeFromPrevious =
            checkpoint.cumulativeTime - checkpoints[i - 1].cumulativeTime;
      } else {
        checkpoint.timeFromPrevious = checkpoint.cumulativeTime;
      }

      accumulatedPauseMinutes += checkpoint.pauseSeconds / 60.0;
    }
  }

  // Format real time based on start time plus cumulative minutes
  String _formatRealTime(double cumulativeMinutes) {
    if (startTime == null) return 'N/A';

    // Convert start time to minutes since midnight
    int startMinutes = startTime!.hour * 60 + startTime!.minute;

    final totalSeconds = startMinutes * 60 + (cumulativeMinutes * 60).round();
    int totalMinutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    // Handle overflow to next day
    bool isNextDay = false;
    if (totalMinutes >= 24 * 60) {
      totalMinutes %= (24 * 60);
      isNextDay = true;
    }

    // Convert back to hours and minutes
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;

    // Format with leading zeros
    String timeStr =
      '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    // Add indicator if time is on the next day
    return isNextDay ? '$timeStr (+1)' : timeStr;
  }

  // Export checkpoints to Excel file
  Future<void> exportCheckpointsToExcel() async {
    if (checkpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No checkpoints to export')),
      );
      return;
    }

    try {
      // Create a new Excel workbook
      final excel = xl.Excel.createExcel();

      // Delete the default sheet and create a new one
      excel.delete('Sheet1');
      final sheet = excel['Checkpoints'];

      // Add headers
      final headers = [
        'Name',
        'Distance (km)',
        'Grade Adj. (km)',
        'Elevation (m)',
        'Elevation Gain (m)',
        'Elevation Loss (m)',
        'Total Time',
        'Segment Time',
        'Pause (s)',
      ];

      // Add Real Time header if start time is set
      if (startTime != null) {
        headers.add('Real Time');
      }

      for (int i = 0; i < headers.length; i++) {
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = xl.TextCellValue(headers[i]);
      }

      // Add checkpoint data
      for (int i = 0; i < checkpoints.length; i++) {
        final checkpoint = checkpoints[i];

        // Name
        sheet
            .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = xl.TextCellValue(checkpoint.name ?? '');

        // Distance
        sheet
            .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = xl.DoubleCellValue(checkpoint.distance);

        // Grade Adjusted Distance
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 2, rowIndex: i + 1))
                .value =
            xl.DoubleCellValue(checkpoint.cumulativeGradeAdjustedDistance);

        // Elevation
        sheet
            .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
            .value = xl.DoubleCellValue(checkpoint.elevation);

        // Elevation Gain
        sheet
            .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1))
            .value = xl.DoubleCellValue(checkpoint.elevationGain);

        // Elevation Loss
        sheet
            .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1))
            .value = xl.DoubleCellValue(checkpoint.elevationLoss);

        // Total Time (formatted)
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 6, rowIndex: i + 1))
                .value =
            xl.TextCellValue(_formatTotalTime(checkpoint.cumulativeTime));

        // Segment Time (formatted)
        sheet
                .cell(xl.CellIndex.indexByColumnRow(
                    columnIndex: 7, rowIndex: i + 1))
                .value =
            xl.TextCellValue(_formatTotalTime(checkpoint.timeFromPrevious));

        sheet
            .cell(xl.CellIndex.indexByColumnRow(
              columnIndex: 8, rowIndex: i + 1))
            .value = xl.DoubleCellValue(checkpoint.pauseSeconds);

        // Column index tracker
        int colIndex = 9;

        // Real Time (if start time is set)
        if (startTime != null) {
          sheet
                  .cell(xl.CellIndex.indexByColumnRow(
                      columnIndex: colIndex, rowIndex: i + 1))
                  .value =
              xl.TextCellValue(_formatRealTime(checkpoint.cumulativeTime));
        }
      }

      // Get the filename
      const String defaultFilename = 'route_checkpoints.xlsx';

      // Check if we're on the web platform
      if (kIsWeb) {
        // On web platforms, the Excel package's save method will trigger
        // a download in the browser
        excel.save(fileName: defaultFilename);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checkpoint data downloaded to your Downloads folder.')),
        );
        return;
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        try {
          final savedPath = await saveBytesFile(defaultFilename, fileBytes);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Checkpoint data exported to your Downloads folder.')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving file: $e')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting checkpoints: $e')),
      );
    }
  }

  // Get average grade adjusted pace for a segment
  double getSegmentBaseGradeAdjustedPace(
      double startDistance, double endDistance) {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty)
      return selectedPaceSeconds;

    // Find elevation points within this segment
    List<int> pointIndices = [];
    double totalDistance = 0;
    double weightedPaceSum = 0;

    for (int i = 0; i < elevationPoints.length; i++) {
      double distance = elevationPoints[i].x;
      if (distance >= startDistance && distance <= endDistance) {
        pointIndices.add(i);
      }
    }

    // If no points found, return default pace
    if (pointIndices.isEmpty) return selectedPaceSeconds;

    // Calculate weighted average of grade adjusted pace
    for (int i = 1; i < pointIndices.length; i++) {
      int idx = pointIndices[i];
      int prevIdx = pointIndices[i - 1];

      double segmentDistance =
          elevationPoints[idx].x - elevationPoints[prevIdx].x;
      double gradientAdj = calculateGradeAdjustment(smoothedGradients[idx]);
      double segmentPace = selectedPaceSeconds * gradientAdj;

      weightedPaceSum += segmentPace * segmentDistance;
      totalDistance += segmentDistance;
    }

    if (totalDistance > 0) {
      return weightedPaceSum / totalDistance;
    } else {
      return selectedPaceSeconds;
    }
  }

  // Calculate the total time for a segment based on grade adjusted pace
  double calculateSegmentTime(double startDistance, double endDistance) {
    if (startDistance >= endDistance) return 0;

    double segmentDistance = endDistance - startDistance;
    double baseGradeAdjustedPace =
        getSegmentBaseGradeAdjustedPace(startDistance, endDistance);

    // Ensure minimum pace
    baseGradeAdjustedPace = max(baseGradeAdjustedPace, minSegmentPace);

    // Calculate time in minutes
    return (segmentDistance * baseGradeAdjustedPace) / 60;
  }

  // Calculate the current overall average pace for the entire route
  double calculateOverallAveragePace() {
    if (elevationPoints.isEmpty || checkpoints.isEmpty) {
      return selectedPaceSeconds;
    }

    double totalDistance = elevationPoints.last.x;
    double totalTimeMinutes = 0;

    // Calculate segment times based on base grade adjusted pace
    if (checkpoints.length > 1) {
      // Calculate multi-segment route
      for (int i = 0; i < checkpoints.length - 1; i++) {
        double startDist = checkpoints[i].distance;
        double endDist = checkpoints[i + 1].distance;
        double segTime = calculateSegmentTime(startDist, endDist);
        totalTimeMinutes += segTime;
      }

      // Add time from start to first checkpoint
      double firstSegTime = calculateSegmentTime(0, checkpoints[0].distance);
      totalTimeMinutes += firstSegTime;
    } else if (checkpoints.length == 1) {
      // Single checkpoint route
      // Time from start to checkpoint
      double segTime = calculateSegmentTime(0, checkpoints[0].distance);
      totalTimeMinutes += segTime;

      // Time from checkpoint to end
      if (checkpoints[0].distance < totalDistance) {
        double endSegTime =
            calculateSegmentTime(checkpoints[0].distance, totalDistance);
        totalTimeMinutes += endSegTime;
      }
    }

    // Convert back to seconds per km
    return (totalTimeMinutes * 60) / totalDistance;
  }

  // Calculate data for summary section charts
  Map<String, List<ChartData>> calculateRouteSummaryData() {
    Map<String, List<ChartData>> result = {
      'elevation': [],
      'pace': [],
      'gradient': []
    };

    if (elevationPoints.isEmpty ||
        smoothedGradients.isEmpty ||
        minElevation == null ||
        maxElevation == null) return result;

    // Safety check - ensure we have enough data to create meaningful bins
    if (elevationPoints.length < 5 || smoothedGradients.length < 5) {
      // Add a "Not enough data" placeholder for each chart
      result['elevation']!.add(ChartData('Insufficient Data', 0));
      result['pace']!.add(ChartData('Insufficient Data', 0));
      result['gradient']!.add(ChartData('Insufficient Data', 0));
      return result;
    }

    // Define custom elevation bins in the current display unit, keeping them
    // readable and rounded while guaranteeing at least five buckets when data
    // is sparse.
    final String elevationUnit = useImperialUnits ? 'ft' : 'm';
    final double minElevationDisplay = elevationPoints
        .map((point) => convertElevationToDisplay(point.y))
        .reduce(min);
    final double maxElevationDisplay = elevationPoints
        .map((point) => convertElevationToDisplay(point.y))
        .reduce(max);
    final List<double> elevationStepOptions = useImperialUnits
        ? [1000.0, 500.0, 250.0, 100.0, 50.0, 25.0, 10.0]
        : [200.0, 100.0, 50.0, 25.0, 10.0];
    final List<double> elevationBreakpoints = RouteAnalyzerScreen.buildRoundedHistogramBoundaries(
      minValue: minElevationDisplay,
      maxValue: maxElevationDisplay,
      stepOptions: elevationStepOptions,
      minimumBins: 5,
      forceZeroStart: true,
    );
    final List<String> elevationLabels = [];
    for (int i = 0; i < elevationBreakpoints.length - 1; i++) {
      final double start = elevationBreakpoints[i];
      final double end = elevationBreakpoints[i + 1];
      if (i == elevationBreakpoints.length - 2) {
        elevationLabels.add('>${start.toStringAsFixed(0)}$elevationUnit');
      } else {
        elevationLabels.add(
          '${start.toStringAsFixed(0)}-${end.toStringAsFixed(0)}$elevationUnit');
      }
    }

    // Define custom gradient bins
    List<String> gradientLabels = [
      '        <-25%',
      ' -25% to -20%',
      ' -20% to -15%',
      ' -15% to -10%',
      '  -10% to -5%',
      '    -5% to 0%',
      '     0% to 5%',
      '    5% to 10%',
      '   10% to 15%',
      '   15% to 20%',
      '   20% to 25%',
      '         >25%'
    ];

    List<double> gradientBreakpoints = [
      double.negativeInfinity,
      -25,
      -20,
      -15,
      -10,
      -5,
      0,
      5,
      10,
      15,
      20,
      25,
      double.infinity
    ];

    final double minPaceDisplay = pacePoints
        .map((point) => convertPaceToDisplayUnit(point.y))
        .reduce(min);
    final double maxPaceDisplay = pacePoints
        .map((point) => convertPaceToDisplayUnit(point.y))
        .reduce(max);
    final List<double> paceStepOptions = useImperialUnits
        ? [300.0, 180.0, 120.0, 60.0, 30.0, 15.0]
        : [240.0, 180.0, 120.0, 60.0, 30.0, 15.0];
    final List<double> paceBreakpoints = RouteAnalyzerScreen.buildRoundedHistogramBoundaries(
      minValue: minPaceDisplay,
      maxValue: maxPaceDisplay,
      stepOptions: paceStepOptions,
      minimumBins: 5,
      forceZeroStart: false,
    );
    final paceLabels = <String>[];
    String formatHistogramPace(double seconds) {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = seconds.round() % 60;
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }

    paceLabels.add('<${formatHistogramPace(paceBreakpoints[1])}');
    for (int i = 2; i < paceBreakpoints.length - 1; i++) {
      paceLabels.add(
        '${formatHistogramPace(paceBreakpoints[i - 1])}-${formatHistogramPace(paceBreakpoints[i])}',
      );
    }
    paceLabels.add('>${formatHistogramPace(paceBreakpoints[paceBreakpoints.length - 2])}');

    // Initialize bins
    Map<int, double> elevationBins = {};
    Map<int, double> gradientBins = {};
    Map<int, double> paceBins = {};

    for (int i = 0; i < elevationBreakpoints.length - 1; i++) {
      elevationBins[i] = 0;
    }
    for (int i = 0; i < gradientBreakpoints.length - 1; i++) {
      gradientBins[i] = 0;
    }
    for (int i = 0; i < paceBreakpoints.length - 1; i++) {
      paceBins[i] = 0;
    }

    // Compute time spent in each segment
    for (int i = 1; i < elevationPoints.length; i++) {
      double segmentDistance = elevationPoints[i].x - elevationPoints[i - 1].x;

      // Skip segments with zero or negative distance (data errors)
      if (segmentDistance <= 0) continue;

      // Ensure we don't go out of bounds with smoothedGradients array
      int gradientIndex = min(i, smoothedGradients.length - 1);
      double gradientPercent =
          gradientIndex >= 0 ? smoothedGradients[gradientIndex] : 0;
      double elevation = convertElevationToDisplay(elevationPoints[i].y);

      // Calculate pace for this segment
      double adjustment = calculateGradeAdjustment(gradientPercent);
      double segmentPace = selectedPaceSeconds * adjustment;
      segmentPace = max(segmentPace, minSegmentPace);

      // Calculate time for this segment in minutes
      double segmentTime = (segmentDistance * segmentPace) / 60;

      // Add to elevation bins
      for (int j = 0; j < elevationBreakpoints.length - 1; j++) {
        if (elevation >= elevationBreakpoints[j] &&
            elevation < elevationBreakpoints[j + 1]) {
          elevationBins[j] = (elevationBins[j] ?? 0) + segmentTime;
          break;
        }
      }

      // Add to gradient bins
      for (int j = 0; j < gradientBreakpoints.length - 1; j++) {
        if (gradientPercent >= gradientBreakpoints[j] &&
            gradientPercent < gradientBreakpoints[j + 1]) {
          gradientBins[j] = (gradientBins[j] ?? 0) + segmentTime;
          break;
        }
      }
    }

    // Compute time spent in each segment
    for (int i = 1; i < pacePoints.length; i++) {
      double segmentDistance = pacePoints[i].x - pacePoints[i - 1].x;
      if (segmentDistance <= 0) continue;

      double segmentPace = pacePoints[i].y;
      double segmentTime = (segmentDistance * segmentPace) / 60;
      double displayPace = convertPaceToDisplayUnit(segmentPace);

      // Add to pace bins
      for (int j = 0; j < paceBreakpoints.length - 1; j++) {
        if (displayPace >= paceBreakpoints[j] &&
          displayPace < paceBreakpoints[j + 1]) {
          paceBins[j] = (paceBins[j] ?? 0) + segmentTime;
          break;
        }
      }
    }

    // Check if any data was collected
    bool hasElevationData = elevationBins.values.any((v) => v > 0);
    bool hasGradientData = gradientBins.values.any((v) => v > 0);
    bool hasPaceData = paceBins.values.any((v) => v > 0);

    // Add placeholder if no data was collected (probably due to processing issues)
    if (!hasElevationData) {
      result['elevation']!.add(ChartData('No Elevation Data', 0));
    }
    if (!hasGradientData) {
      result['gradient']!.add(ChartData('No Gradient Data', 0));
    }
    if (!hasPaceData) {
      result['pace']!.add(ChartData('No Pace Data', 0));
    }

    // Convert to chart data format with custom labels
    if (hasElevationData) {
      for (int i = 0; i < elevationLabels.length; i++) {
        if (elevationBins[i] != null && elevationBins[i]! > 0) {
          result['elevation']!
              .add(ChartData(elevationLabels[i], elevationBins[i]!));
        }
      }
    }

    // Convert gradient bins to chart data with custom labels
    if (hasGradientData) {
      for (int i = 0; i < gradientLabels.length; i++) {
        if (gradientBins[i] != null && gradientBins[i]! > 0) {
          result['gradient']!
              .add(ChartData(gradientLabels[i], gradientBins[i]!));
        }
      }
    }

    if (hasPaceData) {
      for (int i = 0; i < paceLabels.length; i++) {
        if (paceBins[i] != null && paceBins[i]! > 0) {
          result['pace']!.add(ChartData(paceLabels[i], paceBins[i]!));
        }
      }
    }

    return result;
  }

  void _handleMapTap(LatLng point) {
    final closestIndex = _findClosestRoutePointToLatLng(point);
    if (closestIndex < 0 || elevationPoints.isEmpty || !mounted) return;

    final elevationIndex = routePoints.length == elevationPoints.length
        ? closestIndex
        : (closestIndex * elevationPoints.length / routePoints.length)
            .round()
            .clamp(0, elevationPoints.length - 1);
    final distance = elevationPoints[elevationIndex].x;

    setState(() {
      hoveredPointIndex = closestIndex;
      _closestElevationPointIndex = elevationIndex;
      hoveredDistance = distance;
      hoveredSpot = elevationPoints[elevationIndex];
    });
    _handleTapForCheckpoint(distance: distance);
  }

  void _handleElevationChartTap(
      Offset localPosition, BoxConstraints constraints) {
    if (elevationPoints.isEmpty || !mounted) return;

    const leftOffset = 56.0;
    final chartAreaWidth = constraints.maxWidth - leftOffset;
    if (chartAreaWidth <= 0) return;

    final normalizedX = ((localPosition.dx - leftOffset) / chartAreaWidth)
        .clamp(0.0, 1.0);
    final distance = normalizedX * elevationPoints.last.x;
    final chartPoint = findClosestElevationPoint(distance);
    final routePointIndex = _findRoutePointIndexForDistance(chartPoint.x);
    if (routePointIndex < 0 || routePointIndex >= routePoints.length) return;

    setState(() {
      hoveredPointIndex = routePointIndex;
      hoveredDistance = chartPoint.x;
      hoveredSpot = chartPoint;
    });
    _handleTapForCheckpoint(distance: chartPoint.x);
  }

  int _findClosestRoutePointToLatLng(LatLng point) {
    if (routePoints.isEmpty) return -1;

    double minDistance = double.infinity;
    int closestIndex = -1;
    for (int i = 0; i < routePoints.length; i++) {
      final routePoint = routePoints[i];
      final distance = (point.latitude - routePoint.latitude) *
              (point.latitude - routePoint.latitude) +
          (point.longitude - routePoint.longitude) *
              (point.longitude - routePoint.longitude);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  // Handle tap for checkpoint creation
  void _handleTapForCheckpoint({double? distance}) {
    final checkpointDistance = distance ?? hoveredDistance;
    if (checkpointDistance == null || !mounted) return;

    try {
      if (_isPendingCheckpointCreation) {
        // When we already have a pending checkpoint, clicking again anywhere cancels it
        setState(() {
          _isPendingCheckpointCreation = false;
          _pendingCheckpointDistance = null;
        });
      } else {
        // Start checkpoint creation
        setState(() {
          _isPendingCheckpointCreation = true;
          _pendingCheckpointDistance = checkpointDistance;
        });
        _showCheckpointConfirmation(checkpointDistance);
      }
    } catch (e) {
      // Reset state if an error occurs
      setState(() {
        _isPendingCheckpointCreation = false;
        _pendingCheckpointDistance = null;
      });
    }
  }

  Future<void> _showCheckpointConfirmation(double distance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add checkpoint?'),
        content: Text(
          'Add checkpoint at ${convertDistanceToDisplay(distance).toStringAsFixed(2)} $distanceUnitLabel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (!mounted || _pendingCheckpointDistance != distance) return;

    if (confirmed == true) {
      _createCheckpointAtDistance(distance);
    }
    setState(() {
      _isPendingCheckpointCreation = false;
      _pendingCheckpointDistance = null;
    });
  }

  // Get marker for pending checkpoint
  List<Marker> _getPendingCheckpointMarker() {
    if (_pendingCheckpointDistance == null) return [];

    int routePointIndex =
        _findRoutePointIndexForDistance(_pendingCheckpointDistance!);
    if (routePointIndex < 0 || routePointIndex >= routePoints.length) return [];

    return [
      Marker(
        point: routePoints[routePointIndex],
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.7),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
          ),
        ),
      ),
    ];
  }

  // Create a checkpoint at the specified distance
  void _createCheckpointAtDistance(double distance) {
    if (elevationPoints.isEmpty) return;

    // Ensure distance is within valid range
    distance = distance.clamp(0, elevationPoints.last.x);

    // Create a new checkpoint
    final checkpoint = CheckpointData(distance: distance);
    checkpoint.id = DateTime.now().millisecondsSinceEpoch.toString();
    checkpoint.name = 'CP ${(checkpoints.length)}';

    // If table not visible, make it visible
    setState(() {
      if (!showCheckpoints) {
        showCheckpoints = true;
      }

      // Add the checkpoint
      checkpoints.add(checkpoint);

      // Add a finish checkpoint if this is the first one and it's not at the end
      bool isFirstCheckpoint = checkpoints.length == 1;
      bool isAtEnd = (distance - elevationPoints.last.x).abs() < 0.1;
      if (isFirstCheckpoint && !isAtEnd && elevationPoints.isNotEmpty) {
        // Create a finish checkpoint
        final finishCheckpoint =
            CheckpointData(distance: elevationPoints.last.x);
        finishCheckpoint.id = 'finish_${DateTime.now().millisecondsSinceEpoch}';
        finishCheckpoint.name = 'Finish';

        // Add the finish checkpoint
        checkpoints.add(finishCheckpoint);

        // Add focus node for finish checkpoint
        final nameNode = FocusNode();
        final distanceNode = FocusNode();

        if (!_isWeb) {
          try {
            nameNode.addListener(_onFocusChange);
            distanceNode.addListener(_onFocusChange);
          } catch (e) {
            // Silently handle any focus node errors
          }
        }

        _nameFocusNodes.add(nameNode);
        _distanceFocusNodes.add(distanceNode);
      }

      // Add new focus nodes for this checkpoint
      final nameNode = FocusNode();
      final distanceNode = FocusNode();

      // Add focus listeners only if not on web
      if (!_isWeb) {
        try {
          nameNode.addListener(_onFocusChange);
          distanceNode.addListener(_onFocusChange);
        } catch (e) {
          // Silently handle any focus node errors
        }
      }

      _nameFocusNodes.add(nameNode);
      _distanceFocusNodes.add(distanceNode);

      // Sort checkpoints by distance
      checkpoints.sort((a, b) => a.distance.compareTo(b.distance));

      // Recalculate metrics for all checkpoints
      _calculateCheckpointMetrics(startIndex: 0);
    });
  }

  // Helper method to build statistic cards
  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build bar charts
  Widget _buildBarChart(String title, List<ChartData> data, Color color) {
    if (data.isEmpty) return const SizedBox.shrink();

    // Find the maximum value to normalize bars
    double maxValue = 0;
    for (var item in data) {
      maxValue = max(maxValue, item.value);
    }

    // Check if this is a special message (no data, insufficient data)
    if (data.length == 1 &&
        (data[0].category.contains('No ') ||
            data[0].category.contains('Insufficient'))) {
      return Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 180,
            alignment: Alignment.center,
            child: Text(
              data[0].category,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate responsive bar width based on available width
              // Leave some padding between bars (20% of total space)
              final barWidth = (constraints.maxWidth / data.length) * 0.8;
              // Clamp the width between reasonable min and max values
              final clampedWidth = barWidth.clamp(20.0, 60.0);

              return BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxValue,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: Colors.grey.shade800,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${rod.toY.toInt()} min',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 75,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value >= data.length)
                            return const Text('');
                          return RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              data[value.toInt()].category,
                              style: const TextStyle(fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const Text('');
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxValue / 5,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.shade300,
                      strokeWidth: 1,
                    ),
                  ),
                  barGroups: List.generate(
                    data.length,
                    (index) => BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: data[index].value,
                          color: color.withOpacity(0.7),
                          width:
                              clampedWidth, // Use the calculated responsive width
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Helper function for pace color
  Color getPaceColor(double pace, double minPace, double maxPace) {
    // Normalize pace: 0 = min pace (fastest), 1 = max pace (slowest)
    // Handle edge case where minPace == maxPace
    double normalizedPace =
        (maxPace == minPace) ? 0.5 : (pace - minPace) / (maxPace - minPace);
    normalizedPace =
        normalizedPace.clamp(0.0, 1.0); // Ensure it's within [0, 1]

    // Hue range: 120 (green) down to 0 (red)
    double hue = 120.0 * (1.0 - normalizedPace);
    // Use full saturation and value for vibrant colors
    return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
  }

  // Formatting function for pace axis labels
  String formatPaceAxisLabel(double secondsPerKilometer) {
    if (secondsPerKilometer <= 0) return "";
    double displaySeconds = convertPaceToDisplayUnit(secondsPerKilometer);
    int mins = (displaySeconds / 60).floor();
    int secs = (displaySeconds % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  // Helper function to smooth data using a moving average
  List<FlSpot> _smoothData(List<FlSpot> points, int windowSize) {
    if (points.length < windowSize) {
      return points; // Not enough data to smooth
    }

    List<FlSpot> smoothedPoints = [];
    // Keep first few points as is
    for (int i = 0; i < windowSize ~/ 2; i++) {
      smoothedPoints.add(points[i]);
    }

    // Apply moving average
    for (int i = windowSize ~/ 2; i < points.length - windowSize ~/ 2; i++) {
      double sumY = 0;
      for (int j = i - windowSize ~/ 2; j <= i + windowSize ~/ 2; j++) {
        sumY += points[j].y;
      }
      smoothedPoints.add(FlSpot(points[i].x, sumY / windowSize));
    }

    // Keep last few points as is
    for (int i = points.length - windowSize ~/ 2; i < points.length; i++) {
      smoothedPoints.add(points[i]);
    }

    return smoothedPoints;
  }

  // Calculate the grade adjusted distance for a segment
  double calculateGradeAdjustedDistance(
      double startDistance, double endDistance) {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty)
      return endDistance - startDistance;

    double totalAdjustedDistance = 0;

    // Find elevation points within this segment
    for (int i = 1; i < elevationPoints.length; i++) {
      double distance = elevationPoints[i].x;
      if (distance >= startDistance && distance <= endDistance) {
        double segmentDistance =
            elevationPoints[i].x - elevationPoints[i - 1].x;
        if (segmentDistance <= 0) continue;

        // Get gradient for this segment
        int gradientIndex = min(i, smoothedGradients.length - 1);
        double gradientPercent =
            gradientIndex >= 0 ? smoothedGradients[gradientIndex] : 0;

        // Calculate grade adjustment factor (same as pace adjustment)
        double adjustment = calculateGradeAdjustment(gradientPercent);

        // Apply adjustment to segment distance
        totalAdjustedDistance += segmentDistance * adjustment;
      }
    }

    return totalAdjustedDistance;
  }

  // Calculate total grade adjusted distance for the route
  double calculateTotalGradeAdjustedDistance() {
    if (elevationPoints.isEmpty) return 0;
    return calculateGradeAdjustedDistance(0, elevationPoints.last.x);
  }

  // Helper method to get segment distance for a checkpoint
  double _getSegmentDistance(int checkpointIndex) {
    if (checkpointIndex < 0 || checkpointIndex >= checkpoints.length) return 0;

    if (checkpointIndex == 0) {
      // For first checkpoint, segment distance is same as total distance
      return checkpoints[0].distance;
    } else {
      // For other checkpoints, segment distance is difference from previous checkpoint
      return checkpoints[checkpointIndex].distance -
          checkpoints[checkpointIndex - 1].distance;
    }
  }

  // Helper method to get segment pace for a checkpoint
  String _getSegmentPace(int checkpointIndex) {
    if (checkpointIndex < 0 || checkpointIndex >= checkpoints.length)
      return 'N/A';

    // Calculate actual segment pace as segment time / segment distance
    double segmentDistance = _getSegmentDistance(checkpointIndex);
    if (segmentDistance <= 0) return 'N/A';

    double segmentTime = checkpoints[checkpointIndex].timeFromPrevious;
    if (segmentTime <= 0) return 'N/A';

    // Calculate pace in seconds per kilometer
    double paceSecondsPerKm = (segmentTime * 60) / segmentDistance;

    // Format pace as MM:SS in the selected unit basis
    double displayPaceSeconds = convertPaceToDisplayUnit(paceSecondsPerKm);
    int minutes = (displayPaceSeconds / 60).floor();
    int seconds = (displayPaceSeconds % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // Function to calculate carbs units for checkpoints
  void calculateCarbsUnits() {
    if (checkpoints.isEmpty) return;
    if (carbsPerHour <= 0 || gramsPerUnit <= 0) return;

    List<CheckpointData> updatedCheckpoints = List.from(checkpoints);
    int previousCumulativeUnits = 0;

    for (int i = 0; i < updatedCheckpoints.length; i++) {
      final checkpoint = updatedCheckpoints[i];

      // Convert cumulative time to hours
      double currentTotalTimeHours = checkpoint.cumulativeTime / 60.0;

      // Calculate total grams needed up to this point
      double cumulativeGrams = currentTotalTimeHours * carbsPerHour;

      // Calculate total units needed up to this point (round up)
      int currentCumulativeUnits = (cumulativeGrams / gramsPerUnit).ceil();

      // Calculate units needed for this specific leg
      int legUnits = currentCumulativeUnits - previousCumulativeUnits;

      // Update checkpoint values
      checkpoint.legUnits = legUnits;
      checkpoint.cumulativeUnits = currentCumulativeUnits;

      // Update previous cumulative units
      previousCumulativeUnits = currentCumulativeUnits;
    }

    setState(() {
      checkpoints = updatedCheckpoints;
    });
  }

  // Function to calculate fluid units for checkpoints
  void calculateFluidUnits() {
    if (checkpoints.isEmpty) return;
    if (fluidPerHour <= 0 || mlPerUnit <= 0) return;

    List<CheckpointData> updatedCheckpoints = List.from(checkpoints);
    int previousCumulativeFluidUnits = 0;

    for (int i = 0; i < updatedCheckpoints.length; i++) {
      final checkpoint = updatedCheckpoints[i];

      // Convert cumulative time to hours
      double currentTotalTimeHours = checkpoint.cumulativeTime / 60.0;

      // Calculate total ml needed up to this point
      double cumulativeMl = currentTotalTimeHours * fluidPerHour;

      // Calculate total units needed up to this point (round up)
      int currentCumulativeFluidUnits = (cumulativeMl / mlPerUnit).ceil();

      // Calculate units needed for this specific leg
      int legFluidUnits =
          currentCumulativeFluidUnits - previousCumulativeFluidUnits;

      // Update checkpoint values
      checkpoint.legFluidUnits = legFluidUnits;
      checkpoint.cumulativeFluidUnits = currentCumulativeFluidUnits;

      // Update previous cumulative units
      previousCumulativeFluidUnits = currentCumulativeFluidUnits;
    }

    setState(() {
      checkpoints = updatedCheckpoints;
    });
  }
}
