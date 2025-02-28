import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gpx/gpx.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:xml/xml.dart';
import 'dart:math' show pi, sin, cos, sqrt, atan2, max, min, pow;
import '../models/route_analyzer.dart';

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
        print('Error processing GPX file: $e');
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
      routePoints = points
          .where((pt) => pt.lat != null && pt.lon != null)
          .map((pt) => LatLng(pt.lat!, pt.lon!))
          .toList();

      // Reset elevation data
      elevationPoints = [];
      cumulativeDistance = 0.0;
      
      // Process first point
      if (points.isNotEmpty && points[0].ele != null) {
        elevationPoints.add(FlSpot(0, points[0].ele!));
      }

      // Process remaining points
      for (int i = 1; i < points.length; i++) {
        if (points[i].ele == null) continue;

        // Calculate distance between current point and previous point
        double distanceInMeters = calculateDistance(
          points[i-1].lat!,
          points[i-1].lon!,
          points[i].lat!,
          points[i].lon!
        );
        
        cumulativeDistance += distanceInMeters / 1000.0; // Convert to kilometers
        
        // Add point with cumulative distance and elevation
        elevationPoints.add(FlSpot(cumulativeDistance, points[i].ele!));
      }

      if (elevationPoints.isNotEmpty) {
        maxElevation = elevationPoints.map((p) => p.y).reduce((a, b) => max(a, b));
        minElevation = elevationPoints.map((p) => p.y).reduce((a, b) => min(a, b));
      }

      // Calculate and smooth gradients
      List<double> gradients = calculateGradients(elevationPoints);
      smoothedGradients = smoothGradients(gradients, 5); // 5-point moving average

      // Calculate initial time points
      calculateTimePoints();

      // Fit map bounds to show the entire route
      Future.delayed(const Duration(milliseconds: 100), () {
        mapController.fitBounds(
          LatLngBounds.fromPoints(routePoints),
          options: const FitBoundsOptions(padding: EdgeInsets.all(20.0)),
        );
      });
    });
  }

  int findClosestPointIndex(double targetDistance) {
    return elevationPoints.indexWhere((point) => point.x >= targetDistance);
  }

  Color getGradientColor(double gradient) {
    if (gradient < 0) {
      // Downhill: Blue (240) to Cyan (180)
      double hue = 180 + (gradient.abs() / 15).clamp(0.0, 1.0) * 60;
      return HSVColor.fromAHSV(
        1.0,
        hue,
        0.8,
        0.9,
      ).toColor();
    } else {
      // Uphill: Yellow (60) to Red (0)
      double hue = 60 * (1 - (gradient / 15).clamp(0.0, 1.0));
      return HSVColor.fromAHSV(
        1.0,
        hue,
        0.8,
        0.9,
      ).toColor();
    }
  }

  List<double> calculateGradients(List<FlSpot> points) {
    List<double> grads = [];
    for (int i = 1; i < points.length; i++) {
      final dx = (points[i].x - points[i-1].x) * 1000; // Convert to meters
      final dy = points[i].y - points[i-1].y;
      final gradient = (dy / dx) * 100; // Convert to percentage
      grads.add(gradient);
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
      int count = 0;
      for (int j = max(0, i - windowSize ~/ 2); 
           j < min(gradients.length, i + windowSize ~/ 2 + 1); 
           j++) {
        sum += gradients[j];
        count++;
      }
      smoothed[i] = sum / count;
    }
    return smoothed;
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
                height: 300, // Reduced from 400
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        bounds: LatLngBounds.fromPoints(routePoints),
                        boundsOptions: const FitBoundsOptions(
                          padding: EdgeInsets.all(20.0),
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.app',
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
                                width: 10,
                                height: 10,
                                builder: (context) => Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Elevation chart
              Container(
                height: 200,
                padding: const EdgeInsets.all(16.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return MouseRegion(
                      onHover: (event) {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final localPosition = box.globalToLocal(event.position);
                        
                        // Adjust for padding and chart boundaries
                        final chartWidth = constraints.maxWidth - 80; // Increased adjustment
                        final chartLeft = 60.0; // Increased left padding
                        
                        // Calculate relative x position within chart area
                        final relativeX = localPosition.dx - chartLeft;
                        if (relativeX < 0 || relativeX > chartWidth) return;
                        
                        // Calculate distance based on adjusted position
                        final distance = (relativeX / chartWidth) * elevationPoints.last.x;
                        
                        setState(() {
                          hoveredPointIndex = findClosestPointIndex(distance);
                        });
                      },
                      onExit: (_) {
                        setState(() {
                          hoveredPointIndex = null;
                        });
                      },
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: true),
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              axisNameWidget: const Text('Distance (km)'),
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: (elevationPoints.last.x / 10).clamp(1, double.infinity),
                              ),
                            ),
                            leftTitles: AxisTitles(
                              axisNameWidget: const Text('Elevation (m)'),
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: ((maxElevation! - minElevation!) / 5).clamp(50, double.infinity),
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: true),
                          lineBarsData: [
                            LineChartBarData(
                              spots: elevationPoints,
                              isCurved: true,
                              color: Colors.blue,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.blue.withOpacity(0.2),
                              ),
                            ),
                          ],
                          minY: minElevation! - ((maxElevation! - minElevation!) * 0.1),
                          maxY: maxElevation! + ((maxElevation! - minElevation!) * 0.1),
                          minX: 0,
                          maxX: elevationPoints.last.x,
                          lineTouchData: LineTouchData(
                            enabled: true,
                            touchTooltipData: LineTouchTooltipData(
                              tooltipBgColor: Colors.blueAccent,
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
                                    const TextStyle(color: Colors.white),
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
                              if (touchResponse?.lineBarSpots != null && touchResponse!.lineBarSpots!.isNotEmpty) {
                                setState(() {
                                  hoveredPointIndex = touchResponse.lineBarSpots![0].spotIndex;
                                });
                              } else {
                                setState(() {
                                  hoveredPointIndex = null;
                                });
                              }
                            },
                          ),
                        ),
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