import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gpx/gpx.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' show sin, cos, sqrt, atan2, max, min, pow, exp, pi, Point;
import 'dart:async';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';

// Class to store checkpoint data
class CheckpointData {
  double distance;
  double elevation = 0;
  double elevationGain = 0;
  double elevationLoss = 0;
  double cumulativeTime = 0;
  double timeFromPrevious = 0;
  String id = DateTime.now().millisecondsSinceEpoch.toString(); // Unique identifier
  String? name;
  // Base grade adjusted pace for the segment ending at this checkpoint
  double baseGradeAdjustedPace = 0;
  // Add grade adjusted distance
  double gradeAdjustedDistance = 0;
  double cumulativeGradeAdjustedDistance = 0;
  // Adjustment factor in s/km
  double adjustmentFactor = 0;
  // Carbs calculation fields
  int legUnits = 0;
  int cumulativeUnits = 0;

  CheckpointData({required this.distance});
  
  // Create a copy of this checkpoint
  CheckpointData copy() {
    final cp = CheckpointData(distance: distance);
    cp.elevation = elevation;
    cp.elevationGain = elevationGain;
    cp.elevationLoss = elevationLoss;
    cp.cumulativeTime = cumulativeTime;
    cp.timeFromPrevious = timeFromPrevious;
    cp.id = id;
    cp.name = name;
    cp.baseGradeAdjustedPace = baseGradeAdjustedPace;
    cp.gradeAdjustedDistance = gradeAdjustedDistance;
    cp.cumulativeGradeAdjustedDistance = cumulativeGradeAdjustedDistance;
    cp.adjustmentFactor = adjustmentFactor;
    cp.legUnits = legUnits;
    cp.cumulativeUnits = cumulativeUnits;
    return cp;
  }
}

// Class to store chart data for the summary section
class ChartData {
  final String category;
  final double value;
  
  ChartData(this.category, this.value);
}

class RouteAnalyzerScreen extends StatefulWidget {
  const RouteAnalyzerScreen({super.key});

  @override
  State<RouteAnalyzerScreen> createState() => _RouteAnalyzerScreenState();
}

class _RouteAnalyzerScreenState extends State<RouteAnalyzerScreen> {
  Gpx? gpxData;
  List<LatLng> routePoints = [];
  List<FlSpot> elevationPoints = [];
  List<FlSpot> timePoints = []; // Points for time graph
  List<FlSpot> pacePoints = []; // Points for pace graph
  List<double> cumulativeElevationGain = []; // Track cumulative elevation gain at each point
  List<double> cumulativeElevationLoss = []; // Track cumulative elevation loss at each point
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
  
  // Pace-related state
  double selectedPaceSeconds = 240; // Default 4:00 (240 seconds)
  static const double minPaceSeconds = 165; // 2:45
  static const double maxPaceSeconds = 900; // 15:00
  // Add minimum allowed segment pace (2:00 min/km)
  static const double minSegmentPace = 120; // 2:00 min/km
  // Remove the flag to show adjusted pace column

  // Add state variables for min/max pace for chart scaling & color
  double _minPace = 90; // Y-axis min (clamped)
  double _maxPace = 1200; // Y-axis max (clamped)
  double _minRawPace = 90; // For color scaling (unclamped)
  double _maxRawPace = 1200; // For color scaling (unclamped)

  // Add carbs calculation variables
  double carbsPerHour = 60.0;
  double gramsPerUnit = 30.0;

  String formatPace(double seconds) {
    int mins = (seconds / 60).floor();
    int secs = (seconds % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  double calculateGradeAdjustment(double gradientPercent) {
    // Clamp gradient to ±45%
    double g = gradientPercent.clamp(-45.0, 45.0);
    return (-0.0000000005968925381 * pow(g, 5)) +
           (-0.000000366663628576468 * pow(g, 4)) +
           (-0.0000016677964832213 * pow(g, 3)) +
           (0.00182471253566879 * pow(g, 2)) +
           (0.0301350193447792 * g) +
           0.99758437262606;
  }

  void calculateTimePoints() {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty) return;
    
    List<FlSpot> newTimePoints = [];
    List<FlSpot> newPacePoints = []; // <-- Add this
    double cumulativeTime = 0;
    double minCalculatedPace = double.infinity; // Track min/max pace for chart scaling
    double maxCalculatedPace = double.negativeInfinity;
    
    // Get segment boundaries based on checkpoints
    List<double> segmentBoundaries = [];
    if (checkpoints.isNotEmpty) {
      segmentBoundaries = checkpoints.map((cp) => cp.distance).toList();
      segmentBoundaries.sort();
    }
    
    // First, calculate the base grade-adjusted pace for each segment
    if (checkpoints.isNotEmpty) {
      // Calculate for start to first checkpoint
      checkpoints[0].baseGradeAdjustedPace = getSegmentBaseGradeAdjustedPace(0, checkpoints[0].distance);
      
      // Calculate for checkpoint to checkpoint segments
      for (int i = 1; i < checkpoints.length; i++) {
        double startDist = checkpoints[i-1].distance;
        double endDist = checkpoints[i].distance;
        checkpoints[i].baseGradeAdjustedPace = getSegmentBaseGradeAdjustedPace(startDist, endDist);
      }
    }
    
    for (int i = 0; i < elevationPoints.length; i++) {
      if (i == 0) {
        newTimePoints.add(const FlSpot(0, 0));
        // Skip pace point for index 0, calculate starting from first segment
        continue;
      }

      // Calculate distance segment in kilometers
      double segmentDistance = elevationPoints[i].x - elevationPoints[i-1].x;
      
      // Get grade adjustment factor for this segment
      // Ensure gradient index is valid
      int gradientIndex = i.clamp(0, smoothedGradients.length - 1);
      double adjustment = calculateGradeAdjustment(smoothedGradients[gradientIndex]);
      
      // Calculate pace for this segment (in seconds per km)
      double basePace = selectedPaceSeconds;
      
      // Apply grade adjustment
      double gradePace = basePace * adjustment;
      
      // Ensure pace doesn't go below minimum allowed pace (2:00 min/km)
      gradePace = max(gradePace, minSegmentPace);
      
      // Calculate time for this segment
      double segmentTime = (segmentDistance * gradePace) / 60; // Convert to minutes
      cumulativeTime += segmentTime;
      
      newTimePoints.add(FlSpot(elevationPoints[i].x, cumulativeTime));

      // --- Calculate Real Pace ---
      double realPace = basePace * adjustment;
      
      // Clamp real pace between 2:00 (120s) and 20:00 (1200s)
      realPace = realPace.clamp(120.0, 1200.0);

      newPacePoints.add(FlSpot(elevationPoints[i].x, realPace)); // Add pace point

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
         double initialAdjustment = calculateGradeAdjustment(0); // Assume flat start
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
      double adjustment = calculateGradeAdjustment(smoothedGradients[gradientIndex]);

      // Calculate raw real pace: base pace * adjustment factor
      double realPace = basePace * adjustment;
      
      // Update raw min/max for color scaling *before* clamping
      minRawPace = min(minRawPace, realPace);
      maxRawPace = max(maxRawPace, realPace);
      
      // Clamp real pace between 1:30 (90s) and 20:00 (1200s)
      realPace = realPace.clamp(90.0, 1200.0);

      newPacePoints.add(FlSpot(elevationPoints[i].x, realPace)); // Add pace point

      // Update clamped min/max for Y-axis scaling
      minClampedPace = min(minClampedPace, realPace);
      maxClampedPace = max(maxClampedPace, realPace);

      // Track segment distance for average spacing calculation
      if (i > 0) {
        double segmentDist = elevationPoints[i].x - elevationPoints[i-1].x; // in km
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
       double adjustment = calculateGradeAdjustment(smoothedGradients[gradientIndex]);
       double realPace = basePace * adjustment;
       realPace = realPace.clamp(90.0, 1200.0);
       newPacePoints.add(FlSpot(elevationPoints[0].x, realPace));
       minClampedPace = realPace;
       maxClampedPace = realPace;
       minRawPace = realPace;
       maxRawPace = realPace;
    }

    // Calculate adaptive window size for smoothing (~200m)
    double avgSpacingMeters = segmentCount > 0 ? totalSegmentDistance / segmentCount : 10; // Default 10m if no segments
    int pointWindowSize = (200 / avgSpacingMeters).round();
    // Ensure window size is odd and within reasonable bounds (e.g., 3 to 21)
    pointWindowSize = (pointWindowSize ~/ 2 * 2 + 1); // Make odd
    pointWindowSize = pointWindowSize.clamp(3, 21); // Clamp between 3 and 21

    // Smooth the calculated pace data using the adaptive window size
    List<FlSpot> smoothedPacePoints = _smoothData(newPacePoints, pointWindowSize);

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
    double a = sin(dLat/2) * sin(dLat/2) +
               cos(lat1Rad) * cos(lat2Rad) *
               sin(dLon/2) * sin(dLon/2);
    double c = 2 * atan2(sqrt(a), sqrt(1-a));
    
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
            throw const FormatException('No track points found in the GPX file');
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
          content: Text('The GPX file does not contain elevation data. Using 0m as default elevation.'),
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

      // Process route points
      routePoints = points
          .where((pt) => pt.lat != null && pt.lon != null)
          .map((pt) => LatLng(pt.lat!, pt.lon!))
          .toList();

      // Process first elevation point
      if (points.isNotEmpty) {
        // Use 0 as default elevation if data is missing
        double elevation = points[0].ele ?? 0;
        elevationPoints.add(FlSpot(0, elevation));
        cumulativeElevationGain.add(0);
        cumulativeElevationLoss.add(0);
      }

      // Process remaining points and calculate average point spacing
      double totalDistance = 0;
      int pointCount = 0;
      double totalElevationGain = 0;
      double totalElevationLoss = 0;
      
      for (int i = 1; i < points.length; i++) {
        // Use 0 as default elevation if data is missing
        double prevElevation = points[i-1].ele ?? 0;
        double currentElevation = points[i].ele ?? 0;

        // Calculate distance between current point and previous point
        double distanceInMeters = calculateDistance(
          points[i-1].lat!,
          points[i-1].lon!,
          points[i].lat!,
          points[i].lon!
        );
        
        totalDistance += distanceInMeters;
        pointCount++;
        
        cumulativeDistance += distanceInMeters / 1000.0; // Convert to kilometers
        
        // Calculate elevation change
        double elevationChange = currentElevation - prevElevation;
        if (elevationChange > 0) {
          totalElevationGain += elevationChange;
        } else {
          totalElevationLoss += -elevationChange;
        }
        
        // Add point with cumulative distance and elevation
        elevationPoints.add(FlSpot(cumulativeDistance, currentElevation));
        cumulativeElevationGain.add(totalElevationGain);
        cumulativeElevationLoss.add(totalElevationLoss);
      }

      // Calculate average point spacing in meters
      double avgSpacing = pointCount > 0 ? totalDistance / pointCount : 0;
      
      // Calculate window size based on point spacing
      // We want to smooth over roughly 100m of distance
      int windowSize = max(3, min(15, avgSpacing > 0 ? (100 / avgSpacing).round() : 5));

      if (elevationPoints.isNotEmpty) {
        maxElevation = elevationPoints.map((p) => p.y).reduce((a, b) => max(a, b));
        minElevation = elevationPoints.map((p) => p.y).reduce((a, b) => min(a, b));
      }

      // Calculate and smooth gradients
      List<double> gradients = calculateGradients(elevationPoints);
      smoothedGradients = smoothGradients(gradients, windowSize);

      // Calculate initial time and pace points
      calculateTimePoints();
      calculatePacePoints(); // <-- Call new function
      
      // Process waypoints from GPX file
      processWaypoints();

      // Add a default finish checkpoint
      if (elevationPoints.isNotEmpty) {
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
        final distance = calculateDistance(
          waypoint.lat!, 
          waypoint.lon!, 
          routePoint.latitude, 
          routePoint.longitude
        );
        
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
      checkpoint.name = waypoint.name ?? 'Waypoint ${waypointCheckpoints.length + 1}';
      
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
    final point = mapController.camera.pointToLatLng(Point(localPosition.dx, localPosition.dy));
    
    // Find closest point on route using a more efficient approach
    double minDistance = double.infinity;
    int closestIndex = -1;
    
    // Use a step size to check fewer points for better performance
    // For very large routes, check every Nth point first, then refine
    int stepSize = routePoints.length > 1000 ? 10 : 1;
    
    // First pass with step size
    for (int i = 0; i < routePoints.length; i += stepSize) {
      final routePoint = routePoints[i];
      final distance = (point.latitude - routePoint.latitude) * (point.latitude - routePoint.latitude) +
                      (point.longitude - routePoint.longitude) * (point.longitude - routePoint.longitude);
      
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
        final distance = (point.latitude - routePoint.latitude) * (point.latitude - routePoint.latitude) +
                        (point.longitude - routePoint.longitude) * (point.longitude - routePoint.longitude);
        
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
      double distance = points[i].x - points[i-1].x;
      if (distance > 0 && distance < minDistance) {
        minDistance = distance;
      }
    }
    
    // Use this for gradient calculation
    for (int i = 1; i < points.length; i++) {
      final dx = (points[i].x - points[i-1].x) * 1000; // Convert to meters
      final dy = points[i].y - points[i-1].y;
      
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
        double prevDiff = (gradients[i] - gradients[i-1]).abs();
        double nextDiff = (gradients[i+1] - gradients[i]).abs();
        if (prevDiff > 10 || nextDiff > 10) {
          effectiveWindow = windowSize * 2; // Double window size for sparse data
        }
      }
      
      // Calculate window bounds
      int windowStart = max(0, i - effectiveWindow ~/ 2);
      int windowEnd = min(gradients.length, i + effectiveWindow ~/ 2 + 1);
      
      // Calculate weighted average based on distance from center point
      for (int j = windowStart; j < windowEnd; j++) {
        // Use gaussian-like weighting
        double distance = (j - i).abs().toDouble();
        double weight = exp(-distance * distance / (2 * (effectiveWindow / 4) * (effectiveWindow / 4)));
        
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
    
    if (_isEditingDistance && !_distanceFocusNodes.any((node) => node.hasFocus)) {
      setState(() {
        _isEditingDistance = false;
        _editingCheckpointId = null;
      });
      _processCheckpointChanges();
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
              child: ElevatedButton(
                onPressed: pickGPXFile,
                child: const Text('Upload GPX File'),
              ),
            ),
            if (routePoints.isNotEmpty) ...[
              // Pace slider and total time
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('Grade Adjusted Pace: ${formatPace(selectedPaceSeconds)}/km'),
                        Expanded(
                          child: Slider(
                            value: selectedPaceSeconds,
                            min: minPaceSeconds,
                            max: maxPaceSeconds,
                            onChanged: (value) {
                              setState(() {
                                selectedPaceSeconds = value;
                                calculateTimePoints();
                                // Recalculate all checkpoint metrics when pace changes
                                if (checkpoints.isNotEmpty) {
                                  _calculateCheckpointMetrics(startIndex: 0);
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    // Fine-tuning buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              // Decrease by 5 seconds, but not below minimum
                              selectedPaceSeconds = max(minPaceSeconds, selectedPaceSeconds - 5);
                              calculateTimePoints();
                              // Recalculate all checkpoint metrics
                              if (checkpoints.isNotEmpty) {
                                _calculateCheckpointMetrics(startIndex: 0);
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: const Size(40, 36),
                          ),
                          child: const Text('-5s', style: TextStyle(fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              // Decrease by 1 second, but not below minimum
                              selectedPaceSeconds = max(minPaceSeconds, selectedPaceSeconds - 1);
                              calculateTimePoints();
                              // Recalculate all checkpoint metrics
                              if (checkpoints.isNotEmpty) {
                                _calculateCheckpointMetrics(startIndex: 0);
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: const Size(40, 36),
                          ),
                          child: const Text('-1s', style: TextStyle(fontSize: 14)),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              // Increase by 1 second, but not above maximum
                              selectedPaceSeconds = min(maxPaceSeconds, selectedPaceSeconds + 1);
                              calculateTimePoints();
                              // Recalculate all checkpoint metrics
                              if (checkpoints.isNotEmpty) {
                                _calculateCheckpointMetrics(startIndex: 0);
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: const Size(40, 36),
                          ),
                          child: const Text('+1s', style: TextStyle(fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              // Increase by 5 seconds, but not above maximum
                              selectedPaceSeconds = min(maxPaceSeconds, selectedPaceSeconds + 5);
                              calculateTimePoints();
                              // Recalculate all checkpoint metrics
                              if (checkpoints.isNotEmpty) {
                                _calculateCheckpointMetrics(startIndex: 0);
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          'Estimated Total Time: ${_formatTotalTime(timePoints.last.y)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                   // Map toggle button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          showMap = !showMap;
                        });
                      },
                      icon: Icon(showMap ? Icons.visibility_off : Icons.visibility),
                      label: Text(showMap ? 'Hide Map' : 'Show Map'),
                    ),
                  ),      
                  // Map container
                  if (showMap)
                  // Map with reduced height
                  SizedBox(
                    height: 225,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate container width based on available space
                        final screenWidth = constraints.maxWidth;
                        final double horizontalPadding = screenWidth > 600 ? 40.0 : 0.0;
                        final double containerWidth = screenWidth - (horizontalPadding * 2);
                        
                        return Center(
                          child: Container(
                            width: containerWidth,
                            decoration: BoxDecoration(
                              border: screenWidth > 600 ? Border.all(color: Colors.grey.shade300, width: 1) : null,
                              borderRadius: screenWidth > 600 ? BorderRadius.circular(8) : null,
                            ),
                            child: Stack(
                              children: [
                                LayoutBuilder(
                                  builder: (context, mapConstraints) {
                                    return GestureDetector(
                                      onTap: () => _handleTapForCheckpoint(),
                                      child: MouseRegion(
                                        cursor: hoveredDistance != null ? 
                                              SystemMouseCursors.click : 
                                              SystemMouseCursors.basic,
                                        onHover: (event) {
                                          // Throttle hover events for better performance
                                          if (_mapDebounceTimer?.isActive ?? false) return;
                                          
                                          // Safely access the render box
                                          final RenderBox? box = context.findRenderObject() as RenderBox?;
                                          if (box == null) return;
                                          
                                          try {
                                            final localPosition = box.globalToLocal(event.position);
                                            
                                            final closestIndex = findClosestRoutePoint(localPosition, mapConstraints);
                                            if (closestIndex >= 0 && closestIndex < routePoints.length) {
                                              // Map the route point index to an elevation point index
                                              int elevationIndex;
                                              
                                              // If the arrays have the same length, use direct mapping
                                              if (routePoints.length == elevationPoints.length) {
                                                elevationIndex = closestIndex;
                                              } else {
                                                // Otherwise, use proportional mapping
                                                double ratio = elevationPoints.length / routePoints.length;
                                                elevationIndex = (closestIndex * ratio).round();
                                                elevationIndex = elevationIndex.clamp(0, elevationPoints.length - 1);
                                              }
                                              
                                              // If we found a valid elevation point, update the chart and info panel
                                              if (elevationIndex >= 0 && elevationIndex < elevationPoints.length && mounted) {
                                                // Update all state in a single setState call for immediate visual feedback
                                                setState(() {
                                                  hoveredPointIndex = closestIndex;
                                                  _closestElevationPointIndex = elevationIndex;
                                                  hoveredDistance = elevationPoints[elevationIndex].x;
                                                  hoveredSpot = elevationPoints[elevationIndex];
                                                });
                                              }
                                              
                                              // Set a very short throttle to prevent too many updates
                                              _mapDebounceTimer = Timer(const Duration(milliseconds: 5), () {});
                                            }
                                          } catch (e) {
                                            // Silently handle any errors during hover handling
                                          }
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
                                            initialCameraFit: CameraFit.bounds(
                                              bounds: LatLngBounds.fromPoints(routePoints),
                                              padding: const EdgeInsets.all(20.0),
                                            ),
                                          ),
                                          children: [
                                            TileLayer(
                                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                              userAgentPackageName: 'com.example.app',
                                              tileProvider: CancellableNetworkTileProvider(),
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
                                            if (hoveredPointIndex != null && hoveredPointIndex! < routePoints.length)
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
                                            // Add markers for checkpoints and pending checkpoint
                                            MarkerLayer(
                                              markers: [
                                                // Regular checkpoints
                                                if (showCheckpoints)
                                                  ...checkpoints.map((checkpoint) {
                                                    // Find the closest route point to this checkpoint distance
                                                    int routePointIndex = _findRoutePointIndexForDistance(checkpoint.distance);
                                                    if (routePointIndex < 0 || routePointIndex >= routePoints.length) {
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
                                                // Show pending checkpoint if applicable
                                                if (_isPendingCheckpointCreation && _pendingCheckpointDistance != null) 
                                                  ..._getPendingCheckpointMarker(),
                                              ],
                                            ),
                                          ],
                                        ),
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
              ),

              // Elevation chart
              Container(
                height: 200,
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate even 200m intervals for elevation ticks
                    double minElevRounded = max(minElevation! / 200.floor() * 200,0);
                    double maxElevRounded = maxElevation! / 200.ceil() * 200;

                    // Define chart are constants
                    
                    
                    return GestureDetector(
                      onTap: () => _handleTapForCheckpoint(),
                      child: MouseRegion(
                        cursor: hoveredDistance != null ? 
                               SystemMouseCursors.click : 
                               SystemMouseCursors.basic,
                        onHover: (event) {
                          if (elevationPoints.isEmpty) return;
                          
                          // Safely access the render box
                          final RenderBox? box = context.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          
                          try {
                            final localPosition = box.globalToLocal(event.position);
                            
                            // Calculate distance based on x position relative to chart width
                            // Get the actual chart dimensions from the constraints
                            final double totalWidth = constraints.maxWidth;
                            
                            // Define clear left and right offsets
                            const double leftOffset = 56; // Left padding + axis labels
                            const double rightOffset = 0; // Right padding
                            final double chartAreaWidth = totalWidth - leftOffset - rightOffset;
                            
                            // Calculate how far along the chart the mouse is (0.0 to 1.0)
                            double normalizedX = (localPosition.dx - leftOffset) / chartAreaWidth;
                            
                            // Apply boundary constraints to prevent edge artifacts
                            normalizedX = normalizedX.clamp(0.0, 1.0);
                            
                            // Convert to actual distance in km
                            final double hoverDistance = normalizedX * elevationPoints.last.x;
                            
                            // Find closest point on elevation chart
                            final FlSpot hoveredPoint = findClosestElevationPoint(hoverDistance);
                            final int elevationIndex = _closestElevationPointIndex;
                            
                            if (elevationIndex < 0) return;
                            
                            // Find corresponding route point for map marker
                            int routePointIndex = _findRoutePointIndexForDistance(hoveredPoint.x);
                            
                            if (routePointIndex < 0 || routePointIndex >= routePoints.length) return;
                            
                            // Update all state variables in a single setState call
                            if (mounted) {
                              setState(() {
                                hoveredPointIndex = routePointIndex;
                                hoveredDistance = hoveredPoint.x;
                                hoveredSpot = hoveredPoint;
                              });
                            }
                          } catch (e) {
                            // Silently handle any errors during hover handling
                          }
                        },
                        onExit: (_) {
                          // Clear hover state when mouse leaves chart
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
                              drawVerticalLine: false,  // Already set correctly to hide vertical lines
                              horizontalInterval: 200,  // Match the elevation intervals (200m)
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: Colors.grey.shade300,
                                strokeWidth: 1,
                                dashArray: null,  // Setting to null makes the line solid (not dashed)
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(
                                color: Colors.grey.shade300,  // Match the gridline color
                                width: 1,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                axisNameWidget: const Padding(
                                  padding: EdgeInsets.only(top: 12.0),
                                  child: Text(
                                    'Distance (km)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval: (elevationPoints.last.x / 10).clamp(1, double.infinity),
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toInt().toString(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                // Remove the axis name widget
                                axisNameWidget: const SizedBox.shrink(),
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  interval: 200, // Fixed 200m intervals
                                  getTitlesWidget: (value, meta) {
                                    // Only show labels at even 200m intervals
                                    if (value % 200 != 0) {
                                      return Container();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Text(
                                        value.toInt().toString(),
                                        style: const TextStyle(
                                          fontSize: 10, // Same as x-axis
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
                                    // Show dot for the hovered spot
                                    if (hoveredSpot != null && 
                                        (spot.x - hoveredSpot!.x).abs() < 0.05 && 
                                        spot.y == hoveredSpot!.y) {
                                      return true;
                                    }
                                    
                                    // Show dots for checkpoints
                                    if (showCheckpoints) {
                                      for (var checkpoint in checkpoints) {
                                        // Find the closest elevation point to this checkpoint
                                        FlSpot elevSpot = findClosestElevationPoint(checkpoint.distance);
                                        if ((spot.x - elevSpot.x).abs() < 0.05 && spot.y == elevSpot.y) {
                                          return true;
                                        }
                                      }
                                    }
                                    
                                    return false;
                                  },
                                  getDotPainter: (spot, percent, barData, index) {
                                    // Check if this is a checkpoint dot
                                    bool isCheckpoint = false;
                                    if (showCheckpoints) {
                                      for (var checkpoint in checkpoints) {
                                        FlSpot elevSpot = findClosestElevationPoint(checkpoint.distance);
                                        if ((spot.x - elevSpot.x).abs() < 0.05 && spot.y == elevSpot.y) {
                                          isCheckpoint = true;
                                          break;
                                        }
                                      }
                                    }
                                    
                                    // Use red for checkpoints, blue for hovered spot
                                    return FlDotCirclePainter(
                                      radius: isCheckpoint ? 6 : 6,
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
                                      (i) => getGradientColor(smoothedGradients[i]).withOpacity(0.2),
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
                            minY: minElevRounded, // Use rounded value for even intervals
                            maxY: maxElevRounded, // Use rounded value for even intervals
                            minX: 0,
                            maxX: elevationPoints.last.x,
                            lineTouchData: const LineTouchData(
                              enabled: false, // Disable built-in hover interactions
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Add instruction for checkpoint creation if pending (MOVED HERE)
              if (_isPendingCheckpointCreation && _pendingCheckpointDistance != null)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0), // Added vertical margin
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Add checkpoint at ${_pendingCheckpointDistance!.toStringAsFixed(2)} km?',
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          if (mounted) {
                            _createCheckpointAtDistance(_pendingCheckpointDistance!);
                            setState(() {
                              _isPendingCheckpointCreation = false;
                              _pendingCheckpointDistance = null;
                            });
                          }
                        },
                        child: const Text('Confirm'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isPendingCheckpointCreation = false;
                            _pendingCheckpointDistance = null;
                          });
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              
              // Route Summary Section with bar charts
              if (routePoints.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section title
                      Text(
                        'Route Summary',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Total statistics
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Use Wrap for responsive layout
                          return Wrap(
                            spacing: 8.0, // Horizontal spacing between cards
                            runSpacing: 8.0, // Vertical spacing between rows
                            alignment: WrapAlignment.center,
                            children: [
                              SizedBox(
                                width: constraints.maxWidth > 800 ? (constraints.maxWidth - 40) / 6 : (constraints.maxWidth - 8) / 2,
                                child: _buildStatCard(
                                  'Total Distance',
                                  '${elevationPoints.isNotEmpty ? elevationPoints.last.x.toStringAsFixed(1) : "0"} km',
                                  Icons.straighten,
                                  Colors.blue,
                                ),
                              ),
                              SizedBox(
                                width: constraints.maxWidth > 800 ? (constraints.maxWidth - 40) / 6 : (constraints.maxWidth - 8) / 2,
                                child: _buildStatCard(
                                  'Grade Adj. Distance',
                                  '${checkpoints.isNotEmpty ? checkpoints.last.cumulativeGradeAdjustedDistance.toStringAsFixed(1) : "0"} km',
                                  Icons.terrain,
                                  Colors.purple,
                                ),
                              ),
                              SizedBox(
                                width: constraints.maxWidth > 800 ? (constraints.maxWidth - 40) / 6 : (constraints.maxWidth - 8) / 2,
                                child: _buildStatCard(
                                  'Elevation Gain',
                                  '${cumulativeElevationGain.isNotEmpty ? cumulativeElevationGain.last.toInt() : "0"} m',
                                  Icons.trending_up,
                                  Colors.green,
                                ),
                              ),
                              SizedBox(
                                width: constraints.maxWidth > 800 ? (constraints.maxWidth - 40) / 6 : (constraints.maxWidth - 8) / 2,
                                child: _buildStatCard(
                                  'Elevation Loss',
                                  '${cumulativeElevationLoss.isNotEmpty ? cumulativeElevationLoss.last.toInt() : "0"} m',
                                  Icons.trending_down,
                                  Colors.red,
                                ),
                              ),
                              SizedBox(
                                width: constraints.maxWidth > 800 ? (constraints.maxWidth - 40) / 6 : (constraints.maxWidth - 8) / 2,
                                child: _buildStatCard(
                                  'Estimated Time',
                                  timePoints.isNotEmpty ? _formatTotalTime(timePoints.last.y) : '0m',
                                  Icons.timer,
                                  Colors.orange,
                                ),
                              ),
                              SizedBox(
                                width: constraints.maxWidth > 800 ? (constraints.maxWidth - 40) / 6 : (constraints.maxWidth - 8) / 2,
                                child: _buildStatCard(
                                  'Average Pace',
                                  timePoints.isNotEmpty ? '${formatPaceAxisLabel((timePoints.last.y * 60) / elevationPoints.last.x)} min/km' : '0 min/km',
                                  Icons.speed,
                                  Colors.cyan,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      
                      // Bar charts
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Elevation distribution chart
                          _buildBarChart(
                            'Time at Elevation',
                            calculateRouteSummaryData()['elevation'] ?? [],
                            Colors.blue,
                          ),
                          const SizedBox(height: 12),
                          // Gradient distribution chart
                          _buildBarChart(
                            'Time at Gradient',
                            calculateRouteSummaryData()['gradient'] ?? [],
                            Colors.red,
                          ),
                          const SizedBox(height: 12),
                          // Pace distribution chart
                          _buildBarChart(
                            'Time at Pace',
                            calculateRouteSummaryData()['pace'] ?? [],
                            Colors.green,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              
              // Checkpoint button and table
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Button to toggle checkpoint table
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          showCheckpoints = !showCheckpoints;
                          if (showCheckpoints && checkpoints.isEmpty) {
                            // Add a default 'Finish' checkpoint
                            addDefaultFinishCheckpoint();
                          }
                        });
                      },
                      icon: Icon(showCheckpoints ? Icons.visibility_off : Icons.visibility),
                      label: Text(showCheckpoints ? 'Hide Checkpoints' : 'Add Checkpoints'),
                    ),
                    
                    // Checkpoint table
                    if (showCheckpoints) ...[
                      const SizedBox(height: 16),
                      
                      // Export button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Start time picker
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final screenWidth = MediaQuery.of(context).size.width;
                                final bool isWideScreen = screenWidth > 800;
                                
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isWideScreen) ...[
                                      // Start time row (only shown in narrow layout)
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
                                    
                                    // Main controls row
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (isWideScreen) ...[
                                          // Start time (only shown in wide layout)
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
                                        ],
                                        
                                        // Carbs per hour control
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text('Carbs per hour: '),
                                            SizedBox(
                                              width: 45,
                                              child: TextField(
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  hintText: '0',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                                ),
                                                onChanged: (value) {
                                                  double? newValue = double.tryParse(value);
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
                                        
                                        // Carb unit control
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text('Carb unit: '),
                                            SizedBox(
                                              width: 45,
                                              child: TextField(
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  hintText: '0',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                                ),
                                                onChanged: (value) {
                                                  double? newValue = double.tryParse(value);
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
                                        
                                        // Fluid per hour control
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text('Fluid per hour: '),
                                            SizedBox(
                                              width: 45,
                                              child: TextField(
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  hintText: '0',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                                ),
                                                onChanged: (value) {
                                                  // Handle fluid per hour input
                                                },
                                              ),
                                            ),
                                            const Text('ml/h'),
                                          ],
                                        ),
                                        
                                        // Fluid unit control
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text('Fluid unit: '),
                                            SizedBox(
                                              width: 45,
                                              child: TextField(
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  hintText: '0',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                                ),
                                                onChanged: (value) {
                                                  // Handle fluid per hour input
                                                },
                                              ),
                                            ),
                                            const Text('ml'),
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
                      
                      // Wrap the table structure in a horizontal scroll view
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          // Set a minimum width to ensure columns don't wrap and scrolling is enabled
                          constraints: const BoxConstraints(minWidth: 1200), 
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Table header
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
                                    SizedBox( // Name column
                                      width: 120,
                                      child: Text(
                                        'Name',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Total Distance column
                                      width: 110,
                                      child: Text(
                                        'Total Distance\n(km)',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Segment Distance column
                                      width: 110,
                                      child: Text(
                                        'Segment Dist.\n(km)',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Segment Pace column
                                      width: 110,
                                      child: Text(
                                        'Segment Pace\n(min/km)',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Grade Adj. Distance column
                                      width: 110,
                                      child: Text(
                                        'Grade Adj. Dist.\n(km)',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Elevation column
                                      width: 110,
                                      child: Text(
                                        'Elevation\n(m)',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Elev. Gain column
                                      width: 110,
                                      child: Text(
                                        'Elev. Gain\n(m)',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Elev. Loss column
                                      width: 110,
                                      child: Text(
                                        'Elev. Loss\n(m)',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Total Time column
                                      width: 100,
                                      child: Text(
                                        'Total Time',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox( // Segment Time column
                                      width: 100,
                                      child: Text(
                                        'Segment Time',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (carbsPerHour > 0 && gramsPerUnit > 0)
                                      SizedBox( // Carbs Units column
                                        width: 100,
                                        child: Text(
                                          'Carb units',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    // Add Real Time column if start time is set
                                    if (startTime != null) 
                                      SizedBox( // Real Time column
                                        width: 100,
                                        child: Text(
                                          'Real Time',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 180), // Space for delete button
                                  ],
                                ),
                              ),
                              
                              // Table rows - Replace ListView.builder with Column
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                ),
                                // Use a Column instead of ListView.builder
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
                                          // Name field (editable)
                                          SizedBox(
                                            width: 120,
                                            child: TextFormField(
                                              key: ValueKey('checkpoint_name_${checkpoint.id}'),
                                              focusNode: _nameFocusNodes[index],
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
                                          
                                          // Total Distance (editable)
                                          SizedBox(
                                            width: 110,
                                            child: TextFormField(
                                              key: ValueKey('checkpoint_${checkpoint.id}'),
                                              focusNode: _distanceFocusNodes[index],
                                              initialValue: checkpoint.distance > 0
                                                  ? checkpoint.distance.toStringAsFixed(1)
                                                  : '',
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                border: OutlineInputBorder(),
                                                hintText: 'Enter km',
                                              ),
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              onChanged: (value) {
                                                // Try to parse the value, but don't update if it's not a valid number
                                                double? distance = double.tryParse(value);
                                                if (distance != null) {
                                                  updateCheckpointDistance(index, distance);
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
                                          
                                          // Segment Distance (read-only)
                                          SizedBox(
                                            width: 110,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                _getSegmentDistance(index).toStringAsFixed(1),
                                              ),
                                            ),
                                          ),
                                          
                                          // Segment Pace (read-only)
                                          SizedBox(
                                            width: 110,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                _getSegmentPace(index),
                                              ),
                                            ),
                                          ),
                                          
                                          // Grade Adj. Distance (read-only)
                                          SizedBox(
                                            width: 110,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                checkpoint.cumulativeGradeAdjustedDistance.toStringAsFixed(1),
                                              ),
                                            ),
                                          ),
                                          
                                          // Elevation (read-only)
                                          SizedBox(
                                            width: 110,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                checkpoint.elevation.toStringAsFixed(0),
                                              ),
                                            ),
                                          ),
                                          
                                          // Elevation Gain (read-only)
                                          SizedBox(
                                            width: 110,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                checkpoint.elevationGain.toStringAsFixed(0),
                                              ),
                                            ),
                                          ),
                                          
                                          // Elevation Loss (read-only)
                                          SizedBox(
                                            width: 110,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                checkpoint.elevationLoss.toStringAsFixed(0),
                                              ),
                                            ),
                                          ),
                                          
                                          // Cumulative Time (read-only)
                                          SizedBox(
                                            width: 100,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                _formatTotalTime(checkpoint.cumulativeTime),
                                              ),
                                            ),
                                          ),
                                          
                                          // Time from Previous (read-only)
                                          SizedBox(
                                            width: 100,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                _formatTotalTime(checkpoint.timeFromPrevious),
                                              ),
                                            ),
                                          ),
                                          
                                          if (carbsPerHour > 0 && gramsPerUnit > 0)
                                            // Carbs Units (read-only)
                                            SizedBox(
                                              width: 100,
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                                child: Text(
                                                  '${checkpoint.legUnits} (${checkpoint.cumulativeUnits})',
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          
                                          // Add Real Time column if start time is set
                                          if (startTime != null)
                                            SizedBox( // Real Time column
                                              width: 100,
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                                child: Text(
                                                  _formatRealTime(checkpoint.cumulativeTime),
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          
                                          // Control buttons - adjust pace and delete
                                          SizedBox( // Actions column
                                            width: 180,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Adjustment factor controls
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.remove, size: 20),
                                                      onPressed: () {
                                                        setState(() {
                                                          checkpoint.adjustmentFactor -= 5;
                                                        });
                                                      },
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                    SizedBox(
                                                      width: 60,
                                                      child: Text(
                                                        '${checkpoint.adjustmentFactor.toStringAsFixed(0)} s/km',
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.add, size: 20),
                                                      onPressed: () {
                                                        setState(() {
                                                          checkpoint.adjustmentFactor += 5;
                                                        });
                                                      },
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  ],
                                                ),
                                                // Delete button
                                                SizedBox(
                                                  width: 40,
                                                  child: IconButton(
                                                    icon: const Icon(Icons.delete, size: 20),
                                                    onPressed: () => removeCheckpoint(index),
                                                    color: Colors.red,
                                                    padding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }), // End of List.generate
                                ), // End of Column
                              ), // End of Container for rows
                            ],
                          ), // End of inner Column
                        ), // End of ConstrainedBox
                      ), // End of SingleChildScrollView
                      
                      // Add checkpoint button
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // Add a new checkpoint and immediately recalculate all metrics
                            addCheckpoint();
                            // Force a rebuild to ensure the UI reflects the updated values
                            setState(() {});
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Checkpoint'),
                        ),
                      ),
                      
                      // Export to Excel and Reset buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Export to Excel button
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ElevatedButton.icon(
                              onPressed: checkpoints.isNotEmpty ? 
                                exportCheckpointsToExcel : null,
                              icon: const Icon(Icons.file_download),
                              label: const Text('Export to Excel'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTotalTime(double totalMinutes) {
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes.round() % 60;
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  String _getTimeAtDistance(double distance) {
    if (timePoints.isEmpty) return 'N/A';
    
    // Find the closest time point to the given distance
    FlSpot? closestTimePoint;
    double minDist = double.infinity;
    
    for (var point in timePoints) {
      double dist = (point.x - distance).abs();
      if (dist < minDist) {
        minDist = dist;
        closestTimePoint = point;
      }
    }
    
    if (closestTimePoint != null) {
      return _formatTotalTime(closestTimePoint.y);
    }
    
    return 'N/A';
  }

  int _findRoutePointIndexForDistance(double distance) {
    if (elevationPoints.isEmpty || routePoints.isEmpty) return -1;
    
    // First, find the closest elevation point to this distance
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
    setState(() {
      // Create a new checkpoint with a unique ID and timestamp to ensure uniqueness
      final newCheckpoint = CheckpointData(distance: 0.0);
      newCheckpoint.id = DateTime.now().millisecondsSinceEpoch.toString();
      
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
      
      // Calculate base grade adjusted pace for this segment if not already done
      double startDistance = 0;
      if (i > 0) {
        startDistance = checkpoints[i-1].distance;
      }
      if (checkpoint.baseGradeAdjustedPace <= 0) {
        checkpoint.baseGradeAdjustedPace = getSegmentBaseGradeAdjustedPace(startDistance, checkpoint.distance);
      }
      
      // Calculate grade adjusted distance for this segment
      checkpoint.gradeAdjustedDistance = calculateGradeAdjustedDistance(startDistance, checkpoint.distance);
    }
    
    // Re-sort checkpoints by distance to ensure correct order
    checkpoints.sort((a, b) => a.distance.compareTo(b.distance));
    
    // Process all checkpoints to ensure consistency
    for (int i = 0; i < checkpoints.length; i++) {
      final checkpoint = checkpoints[i];
      
      // Find the closest elevation point to this distance
      FlSpot elevationSpot = findClosestElevationPoint(checkpoint.distance);
      int elevationIndex = _closestElevationPointIndex;
      
      // Set elevation
      checkpoint.elevation = elevationSpot.y;
      
      // Set cumulative elevation gain/loss
      if (elevationIndex >= 0 && elevationIndex < cumulativeElevationGain.length) {
        checkpoint.elevationGain = cumulativeElevationGain[elevationIndex];
        checkpoint.elevationLoss = cumulativeElevationLoss[elevationIndex];
      }
      
      // Calculate cumulative grade adjusted distance
      if (i == 0) {
        checkpoint.cumulativeGradeAdjustedDistance = checkpoint.gradeAdjustedDistance;
      } else {
        checkpoint.cumulativeGradeAdjustedDistance = checkpoints[i-1].cumulativeGradeAdjustedDistance + checkpoint.gradeAdjustedDistance;
      }
      
      // Find the closest time point to this distance
      double cumulativeTime = 0;
      
      // Handle edge cases for time calculation
      if (checkpoint.distance <= 0 && timePoints.isNotEmpty) {
        // At start of route
        cumulativeTime = 0;
      } else if (checkpoint.distance >= timePoints.last.x) {
        // At or beyond end of route
        cumulativeTime = timePoints.last.y;
      } else {
        // Somewhere in the middle - find the closest time points and interpolate
        FlSpot? prevPoint;
        FlSpot? nextPoint;
        
        for (int j = 0; j < timePoints.length - 1; j++) {
          if (timePoints[j].x <= checkpoint.distance && timePoints[j + 1].x >= checkpoint.distance) {
            prevPoint = timePoints[j];
            nextPoint = timePoints[j + 1];
            break;
          }
        }
        
        if (prevPoint != null && nextPoint != null) {
          // Interpolate between the two points
          double timeDiff = nextPoint.y - prevPoint.y;
          double distDiff = nextPoint.x - prevPoint.x;
          if (distDiff > 0) {  // Avoid division by zero
            double ratio = (checkpoint.distance - prevPoint.x) / distDiff;
            cumulativeTime = prevPoint.y + (timeDiff * ratio);
          } else {
            cumulativeTime = prevPoint.y;
          }
        } else {
          // Fallback to the old method if we couldn't find bracketing points
          for (var timePoint in timePoints) {
            if (timePoint.x <= checkpoint.distance) {
              cumulativeTime = timePoint.y;
            } else {
              break;
            }
          }
        }
      }
      
      // Set cumulative time
      checkpoint.cumulativeTime = cumulativeTime;
      
      // Calculate time from previous checkpoint
      if (i > 0) {
        checkpoint.timeFromPrevious = checkpoint.cumulativeTime - checkpoints[i-1].cumulativeTime;
      } else {
        checkpoint.timeFromPrevious = checkpoint.cumulativeTime;
      }
    }
  }

  // Format real time based on start time plus cumulative minutes
  String _formatRealTime(double cumulativeMinutes) {
    if (startTime == null) return 'N/A';
    
    // Convert start time to minutes since midnight
    int startMinutes = startTime!.hour * 60 + startTime!.minute;
    
    // Add cumulative time (in minutes)
    int totalMinutes = startMinutes + cumulativeMinutes.round();
    
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
    String timeStr = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    
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
      ];
      
      // Add Real Time header if start time is set
      if (startTime != null) {
        headers.add('Real Time');
      }
      
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = 
            xl.TextCellValue(headers[i]);
      }
      
      // Add checkpoint data
      for (int i = 0; i < checkpoints.length; i++) {
        final checkpoint = checkpoints[i];
        
        // Name
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i+1)).value = 
            xl.TextCellValue(checkpoint.name ?? '');
        
        // Distance
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i+1)).value = 
            xl.DoubleCellValue(checkpoint.distance);
        
        // Grade Adjusted Distance
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i+1)).value = 
            xl.DoubleCellValue(checkpoint.cumulativeGradeAdjustedDistance);
        
        // Elevation
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i+1)).value = 
            xl.DoubleCellValue(checkpoint.elevation);
        
        // Elevation Gain
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i+1)).value = 
            xl.DoubleCellValue(checkpoint.elevationGain);
        
        // Elevation Loss
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i+1)).value = 
            xl.DoubleCellValue(checkpoint.elevationLoss);
        
        // Total Time (formatted)
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: i+1)).value = 
            xl.TextCellValue(_formatTotalTime(checkpoint.cumulativeTime));
        
        // Segment Time (formatted)
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: i+1)).value = 
            xl.TextCellValue(_formatTotalTime(checkpoint.timeFromPrevious));
        
        // Column index tracker
        int colIndex = 8;
        
        // Real Time (if start time is set)
        if (startTime != null) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: i+1)).value = 
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
          const SnackBar(content: Text('Downloading checkpoint data')),
        );
        return;
      } 
      
      // For native platforms
      String? outputFile;
      try {
        // Try to use FilePicker to get save location from user
        outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save checkpoint data',
          fileName: defaultFilename,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
        
        if (outputFile == null) {
          // User cancelled the save dialog
          return;
        }
        
        // Ensure the file has the correct extension
        if (!outputFile.endsWith('.xlsx')) {
          outputFile += '.xlsx';
        }
      } catch (e) {
        // FilePicker's saveFile isn't implemented on all platforms
        // Show error and return
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open save dialog: $e')),
        );
        return;
      }
      
      // Save the Excel file to disk (only for native platforms)
      final fileBytes = excel.save();
      if (fileBytes != null) {
        try {
          File(outputFile)
            ..createSync(recursive: true)
            ..writeAsBytesSync(fileBytes);
            
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported checkpoints to $outputFile')),
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
  double getSegmentBaseGradeAdjustedPace(double startDistance, double endDistance) {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty) return selectedPaceSeconds;
    
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
      int prevIdx = pointIndices[i-1];
      
      double segmentDistance = elevationPoints[idx].x - elevationPoints[prevIdx].x;
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
    double baseGradeAdjustedPace = getSegmentBaseGradeAdjustedPace(startDistance, endDistance);
    
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
        double endSegTime = calculateSegmentTime(checkpoints[0].distance, totalDistance);
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
    
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty || minElevation == null || maxElevation == null) return result;
    
    // Safety check - ensure we have enough data to create meaningful bins
    if (elevationPoints.length < 5 || smoothedGradients.length < 5) {
      // Add a "Not enough data" placeholder for each chart
      result['elevation']!.add(ChartData('Insufficient Data', 0));
      result['pace']!.add(ChartData('Insufficient Data', 0));
      result['gradient']!.add(ChartData('Insufficient Data', 0));
      return result;
    }
    
    // Define custom elevation bins (0-500, 500-1000, 1000-1500, 1500-2000, 2000-2500, 2500-3000, >3000)
    List<String> elevationLabels = [
      '    0 to 200m', 
      '  200 to 400m', 
      '  400 to 600m', 
      '  600 to 800m', 
      '  800 to 1000m', 
      '1000 to 1200m', 
      '1200 to 1400m', 
      '1400 to 1600m', 
      '1600 to 1800m', 
      '1800 to 2000m', 
      '2000 to 2200m', 
      '2200 to 2400m', 
      '2400 to 2600m', 
      '2600 to 2800m', 
      '2800 to 3000m', 
      '       >3000m'
    ];
    
    List<double> elevationBreakpoints = [0, 200, 400, 600, 800, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2400, 2600, 2800, 3000, double.infinity];
    
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
      double.negativeInfinity, -25, -20, -15, -10, -5, 0, 5, 10, 15, 20, 25, double.infinity
    ];
    
// Define pace bins (30s intervals)
    List<String> paceLabels = [
      '         <3:00',
      '  3:00 to 4:00',
      '  4:00 to 5:00',
      '  5:00 to 6:00',
      '  6:00 to 7:00',
      '  7:00 to 8:00',
      '  8:00 to 9:00',
      ' 9:00 to 10:00',
      '10:00 to 11:00',
      '11:00 to 12:00',
      '        >12:00',
    ];
    
    List<double> paceBreakpoints = [
      0, 180, 240, 300, 360, 420, 480, 540, 600, 660, 720, double.infinity
    ];

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
      double segmentDistance = elevationPoints[i].x - elevationPoints[i-1].x;
      
      // Skip segments with zero or negative distance (data errors)
      if (segmentDistance <= 0) continue;
      
      // Ensure we don't go out of bounds with smoothedGradients array
      int gradientIndex = min(i, smoothedGradients.length - 1);
      double gradientPercent = gradientIndex >= 0 ? smoothedGradients[gradientIndex] : 0;
      double elevation = elevationPoints[i].y;
      
      // Calculate pace for this segment
      double adjustment = calculateGradeAdjustment(gradientPercent);
      double segmentPace = selectedPaceSeconds * adjustment;
      segmentPace = max(segmentPace, minSegmentPace);
      
      // Calculate time for this segment in minutes
      double segmentTime = (segmentDistance * segmentPace) / 60;
      
      // Add to elevation bins
      for (int j = 0; j < elevationBreakpoints.length - 1; j++) {
        if (elevation >= elevationBreakpoints[j] && elevation < elevationBreakpoints[j + 1]) {
          elevationBins[j] = (elevationBins[j] ?? 0) + segmentTime;
          break;
        }
      }
      
      // Add to gradient bins
      for (int j = 0; j < gradientBreakpoints.length - 1; j++) {
        if (gradientPercent >= gradientBreakpoints[j] && gradientPercent < gradientBreakpoints[j + 1]) {
          gradientBins[j] = (gradientBins[j] ?? 0) + segmentTime;
          break;
        }
      }
      
    }

    // Compute time spent in each segment
    for (int i = 1; i < pacePoints.length; i++) {
      double segmentDistance = pacePoints[i].x - pacePoints[i-1].x;
      if (segmentDistance <= 0) continue;

      double segmentPace = pacePoints[i].y;
      double segmentTime = (segmentDistance * segmentPace) / 60;

      // Add to pace bins
      for (int j = 0; j < paceBreakpoints.length - 1; j++) {
        if (segmentPace >= paceBreakpoints[j] && segmentPace < paceBreakpoints[j + 1]) {
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
          result['elevation']!.add(ChartData(elevationLabels[i], elevationBins[i]!));
        }
      }
    }
    
    // Convert gradient bins to chart data with custom labels
    if (hasGradientData) {
      for (int i = 0; i < gradientLabels.length; i++) {
        if (gradientBins[i] != null && gradientBins[i]! > 0) {
          result['gradient']!.add(ChartData(gradientLabels[i], gradientBins[i]!));
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

  // Handle tap for checkpoint creation
  void _handleTapForCheckpoint() {
    if (hoveredDistance == null || !mounted) return;
    
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
          _pendingCheckpointDistance = hoveredDistance;
        });
      }
    } catch (e) {
      // Reset state if an error occurs
      setState(() {
        _isPendingCheckpointCreation = false;
        _pendingCheckpointDistance = null;
      });
    }
  }
  
  // Get marker for pending checkpoint
  List<Marker> _getPendingCheckpointMarker() {
    if (_pendingCheckpointDistance == null) return [];
    
    int routePointIndex = _findRoutePointIndexForDistance(_pendingCheckpointDistance!);
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
        final finishCheckpoint = CheckpointData(distance: elevationPoints.last.x);
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
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
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
    if (data.length == 1 && (data[0].category.contains('No ') || data[0].category.contains('Insufficient'))) {
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
          height: 250,
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
                          if (value < 0 || value >= data.length) return const Text('');
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
                          width: clampedWidth,  // Use the calculated responsive width
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
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
    double normalizedPace = (maxPace == minPace) ? 0.5 : (pace - minPace) / (maxPace - minPace);
    normalizedPace = normalizedPace.clamp(0.0, 1.0); // Ensure it's within [0, 1]

    // Hue range: 120 (green) down to 0 (red)
    double hue = 120.0 * (1.0 - normalizedPace);
    // Use full saturation and value for vibrant colors
    return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
  }

  // Formatting function for pace axis labels
  String formatPaceAxisLabel(double seconds) {
    if (seconds <= 0) return ""; // Don't show 0:00 or negative
    int mins = (seconds / 60).floor();
    int secs = (seconds % 60).round();
    // Pad seconds to two digits
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
  double calculateGradeAdjustedDistance(double startDistance, double endDistance) {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty) return endDistance - startDistance;
    
    double totalAdjustedDistance = 0;
    
    // Find elevation points within this segment
    for (int i = 1; i < elevationPoints.length; i++) {
      double distance = elevationPoints[i].x;
      if (distance >= startDistance && distance <= endDistance) {
        double segmentDistance = elevationPoints[i].x - elevationPoints[i-1].x;
        if (segmentDistance <= 0) continue;
        
        // Get gradient for this segment
        int gradientIndex = min(i, smoothedGradients.length - 1);
        double gradientPercent = gradientIndex >= 0 ? smoothedGradients[gradientIndex] : 0;
        
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
      return checkpoints[checkpointIndex].distance - checkpoints[checkpointIndex - 1].distance;
    }
  }

  // Helper method to get segment pace for a checkpoint
  String _getSegmentPace(int checkpointIndex) {
    if (checkpointIndex < 0 || checkpointIndex >= checkpoints.length) return 'N/A';
    
    double segmentDistance = _getSegmentDistance(checkpointIndex);
    if (segmentDistance <= 0) return 'N/A';
    
    double segmentTime = checkpoints[checkpointIndex].timeFromPrevious;
    if (segmentTime <= 0) return 'N/A';
    
    // Calculate pace in seconds per km
    double paceSeconds = (segmentTime * 60) / segmentDistance;
    
    // Format pace as MM:SS
    int minutes = (paceSeconds / 60).floor();
    int seconds = (paceSeconds % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // Function to calculate carbs units for checkpoints
  void calculateCarbsUnits() {
    if (checkpoints.isEmpty) return;

    int previousCumulativeUnits = 0;

    for (int i = 0; i < checkpoints.length; i++) {
      final checkpoint = checkpoints[i];
      
      // Convert cumulative time to hours
      double currentTotalTimeHours = checkpoint.cumulativeTime / 60.0;
      
      // Calculate total grams needed up to this point
      double cumulativeGrams = currentTotalTimeHours * carbsPerHour;
      
      // Calculate total units needed up to this point (round up)
      int currentCumulativeUnits = (cumulativeGrams / gramsPerUnit).ceil();
      
      // Calculate units needed for this specific leg
      int legUnits = currentCumulativeUnits - previousCumulativeUnits;
      
      // Update checkpoint values
      setState(() {
        checkpoint.legUnits = legUnits;
        checkpoint.cumulativeUnits = currentCumulativeUnits;
      });
      
      // Update previous cumulative units
      previousCumulativeUnits = currentCumulativeUnits;
    }
  }

  // Function to parse time string to hours
  double _parseTimeToHours(String timeStr) {
    int hours = 0;
    int minutes = 0;
    
    if (timeStr.contains('h')) {
      final parts = timeStr.split('h');
      hours = int.parse(parts[0]);
      if (parts.length > 1 && parts[1].contains('m')) {
        minutes = int.parse(parts[1].replaceAll('m', ''));
      }
    } else if (timeStr.contains('m')) {
      minutes = int.parse(timeStr.replaceAll('m', ''));
    }
    
    return hours + (minutes / 60.0);
  }
} 