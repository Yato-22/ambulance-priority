import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/hospital_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signals_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// Main Application widget with Material 3 styling and 3-tab navigation.
class AmbulancePriorityApp extends StatefulWidget {
  const AmbulancePriorityApp({super.key});

  @override
  State<AmbulancePriorityApp> createState() => _AmbulancePriorityAppState();
}

class _AmbulancePriorityAppState extends State<AmbulancePriorityApp> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    const MapScreen(),
    const SignalsScreen(),
    HospitalScreen(
      onTapMap: () {
        setState(() {
          _currentIndex = 0;
        });
      },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController?>();
    final themeMode = themeController?.themeMode ?? ThemeMode.system;

    return MaterialApp(
      title: 'Ambulance Priority LoRa System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: Builder(
        builder: (scaffoldContext) {
          return Scaffold(
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
                // Quick Theme Toggle (Light -> Dark -> System)
                IconButton(
                  icon: Icon(themeController?.icon ?? Icons.brightness_auto_rounded),
                  tooltip: 'Theme: ${themeController?.themeModeName ?? "System"} (Tap to cycle)',
                  onPressed: () {
                    if (themeController != null) {
                      themeController.cycleThemeMode();
                      ScaffoldMessenger.of(scaffoldContext).hideCurrentSnackBar();
                      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                        SnackBar(
                          content: Text('Theme: ${themeController.themeModeName}'),
                          duration: const Duration(milliseconds: 1400),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () {
                    Navigator.push(
                      scaffoldContext,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
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
          );
        },
      ),
    );
  }
}
