import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for input formatters

class StairsCalculatorScreen extends StatefulWidget {
  const StairsCalculatorScreen({super.key});

  @override
  State<StairsCalculatorScreen> createState() => _StairsCalculatorScreenState();
}

class _StairsCalculatorScreenState extends State<StairsCalculatorScreen> {
  // --- State Variables ---
  bool _isMetric = true; // True for cm, false for inches
  double _stairHeight = 19.0; // cm or inches based on _isMetric
  double _stairLength = 24.0; // cm or inches based on _isMetric
  double _cadence = 100.0; // steps per minute
  int _totalSteps = 1000; // Default value

  final _stepsController = TextEditingController();

  // --- Constants ---
  static const double _cmToInches = 0.393701;
  static const double _inchesToCm = 2.54;
  static const double _metersToFeet = 3.28084;
  static const double _minHeightCm = 10.0;
  static const double _maxHeightCm = 30.0;
  static const double _minLengthCm = 10.0;
  static const double _maxLengthCm = 30.0;
  static const double _minCadence = 0.0;
  static const double _maxCadence = 200.0;

  // --- Lifecycle Methods ---
  @override
  void initState() {
    super.initState();
    _stepsController.text = _totalSteps.toString();
    _stepsController.addListener(_updateTotalSteps);
  }

  @override
  void dispose() {
    _stepsController.removeListener(_updateTotalSteps);
    _stepsController.dispose();
    super.dispose();
  }

  // --- Input Update Handlers ---
  void _updateTotalSteps() {
    setState(() {
      _totalSteps = int.tryParse(_stepsController.text) ?? 0;
      if (_totalSteps < 0) {
        _totalSteps = 0; // Ensure non-negative
        _stepsController.text = '0'; // Correct the input field
        _stepsController.selection = TextSelection.fromPosition(
          TextPosition(offset: _stepsController.text.length),
        );
      }
    });
  }

  void _toggleUnits(int index) {
    setState(() {
      bool newIsMetric = index == 0;
      if (newIsMetric != _isMetric) {
        // Convert state values when switching units
        if (newIsMetric) {
          // Imperial to Metric
          _stairHeight *= _inchesToCm;
          _stairLength *= _inchesToCm;
        } else {
          // Metric to Imperial
          _stairHeight *= _cmToInches;
          _stairLength *= _cmToInches;
        }
        // Clamp values after conversion to ensure they stay within bounds if necessary
        _stairHeight = _stairHeight.clamp(_getSliderMin(true), _getSliderMax(true));
        _stairLength = _stairLength.clamp(_getSliderMin(false), _getSliderMax(false));

        _isMetric = newIsMetric;
      }
    });
  }

  // --- Calculation Helpers ---

  // Returns height in CM regardless of current unit selection
  double _getHeightInCm() {
    return _isMetric ? _stairHeight : _stairHeight * _inchesToCm;
  }

  // Returns length in CM regardless of current unit selection
  double _getLengthInCm() {
    return _isMetric ? _stairLength : _stairLength * _inchesToCm;
  }

  double calculateVerticalSpeed() {
    double heightCm = _getHeightInCm();
    if (heightCm <= 0 || _cadence <= 0) return 0;

    // Vertical speed (m/h) = (cadence * 60) * (stair_height_cm / 100)
    double verticalSpeedMetersPerHour = (_cadence * 60.0) * (heightCm / 100.0);

    if (!_isMetric) {
      // Convert m/h to ft/h
      return verticalSpeedMetersPerHour * _metersToFeet;
    } else {
      return verticalSpeedMetersPerHour;
    }
  }

  double calculateTotalDistance() {
    double lengthCm = _getLengthInCm();
    if (lengthCm <= 0 || _totalSteps <= 0) return 0;

    // Total distance (m) = total_steps * (step_length_cm / 100)
    double totalDistanceMeters = _totalSteps * (lengthCm / 100.0);

    if (!_isMetric) {
      // Convert m to ft
      return totalDistanceMeters * _metersToFeet;
    } else {
      return totalDistanceMeters;
    }
  }

  double calculateTotalAscent() {
    double heightCm = _getHeightInCm();
    if (heightCm <= 0 || _totalSteps <= 0) return 0;

    // Total ascent (m) = total_steps * (step_height_cm / 100)
    double totalAscentMeters = _totalSteps * (heightCm / 100.0);

    if (!_isMetric) {
      // Convert m to ft
      return totalAscentMeters * _metersToFeet;
    } else {
      return totalAscentMeters;
    }
  }

  // --- UI Helpers ---
  double _getSliderMin(bool isHeight) {
    double minCm = isHeight ? _minHeightCm : _minLengthCm;
    return _isMetric ? minCm : minCm * _cmToInches;
  }

  double _getSliderMax(bool isHeight) {
    double maxCm = isHeight ? _maxHeightCm : _maxLengthCm;
    return _isMetric ? maxCm : maxCm * _cmToInches;
  }

  String _getDimensionUnit() {
    return _isMetric ? 'cm' : 'in';
  }

  String _getDistanceUnit() {
    return _isMetric ? 'm' : 'ft';
  }

  String _getSpeedUnit() {
    return _isMetric ? 'm/h' : 'ft/h';
  }

  @override
  Widget build(BuildContext context) {
    // Calculate slider values based on current unit
    double heightSliderValue = _stairHeight;
    double lengthSliderValue = _stairLength;
    double heightMin = _getSliderMin(true);
    double heightMax = _getSliderMax(true);
    double lengthMin = _getSliderMin(false);
    double lengthMax = _getSliderMax(false);
    String dimensionUnit = _getDimensionUnit();
    String distanceUnit = _getDistanceUnit();
    String speedUnit = _getSpeedUnit();

    return Scaffold(
      appBar: AppBar(title: const Text('Stairs Calculator')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unit Selection
              Center(
                child: ToggleButtons(
                  isSelected: [_isMetric, !_isMetric],
                  onPressed: _toggleUnits,
                  borderRadius: BorderRadius.circular(8.0),
                  constraints: const BoxConstraints(minHeight: 40.0, minWidth: 80.0),
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Metric (cm)')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Imperial (in)')),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Stair Height
              Text(
                'Stair Height: ${heightSliderValue.toStringAsFixed(1)} $dimensionUnit',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: heightSliderValue.clamp(heightMin, heightMax), // Clamp value to be safe
                min: heightMin,
                max: heightMax,
                label: '${heightSliderValue.toStringAsFixed(1)} $dimensionUnit',
                onChanged: (value) {
                  setState(() {
                    _stairHeight = value;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Stair Length
              Text(
                'Stair Length: ${lengthSliderValue.toStringAsFixed(1)} $dimensionUnit',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: lengthSliderValue.clamp(lengthMin, lengthMax), // Clamp value to be safe
                min: lengthMin,
                max: lengthMax,
                label: '${lengthSliderValue.toStringAsFixed(1)} $dimensionUnit',
                onChanged: (value) {
                  setState(() {
                    _stairLength = value;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Cadence
              Text(
                'Cadence: ${_cadence.toStringAsFixed(0)} spm',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _cadence,
                min: _minCadence,
                max: _maxCadence,
                divisions: (_maxCadence - _minCadence).toInt(),
                label: '${_cadence.toStringAsFixed(0)} spm',
                onChanged: (value) {
                  setState(() {
                    _cadence = value;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Total Steps
              TextField(
                controller: _stepsController,
                decoration: const InputDecoration(
                  labelText: 'Total Steps',
                  border: OutlineInputBorder(),
                  hintText: 'Enter number of steps',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly // Allow only digits
                ],
              ),
              const SizedBox(height: 32),

              // Results Section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildResultRow(
                        icon: Icons.speed,
                        label: 'Vertical Speed',
                        value: calculateVerticalSpeed().toStringAsFixed(0),
                        unit: speedUnit,
                        context: context,
                      ),
                      const Divider(),
                      _buildResultRow(
                        icon: Icons.straighten,
                        label: 'Total Distance',
                        value: calculateTotalDistance().toStringAsFixed(1),
                        unit: distanceUnit,
                        context: context,
                      ),
                      const Divider(),
                      _buildResultRow(
                        icon: Icons.trending_up,
                        label: 'Total Ascent',
                        value: calculateTotalAscent().toStringAsFixed(1),
                        unit: distanceUnit,
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

  // Helper to build result rows for consistent styling
  Widget _buildResultRow({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required BuildContext context,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
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