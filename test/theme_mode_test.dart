import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ambulance_priority/app.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/ambulance.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/screens/settings_screen.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';
import 'package:ambulance_priority/theme/app_theme.dart';
import 'package:ambulance_priority/theme/theme_controller.dart';
import 'package:ambulance_priority/widgets/schematic_graph_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with ThemeMode.system and correct name/icon', () {
      final controller = ThemeController();
      expect(controller.themeMode, ThemeMode.system);
      expect(controller.themeModeName, 'System');
      expect(controller.icon, Icons.brightness_auto_rounded);
    });

    test('Cycles theme mode in order: Light -> Dark -> System', () async {
      final controller = ThemeController();
      expect(controller.themeMode, ThemeMode.system);

      // System -> Light
      await controller.cycleThemeMode();
      expect(controller.themeMode, ThemeMode.light);
      expect(controller.themeModeName, 'Light');
      expect(controller.icon, Icons.light_mode_rounded);

      // Light -> Dark
      await controller.cycleThemeMode();
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.themeModeName, 'Dark');
      expect(controller.icon, Icons.dark_mode_rounded);

      // Dark -> System
      await controller.cycleThemeMode();
      expect(controller.themeMode, ThemeMode.system);
      expect(controller.themeModeName, 'System');
      expect(controller.icon, Icons.brightness_auto_rounded);
    });

    test('Explicit setThemeMode persists choice to SharedPreferences', () async {
      final controller = ThemeController();
      await controller.setThemeMode(ThemeMode.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), 'light');

      // Create new controller and verify it loads the persisted preference
      final newController = ThemeController();
      await newController.loadTheme();
      expect(newController.themeMode, ThemeMode.light);

      await newController.setThemeMode(ThemeMode.dark);
      expect(prefs.getString('app_theme_mode'), 'dark');

      final thirdController = ThemeController();
      await thirdController.loadTheme();
      expect(thirdController.themeMode, ThemeMode.dark);
    });
  });

  group('AppTheme & MapColors Design Spec Tests', () {
    test('Light theme background is soft light blue-grey (#EEF4FA), NOT pure white', () {
      final light = AppTheme.lightTheme;
      expect(light.scaffoldBackgroundColor, const Color(0xFFEEF4FA));
      expect(light.scaffoldBackgroundColor, isNot(const Color(0xFFFFFFFF)));
      expect(light.colorScheme.surface, const Color(0xFFF7FAFD));
      expect(light.brightness, Brightness.light);
    });

    test('Dark theme background remains unchanged (#0F141C)', () {
      final dark = AppTheme.darkTheme;
      expect(dark.scaffoldBackgroundColor, const Color(0xFF0F141C));
      expect(dark.brightness, Brightness.dark);
    });

    test('MapColors light and dark provide correct distinct schematic palettes', () {
      expect(MapColors.light.background, const Color(0xFFE8F0F8));
      expect(MapColors.dark.background, const Color(0xFF161B22));
      expect(MapColors.light.background, isNot(MapColors.dark.background));

      // Light mode open roads must be clearly visible
      expect(MapColors.light.openRoad, const Color(0xFF8FA3B5));
      expect(MapColors.dark.openRoad, const Color(0xFF607D8B));

      // Light mode signals have a thin dark outline
      expect(MapColors.light.signalBorder, const Color(0xFF334155));
      expect(MapColors.dark.signalBorder, Colors.transparent);

      // Light mode labels have light chip background and dark text
      expect(MapColors.light.labelChipBackground, const Color(0xFFF1F5F9));
      expect(MapColors.light.labelChipText, const Color(0xFF1E293B));
    });

    test('SchematicGraphPainter respects passed MapColors', () {
      final graph = RoadGraph(meta: {}, nodes: {}, edges: [], adjacency: {}, hospitals: []);
      final ambulance = Ambulance(lat: 18.5, lon: 73.8, speedMps: 11.11);

      final lightPainter = SchematicGraphPainter(
        graph: graph,
        ambulance: ambulance,
        signals: [],
        triggerRadiusM: 200,
        routeNodeIds: [],
        routePolyline: [],
        isEnRoute: false,
        mapColors: MapColors.light,
      );

      final darkPainter = SchematicGraphPainter(
        graph: graph,
        ambulance: ambulance,
        signals: [],
        triggerRadiusM: 200,
        routeNodeIds: [],
        routePolyline: [],
        isEnRoute: false,
        mapColors: MapColors.dark,
      );

      expect(lightPainter.mapColors.background, const Color(0xFFE8F0F8));
      expect(darkPainter.mapColors.background, const Color(0xFF161B22));
    });
  });

  group('UI Integration & Theme Toggle Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('AppBar theme button cycles theme mode and displays feedback', (WidgetTester tester) async {
      final simController = SimulationController();
      simController.setGraph(SampleGraphBuilder.build());
      final themeController = ThemeController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SimulationController>.value(value: simController),
            ChangeNotifierProvider<ThemeController>.value(value: themeController),
          ],
          child: const AmbulancePriorityApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Find AppBar theme action button
      final themeButtonFinder = find.byTooltip('Theme: System (Tap to cycle)');
      expect(themeButtonFinder, findsOneWidget);

      // Tap to cycle: System -> Light
      await tester.tap(themeButtonFinder);
      await tester.pumpAndSettle();

      expect(themeController.themeMode, ThemeMode.light);
      expect(find.text('Theme: Light'), findsOneWidget);

      // Tap again: Light -> Dark
      await tester.tap(find.byTooltip('Theme: Light (Tap to cycle)'));
      await tester.pumpAndSettle();

      expect(themeController.themeMode, ThemeMode.dark);
      expect(find.text('Theme: Dark'), findsOneWidget);
    });

    testWidgets('SettingsScreen SegmentedButton switches theme mode between Light, Dark, System', (WidgetTester tester) async {
      final simController = SimulationController();
      final themeController = ThemeController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SimulationController>.value(value: simController),
            ChangeNotifierProvider<ThemeController>.value(value: themeController),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('App Appearance'), findsOneWidget);
      expect(find.text('Theme Mode'), findsOneWidget);
      expect(find.text('Current: System'), findsOneWidget);

      // Tap Light segment
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(themeController.themeMode, ThemeMode.light);
      expect(find.text('Current: Light'), findsOneWidget);
      expect(find.text('Theme set to Light'), findsOneWidget);

      // Tap Dark segment
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(themeController.themeMode, ThemeMode.dark);
      expect(find.text('Current: Dark'), findsOneWidget);
      expect(find.text('Theme set to Dark'), findsOneWidget);

      // Tap System segment
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();

      expect(themeController.themeMode, ThemeMode.system);
      expect(find.text('Current: System'), findsOneWidget);
    });
  });
}
