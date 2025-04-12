import 'package:flutter/material.dart';
import 'screens/route_analyzer_screen.dart';
import 'screens/pace_calculator_screen.dart';
import 'screens/stairs_calculator_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void main() {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure for web if running on web
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trail Toolbox',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        fontFamily: 'Roboto', // Use Roboto which has good Unicode coverage
        textTheme: Typography.material2018().black.apply(fontFamily: 'Roboto'),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  
  static const List<Widget> _screens = [
    RouteAnalyzerScreen(),
    PaceCalculatorScreen(),
    StairsCalculatorScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map),
            label: 'Race Planner',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed),
            label: 'Pace Calculator',
          ),
          NavigationDestination(
            icon: Icon(Icons.stairs),
            label: 'Stairs Calculator',
          ),
        ],
      ),
    );
  }
}