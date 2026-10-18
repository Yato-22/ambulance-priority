import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/astar.dart';
import 'package:ambulance_priority/algorithms/haversine.dart';
import 'package:ambulance_priority/config/constants.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/ambulance.dart';
import 'package:ambulance_priority/models/graph_edge.dart';
import 'package:ambulance_priority/models/graph_node.dart';
import 'package:ambulance_priority/models/hospital.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/models/sim_state.dart';
import 'package:ambulance_priority/simulation/ambulance_mover.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';

void main() {
  group('Step 1: Road Types & Classes Tests', () {
    test('1. Generated network is strongly connected (every junction reaches every junction)', () {
      final graph = SampleGraphBuilder.build();
      final totalNodes = graph.nodes.length;
      expect(totalNodes, equals(42));

      // Test that every node can reach every other node via directed routing
      for (int u = 1; u <= totalNodes; u++) {
        for (int v = 1; v <= totalNodes; v++) {
          if (u == v) continue;
          final route = AStarRouter.findRoute(
            graph: graph,
            startNodeId: u,
            goalNodeId: v,
          );
          expect(route, isNotNull, reason: 'Node $u should be able to reach Node $v');
          expect(route!.nodeIds.first, equals(u));
          expect(route.nodeIds.last, equals(v));
        }
      }

      // Verify both hospitals can reach all nodes and be reached from all nodes
      for (final hospital in graph.hospitals) {
        for (int n = 1; n <= totalNodes; n++) {
          expect(
            AStarRouter.findRoute(graph: graph, startNodeId: n, goalNodeId: hospital.nodeId),
            isNotNull,
            reason: 'Node $n must reach hospital ${hospital.id} (node ${hospital.nodeId})',
          );
          expect(
            AStarRouter.findRoute(graph: graph, startNodeId: hospital.nodeId, goalNodeId: n),
            isNotNull,
            reason: 'Hospital ${hospital.id} (node ${hospital.nodeId}) must reach node $n',
          );
        }
      }

      // Verify all 12 signals can reach all nodes and be reached from all nodes
      final signalNodes = graph.nodes.values.where((n) => n.hasSignal).map((n) => n.id).toList();
      expect(signalNodes.length, equals(12));
      for (final sigNode in signalNodes) {
        for (int n = 1; n <= totalNodes; n++) {
          expect(
            AStarRouter.findRoute(graph: graph, startNodeId: n, goalNodeId: sigNode),
            isNotNull,
            reason: 'Node $n must reach signal at node $sigNode',
          );
          expect(
            AStarRouter.findRoute(graph: graph, startNodeId: sigNode, goalNodeId: n),
            isNotNull,
            reason: 'Signal at node $sigNode must reach node $n',
          );
        }
      }
    });

    test('2. Generator marks roughly 20% of roads as one-way and clear subset as major', () {
      final graph = SampleGraphBuilder.build();

      // Collect unique road pairs
      final seenPairs = <String>{};
      int totalRoads = 0;
      int oneWayCount = 0;
      int twoWayCount = 0;
      int majorCount = 0;
      int minorCount = 0;

      for (final edge in graph.edges) {
        final key = RoadGraph.roadKey(edge.from, edge.to);
        if (!seenPairs.contains(key)) {
          seenPairs.add(key);
          totalRoads++;

          if (edge.direction == RoadDirection.oneWay) {
            oneWayCount++;
            expect(edge.permittedFromNode, isNotNull);
            expect(edge.permittedToNode, isNotNull);
            expect(edge.permittedFromNode, equals(edge.from));
            expect(edge.permittedToNode, equals(edge.to));
          } else {
            twoWayCount++;
            expect(edge.direction, equals(RoadDirection.twoWay));
          }

          if (edge.roadClass == RoadClass.major) {
            majorCount++;
            expect(edge.classSpeedFactor, equals(AppConstants.speedFactorMajor));
            expect(edge.classSpeedFactor, equals(1.0));
          } else {
            minorCount++;
            expect(edge.roadClass, equals(RoadClass.minor));
            expect(edge.classSpeedFactor, equals(AppConstants.speedFactorMinor));
            expect(edge.classSpeedFactor, equals(0.6));
          }
        }
      }

      expect(totalRoads, equals(seenPairs.length));
      final oneWayFraction = oneWayCount / totalRoads;
      // Roughly 20% (between 15% and 25%)
      expect(oneWayFraction, greaterThanOrEqualTo(0.15));
      expect(oneWayFraction, lessThanOrEqualTo(0.25));
      expect(twoWayCount + oneWayCount, equals(totalRoads));

      // Clear subset as major
      expect(majorCount, greaterThan(0));
      expect(minorCount, greaterThan(0));
      final majorFraction = majorCount / totalRoads;
      expect(majorFraction, greaterThan(0.20));
      expect(majorFraction, lessThan(0.60));
    });

    test('3. Generator is strictly deterministic across runs', () {
      final g1 = SampleGraphBuilder.build();
      final g2 = SampleGraphBuilder.build();

      expect(g1.edges.length, equals(g2.edges.length));
      for (int i = 0; i < g1.edges.length; i++) {
        final e1 = g1.edges[i];
        final e2 = g2.edges[i];
        expect(e1.from, equals(e2.from));
        expect(e1.to, equals(e2.to));
        expect(e1.length, equals(e2.length));
        expect(e1.direction, equals(e2.direction));
        expect(e1.roadClass, equals(e2.roadClass));
        expect(e1.permittedFromNode, equals(e2.permittedFromNode));
        expect(e1.permittedToNode, equals(e2.permittedToNode));
      }
    });

    test('4. A* never uses a one-way road against its permitted direction', () {
      final graph = SampleGraphBuilder.build();
      final rng = math.Random(12345);

      // Test 40 random pairs
      for (int i = 0; i < 40; i++) {
        final start = 1 + rng.nextInt(42);
        final goal = 1 + rng.nextInt(42);
        if (start == goal) continue;

        final route = AStarRouter.findRoute(
          graph: graph,
          startNodeId: start,
          goalNodeId: goal,
        );

        expect(route, isNotNull);
        for (int j = 0; j < route!.nodeIds.length - 1; j++) {
          final u = route.nodeIds[j];
          final v = route.nodeIds[j + 1];

          final edge = graph.getEdge(u, v);
          expect(edge, isNotNull, reason: 'Edge $u -> $v must exist in graph');

          if (edge!.direction == RoadDirection.oneWay) {
            expect(edge.permittedFromNode, equals(u));
            expect(edge.permittedToNode, equals(v));
            // Reverse edge must NOT exist in the graph
            final reverseEdge = graph.getEdge(v, u);
            expect(reverseEdge, isNull, reason: 'One-way road must not have reverse edge');
          }
        }
      }

      // Explicit synthetic test:
      // Node 1 -> Node 2 (two-way)
      // Node 2 -> Node 3 (one-way: 2 -> 3 ONLY)
      // Node 3 -> Node 4 (two-way)
      final synthNodes = {
        1: const GraphNode(id: 1, lat: 18.500, lon: 73.850),
        2: const GraphNode(id: 2, lat: 18.501, lon: 73.850),
        3: const GraphNode(id: 3, lat: 18.502, lon: 73.850),
        4: const GraphNode(id: 4, lat: 18.503, lon: 73.850),
      };
      final synthEdges = [
        GraphEdge(from: 1, to: 2, length: 100.0, name: '1-2', direction: RoadDirection.twoWay),
        GraphEdge(from: 2, to: 1, length: 100.0, name: '1-2', direction: RoadDirection.twoWay),
        GraphEdge(
          from: 2,
          to: 3,
          length: 100.0,
          name: '2-3',
          direction: RoadDirection.oneWay,
          permittedFromNode: 2,
          permittedToNode: 3,
        ),
        GraphEdge(from: 3, to: 4, length: 100.0, name: '3-4', direction: RoadDirection.twoWay),
        GraphEdge(from: 4, to: 3, length: 100.0, name: '3-4', direction: RoadDirection.twoWay),
      ];
      final synthAdj = <int, List<GraphEdge>>{
        1: [synthEdges[0]],
        2: [synthEdges[1], synthEdges[2]],
        3: [synthEdges[3]],
        4: [synthEdges[4]],
      };
      final synthGraph = RoadGraph(
        meta: {},
        nodes: synthNodes,
        edges: synthEdges,
        adjacency: synthAdj,
        hospitals: [const Hospital(id: 'H1', name: 'H', nodeId: 4)],
      );

      // Route 1 -> 4 succeeds via 2 -> 3
      final forwardRoute = AStarRouter.findRoute(graph: synthGraph, startNodeId: 1, goalNodeId: 4);
      expect(forwardRoute, isNotNull);
      expect(forwardRoute!.nodeIds, equals([1, 2, 3, 4]));

      // Route 4 -> 1 FAILS because 3 -> 2 is against the one-way direction
      final backwardRoute = AStarRouter.findRoute(graph: synthGraph, startNodeId: 4, goalNodeId: 1);
      expect(backwardRoute, isNull);
    });

    test('5. Route validation rejects any route using a road against its direction', () {
      final synthNodes = {
        1: const GraphNode(id: 1, lat: 18.500, lon: 73.850),
        2: const GraphNode(id: 2, lat: 18.501, lon: 73.850),
      };
      final synthEdges = [
        GraphEdge(
          from: 1,
          to: 2,
          length: 100.0,
          name: '1-2',
          direction: RoadDirection.oneWay,
          permittedFromNode: 1,
          permittedToNode: 2,
        ),
      ];
      final synthGraph = RoadGraph(
        meta: {},
        nodes: synthNodes,
        edges: synthEdges,
        adjacency: {1: [synthEdges[0]], 2: []},
        hospitals: [],
      );

      // Valid forward
      expect(AStarRouter.assertRouteIsValid(synthGraph, [1, 2]), isTrue);

      // Invalid reverse against one-way
      expect(AStarRouter.assertRouteIsValid(synthGraph, [2, 1]), isFalse);
      expect(
        () => AStarRouter.assertRouteIsValid(synthGraph, [2, 1], throwOnError: true),
        throwsA(isA<AssertionError>()),
      );
    });

    test('6. A* cost equals Dijkstra cost for many random pairs on the new network', () {
      final graph = SampleGraphBuilder.build();
      final rng = math.Random(999);

      for (int i = 0; i < 30; i++) {
        final start = 1 + rng.nextInt(42);
        final goal = 1 + rng.nextInt(42);
        if (start == goal) continue;

        final astar = AStarRouter.findRoute(graph: graph, startNodeId: start, goalNodeId: goal);
        final dijkstra = AStarRouter.findRouteDijkstra(graph: graph, startNodeId: start, goalNodeId: goal);

        expect(astar, isNotNull);
        expect(dijkstra, isNotNull);
        expect(
          astar!.totalCost,
          closeTo(dijkstra!.totalCost, 1e-4),
          reason: 'A* and Dijkstra must return optimal cost for $start -> $goal',
        );
      }
    });

    test('7. A* heuristic never exceeds true remaining cost (admissibility check)', () {
      final graph = SampleGraphBuilder.build();
      final rng = math.Random(54321);

      for (int i = 0; i < 25; i++) {
        final start = 1 + rng.nextInt(42);
        final goal = 1 + rng.nextInt(42);
        if (start == goal) continue;

        final route = AStarRouter.findRoute(graph: graph, startNodeId: start, goalNodeId: goal);
        if (route == null) continue;

        final goalNode = graph.nodes[goal]!;

        // Check admissibility at every node along the optimal path
        for (final nodeId in route.nodeIds) {
          final currNode = graph.nodes[nodeId]!;
          final h = Haversine.distanceMeters(
                currNode.lat,
                currNode.lon,
                goalNode.lat,
                goalNode.lon,
              ) /
              AppConstants.maxClassSpeedFactor;

          final trueRemaining = AStarRouter.findRoute(graph: graph, startNodeId: nodeId, goalNodeId: goal)!;

          expect(
            h,
            lessThanOrEqualTo(trueRemaining.totalCost + 1e-6),
            reason: 'Heuristic $h must not overestimate true cost ${trueRemaining.totalCost} from $nodeId to $goal',
          );
        }
      }
    });

    test('8. Congestion sharing: two-way road shares state, one-way road has single state', () {
      final graph = SampleGraphBuilder.build();

      // Find a two-way road
      final twoWayEdge = graph.edges.firstWhere((e) => e.direction == RoadDirection.twoWay);
      final u2 = twoWayEdge.from;
      final v2 = twoWayEdge.to;

      expect(graph.getEdge(u2, v2)?.state, equals(RoadState.open));
      expect(graph.getEdge(v2, u2)?.state, equals(RoadState.open));

      // Cycle two-way road
      final newSt2 = graph.cycleRoadState(u2, v2);
      expect(newSt2, equals(RoadState.moderate));
      expect(graph.getEdge(u2, v2)?.state, equals(RoadState.moderate));
      expect(graph.getEdge(v2, u2)?.state, equals(RoadState.moderate));

      // Find a one-way road
      final oneWayEdge = graph.edges.firstWhere((e) => e.direction == RoadDirection.oneWay);
      final u1 = oneWayEdge.from;
      final v1 = oneWayEdge.to;

      expect(graph.getEdge(u1, v1), isNotNull);
      expect(graph.getEdge(v1, u1), isNull);

      // Cycle one-way road
      final newSt1 = graph.cycleRoadState(u1, v1);
      expect(newSt1, equals(RoadState.moderate));
      expect(graph.getEdge(u1, v1)?.state, equals(RoadState.moderate));
      expect(graph.getEdge(v1, u1), isNull); // Still no reverse edge
    });

    test('9. Ambulance travels slower on minor roads than on major roads at the same speed setting', () {
      final graph = SampleGraphBuilder.build();

      // Find a major road and a minor road
      final majorEdge = graph.edges.firstWhere((e) => e.roadClass == RoadClass.major);
      final minorEdge = graph.edges.firstWhere((e) => e.roadClass == RoadClass.minor);

      const baseSpeedMps = 40.0 / 3.6; // 40 km/h = 11.11 m/s
      const dt = 1.0;
      const timeScale = 1.0;

      final trajMajor = RouteTrajectory(
        points: [
          [graph.nodes[majorEdge.from]!.lat, graph.nodes[majorEdge.from]!.lon],
          [graph.nodes[majorEdge.to]!.lat, graph.nodes[majorEdge.to]!.lon],
        ],
        cumulativeDistances: [0.0, majorEdge.length],
        totalDistanceMeters: majorEdge.length,
        routeNodeIds: [majorEdge.from, majorEdge.to],
        segmentEdges: [
          [majorEdge.from, majorEdge.to]
        ],
      );

      final trajMinor = RouteTrajectory(
        points: [
          [graph.nodes[minorEdge.from]!.lat, graph.nodes[minorEdge.from]!.lon],
          [graph.nodes[minorEdge.to]!.lat, graph.nodes[minorEdge.to]!.lon],
        ],
        cumulativeDistances: [0.0, minorEdge.length],
        totalDistanceMeters: minorEdge.length,
        routeNodeIds: [minorEdge.from, minorEdge.to],
        segmentEdges: [
          [minorEdge.from, minorEdge.to]
        ],
      );

      final ambInitial = Ambulance(
        lat: trajMajor.points.first[0],
        lon: trajMajor.points.first[1],
        speedMps: baseSpeedMps,
        distanceTravelledM: 0.0,
      );

      final ambMajorAdvanced = AmbulanceMover.advance(
        current: ambInitial.copyWith(
          currentEdgeFrom: majorEdge.from,
          currentEdgeTo: majorEdge.to,
        ),
        trajectory: trajMajor,
        baseSpeedMps: baseSpeedMps,
        dtSeconds: dt,
        timeScale: timeScale,
        graph: graph,
      );

      final ambMinorAdvanced = AmbulanceMover.advance(
        current: ambInitial.copyWith(
          currentEdgeFrom: minorEdge.from,
          currentEdgeTo: minorEdge.to,
          lat: trajMinor.points.first[0],
          lon: trajMinor.points.first[1],
        ),
        trajectory: trajMinor,
        baseSpeedMps: baseSpeedMps,
        dtSeconds: dt,
        timeScale: timeScale,
        graph: graph,
      );

      // Major road effective speed should be baseSpeedMps * 1.0 = 11.11 m/s
      expect(ambMajorAdvanced.speedMps, closeTo(baseSpeedMps * 1.0, 0.01));

      // Minor road effective speed should be baseSpeedMps * 0.6 = 6.67 m/s
      expect(ambMinorAdvanced.speedMps, closeTo(baseSpeedMps * 0.6, 0.01));

      // Travel distance on minor should be exactly 0.6x that of major
      expect(ambMinorAdvanced.distanceTravelledM, lessThan(ambMajorAdvanced.distanceTravelledM));
      expect(
        ambMinorAdvanced.distanceTravelledM / ambMajorAdvanced.distanceTravelledM,
        closeTo(0.6, 0.05),
      );
    });

    test('10. Full headless trip still completes on the new network', () {
      final controller = SimulationController();
      final graph = SampleGraphBuilder.build();
      controller.setGraph(graph);

      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);

      controller.setTimeScale(2.0);
      controller.setAmbulanceSpeed(40.0);

      controller.startTrip();
      expect(controller.state.status, equals(SimulationStatus.enRoute));

      int maxTicks = 1200;
      int ticks = 0;
      while (controller.state.status == SimulationStatus.enRoute && ticks < maxTicks) {
        ticks++;
        controller.tick();
      }

      expect(controller.state.status, equals(SimulationStatus.arrived));
      expect(controller.state.elapsedTimeSeconds, greaterThan(60.0));
      expect(controller.state.signalsClearedCount, greaterThanOrEqualTo(1));
    });
  });
}

