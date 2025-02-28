import 'package:gpx/gpx.dart';

class RouteAnalyzer {
  final List<Wpt> points;
  final Map<PathType, double> pathTypeFactors;
  final GradeModel gradeModel;

  RouteAnalyzer({
    required this.points,
    required this.pathTypeFactors,
    required this.gradeModel,
  });

  double calculateGradeAdjustedPace(double baselinePace, double grade) {
    return gradeModel.adjustPace(baselinePace, grade);
  }

}

enum PathType {
  singleTrack,
  doubleTrack,
  road,
  technical
}

class GradeModel {
  // Coefficients for grade adjustment
  final double uphillFactor;
  final double downhillFactor;

  GradeModel({
    this.uphillFactor = 1.74,   // Default from Minetti et al.
    this.downhillFactor = 1.26, // These can be user-modified
  });

  double adjustPace(double baselinePace, double grade) {
    if (grade > 0) {
      return baselinePace * (1 + (uphillFactor * grade));
    } else {
      return baselinePace * (1 + (downhillFactor * grade.abs()));
    }
  }
} 