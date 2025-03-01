import 'package:gpx/gpx.dart';
import 'dart:math';

class RouteAnalyzer {
  final List<Wpt> points;

  RouteAnalyzer({
    required this.points,
  });

  // This is the only function that's actually being used
  double calculateGradeAdjustment(double gradientPercent) {
    double g = gradientPercent;
    return (-0.000000447713 * pow(g, 4)) +
           (-0.000003068688 * pow(g, 3)) +
           (0.001882643005 * pow(g, 2)) +
           (0.030457306268 * g) +
           1;
  }
} 