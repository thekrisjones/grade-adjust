import 'package:flutter/material.dart';
import 'dart:math' show pow;

enum PaceUnit { minPerKm, minPerMile, kph, mph }

// Data class for treadmill session rows
class TreadmillSessionRow {
  String timeMinutes;
  String timeSeconds;
  String pace;
  String gradient;

  TreadmillSessionRow({
    this.timeMinutes = '',
    this.timeSeconds = '',
    this.pace = '',
    this.gradient = '0.0',
  });

  // Get total time in minutes
  double getTotalMinutes() {
    double mins = double.tryParse(timeMinutes) ?? 0.0;
    double secs = double.tryParse(timeSeconds) ?? 0.0;
    return mins + (secs / 60.0);
  }

  // Get time as mm:ss string
  String getTimeString() {
    if (timeMinutes.isEmpty && timeSeconds.isEmpty) return '';
    String mins = timeMinutes.padLeft(2, '0');
    String secs = timeSeconds.padLeft(2, '0');
    return '$mins:$secs';
  }

  // Get pace in seconds per km (always store internally as seconds per km)
  double getPaceSecondsPerKm() {
    return double.tryParse(pace) ?? 0.0;
  }

  // Convert pace value based on selected unit to seconds per km for calculations
  double getPaceSecondsPerKmFromUnit(PaceUnit unit) {
    switch (unit) {
      case PaceUnit.minPerKm:
      case PaceUnit.minPerMile:
        // Parse mm:ss format
        if (pace.contains(':')) {
          List<String> parts = pace.split(':');
          if (parts.length == 2) {
            int minutes = int.tryParse(parts[0]) ?? 0;
            int seconds = int.tryParse(parts[1]) ?? 0;
            double totalSeconds = (minutes * 60.0) + seconds.toDouble();
            if (unit == PaceUnit.minPerMile) {
              totalSeconds =
                  totalSeconds / 1.609344; // Convert mile pace to km pace
            }
            return totalSeconds;
          }
        }
        return 0.0;
      case PaceUnit.kph:
        double speedValue = double.tryParse(pace) ?? 0.0;
        return speedValue > 0 ? 3600.0 / speedValue : 0.0;
      case PaceUnit.mph:
        double speedValue = double.tryParse(pace) ?? 0.0;
        return speedValue > 0 ? 3600.0 / (speedValue * 1.609344) : 0.0;
    }
  }

  // Get gradient as percentage
  double getGradientPercent() {
    return double.tryParse(gradient) ?? 0.0;
  }
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

  // Treadmill session table data
  List<TreadmillSessionRow> treadmillRows = [TreadmillSessionRow()];

  // Controllers for treadmill table cells
  List<List<TextEditingController>> treadmillControllers = [];

  @override
  void initState() {
    super.initState();
    _initializeTreadmillControllers();
  }

  @override
  void dispose() {
    _disposeTreadmillControllers();
    super.dispose();
  }

  void _initializeTreadmillControllers() {
    treadmillControllers.clear();
    for (int i = 0; i < treadmillRows.length; i++) {
      treadmillControllers.add([
        TextEditingController(text: treadmillRows[i].getTimeString()),
        TextEditingController(text: treadmillRows[i].pace),
        TextEditingController(text: treadmillRows[i].gradient),
      ]);
    }
  }

  void _disposeTreadmillControllers() {
    for (var controllerGroup in treadmillControllers) {
      for (var controller in controllerGroup) {
        controller.dispose();
      }
    }
  }

  void _addTreadmillRow() {
    setState(() {
      treadmillRows.add(TreadmillSessionRow());
      treadmillControllers.add([
        TextEditingController(),
        TextEditingController(),
        TextEditingController(text: '0.0'),
      ]);
    });
  }

  void _deleteTreadmillRow(int index) {
    if (treadmillRows.length > 1) {
      setState(() {
        // Dispose controllers for this row
        for (var controller in treadmillControllers[index]) {
          controller.dispose();
        }

        treadmillRows.removeAt(index);
        treadmillControllers.removeAt(index);
      });
    }
  }

  void _updateTreadmillRow(int rowIndex, int fieldIndex, String value) {
    setState(() {
      switch (fieldIndex) {
        case 0:
          // Parse mm:ss format and update timeMinutes/timeSeconds
          if (value.contains(':')) {
            List<String> parts = value.split(':');
            if (parts.length == 2) {
              treadmillRows[rowIndex].timeMinutes = parts[0];
              treadmillRows[rowIndex].timeSeconds = parts[1];
            }
          } else {
            // If no colon, treat as minutes only
            treadmillRows[rowIndex].timeMinutes = value;
            treadmillRows[rowIndex].timeSeconds = '0';
          }
          break;
        case 1:
          treadmillRows[rowIndex].pace = value;
          break;
        case 2:
          treadmillRows[rowIndex].gradient = value;
          break;
      }
    });
  }

  double _calculateTotalDistance() {
    double totalDistance = 0.0;
    for (var row in treadmillRows) {
      double timeInMinutes = row.getTotalMinutes();
      double paceSecondsPerKm = row.getPaceSecondsPerKmFromUnit(selectedUnit);

      if (timeInMinutes > 0 && paceSecondsPerKm > 0) {
        double timeInHours = timeInMinutes / 60.0;
        double speedKmPerHour = 3600.0 / paceSecondsPerKm;
        totalDistance += speedKmPerHour * timeInHours;
      }
    }
    return totalDistance;
  }

  double _calculateTotalClimb() {
    double totalClimb = 0.0;
    for (var row in treadmillRows) {
      double timeInMinutes = row.getTotalMinutes();
      double paceSecondsPerKm = row.getPaceSecondsPerKmFromUnit(selectedUnit);
      double gradientPercent = row.getGradientPercent();

      if (timeInMinutes > 0 && paceSecondsPerKm > 0 && gradientPercent > 0) {
        double timeInHours = timeInMinutes / 60.0;
        double speedKmPerHour = 3600.0 / paceSecondsPerKm;
        double distanceKm = speedKmPerHour * timeInHours;
        double climbMeters = (distanceKm * 1000.0 * gradientPercent) / 100.0;
        totalClimb += climbMeters;
      }
    }
    return totalClimb;
  }

  String getPaceColumnHeader() {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        return 'Pace\n(min/km)';
      case PaceUnit.minPerMile:
        return 'Pace\n(min/mi)';
      case PaceUnit.kph:
        return 'Speed\n(km/h)';
      case PaceUnit.mph:
        return 'Speed\n(mph)';
    }
  }

  String getPaceHintText() {
    switch (selectedUnit) {
      case PaceUnit.minPerKm:
        return '5:00';
      case PaceUnit.minPerMile:
        return '8:00';
      case PaceUnit.kph:
        return '12.0';
      case PaceUnit.mph:
        return '7.5';
    }
  }

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
        return paceSeconds *
            1.609344; // Convert to mile pace (more seconds per mile)
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
        return displayValue /
            1.609344; // Convert back to km pace (fewer seconds per km)
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
    // Updated to 4th-order polynomial as per target algorithm
    return (-0.000000447713 * pow(g, 4)) +
        (-0.000003068688 * pow(g, 3)) +
        (0.001882643005 * pow(g, 2)) +
        (0.030457306268 * g) +
        1.0;
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                label:
                    '${formatPace(gradeAdjustedPaceSeconds)}${getUnitSuffix()}',
                onChanged: (value) =>
                    updateFromGradeAdjustedPace(convertFromDisplayValue(value)),
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
                            updateFromGradeAdjustedPace(
                                gradeAdjustedPaceSeconds - 5);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Decrease by 1.0 speed units (increase seconds)
                            double currentSpeed =
                                convertToDisplayValue(gradeAdjustedPaceSeconds);
                            double newSpeed = currentSpeed - 1.0;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed =
                                newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromGradeAdjustedPace(
                                convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm ||
                              selectedUnit == PaceUnit.minPerMile
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
                            updateFromGradeAdjustedPace(
                                gradeAdjustedPaceSeconds - 1);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Decrease by 0.1 speed units (increase seconds)
                            double currentSpeed =
                                convertToDisplayValue(gradeAdjustedPaceSeconds);
                            double newSpeed = currentSpeed - 0.1;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed =
                                newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromGradeAdjustedPace(
                                convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm ||
                              selectedUnit == PaceUnit.minPerMile
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
                            updateFromGradeAdjustedPace(
                                gradeAdjustedPaceSeconds + 1);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Increase by 0.1 speed units (decrease seconds)
                            double currentSpeed =
                                convertToDisplayValue(gradeAdjustedPaceSeconds);
                            double newSpeed = currentSpeed + 0.1;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed =
                                newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromGradeAdjustedPace(
                                convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm ||
                              selectedUnit == PaceUnit.minPerMile
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
                            updateFromGradeAdjustedPace(
                                gradeAdjustedPaceSeconds + 5);
                            break;
                          case PaceUnit.kph:
                          case PaceUnit.mph:
                            // Increase by 1.0 speed units (decrease seconds)
                            double currentSpeed =
                                convertToDisplayValue(gradeAdjustedPaceSeconds);
                            double newSpeed = currentSpeed + 1.0;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed =
                                newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromGradeAdjustedPace(
                                convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm ||
                              selectedUnit == PaceUnit.minPerMile
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
                onChanged: (value) =>
                    updateFromRealPace(convertFromDisplayValue(value)),
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
                            double currentSpeed =
                                convertToDisplayValue(realPaceSeconds);
                            double newSpeed = currentSpeed - 1.0;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed =
                                newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromRealPace(
                                convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm ||
                              selectedUnit == PaceUnit.minPerMile
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
                            double currentSpeed =
                                convertToDisplayValue(realPaceSeconds);
                            double newSpeed = currentSpeed - 0.1;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed =
                                newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromRealPace(
                                convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm ||
                              selectedUnit == PaceUnit.minPerMile
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
                            double currentSpeed =
                                convertToDisplayValue(realPaceSeconds);
                            double newSpeed = currentSpeed + 0.1;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed =
                                newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromRealPace(
                                convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm ||
                              selectedUnit == PaceUnit.minPerMile
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
                            double currentSpeed =
                                convertToDisplayValue(realPaceSeconds);
                            double newSpeed = currentSpeed + 1.0;
                            // Ensure we don't exceed max speed (min pace)
                            newSpeed =
                                newSpeed.clamp(getMinValue(), getMaxValue());
                            updateFromRealPace(
                                convertFromDisplayValue(newSpeed));
                            break;
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(40, 36),
                    ),
                    child: Text(
                      selectedUnit == PaceUnit.minPerKm ||
                              selectedUnit == PaceUnit.minPerMile
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
                    unit: selectedUnit == PaceUnit.minPerMile ||
                            selectedUnit == PaceUnit.mph
                        ? 'ft/h'
                        : 'm/h',
                    context: context,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Treadmill Session Calculator
              Text(
                'Treadmill Session Calculator',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),

              // Treadmill Table
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Wrap the table structure in a horizontal scroll view (matching route analyzer)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 600),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Table header (matching route analyzer styling)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                    topRight: Radius.circular(8),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 8),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 120,
                                      child: Text(
                                        'Time\n(mm:ss)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: Text(
                                        getPaceColumnHeader(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: Text(
                                        'Gradient\n(%)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        'Actions',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Table rows (matching route analyzer styling)
                              ...List.generate(treadmillRows.length, (index) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: index % 2 == 0
                                        ? Colors.white
                                        : Colors.grey.shade50,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade300,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 8),
                                  child: Row(
                                    children: [
                                      // Time input (mm:ss)
                                      SizedBox(
                                        width: 120,
                                        child: TextField(
                                          controller:
                                              treadmillControllers[index][0],
                                          decoration: const InputDecoration(
                                            hintText: '10:30',
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 4),
                                          ),
                                          keyboardType: TextInputType.text,
                                          onChanged: (value) =>
                                              _updateTreadmillRow(
                                                  index, 0, value),
                                        ),
                                      ),

                                      // Pace input
                                      SizedBox(
                                        width: 120,
                                        child: TextField(
                                          controller:
                                              treadmillControllers[index][1],
                                          decoration: InputDecoration(
                                            hintText: getPaceHintText(),
                                            border: const OutlineInputBorder(),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 4),
                                          ),
                                          keyboardType: TextInputType.text,
                                          onChanged: (value) =>
                                              _updateTreadmillRow(
                                                  index, 1, value),
                                        ),
                                      ),

                                      // Gradient input
                                      SizedBox(
                                        width: 120,
                                        child: TextField(
                                          controller:
                                              treadmillControllers[index][2],
                                          decoration: const InputDecoration(
                                            hintText: '0.0',
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 4),
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (value) =>
                                              _updateTreadmillRow(
                                                  index, 2, value),
                                        ),
                                      ),

                                      // Delete button
                                      SizedBox(
                                        width: 80,
                                        child: IconButton(
                                          onPressed: treadmillRows.length > 1
                                              ? () => _deleteTreadmillRow(index)
                                              : null,
                                          icon: const Icon(Icons.delete),
                                          iconSize: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Add Row Button
                      ElevatedButton.icon(
                        onPressed: _addTreadmillRow,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Row'),
                      ),

                      const SizedBox(height: 16),

                      // Summary Results
                      const Divider(),
                      Text(
                        'Session Summary',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      _buildResultRow(
                        icon: Icons.straighten,
                        label: 'Total Distance',
                        value: _calculateTotalDistance().toStringAsFixed(2),
                        unit: 'km',
                        context: context,
                      ),

                      _buildResultRow(
                        icon: Icons.trending_up,
                        label: 'Total Climb',
                        value: _calculateTotalClimb().toStringAsFixed(0),
                        unit: 'm',
                        context: context,
                      ),
                    ],
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
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
