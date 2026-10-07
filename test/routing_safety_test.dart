import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/astar.dart';
import 'package:ambulance_priority/algorithms/haversine.dart';
import 'package:ambulance_priority/config/constants.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/graph_edge.dart';
import 'package:ambulance_priority/models/graph_node.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/models/sim_state.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';

RoadGraph _createGraph(Map<int, GraphNode> nodes, List<GraphEdge> edges) {
  final adj = <int, List<GraphEdge>>{};
  for (final edge in edges) {
    adj.putIfAbsent(edge.from, () => []).add(edge);
  }
  return RoadGraph(
    meta: {'test': true},
    nodes: nodes,
    edges: edges,
    adjacency: adj,
    hospitals: [],
  );
}

void main() {
  group('Routing Safety & Phantom Edge Prevention Tests', () {
    late SimulationController controller;

    setUp(() {
      controller = SimulationController();
      final graph = SampleGraphBuilder.build();
      controller.setGraph(graph);
    });

    test('1. Block all roads leaving the start node -> status is NO_ROUTE, no route line drawn', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);

      // Block all outgoing roads from start node 1
      final outgoing = controller.graph!.adjacency[1] ?? [];
      for (final edge in outgoing) {
        controller.setRoadState(1, edge.to, RoadState.blocked);
      }

      // Attempt to start trip
      controller.startTrip();

      expect(controller.state.status, equals(SimulationStatus.noRoute));
      expect(controller.state.isPaused, isTrue);
      expect(controller.state.routePolyline, isEmpty);
      expect(controller.state.routeNodeIds, isEmpty);
    });

    test('2. Only one path exists to hospital, set it to Heavy -> A* still finds it (cost is 4x), no phantom shortcuts', () {
      // Build a dedicated graph: Start(1) -> Mid(2) -> Goal(3)
      final nodes = {
        1: const GraphNode(id: 1, lat: 18.500, lon: 73.850),
        2: const GraphNode(id: 2, lat: 18.503, lon: 73.850),
        3: const GraphNode(id: 3, lat: 18.506, lon: 73.850),
      };

      final d12 = Haversine.distanceMeters(18.500, 73.850, 18.503, 73.850);
      final d23 = Haversine.distanceMeters(18.503, 73.850, 18.506, 73.850);

      final edges = [
        GraphEdge(
          from: 1, to: 2, name: 'Road 1-2', length: d12,
          state: RoadState.heavy, currentCongestion: AppConstants.roadFactorHeavy,
        ),
        GraphEdge(
          from: 2, to: 1, name: 'Road 1-2', length: d12,
          state: RoadState.heavy, currentCongestion: AppConstants.roadFactorHeavy,
        ),
        GraphEdge(
          from: 2, to: 3, name: 'Road 2-3', length: d23,
          state: RoadState.heavy, currentCongestion: AppConstants.roadFactorHeavy,
        ),
        GraphEdge(
          from: 3, to: 2, name: 'Road 2-3', length: d23,
          state: RoadState.heavy, currentCongestion: AppConstants.roadFactorHeavy,
        ),
      ];

      final graph = _createGraph(nodes, edges);

      final route = AStarRouter.findRoute(graph: graph, startNodeId: 1, goalNodeId: 3);
      expect(route, isNotNull);
      expect(route!.nodeIds, equals([1, 2, 3]));

      // Verify cost is 4x edge lengths
      final totalDist = d12 + d23;
      expect(route.totalDistanceMeters, closeTo(totalDist, 0.01));
      expect(route.totalCost, closeTo(totalDist * 4.0, 0.05));

      // Verify route safety
      expect(AStarRouter.assertRouteIsValid(graph, route.nodeIds), isTrue);
    });

    test('3. Two paths: one heavy, one open but longer. A* chooses open when < 4x, heavy when > 4x', () {
      // Setup graph with:
      // Path 1 (Direct, Heavy): 1 -> 2 -> 4 (Total Length = 100m, Cost = 100 * 4 = 400)
      // Path 2 (Detour, Open): 1 -> 3 -> 4 (Variable Length L2, Cost = L2 * 1)
      final nodes = {
        1: const GraphNode(id: 1, lat: 18.500, lon: 73.850),
        2: const GraphNode(id: 2, lat: 18.5005, lon: 73.850),
        3: const GraphNode(id: 3, lat: 18.500, lon: 73.852),
        4: const GraphNode(id: 4, lat: 18.501, lon: 73.850),
      };

      // Case A: Path 2 is 300m (3x longer, < 4x) -> Open Path 2 must win (Cost 300 < 400)
      final edgesA = [
        // Path 1 edges (Heavy, 100m total)
        GraphEdge(
          from: 1, to: 2, name: 'P1a', length: 50.0,
          state: RoadState.heavy, currentCongestion: 4.0,
        ),
        GraphEdge(
          from: 2, to: 1, name: 'P1a', length: 50.0,
          state: RoadState.heavy, currentCongestion: 4.0,
        ),
        GraphEdge(
          from: 2, to: 4, name: 'P1b', length: 50.0,
          state: RoadState.heavy, currentCongestion: 4.0,
        ),
        GraphEdge(
          from: 4, to: 2, name: 'P1b', length: 50.0,
          state: RoadState.heavy, currentCongestion: 4.0,
        ),
        // Path 2 edges (Open, 300m total)
        GraphEdge(
          from: 1, to: 3, name: 'P2a', length: 150.0,
          state: RoadState.open, currentCongestion: 1.0,
        ),
        GraphEdge(
          from: 3, to: 1, name: 'P2a', length: 150.0,
          state: RoadState.open, currentCongestion: 1.0,
        ),
        GraphEdge(
          from: 3, to: 4, name: 'P2b', length: 150.0,
          state: RoadState.open, currentCongestion: 1.0,
        ),
        GraphEdge(
          from: 4, to: 3, name: 'P2b', length: 150.0,
          state: RoadState.open, currentCongestion: 1.0,
        ),
      ];

      final graphA = _createGraph(nodes, edgesA);
      final routeA = AStarRouter.findRoute(graph: graphA, startNodeId: 1, goalNodeId: 4);
      expect(routeA, isNotNull);
      expect(routeA!.nodeIds, equals([1, 3, 4])); // Open path chosen

      // Case B: Path 2 is 500m (> 4x longer) -> Heavy Path 1 must win (Cost 400 < 500)
      final edgesB = [
        // Path 1 edges (Heavy, 100m total)
        GraphEdge(
          from: 1, to: 2, name: 'P1a', length: 50.0,
          state: RoadState.heavy, currentCongestion: 4.0,
        ),
        GraphEdge(
          from: 2, to: 1, name: 'P1a', length: 50.0,
          state: RoadState.heavy, currentCongestion: 4.0,
        ),
        GraphEdge(
          from: 2, to: 4, name: 'P1b', length: 50.0,
          state: RoadState.heavy, currentCongestion: 4.0,
        ),
        GraphEdge(
          from: 4, to: 2, name: 'P1b', length: 50.0,
          state: RoadState.heavy, currentCongestion: 4.0,
        ),
        // Path 2 edges (Open, 500m total)
        GraphEdge(
          from: 1, to: 3, name: 'P2a', length: 250.0,
          state: RoadState.open, currentCongestion: 1.0,
        ),
        GraphEdge(
          from: 3, to: 1, name: 'P2a', length: 250.0,
          state: RoadState.open, currentCongestion: 1.0,
        ),
        GraphEdge(
          from: 3, to: 4, name: 'P2b', length: 250.0,
          state: RoadState.open, currentCongestion: 1.0,
        ),
        GraphEdge(
          from: 4, to: 3, name: 'P2b', length: 250.0,
          state: RoadState.open, currentCongestion: 1.0,
        ),
      ];

      final graphB = _createGraph(nodes, edgesB);
      final routeB = AStarRouter.findRoute(graph: graphB, startNodeId: 1, goalNodeId: 4);
      expect(routeB, isNotNull);
      expect(routeB!.nodeIds, equals([1, 2, 4])); // Heavy path chosen
    });

    test('4. Stress test: randomize 200 road configurations -> all routes pass assertRouteIsValid', () {
      final rng = math.Random(42);

      for (int i = 0; i < 200; i++) {
        final g = SampleGraphBuilder.build();
        final roadKeys = g.edges.map((e) => RoadGraph.roadKey(e.from, e.to)).toSet().toList();

        // Randomly modify ~30% of roads
        for (final rKey in roadKeys) {
          final parts = rKey.split('-');
          final u = int.parse(parts[0]);
          final v = int.parse(parts[1]);
          final roll = rng.nextDouble();
          if (roll < 0.15) {
            g.setRoadState(u, v, RoadState.moderate);
          } else if (roll < 0.25) {
            g.setRoadState(u, v, RoadState.heavy);
          } else if (roll < 0.30) {
            g.setRoadState(u, v, RoadState.blocked);
          }
        }

        final startId = 1 + rng.nextInt(g.nodes.length);
        final goalId = 1 + rng.nextInt(g.nodes.length);
        if (startId == goalId) continue;

        final route = AStarRouter.findRoute(graph: g, startNodeId: startId, goalNodeId: goalId);
        if (route != null) {
          final isValid = AStarRouter.assertRouteIsValid(g, route.nodeIds);
          expect(isValid, isTrue, reason: 'Route $route failed validation in trial $i');

          // Ensure every consecutive pair has a real edge and is not blocked
          for (int j = 0; j < route.nodeIds.length - 1; j++) {
            final u = route.nodeIds[j];
            final v = route.nodeIds[j + 1];
            final edge = g.getEdge(u, v);
            expect(edge, isNotNull);
            expect(edge!.isBlocked, isFalse);
          }
        }
      }
    });

    test('5. Mid-trip reroute: leaves through one of two endpoints, no position teleportation, only real edges', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.setTimeScale(1.0);
      controller.setAmbulanceSpeed(40.0);
      controller.startTrip();

      expect(controller.state.status, equals(SimulationStatus.enRoute));

      // Advance 5 ticks so ambulance is mid-edge
      for (int i = 0; i < 5; i++) {
        controller.tick();
      }

      final amb = controller.state.ambulance;
      final edgeFrom = amb.currentEdgeFrom;
      final edgeTo = amb.currentEdgeTo;
      expect(edgeFrom, isNotNull);
      expect(edgeTo, isNotNull);

      final posBefore = [amb.lat, amb.lon];
      final dt = AppConstants.tickMs / 1000.0;
      final maxPerTickDistance = amb.speedMps * dt * controller.timeScale;

      // Block the upcoming road ahead (e.g. edgeTo to its next neighbor on route)
      final routeNodes = controller.state.routeNodeIds;
      final nextIdx = routeNodes.indexOf(edgeTo!);
      if (nextIdx >= 0 && nextIdx + 1 < routeNodes.length) {
        controller.setRoadState(edgeTo, routeNodes[nextIdx + 1], RoadState.blocked);
      } else {
        // Block the current edge itself to force turnaround
        controller.setRoadState(edgeFrom!, edgeTo, RoadState.blocked);
      }

      // Verify after dynamic reroute:
      expect(controller.state.status, equals(SimulationStatus.enRoute));

      final ambAfter = controller.state.ambulance;
      final jumpMeters = Haversine.distanceMeters(
        posBefore[0], posBefore[1],
        ambAfter.lat, ambAfter.lon,
      );

      // Verify no teleportation: position jump is negligible (< 2x per-tick distance)
      expect(jumpMeters, lessThanOrEqualTo(2.0 * maxPerTickDistance));

      // Verify route leaves through one of the two endpoints
      final newEdgeFrom = ambAfter.currentEdgeFrom;
      final newEdgeTo = ambAfter.currentEdgeTo;
      expect([edgeFrom, edgeTo], contains(newEdgeTo));

      // Verify all edges in new route are real edges
      final isValid = AStarRouter.assertRouteIsValid(
        controller.graph!,
        controller.state.routeNodeIds,
        currentEdgeFrom: newEdgeFrom,
        currentEdgeTo: newEdgeTo,
      );
      expect(isValid, isTrue);
    });

    test('6. NO_ROUTE recovery: blocks all paths mid-trip -> stops in NO_ROUTE, unblocks -> resumes and arrives', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.setTimeScale(2.0);
      controller.setAmbulanceSpeed(40.0);
      controller.startTrip();

      expect(controller.state.status, equals(SimulationStatus.enRoute));

      // Move 5 ticks
      for (int i = 0; i < 5; i++) {
        controller.tick();
      }

      // Block all incident roads to hospital 42
      final hospitalNeighbors = controller.graph!.adjacency[h2.nodeId]!.map((e) => e.to).toList();
      for (final neighbor in hospitalNeighbors) {
        controller.setRoadState(h2.nodeId, neighbor, RoadState.blocked);
      }

      // Status must immediately transition to NO_ROUTE
      expect(controller.state.status, equals(SimulationStatus.noRoute));
      expect(controller.state.isPaused, isTrue);
      expect(controller.state.routePolyline, isEmpty);

      final stoppedLat = controller.state.ambulance.lat;
      final stoppedLon = controller.state.ambulance.lon;

      // Ensure tick does not move ambulance while in NO_ROUTE
      for (int i = 0; i < 10; i++) {
        controller.tick();
      }
      expect(controller.state.ambulance.lat, equals(stoppedLat));
      expect(controller.state.ambulance.lon, equals(stoppedLon));
      expect(controller.state.status, equals(SimulationStatus.noRoute));

      // Now unblock one path to hospital
      controller.setRoadState(h2.nodeId, hospitalNeighbors.first, RoadState.open);

      // Status must automatically recover to EN_ROUTE
      expect(controller.state.status, equals(SimulationStatus.enRoute));
      expect(controller.state.isPaused, isFalse);
      expect(controller.state.routePolyline, isNotEmpty);

      // Continue headless simulation until arrival
      int ticks = 0;
      while (controller.state.status == SimulationStatus.enRoute && ticks < 1000) {
        ticks++;
        controller.tick();
      }

      expect(controller.state.status, equals(SimulationStatus.arrived));
      expect(controller.state.ambulance.distanceTravelledM, greaterThan(1000.0));
    });
  });
}

