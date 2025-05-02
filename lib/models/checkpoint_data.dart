import 'dart:math' show pow; // Needed for copy() which might use pow implicitly if fields change

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
  // Fluid calculation fields
  int legFluidUnits = 0;
  int cumulativeFluidUnits = 0;

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
    cp.legFluidUnits = legFluidUnits;
    cp.cumulativeFluidUnits = cumulativeFluidUnits;
    return cp;
  }
} 