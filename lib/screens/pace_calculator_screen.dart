import 'package:flutter/material.dart';
import 'dart:math' show pow;

enum PaceUnit {
  minPerKm,
  minPerMile,
  kph,
  mph
}

class PaceCalculatorScreen extends StatefulWidget {
  const PaceCalculatorScreen({super.key});

  @override
  State<PaceCalculatorScreen> createState() => _PaceCalculatorScreenState();
}

class _PaceCalculatorScreenState extends State<PaceCalculatorScreen> {
  double gradient = 0.0; // -20 to +20
  double realPaceSeconds = 300.0; // 5:00 min/km
  double gradeAdjustedPaceSeconds = 300.0; // Will be calculated
  PaceUnit selectedUnit = PaceUnit.minPerKm;

  // Conversion constants
  static const double kmToMiles = 0.621371;
  static const double secsPerHour = 3600;

  String formatPace(double seconds) {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        int mins = (seconds / 60).floor();
        int secs = (seconds % 60).round();
        return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      case PaceUnit.minPerMile:
        double mileSeconds = seconds * 1.609344; // Convert km pace to mile pace (mile is longer, so more seconds per mile)
        int mins = (mileSeconds / 60).floor();
        int secs = (mileSeconds % 60).round();
        return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      case PaceUnit.kph:
        double speed = secsPerHour / seconds;
        return speed.toStringAsFixed(1);
      case PaceUnit.mph:
        double speed = (secsPerHour / seconds) * kmToMiles;
        return speed.toStringAsFixed(1);
    }
  }

  String getUnitSuffix() {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        return '/km';
      case PaceUnit.minPerMile:
        return '/mi';
      case PaceUnit.kph:
        return ' kph';
      case PaceUnit.mph:
        return ' mph';
    }
  }

  double convertToDisplayValue(double paceSeconds) {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        return paceSeconds;
      case PaceUnit.minPerMile:
        return paceSeconds * 1.609344; // Convert to mile pace (more seconds per mile)
      case PaceUnit.kph:
        return secsPerHour / paceSeconds;
      case PaceUnit.mph:
        return (secsPerHour / paceSeconds) * kmToMiles;
    }
  }

  double convertFromDisplayValue(double displayValue) {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        return displayValue;
      case PaceUnit.minPerMile:
        return displayValue / 1.609344; // Convert back to km pace (fewer seconds per km)
      case PaceUnit.kph:
        return secsPerHour / displayValue;
      case PaceUnit.mph:
        return secsPerHour / (displayValue / kmToMiles);
    }
  }

  double getMinValue() {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        return 120.0; // 2:00 min/km
      case PaceUnit.minPerMile:
        return 120.0 * 1.609344; // ~3:13 min/mile
      case PaceUnit.kph:
        return 5.0; // equivalent to 12:00 min/km
      case PaceUnit.mph:
        return 3.1; // equivalent to 12:00 min/km
    }
  }

  double getMaxValue() {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        return 720.0; // 12:00 min/km
      case PaceUnit.minPerMile:
        return 720.0 * 1.609344; // ~19:19 min/mile
      case PaceUnit.kph:
        return 30.0; // equivalent to 2:00 min/km
      case PaceUnit.mph:
        return 18.6; // equivalent to 2:00 min/km
    }
  }

  double calculateGradeAdjustment(double gradientPercent) {
    double g = gradientPercent;
    return (-0.000000447713 * pow(g, 4)) +
           (-0.000003068688 * pow(g, 3)) +
           (0.001882643005 * pow(g, 2)) +
           (0.030457306268 * g) +
           1;
  }

  void updateFromRealPace(double newRealPaceSeconds) {
    setState(() {
      double adjustment = calculateGradeAdjustment(gradient);
      double newGradeAdjustedPaceSeconds = newRealPaceSeconds / adjustment;
      
      // Check if grade adjusted pace would be out of bounds
      if (newGradeAdjustedPaceSeconds < 120.0) {
        // If too fast, set grade adjusted pace to minimum and recalculate real pace
        gradeAdjustedPaceSeconds = 120.0;
        realPaceSeconds = 120.0 * adjustment;
      } else if (newGradeAdjustedPaceSeconds > 720.0) {
        // If too slow, set grade adjusted pace to maximum and recalculate real pace
        gradeAdjustedPaceSeconds = 720.0;
        realPaceSeconds = 720.0 * adjustment;
      } else {
        // Within bounds, use the provided values
        realPaceSeconds = newRealPaceSeconds;
        gradeAdjustedPaceSeconds = newGradeAdjustedPaceSeconds;
      }
    });
  }

  void updateFromGradeAdjustedPace(double newGradeAdjustedPaceSeconds) {
    setState(() {
      double adjustment = calculateGradeAdjustment(gradient);
      double newRealPaceSeconds = newGradeAdjustedPaceSeconds * adjustment;
      
      // Check if real pace would be out of bounds
      if (newRealPaceSeconds < 120.0) {
        // If too fast, set real pace to minimum and recalculate grade adjusted pace
        realPaceSeconds = 120.0;
        gradeAdjustedPaceSeconds = 120.0 / adjustment;
      } else if (newRealPaceSeconds > 720.0) {
        // If too slow, set real pace to maximum and recalculate grade adjusted pace
        realPaceSeconds = 720.0;
        gradeAdjustedPaceSeconds = 720.0 / adjustment;
      } else {
        // Within bounds, use the provided values
        gradeAdjustedPaceSeconds = newGradeAdjustedPaceSeconds;
        realPaceSeconds = newRealPaceSeconds;
      }
    });
  }

  void updateGradient(double newGradient) {
    setState(() {
      gradient = newGradient;
      double adjustment = calculateGradeAdjustment(newGradient);
      double newRealPaceSeconds = gradeAdjustedPaceSeconds * adjustment;
      
      // Check if the new gradient would push real pace out of bounds
      if (newRealPaceSeconds < 120.0) {
        // If too fast, set real pace to minimum and recalculate grade adjusted pace
        realPaceSeconds = 120.0;
        gradeAdjustedPaceSeconds = 120.0 / adjustment;
      } else if (newRealPaceSeconds > 720.0) {
        // If too slow, set real pace to maximum and recalculate grade adjusted pace
        realPaceSeconds = 720.0;
        gradeAdjustedPaceSeconds = 720.0 / adjustment;
      } else {
        // Within bounds, use the calculated value
        realPaceSeconds = newRealPaceSeconds;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pace Calculator')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unit selection buttons
            Wrap(
              spacing: 8.0,
              children: [
                for (var unit in PaceUnit.values)
                  FilterChip(
                    label: Text(
                      switch (unit) {
                        PaceUnit.minPerKm => 'min/km',
                        PaceUnit.minPerMile => 'min/mi',
                        PaceUnit.kph => 'km/h',
                        PaceUnit.mph => 'mph',
                      },
                    ),
                    selected: selectedUnit == unit,
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() {
                          selectedUnit = unit;
                        });
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),
            
            Text(
              'Gradient: ${gradient.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: gradient,
              min: -20.0,
              max: 20.0,
              divisions: 40,
              label: '${gradient.toStringAsFixed(1)}%',
              onChanged: updateGradient,
            ),
            const SizedBox(height: 32),
            
            Text(
              'Grade Adjusted Pace: ${formatPace(gradeAdjustedPaceSeconds)}${getUnitSuffix()}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: convertToDisplayValue(gradeAdjustedPaceSeconds),
              min: getMinValue(),
              max: getMaxValue(),
              label: '${formatPace(gradeAdjustedPaceSeconds)}${getUnitSuffix()}',
              onChanged: (value) => updateFromGradeAdjustedPace(convertFromDisplayValue(value)),
            ),
            const SizedBox(height: 32),
            
            Text(
              'Real Pace: ${formatPace(realPaceSeconds)}${getUnitSuffix()}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: convertToDisplayValue(realPaceSeconds),
              min: getMinValue(),
              max: getMaxValue(),
              label: '${formatPace(realPaceSeconds)}${getUnitSuffix()}',
              onChanged: (value) => updateFromRealPace(convertFromDisplayValue(value)),
            ),
          ],
        ),
      ),
    );
  }
} 