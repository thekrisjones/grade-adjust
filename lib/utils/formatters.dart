import 'package:flutter/material.dart' show TimeOfDay;

/// Formats pace from seconds to MM:SS string.
String formatPace(double seconds) {
  int mins = (seconds / 60).floor();
  int secs = (seconds % 60).round();
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

/// Formats total time in minutes to a string like "Xh Ym" or "Ym".
String formatTotalTime(double totalMinutes) {
  int hours = totalMinutes ~/ 60;
  int minutes = totalMinutes.round() % 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

/// Formats pace in seconds for axis labels (MM:SS).
String formatPaceAxisLabel(double seconds) {
  if (seconds <= 0) return ""; // Don't show 0:00 or negative
  int mins = (seconds / 60).floor();
  int secs = (seconds % 60).round();
  // Pad seconds to two digits
  return '$mins:${secs.toString().padLeft(2, '0')}';
}

/// Format real time based on start time plus cumulative minutes.
String formatRealTime(double cumulativeMinutes, TimeOfDay? startTime) {
    if (startTime == null) return 'N/A';

    // Convert start time to minutes since midnight
    int startMinutes = startTime.hour * 60 + startTime.minute;

    // Add cumulative time (in minutes)
    int totalMinutes = startMinutes + cumulativeMinutes.round();

    // Handle overflow to next day
    bool isNextDay = false;
    if (totalMinutes >= 24 * 60) {
      totalMinutes %= (24 * 60);
      isNextDay = true;
    }

    // Convert back to hours and minutes
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;

    // Format with leading zeros
    String timeStr = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';

    // Add indicator if time is on the next day
    return isNextDay ? '$timeStr (+1)' : timeStr;
} 