// Pace-related constants
const double minPaceSeconds = 165; // 2:45
const double maxPaceSeconds = 900; // 15:00
const double minSegmentPace = 120; // 2:00 min/km

// Pace chart Y-axis limits (clamped)
const double defaultMinPaceChart = 90; // 1:30 min/km
const double defaultMaxPaceChart = 1200; // 20:00 min/km

// Earth radius for distance calculations
const double earthRadius = 6371000; // meters

// Max gradient for color scaling and clamping
const double maxGradientPercent = 25.0;
const double clampGradientPercent = 45.0;

// Smoothing window defaults
const double gradientSmoothingDistanceMeters = 100.0;
const int gradientSmoothingMinWindowSize = 3;
const int gradientSmoothingMaxWindowSize = 15;
const double paceSmoothingDistanceMeters = 200.0;
const int paceSmoothingMinWindowSize = 3;
const int paceSmoothingMaxWindowSize = 21;

// Waypoint proximity threshold
const double waypointMaxDistanceMeters = 100.0;

// Short segment threshold for gradient calculation
const double minSegmentLengthMeters = 1.0; 