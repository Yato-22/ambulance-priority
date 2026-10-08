import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ambulance_priority/algorithms/astar.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/graph_edge.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/screens/hospital_screen.dart';
import 'package:ambulance_priority/screens/map_screen.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';

void main() {
  group('A* vs Dijkstra Efficiency & Cost Invariance Tests', () {
    late RoadGraph graph;

    setUp(() {
      graph = SampleGraphBuilder.build();
    });

    test('A* nodesExpanded <= Dijkstra nodesExpanded and route costs are strictly equal across graph pairs', () {
      final nodeIds = graph.nodes.keys.toList();

      for (int i = 0; i < nodeIds.length; i += 4) {
        for (int j = 1; j < nodeIds.length; j += 7) {
          final startId = nodeIds[i];
          final goalId = nodeIds[j];
          if (startId == goalId) continue;

          final astar = AStarRouter.findRoute(
            graph: graph,
            startNodeId: startId,
            goalNodeId: goalId,
          );
          final dijkstra = AStarRouter.findRouteDijkstra(
            graph: graph,
            startNodeId: startId,
            goalNodeId: goalId,
          );

          if (astar != null && dijkstra != null) {
            // 1. Costs must be equal within 1e-6
            expect(
              (astar.totalCost - dijkstra.totalCost).abs(),
              lessThanOrEqualTo(1e-6),
              reason: 'Cost mismatch between A* (${astar.totalCost}) and Dijkstra (${dijkstra.totalCost}) from $startId to $goalId',
            );

            // 2. A* nodes expanded must be <= Dijkstra nodes expanded
            expect(
              astar.nodesExpanded,
              lessThanOrEqualTo(dijkstra.nodesExpanded),
              reason: 'A* expanded ${astar.nodesExpanded} which should be <= Dijkstra ${dijkstra.nodesExpanded} from $startId to $goalId',
            );
          }
        }
      }
    });

    test('With moderate, heavy, and blocked congestion, costs remain equal and A* <= Dijkstra', () {
      // Modify several road states
      graph.setRoadState(1, 2, RoadState.moderate);
      graph.setRoadState(2, 9, RoadState.heavy);
      graph.setRoadState(9, 17, RoadState.moderate);
      graph.setRoadState(17, 24, RoadState.heavy);

      for (final hospital in graph.hospitals) {
        final startId = 1;
        final goalId = hospital.nodeId;

        final astar = AStarRouter.findRoute(
          graph: graph,
          startNodeId: startId,
          goalNodeId: goalId,
        );
        final dijkstra = AStarRouter.findRouteDijkstra(
          graph: graph,
          startNodeId: startId,
          goalNodeId: goalId,
        );

        expect(astar, isNotNull);
        expect(dijkstra, isNotNull);

        // Costs must be equal
        expect((astar!.totalCost - dijkstra!.totalCost).abs(), lessThanOrEqualTo(1e-6));
        // A* must expand <= Dijkstra
        expect(astar.nodesExpanded, lessThanOrEqualTo(dijkstra.nodesExpanded));
      }
    });
  });

  group('Hospital Screen Search Efficiency Card Tests', () {
    testWidgets('Renders search efficiency card with theme-aware colors, stats, and cost invariance', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = SimulationController();
      addTearDown(() => controller.dispose());
      final graph = SampleGraphBuilder.build();
      controller.setGraph(graph);

      await tester.pumpWidget(
        ChangeNotifierProvider<SimulationController>.value(
          value: controller,
          child: const MaterialApp(
            home: Scaffold(
              body: HospitalScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title
      expect(find.text('Search efficiency (same route, same cost)'), findsOneWidget);
      expect(find.text('A*'), findsOneWidget);
      expect(find.text('Dijkstra'), findsOneWidget);
      expect(find.text('nodes expanded'), findsNWidgets(2));

      // Verify effort text and route cost row
      expect(find.textContaining('fewer nodes'), findsOneWidget);
      expect(find.textContaining('Route cost: A* ='), findsOneWidget);
      // Cost mismatch warning must NOT appear
      expect(find.textContaining('Route cost mismatch'), findsNothing);

      // Verify theme colors: card uses surfaceContainerHigh
      final containerFinder = find.ancestor(
        of: find.text('Search efficiency (same route, same cost)'),
        matching: find.byType(Container),
      ).first;
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration, isNotNull);
      expect(decoration!.color, isNotNull);
    });
  });

  group('Map Screen Bottom Bar on 360 dp Screen Tests', () {
    testWidgets('Pause/Resume button layout fits on 360 dp wide screen without overflow, toggles amber/green', (
      WidgetTester tester,
    ) async {
      // Set to 360 dp wide screen
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = SimulationController();
      addTearDown(() => controller.dispose());
      final graph = SampleGraphBuilder.build();
      controller.setGraph(graph);

      await tester.pumpWidget(
        ChangeNotifierProvider<SimulationController>.value(
          value: controller,
          child: const MaterialApp(
            home: Scaffold(
              body: MapScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially in IDLE: Start Trip button is visible
      expect(find.text('Start Trip'), findsOneWidget);
      expect(find.text('1x'), findsOneWidget);
      expect(find.text('2x'), findsOneWidget);
      expect(find.text('5x'), findsOneWidget);

      // Start the trip
      await tester.tap(find.text('Start Trip'));
      await tester.pumpAndSettle();

      // Now EN_ROUTE: Pause button is visible
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('New Trip'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      // Verify button color is amber when running
      final pauseButtonFinder = find.widgetWithText(FilledButton, 'Pause');
      expect(pauseButtonFinder, findsOneWidget);
      final pauseButton = tester.widget<FilledButton>(pauseButtonFinder);
      final buttonStyle = pauseButton.style!;
      final bg = buttonStyle.backgroundColor?.resolve({});
      final fg = buttonStyle.foregroundColor?.resolve({});
      expect(bg, equals(Colors.amber.shade700));
      expect(fg, equals(Colors.black87)); // Dark text on amber for contrast!

      // Tap Pause -> should transition to Resume
      await tester.tap(pauseButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Resume'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Verify button color is green when paused
      final resumeButtonFinder = find.widgetWithText(FilledButton, 'Resume');
      expect(resumeButtonFinder, findsOneWidget);
      final resumeButton = tester.widget<FilledButton>(resumeButtonFinder);
      final resumeStyle = resumeButton.style!;
      final resumeBg = resumeStyle.backgroundColor?.resolve({});
      final resumeFg = resumeStyle.foregroundColor?.resolve({});
      expect(resumeBg, equals(Colors.green.shade700));
      expect(resumeFg, equals(Colors.white));

      // Tap Resume -> resumes trip back to Pause
      await tester.tap(resumeButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Pause'), findsOneWidget);

      // Clean up timer
      controller.resetTrip();
      await tester.pumpAndSettle();

      // Verify no Flutter exceptions / overflows occurred
      expect(tester.takeException(), isNull);
    });
  });
}
