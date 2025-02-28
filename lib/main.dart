import 'package:flutter/material.dart';
import 'package:gpx/gpx.dart';
import 'package:file_picker/file_picker.dart';
import 'screens/route_analyzer_screen.dart';

void main() {
  runApp(const TrailRunningAnalyzerApp());
}

class TrailRunningAnalyzerApp extends StatelessWidget {
  const TrailRunningAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trail Running Analyzer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const RouteAnalyzerScreen(),
    );
  }
} 