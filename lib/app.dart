import 'package:flutter/material.dart';
import 'screens/hospital_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signals_screen.dart';

/// Main Application widget with Material 3 styling and 3-tab navigation.
class AmbulancePriorityApp extends StatefulWidget {
  const AmbulancePriorityApp({super.key});

  @override
  State<AmbulancePriorityApp> createState() => _AmbulancePriorityAppState();
}

class _AmbulancePriorityAppState extends State<AmbulancePriorityApp> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    MapScreen(),
    SignalsScreen(),
    HospitalScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ambulance Priority LoRa System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
        ),
      ),
      themeMode: ThemeMode.system,
      home: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.emergency_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Ambulance Priority',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          actions: [
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) {
            setState(() {
              _currentIndex = idx;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.traffic_outlined),
              selectedIcon: Icon(Icons.traffic_rounded),
              label: 'Signals',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_hospital_outlined),
              selectedIcon: Icon(Icons.local_hospital_rounded),
              label: 'Hospital',
            ),
          ],
        ),
      ),
    );
  }
}
