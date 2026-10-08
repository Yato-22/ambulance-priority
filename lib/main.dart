import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'data/sample_graph.dart';
import 'simulation/simulation_controller.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController();
  await themeController.loadTheme();

  final controller = SimulationController();
  // Build reproducible 6x7 road network entirely in pure Dart (no Python, no assets, no OSM)
  final graph = SampleGraphBuilder.build();
  controller.setGraph(graph);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SimulationController>.value(value: controller),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: const AmbulancePriorityApp(),
    ),
  );
}
