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
  static const double metersToFeet = 3.28084;

  String formatPace(double seconds) {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        int totalSecondsRounded = seconds.round();
        int mins = totalSecondsRounded ~/ 60;
        int secs = totalSecondsRounded % 60;
        return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      case PaceUnit.minPerMile:
        double mileSeconds = seconds * 1.609344;
        int totalMileSecondsRounded = mileSeconds.round();
        int mins = totalMileSecondsRounded ~/ 60;
        int secs = totalMileSecondsRounded % 60;
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
    // Clamp gradient to ±35%
    double g = gradientPercent.clamp(-35.0, 35.0);
    return (-0.0000000005968925381 * pow(g, 5)) +
           (-0.000000366663628576468 * pow(g, 4)) +
           (-0.0000016677964832213 * pow(g, 3)) +
           (0.00182471253566879 * pow(g, 2)) +
           (0.0301350193447792 * g) +
           0.99758437262606;
  }

  void updateFromRealPace(double newRealPaceSeconds) {
    setState(() {
      if (newRealPaceSeconds < 120.0) {
        newRealPaceSeconds = 120.0;
      } else if (newRealPaceSeconds > 720.0) {
        newRealPaceSeconds = 720.0;
      }
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
      if (newGradeAdjustedPaceSeconds < 120.0) {
        newGradeAdjustedPaceSeconds = 120.0;
      } else if (newGradeAdjustedPaceSeconds > 720.0) {
        newGradeAdjustedPaceSeconds = 720.0;
      }
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
      if (newGradient < -35.0) {
        newGradient = -35.0;
      } else if (newGradient > 35.0) {
        newGradient = 35.0;
      }
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

  double calculateVerticalPace() {
    // Calculate horizontal speed in km/h
    double speedKmPerHour = secsPerHour / realPaceSeconds;
    
    // Calculate vertical speed in m/h
    double verticalPaceMetersPerHour = speedKmPerHour * gradient * 10;

    // Convert to ft/h if necessary
    if (selectedUnit == PaceUnit.minPerMile || selectedUnit == PaceUnit.mph) {
      double verticalPaceFeetPerHour = verticalPaceMetersPerHour * metersToFeet;
      return verticalPaceFeetPerHour.roundToDouble();
    } else {
      return verticalPaceMetersPerHour.roundToDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pace Calculator')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unit selection buttons
              Center(
                child: Wrap(
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
              ),
              const SizedBox(height: 12),
              
              Text(
                'Gradient: ${gradient.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: gradient,
                min: -35.0,
                max: 35.0,
                divisions: 70,
                label: '${gradient.toStringAsFixed(1)}%',
                onChanged: updateGradient,
              ),
              // Fine-tuning buttons for gradient
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Decrease by 5%, but not below minimum
                        updateGradient(gradient - 5.0);
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: const Text('-5%', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Decrease by 1%, but not below minimum
                        updateGradient(gradient - 1.0);
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: const Text('-1%', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Increase by 1%, but not above maximum
                        updateGradient(gradient + 1.0);
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: const Text('+1%', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Increase by 5%, but not above maximum
                        updateGradient(gradient + 5.0);
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: const Text('+5%', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
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
              // Fine-tuning buttons for grade adjusted pace
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Adjust based on unit type
                        switch (selectedUnit) {
                          case PaceUnit.minPerKm:
                          case PaceUnit.minPerMile:
                            // Decrease by 5 seconds
                            updateFromGradeAdjustedPace(gradeAdjustedPaceSeconds - 5);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Decrease by 1.0 speed units (increase seconds)
                            double currentSpeed = convertToDisplayValue(gradeAdjustedPaceSeconds);
                            double newSpeed = currentSpeed - 1.0;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed = newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromGradeAdjustedPace(convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm || selectedUnit == PaceUnit.minPerMile
                          ? '-5s'
                          : '-1.0',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Adjust based on unit type
                        switch (selectedUnit) {
                          case PaceUnit.minPerKm:
                          case PaceUnit.minPerMile:
                            // Decrease by 1 second
                            updateFromGradeAdjustedPace(gradeAdjustedPaceSeconds - 1);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Decrease by 0.1 speed units (increase seconds)
                            double currentSpeed = convertToDisplayValue(gradeAdjustedPaceSeconds);
                            double newSpeed = currentSpeed - 0.1;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed = newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromGradeAdjustedPace(convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm || selectedUnit == PaceUnit.minPerMile
                          ? '-1s'
                          : '-0.1',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Adjust based on unit type
                        switch (selectedUnit) {
                          case PaceUnit.minPerKm:
                          case PaceUnit.minPerMile:
                            // Increase by 1 second
                            updateFromGradeAdjustedPace(gradeAdjustedPaceSeconds + 1);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Increase by 0.1 speed units (decrease seconds)
                            double currentSpeed = convertToDisplayValue(gradeAdjustedPaceSeconds);
                            double newSpeed = currentSpeed + 0.1;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed = newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromGradeAdjustedPace(convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm || selectedUnit == PaceUnit.minPerMile
                          ? '+1s'
                          : '+0.1',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Adjust based on unit type
                        switch (selectedUnit) {
                          case PaceUnit.minPerKm:
                          case PaceUnit.minPerMile:
                            // Increase by 5 seconds
                            updateFromGradeAdjustedPace(gradeAdjustedPaceSeconds + 5);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Increase by 1.0 speed units (decrease seconds)
                            double currentSpeed = convertToDisplayValue(gradeAdjustedPaceSeconds);
                            double newSpeed = currentSpeed + 1.0;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed = newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromGradeAdjustedPace(convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm || selectedUnit == PaceUnit.minPerMile
                          ? '+5s'
                          : '+1.0',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
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
              // Fine-tuning buttons for real pace
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Adjust based on unit type
                        switch (selectedUnit) {
                          case PaceUnit.minPerKm:
                          case PaceUnit.minPerMile:
                            // Decrease by 5 seconds
                            updateFromRealPace(realPaceSeconds - 5);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Decrease by 1.0 speed units (increase seconds)
                            double currentSpeed = convertToDisplayValue(realPaceSeconds);
                            double newSpeed = currentSpeed - 1.0;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed = newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromRealPace(convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm || selectedUnit == PaceUnit.minPerMile
                          ? '-5s'
                          : '-1.0',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Adjust based on unit type
                        switch (selectedUnit) {
                          case PaceUnit.minPerKm:
                          case PaceUnit.minPerMile:
                            // Decrease by 1 second
                            updateFromRealPace(realPaceSeconds - 1);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Decrease by 0.1 speed units (increase seconds)
                            double currentSpeed = convertToDisplayValue(realPaceSeconds);
                            double newSpeed = currentSpeed - 0.1;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed = newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromRealPace(convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm || selectedUnit == PaceUnit.minPerMile
                          ? '-1s'
                          : '-0.1',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Adjust based on unit type
                        switch (selectedUnit) {
                          case PaceUnit.minPerKm:
                          case PaceUnit.minPerMile:
                            // Increase by 1 second
                            updateFromRealPace(realPaceSeconds + 1);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Increase by 0.1 speed units (decrease seconds)
                            double currentSpeed = convertToDisplayValue(realPaceSeconds);
                            double newSpeed = currentSpeed + 0.1;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed = newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromRealPace(convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm || selectedUnit == PaceUnit.minPerMile
                          ? '+1s'
                          : '+0.1',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Adjust based on unit type
                        switch (selectedUnit) {
                          case PaceUnit.minPerKm:
                          case PaceUnit.minPerMile:
                            // Increase by 5 seconds
                            updateFromRealPace(realPaceSeconds + 5);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Increase by 1.0 speed units (decrease seconds)
                            double currentSpeed = convertToDisplayValue(realPaceSeconds);
                            double newSpeed = currentSpeed + 1.0;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed = newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromRealPace(convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm || selectedUnit == PaceUnit.minPerMile
                          ? '+5s'
                          : '+1.0',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Results Display (using Card and _buildResultRow for consistency)
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildResultRow(
                    icon: Icons.trending_up,
                    label: 'Vertical Pace',
                    value: calculateVerticalPace().toStringAsFixed(0),
                    unit: selectedUnit == PaceUnit.minPerMile || selectedUnit == PaceUnit.mph ? 'ft/h' : 'm/h',
                    context: context,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to build result rows for consistent styling (copied from Stairs)
  Widget _buildResultRow({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required BuildContext context,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Text('$label:', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text(
            '$value $unit',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
} 