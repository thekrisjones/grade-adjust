import 'dart:math' show sin, cos, sqrt, atan2, pow, exp, pi, min, max;
import 'package:fl_chart/fl_chart.dart' show FlSpot;
import 'constants.dart'; // Import constants

/// Calculates the distance between two lat/lon coordinates using the Haversine formula.
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  // Convert degrees to radians
  double lat1Rad = lat1 * (pi / 180.0); // Use 180.0 for double division
  double lon1Rad = lon1 * (pi / 180.0);
  double lat2Rad = lat2 * (pi / 180.0);
  double lon2Rad = lon2 * (pi / 180.0);

  // Differences in coordinates
  double dLat = lat2Rad - lat1Rad;
  double dLon = lon2Rad - lon1Rad;

  // Haversine formula
  double a = sin(dLat / 2.0) * sin(dLat / 2.0) + // Use 2.0 for double division
             cos(lat1Rad) * cos(lat2Rad) *
             sin(dLon / 2.0) * sin(dLon / 2.0); // Use 2.0 for double division
  // atan2 and sqrt return double, ensure multiplication results in double
  double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a)); // Use 2.0, 1.0

  // Ensure the final result is double
  return (earthRadius * c); // Multiplication of doubles should be double
}

/// Calculates the grade adjustment factor based on gradient percentage.
/// Uses a polynomial approximation.
double calculateGradeAdjustment(double gradientPercent) {
  // Clamp gradient to ±45%
  double g = gradientPercent.clamp(-clampGradientPercent, clampGradientPercent);
  return (-0.0000000005968925381 * pow(g, 5)) +
         (-0.000000366663628576468 * pow(g, 4)) +
         (-0.0000016677964832213 * pow(g, 3)) +
         (0.00182471253566879 * pow(g, 2)) +
         (0.0301350193447792 * g) +
         0.99758437262606;
}

/// Calculates gradients between elevation points.
List<double> calculateGradients(List<FlSpot> points) {
  List<double> grads = [];
  if (points.length < 2) {
    return List.filled(points.length, 0.0); // Return zeros if not enough points
  }

  for (int i = 1; i < points.length; i++) {
    final dx = (points[i].x - points[i - 1].x) * 1000; // Convert km to meters
    final dy = points[i].y - points[i - 1].y;

    // Skip extremely short segments that might cause extreme gradients
    if (dx < minSegmentLengthMeters) {
      // Use previous gradient or 0 if first valid segment
      grads.add(grads.isEmpty ? 0.0 : grads.last);
      continue;
    }

    // Calculate gradient percentage
    final gradient = (dy / dx) * 100;

    // Clamp extreme values that might be due to GPS errors
    final clampedGradient = gradient.clamp(-clampGradientPercent, clampGradientPercent);
    grads.add(clampedGradient);
  }

  // Add first gradient to start of list to match points length
  if (grads.isNotEmpty) {
    grads.insert(0, grads[0]);
  } else if (points.isNotEmpty) {
    // Handle case where all segments were too short
    grads.add(0.0);
  }

  // Ensure the output list has the same length as the input points list
  while (grads.length < points.length) {
      grads.add(grads.isNotEmpty ? grads.last : 0.0);
  }
   if (grads.length > points.length) {
       grads = grads.sublist(0, points.length);
   }


  return grads;
}

/// Smooths gradient data using a weighted moving average (Gaussian-like).
List<double> smoothGradients(List<double> gradients, int windowSize) {
  if (gradients.isEmpty || windowSize <= 1) return gradients;

  List<double> smoothed = List.filled(gradients.length, 0);

  for (int i = 0; i < gradients.length; i++) {
    double sum = 0;
    double weightSum = 0;

    // Calculate window bounds
    int windowStart = max(0, i - windowSize ~/ 2);
    int windowEnd = min(gradients.length, i + windowSize ~/ 2 + 1);

    // Calculate weighted average based on distance from center point
    for (int j = windowStart; j < windowEnd; j++) {
      // Use gaussian-like weighting
      double distance = (j - i).abs().toDouble();
      // Adjust sigma based on window size for better smoothing effect
      double sigma = max(1.0, windowSize / 4.0);
      double weight = exp(-distance * distance / (2 * sigma * sigma));

      sum += gradients[j] * weight;
      weightSum += weight;
    }

    if (weightSum > 0) {
      smoothed[i] = sum / weightSum;
    } else {
      // Fallback if weightSum is zero (shouldn't happen with valid windowSize)
      smoothed[i] = gradients[i];
    }
  }

  return smoothed;
}

/// Smooths FlSpot data using a simple moving average.
List<FlSpot> smoothData(List<FlSpot> points, int windowSize) {
    if (points.length < windowSize || windowSize <= 1) {
      return points; // Not enough data to smooth or window too small
    }

    List<FlSpot> smoothedPoints = [];
    int halfWindow = windowSize ~/ 2;

    // Handle the beginning points (use smaller window or copy directly)
    for (int i = 0; i < halfWindow; i++) {
       smoothedPoints.add(points[i]); // Or calculate average with available points
    }

    // Apply moving average for the main part
    for (int i = halfWindow; i < points.length - halfWindow; i++) {
      double sumY = 0;
      for (int j = i - halfWindow; j <= i + halfWindow; j++) {
        sumY += points[j].y;
      }
      smoothedPoints.add(FlSpot(points[i].x, sumY / windowSize));
    }

    // Handle the ending points (use smaller window or copy directly)
     for (int i = points.length - halfWindow; i < points.length; i++) {
       smoothedPoints.add(points[i]); // Or calculate average with available points
     }

    // Ensure output length matches input length
    if (smoothedPoints.length != points.length) {
        // This might happen if window calculation logic needs adjustment
        // For now, return original points as a fallback
        print("Warning: Smoothed data length mismatch. Returning original data.");
        return points;
    }


    return smoothedPoints;
}

/// Calculates the grade-adjusted distance for a segment.
double calculateSegmentGradeAdjustedDistance(double startDistance, double endDistance, List<FlSpot> elevationPoints, List<double> smoothedGradients) {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty || startDistance >= endDistance) {
        return max(0, endDistance - startDistance); // Return geometric distance or 0
    }

    double totalAdjustedDistance = 0;
    int startIdx = -1, endIdx = -1;

    // Find the indices in elevationPoints corresponding to start and end distances
    for (int i = 0; i < elevationPoints.length; i++) {
        if (startIdx == -1 && elevationPoints[i].x >= startDistance) {
            startIdx = i;
        }
        if (elevationPoints[i].x >= endDistance) {
            endIdx = i;
            break;
        }
    }

    // If endDistance is beyond the last point, use the last index
    if (endIdx == -1) {
        endIdx = elevationPoints.length - 1;
    }
    // If startDistance is beyond the last point, return 0
    if (startIdx == -1) {
        startIdx = elevationPoints.length -1; // Will result in 0 distance calculation below
    }


    // Iterate over the relevant segments within the range
    double currentPos = startDistance;
    for (int i = startIdx; i <= endIdx; i++) {
        double pointDist = elevationPoints[i].x;
        double prevPointDist = (i > 0) ? elevationPoints[i-1].x : 0;

        // Determine the actual start and end points for this segment calculation
        double segStart = max(currentPos, prevPointDist);
        double segEnd = min(pointDist, endDistance);

        if (segEnd > segStart) {
            double segmentDistance = segEnd - segStart;

            // Get gradient for this segment (use gradient at the end of the small segment)
            int gradientIndex = min(i, smoothedGradients.length - 1);
            double gradientPercent = gradientIndex >= 0 ? smoothedGradients[gradientIndex] : 0;

            // Calculate grade adjustment factor
            double adjustment = calculateGradeAdjustment(gradientPercent);

            // Apply adjustment to segment distance
            // Ensure adjustment doesn't result in negative distance
            totalAdjustedDistance += segmentDistance * max(0, adjustment);

            // Move current position forward
            currentPos = segEnd;
        }

         // Break if we've processed the full distance
        if (currentPos >= endDistance) break;
    }

    return totalAdjustedDistance;
}

/// Calculates the base grade-adjusted pace for a segment in seconds/km.
double getSegmentBaseGradeAdjustedPace(double startDistance, double endDistance, List<FlSpot> elevationPoints, List<double> smoothedGradients, double basePaceSelected) {
    if (elevationPoints.isEmpty || smoothedGradients.isEmpty || startDistance >= endDistance) return basePaceSelected;

    double weightedPaceSum = 0;
    double totalDistance = 0;
    int startIdx = -1, endIdx = -1;

     // Find the indices in elevationPoints corresponding to start and end distances
    for (int i = 0; i < elevationPoints.length; i++) {
        if (startIdx == -1 && elevationPoints[i].x >= startDistance) {
            startIdx = i;
        }
        if (elevationPoints[i].x >= endDistance) {
            endIdx = i;
            break;
        }
    }

    // If endDistance is beyond the last point, use the last index
    if (endIdx == -1) endIdx = elevationPoints.length - 1;
    // If startDistance is beyond the last point, return base pace
    if (startIdx == -1) return basePaceSelected;


    double currentPos = startDistance;
    for (int i = startIdx; i <= endIdx; i++) {
        double pointDist = elevationPoints[i].x;
        double prevPointDist = (i > 0) ? elevationPoints[i-1].x : 0;

        // Determine the actual start and end points for this segment calculation
        double segStart = max(currentPos, prevPointDist);
        double segEnd = min(pointDist, endDistance);


        if (segEnd > segStart) {
            double segmentDistance = segEnd - segStart;

            // Get gradient for this segment (use gradient at the end of the small segment)
            int gradientIndex = min(i, smoothedGradients.length - 1);
            double gradientPercent = gradientIndex >= 0 ? smoothedGradients[gradientIndex] : 0;

             // Calculate grade adjustment factor
            double adjustment = calculateGradeAdjustment(gradientPercent);
            double segmentPace = basePaceSelected * adjustment;
            // Apply min segment pace constraint if needed (optional here, applied later)
            // segmentPace = max(segmentPace, minSegmentPace);

            weightedPaceSum += segmentPace * segmentDistance;
            totalDistance += segmentDistance;

             // Move current position forward
            currentPos = segEnd;
        }
         // Break if we've processed the full distance
        if (currentPos >= endDistance) break;
    }


    if (totalDistance > 0) {
      return weightedPaceSum / totalDistance;
    } else {
      // Handle zero distance case: return base pace or pace at the start point
       int startGradientIndex = min(startIdx, smoothedGradients.length - 1);
       if (startGradientIndex >= 0) {
          double startAdjustment = calculateGradeAdjustment(smoothedGradients[startGradientIndex]);
          return basePaceSelected * startAdjustment;
       }
       return basePaceSelected;
    }
  } 