import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'data/sample_graph.dart';
import 'simulation/simulation_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = SimulationController();
  // Build reproducible 6x7 road network entirely in pure Dart (no Python, no assets, no OSM)
  final graph = SampleGraphBuilder.build();
  controller.setGraph(graph);

  runApp(
    ChangeNotifierProvider<SimulationController>.value(
      value: controller,
      child: const AmbulancePriorityApp(),
    ),
  );
}
