import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gpx/gpx.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' show sin, cos, sqrt, atan2, max, min, pow, exp, pi, Point;
import 'dart:async'; // Add timer import for debounce
import '../models/route_analyzer.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

class RouteAnalyzerScreen extends StatefulWidget {
  const RouteAnalyzerScreen({super.key});

  @override
  State<RouteAnalyzerScreen> createState() => _RouteAnalyzerScreenState();
}

class _RouteAnalyzerScreenState extends State<RouteAnalyzerScreen> {
  Gpx? gpxData;
  RouteAnalyzer? analyzer;
  List<LatLng> routePoints = [];
  List<FlSpot> elevationPoints = [];
  List<FlSpot> timePoints = []; // Points for time graph
  double? maxElevation;
  double? minElevation;
  double cumulativeDistance = 0.0;
  int? hoveredPointIndex;
  double? hoveredDistance;
  FlSpot? hoveredSpot; // Add this to track the exact hovered spot
  Timer? _mapDebounceTimer; // Separate timer for map marker
  Timer? _chartDebounceTimer; // Separate timer for chart marker
  final mapController = MapController();
  List<double> smoothedGradients = [];
  
  // Pace-related state
  double selectedPaceSeconds = 150; // Default 2:30 (150 seconds)
  static const double minPaceSeconds = 150; // 2:30
  static const double maxPaceSeconds = 1200; // 20:00

  String formatPace(double seconds) {
    int mins = (seconds / 60).floor();
    int secs = (seconds % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  double calculateGradeAdjustment(double gradientPercent) {
    double g = gradientPercent;
    return (-0.000000447713 * pow(g, 4)) +
           (-0.000003068688 * pow(g, 3)) +
           (0.001882643005 * pow(g, 2)) +
           (0.030457306268 * g) +
           1;
  }

  void calculateTimePoints() {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty) return;
    
    List<FlSpot> newTimePoints = [];
    double cumulativeTime = 0;
    
    for (int i = 0; i < elevationPoints.length; i++) {
      if (i == 0) {
        newTimePoints.add(FlSpot(0, 0));
        continue;
      }

      // Calculate distance segment in kilometers
      double segmentDistance = elevationPoints[i].x - elevationPoints[i-1].x;
      
      // Get grade adjustment factor for this segment
      double adjustment = calculateGradeAdjustment(smoothedGradients[i]);
      
      // Calculate real pace for this segment (in seconds per km)
      double realPace = selectedPaceSeconds * adjustment;
      
      // Calculate time for this segment
      double segmentTime = (segmentDistance * realPace) / 60; // Convert to minutes
      cumulativeTime += segmentTime;
      
      newTimePoints.add(FlSpot(elevationPoints[i].x, cumulativeTime));
    }

    setState(() {
      timePoints = newTimePoints;
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
        gpxData = GpxReader().fromString(fileContent);
        processGpxData();
      } catch (e) {
        debugPrint('Error processing GPX file: $e');
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

    if (points.isEmpty) return;

    setState(() {
      // Reset all data
      routePoints = [];
      elevationPoints = [];
      timePoints = [];
      smoothedGradients = [];
      cumulativeDistance = 0.0;
      maxElevation = null;
      minElevation = null;
      hoveredPointIndex = null;
      hoveredDistance = null;

      // Process route points
      routePoints = points
          .where((pt) => pt.lat != null && pt.lon != null)
          .map((pt) => LatLng(pt.lat!, pt.lon!))
          .toList();

      // Process first elevation point
      if (points.isNotEmpty && points[0].ele != null) {
        elevationPoints.add(FlSpot(0, points[0].ele!));
      }

      // Process remaining points and calculate average point spacing
      double totalDistance = 0;
      int pointCount = 0;
      
      for (int i = 1; i < points.length; i++) {
        if (points[i].ele == null) continue;

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
        
        // Add point with cumulative distance and elevation
        elevationPoints.add(FlSpot(cumulativeDistance, points[i].ele!));
      }

      // Calculate average point spacing in meters
      double avgSpacing = totalDistance / pointCount;
      
      // Calculate window size based on point spacing
      // We want to smooth over roughly 100m of distance
      int windowSize = max(3, min(15, (100 / avgSpacing).round()));

      if (elevationPoints.isNotEmpty) {
        maxElevation = elevationPoints.map((p) => p.y).reduce((a, b) => max(a, b));
        minElevation = elevationPoints.map((p) => p.y).reduce((a, b) => min(a, b));
      }

      // Calculate and smooth gradients
      List<double> gradients = calculateGradients(elevationPoints);
      smoothedGradients = smoothGradients(gradients, windowSize);

      // Calculate initial time points
      calculateTimePoints();

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

  int findClosestPointIndex(double targetDistance) {
    return elevationPoints.indexWhere((point) => point.x >= targetDistance);
  }

  Color getGradientColor(double gradient) {
    const maxGradient = 15.0; // Maximum gradient percentage to consider
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
      final clampedGradient = gradient.clamp(-40.0, 40.0);
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

  int findClosestRoutePoint(Offset localPosition, BoxConstraints constraints) {
    // Convert screen coordinates to lat/lng
    final point = mapController.camera.pointToLatLng(Point(localPosition.dx, localPosition.dy));
    
    // Find closest point on route
    double minDistance = double.infinity;
    int closestIndex = -1;
    
    for (int i = 0; i < routePoints.length; i++) {
      final routePoint = routePoints[i];
      final distance = (point.latitude - routePoint.latitude) * (point.latitude - routePoint.latitude) +
                      (point.longitude - routePoint.longitude) * (point.longitude - routePoint.longitude);
      
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    return closestIndex;
  }

  // Add this method to find the closest elevation point to a given distance
  FlSpot findClosestElevationPoint(double distance) {
    if (elevationPoints.isEmpty) return const FlSpot(0, 0);
    
    // Find the closest point by distance
    FlSpot closest = elevationPoints.first;
    double minDist = double.infinity;
    int closestIndex = 0;
    
    for (int i = 0; i < elevationPoints.length; i++) {
      var point = elevationPoints[i];
      double dist = (point.x - distance).abs();
      if (dist < minDist) {
        minDist = dist;
        closest = point;
        closestIndex = i;
      }
    }
    
    // Store the index of the closest point for tooltip display
    _closestElevationPointIndex = closestIndex;
    
    // Return a spot with the exact x-coordinate from the hover position
    // but the y-coordinate from the closest data point
    // This ensures the vertical line aligns perfectly with the mouse
    return FlSpot(distance, closest.y);
  }

  // Add a field to track the index of the closest elevation point
  int _closestElevationPointIndex = 0;
  
  // Add this method to update the map marker with a shorter debounce
  void _updateMapMarker(int? pointIndex) {
    // Cancel previous timer if it exists
    _mapDebounceTimer?.cancel();
    
    // Use a much shorter debounce time for the map marker to reduce delay
    // but still prevent flickering during rapid mouse movement
    _mapDebounceTimer = Timer(const Duration(milliseconds: 10), () {
      if (mounted) {
        setState(() {
          hoveredPointIndex = pointIndex;
        });
      }
    });
  }

  // Modify this method to only update the chart-related state with no debounce
  void _updateHoveredPoint(int? pointIndex, double? distance) {
    // Cancel previous timer if it exists
    _chartDebounceTimer?.cancel();
    
    // When hovering over the map, we want to update the chart marker immediately
    if (distance != null) {
      // For map hover, update immediately without debounce
      setState(() {
        hoveredDistance = distance;
        hoveredSpot = findClosestElevationPoint(distance);
        
        // Make sure we have a valid index for the tooltip
        if (_closestElevationPointIndex >= 0 && _closestElevationPointIndex < elevationPoints.length) {
          // This will force the chart to rebuild with the tooltip visible
          // The tooltip will appear at the position determined by hoveredSpot and _closestElevationPointIndex
        }
      });
    } else {
      // For chart exit events, use a very short debounce
      _chartDebounceTimer = Timer(const Duration(milliseconds: 10), () {
        if (mounted) {
          setState(() {
            hoveredDistance = null;
            hoveredSpot = null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _mapDebounceTimer?.cancel();
    _chartDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route Analyzer')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ElevatedButton(
              onPressed: pickGPXFile,
              child: const Text('Upload GPX File'),
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
                              });
                            },
                          ),
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
              // Map with reduced height
              SizedBox(
                height: 225, // Reduced from 300 to 75% of original size
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return MouseRegion(
                          onHover: (event) {
                            final RenderBox box = context.findRenderObject() as RenderBox;
                            final localPosition = box.globalToLocal(event.position);
                            
                            final closestIndex = findClosestRoutePoint(localPosition, constraints);
                            if (closestIndex >= 0 && closestIndex < elevationPoints.length) {
                              // Update both markers but with different debounce times
                              _updateMapMarker(closestIndex);
                              
                              // Get the distance value for this point
                              final distance = elevationPoints[closestIndex].x;
                              
                              // Update the chart marker with the distance
                              _updateHoveredPoint(closestIndex, distance);
                            }
                          },
                          onExit: (_) {
                            _updateMapMarker(null);
                            _updateHoveredPoint(null, null);
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
                                        width: 3, // Reduced from 5 to 3 (40% smaller)
                                        height: 3, // Reduced from 5 to 3 (40% smaller)
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
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              
              // Elevation chart
              Container(
                height: 200,
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 30.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate even 200m intervals for elevation ticks
                    double minElevRounded = (minElevation! / 200).floor() * 200;
                    double maxElevRounded = (maxElevation! / 200).ceil() * 200;
                    
                    return LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(color: Colors.grey.shade300, width: 1),
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
                            axisNameSize: 25,
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
                            axisNameWidget: const Padding(
                              padding: EdgeInsets.only(bottom: 8.0, right: 8.0),
                              child: Text(
                                'Elevation (m)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            axisNameSize: 40,
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
                                // Only show dot for the hovered spot
                                // But we need to find the actual data point on the line
                                if (hoveredSpot == null) return false;
                                
                                // Find the closest actual data point to show the dot
                                for (var dataPoint in elevationPoints) {
                                  // Use a small threshold to find the closest point
                                  if ((dataPoint.x - hoveredSpot!.x).abs() < 0.05) {
                                    return spot.x == dataPoint.x && spot.y == dataPoint.y;
                                  }
                                }
                                return false;
                              },
                              getDotPainter: (spot, percent, barData, index) {
                                return FlDotCirclePainter(
                                  radius: 6,
                                  color: Colors.blue,
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
                        lineTouchData: LineTouchData(
                          enabled: true,
                          // Always show tooltip when hoveredSpot is not null (from map or chart)
                          touchTooltipData: LineTouchTooltipData(
                            tooltipBgColor: Colors.blueAccent,
                            tooltipHorizontalAlignment: FLHorizontalAlignment.center,
                            tooltipMargin: 8,
                            fitInsideHorizontally: true,
                            fitInsideVertically: false,
                            tooltipPadding: const EdgeInsets.all(8),
                            tooltipRoundedRadius: 8,
                            tooltipHorizontalOffset: 0,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                // Find the exact time point for this distance
                                double targetDistance = spot.x;
                                FlSpot? timePoint;
                                
                                // Find the exact matching time point
                                for (var point in timePoints) {
                                  if ((point.x - targetDistance).abs() < 0.0001) {
                                    timePoint = point;
                                    break;
                                  }
                                }
                                
                                String timeStr = timePoint != null 
                                    ? _formatTotalTime(timePoint.y)
                                    : 'N/A';
                                    
                                return LineTooltipItem(
                                  'Distance: ${spot.x.toStringAsFixed(2)} km\n'
                                  'Elevation: ${spot.y.toStringAsFixed(0)} m\n'
                                  'Time: $timeStr',
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                );
                              }).toList();
                            },
                          ),
                          getTouchedSpotIndicator: (barData, spotIndexes) {
                            return spotIndexes.map((spotIndex) {
                              return TouchedSpotIndicatorData(
                                FlLine(
                                  color: Colors.blue,
                                  strokeWidth: 2,
                                  dashArray: [5, 5],
                                ),
                                FlDotData(
                                  getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                      radius: 6,
                                      color: Colors.blue,
                                      strokeWidth: 2,
                                      strokeColor: Colors.white,
                                    );
                                  },
                                ),
                              );
                            }).toList();
                          },
                          touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                            // Handle touch/hover events directly from the chart
                            if (event is FlPointerHoverEvent || event is FlPanUpdateEvent) {
                              if (touchResponse?.lineBarSpots != null && 
                                  touchResponse!.lineBarSpots!.isNotEmpty) {
                                // Get the touched spot directly from the chart's touch response
                                final touchedBarSpot = touchResponse.lineBarSpots![0];
                                
                                // Find the closest point for the tooltip
                                final touchedSpot = touchedBarSpot.spotIndex < elevationPoints.length 
                                    ? elevationPoints[touchedBarSpot.spotIndex] 
                                    : null;
                                
                                if (touchedSpot != null) {
                                  // Use the touched spot's x value directly
                                  _updateHoveredPoint(touchedBarSpot.spotIndex, touchedSpot.x);
                                }
                              }
                            } else if (event is FlPointerExitEvent) {
                              _updateHoveredPoint(null, null);
                            }
                          },
                          handleBuiltInTouches: true, // Let the chart handle touches
                          touchSpotThreshold: 20,
                        ),
                        extraLinesData: ExtraLinesData(
                          verticalLines: hoveredSpot != null ? [
                            VerticalLine(
                              x: hoveredSpot!.x,
                              color: Colors.blue.withOpacity(0.7),
                              strokeWidth: 1.5,
                              dashArray: [5, 5],
                              label: VerticalLineLabel(
                                show: false,
                              ),
                            ),
                          ] : [],
                        ),
                        showingTooltipIndicators: hoveredSpot != null ? 
                          [
                            ShowingTooltipIndicators([
                              LineBarSpot(
                                LineChartBarData(
                                  spots: elevationPoints,
                                  isCurved: true,
                                  color: Colors.blue,
                                ),
                                _closestElevationPointIndex, // Use the stored index
                                hoveredSpot!,
                              ),
                            ])
                          ] : [],
                      ),
                    );
                  },
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
} 