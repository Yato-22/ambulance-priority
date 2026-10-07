import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ambulance_priority/app.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/graph_node.dart';
import 'package:ambulance_priority/models/hospital.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';

void main() {
  testWidgets('AmbulancePriorityApp smoke test', (WidgetTester tester) async {
    final controller = SimulationController();
    final testGraph = RoadGraph(
      meta: {},
      nodes: {
        1: const GraphNode(id: 1, lat: 18.4925, lon: 73.8230),
        2: const GraphNode(id: 2, lat: 18.4950, lon: 73.8250, hasSignal: true, signalId: 'S1'),
      },
      edges: [],
      adjacency: {},
      hospitals: [
        const Hospital(id: 'H1', name: 'Test Hospital', nodeId: 2),
      ],
    );
    controller.setGraph(testGraph);

    await tester.pumpWidget(
      ChangeNotifierProvider<SimulationController>.value(
        value: controller,
        child: const AmbulancePriorityApp(),
      ),
    );

    // Verify app bar title and bottom navigation labels
    expect(find.text('Ambulance Priority'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Signals'), findsOneWidget);
    expect(find.text('Hospital'), findsOneWidget);
  });

  testWidgets('MapScreen interactive pan, zoom and fitting controls test', (WidgetTester tester) async {
    final controller = SimulationController();
    controller.setGraph(SampleGraphBuilder.build());
    await tester.pumpWidget(
      ChangeNotifierProvider<SimulationController>.value(
        value: controller,
        child: const AmbulancePriorityApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify zoom and fit action buttons exist
    expect(find.byTooltip('Zoom In'), findsOneWidget);
    expect(find.byTooltip('Zoom Out'), findsOneWidget);
    expect(find.byTooltip('Fit Whole Graph'), findsOneWidget);
    expect(find.byTooltip('Congestion & Road Block Mode'), findsOneWidget);
    expect(find.byTooltip('Set Start Location'), findsOneWidget);

    // Test Zoom In button
    await tester.tap(find.byTooltip('Zoom In'));
    await tester.pumpAndSettle();

    // Test Zoom Out button
    await tester.tap(find.byTooltip('Zoom Out'));
    await tester.pumpAndSettle();

    // Test Fit Whole Graph button
    await tester.tap(find.byTooltip('Fit Whole Graph'));
    await tester.pumpAndSettle();

    // Test Drag/Pan gesture across the schematic map
    await tester.drag(find.byType(InteractiveViewer), const Offset(-80, -60));
    await tester.pumpAndSettle();

    // Test toggling Congestion Mode
    await tester.tap(find.byTooltip('Congestion & Road Block Mode'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CONGESTION MODE'), findsOneWidget);

    // Toggle off Congestion Mode
    await tester.tap(find.byTooltip('Congestion & Road Block Mode'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CONGESTION MODE'), findsNothing);

    // Test toggling Select Start Mode
    await tester.tap(find.byTooltip('Set Start Location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SELECT START MODE'), findsOneWidget);
  });
}
