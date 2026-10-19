import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/astar.dart';
import 'package:ambulance_priority/algorithms/haversine.dart';
import 'package:ambulance_priority/config/constants.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/graph_edge.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/models/sim_state.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';

/// Helper to test if two 2D line segments (p1-p2) and (q1-q2) strictly cross each other.
/// Endpoints touching is allowed (edges sharing a node), but interior intersection is rejected.
bool segmentsIntersect(
  double p1x, double p1y,
  double p2x, double p2y,
  double q1x, double q1y,
  double q2x, double q2y,
) {
  double ccw(double ax, double ay, double bx, double by, double cx, double cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }

  final cp1 = ccw(p1x, p1y, p2x, p2y, q1x, q1y);
  final cp2 = ccw(p1x, p1y, p2x, p2y, q2x, q2y);
  final cq1 = ccw(q1x, q1y, q2x, q2y, p1x, p1y);
  final cq2 = ccw(q1x, q1y, q2x, q2y, p2x, p2y);

  // Strict intersection: endpoints of each segment are on strictly opposite sides of the other segment line
  if (((cp1 > 1e-7 && cp2 < -1e-7) || (cp1 < -1e-7 && cp2 > 1e-7)) &&
      ((cq1 > 1e-7 && cq2 < -1e-7) || (cq1 < -1e-7 && cq2 > 1e-7))) {
    return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Step 1.5: Random Road Network Generator Tests', () {
    test('1. Determinism: same seed gives identical graph; different seed gives different graph', () {
      final g1 = SampleGraphBuilder.build(seed: 42);
      final g2 = SampleGraphBuilder.build(seed: 42);
      final g3 = SampleGraphBuilder.build(seed: 99);

      // Same seed: nodes identical
      expect(g1.nodes.length, equals(g2.nodes.length));
      for (final id in g1.nodes.keys) {
        final n1 = g1.nodes[id]!;
        final n2 = g2.nodes[id]!;
        expect(n1.lat, equals(n2.lat));
        expect(n1.lon, equals(n2.lon));
        expect(n1.hasSignal, equals(n2.hasSignal));
        expect(n1.signalId, equals(n2.signalId));
      }

      // Same seed: edges identical
      expect(g1.edges.length, equals(g2.edges.length));
      for (int i = 0; i < g1.edges.length; i++) {
        final e1 = g1.edges[i];
        final e2 = g2.edges[i];
        expect(e1.from, equals(e2.from));
        expect(e1.to, equals(e2.to));
        expect(e1.length, equals(e2.length));
        expect(e1.direction, equals(e2.direction));
        expect(e1.roadClass, equals(e2.roadClass));
      }

      // Different seed produces different node coordinates or edges
      expect(g1.nodes[1]!.lat != g3.nodes[1]!.lat || g1.edges.length != g3.edges.length, isTrue);
    });

    test('2. Exactly 42 junctions, 12 signals (S1-S12), and 2 hospitals (>= 1000m apart)', () {
      final graph = SampleGraphBuilder.build(seed: 42);

      // 42 junctions
      expect(graph.nodes.length, equals(42));

      // 12 signals
      final signalNodes = graph.nodes.values.where((n) => n.hasSignal).toList();
      expect(signalNodes.length, equals(12));
      final signalIds = signalNodes.map((n) => n.signalId).toSet();
      expect(signalIds.length, equals(12));
      for (int s = 1; s <= 12; s++) {
        expect(signalIds.contains('S$s'), isTrue, reason: 'Must contain signal S$s');
      }

      // 2 hospitals
      expect(graph.hospitals.length, equals(2));
      final h1 = graph.hospitals[0];
      final h2 = graph.hospitals[1];
      expect(h1.name, equals('City Hospital'));
      expect(h2.name, equals('Lifeline Hospital'));

      final h1Node = graph.nodes[h1.nodeId]!;
      final h2Node = graph.nodes[h2.nodeId]!;
      final hospitalDist = Haversine.distanceMeters(h1Node.lat, h1Node.lon, h2Node.lat, h2Node.lon);
      expect(hospitalDist, greaterThanOrEqualTo(1000.0),
          reason: 'Hospitals must be well-separated by at least 1000m');
    });

    test('3. Degree requirements: every junction degree >= 2; every signal junction degree >= 3', () {
      final graph = SampleGraphBuilder.build(seed: 42);

      // Compute undirected degree of each junction
      final degreeMap = <int, Set<int>>{};
      for (final id in graph.nodes.keys) {
        degreeMap[id] = <int>{};
      }
      for (final edge in graph.edges) {
        degreeMap[edge.from]?.add(edge.to);
        degreeMap[edge.to]?.add(edge.from);
      }

      for (final entry in degreeMap.entries) {
        final nodeId = entry.key;
        final degree = entry.value.length;
        expect(degree, greaterThanOrEqualTo(2),
            reason: 'Junction $nodeId has degree $degree, expected >= 2 (no dead ends)');

        if (graph.nodes[nodeId]!.hasSignal) {
          expect(degree, greaterThanOrEqualTo(3),
              reason: 'Signal junction $nodeId (${graph.nodes[nodeId]!.signalId}) has degree $degree, expected >= 3');
        }
      }
    });

    test('4. Planarity: no two edges cross each other', () {
      final graph = SampleGraphBuilder.build(seed: 42);

      // Unique undirected edges
      final uniqueEdges = <String, GraphEdge>{};
      for (final edge in graph.edges) {
        final key = RoadGraph.roadKey(edge.from, edge.to);
        uniqueEdges.putIfAbsent(key, () => edge);
      }

      final edgeList = uniqueEdges.values.toList();
      int intersectionCount = 0;

      for (int i = 0; i < edgeList.length; i++) {
        for (int j = i + 1; j < edgeList.length; j++) {
          final e1 = edgeList[i];
          final e2 = edgeList[j];

          // If they share a junction endpoint, they meet at a node, not crossing
          if (e1.from == e2.from || e1.from == e2.to || e1.to == e2.from || e1.to == e2.to) {
            continue;
          }

          final p1 = graph.nodes[e1.from]!;
          final p2 = graph.nodes[e1.to]!;
          final q1 = graph.nodes[e2.from]!;
          final q2 = graph.nodes[e2.to]!;

          final crosses = segmentsIntersect(
            p1.lon, p1.lat,
            p2.lon, p2.lat,
            q1.lon, q1.lat,
            q2.lon, q2.lat,
          );

          if (crosses) {
            intersectionCount++;
          }
        }
      }

      expect(intersectionCount, equals(0), reason: 'Graph must be strictly planar with no crossing edges');
    });

    test('5. Minimum spacing between junctions is respected (>= 150m)', () {
      final graph = SampleGraphBuilder.build(seed: 42);
      final nodes = graph.nodes.values.toList();

      double minObservedDist = double.infinity;
      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          final d = Haversine.distanceMeters(nodes[i].lat, nodes[i].lon, nodes[j].lat, nodes[j].lon);
          if (d < minObservedDist) {
            minObservedDist = d;
          }
        }
      }

      expect(minObservedDist, greaterThanOrEqualTo(150.0),
          reason: 'Minimum spacing between junctions must be at least 150m');
    });

    test('6. Strong connectivity for directed travel: every junction can reach every other junction', () {
      final graph = SampleGraphBuilder.build(seed: 42);
      final totalNodes = graph.nodes.length;

      // Check directed reachability from all nodes to all nodes via BFS
      final directedAdj = <int, List<int>>{};
      for (int id in graph.nodes.keys) {
        directedAdj[id] = [];
      }
      for (final edge in graph.edges) {
        directedAdj[edge.from]?.add(edge.to);
      }

      for (int start in graph.nodes.keys) {
        final visited = <int>{start};
        final queue = <int>[start];
        while (queue.isNotEmpty) {
          final curr = queue.removeAt(0);
          for (final next in directedAdj[curr] ?? const <int>[]) {
            if (!visited.contains(next)) {
              visited.add(next);
              queue.add(next);
            }
          }
        }
        expect(visited.length, equals(totalNodes),
            reason: 'Node $start must be able to reach all $totalNodes nodes in directed graph');
      }
    });

    test('7. Road attributes: ~20% one-way and ~30% major roads', () {
      final graph = SampleGraphBuilder.build(seed: 42);

      final seenPairs = <String>{};
      int totalUniqueRoads = 0;
      int oneWayCount = 0;
      int majorCount = 0;

      for (final edge in graph.edges) {
        final key = RoadGraph.roadKey(edge.from, edge.to);
        if (!seenPairs.contains(key)) {
          seenPairs.add(key);
          totalUniqueRoads++;

          if (edge.direction == RoadDirection.oneWay) {
            oneWayCount++;
          }
          if (edge.roadClass == RoadClass.major) {
            majorCount++;
          }
        }
      }

      final oneWayFraction = oneWayCount / totalUniqueRoads;
      final majorFraction = majorCount / totalUniqueRoads;

      // Roughly 20% (allow 15% - 25%)
      expect(oneWayFraction, greaterThanOrEqualTo(0.15));
      expect(oneWayFraction, lessThanOrEqualTo(0.25));

      // Roughly 30% (allow 25% - 35%)
      expect(majorFraction, greaterThanOrEqualTo(0.25));
      expect(majorFraction, lessThanOrEqualTo(0.35));
    });

    test('8. Major roads form a connected backbone touching both hospitals', () {
      final graph = SampleGraphBuilder.build(seed: 42);
      final h1NodeId = graph.hospitals[0].nodeId;
      final h2NodeId = graph.hospitals[1].nodeId;

      // Extract major edges
      final majorEdges = graph.edges.where((e) => e.roadClass == RoadClass.major).toList();
      final majorAdj = <int, Set<int>>{};
      for (final edge in majorEdges) {
        majorAdj.putIfAbsent(edge.from, () => <int>{}).add(edge.to);
        majorAdj.putIfAbsent(edge.to, () => <int>{}).add(edge.from);
      }

      // Check both hospitals touch major roads
      expect(majorAdj.containsKey(h1NodeId), isTrue, reason: 'Hospital 1 must touch major road backbone');
      expect(majorAdj.containsKey(h2NodeId), isTrue, reason: 'Hospital 2 must touch major road backbone');

      // Check major roads form a single connected component
      final start = majorAdj.keys.first;
      final visited = <int>{start};
      final queue = <int>[start];
      while (queue.isNotEmpty) {
        final curr = queue.removeAt(0);
        for (final next in majorAdj[curr] ?? const <int>{}) {
          if (!visited.contains(next)) {
            visited.add(next);
            queue.add(next);
          }
        }
      }

      expect(visited.length, equals(majorAdj.keys.length),
          reason: 'All major roads must form a single connected backbone');
      expect(visited.contains(h1NodeId), isTrue);
      expect(visited.contains(h2NodeId), isTrue);
    });

    test('9. Road lengths match true Haversine distance between endpoints', () {
      final graph = SampleGraphBuilder.build(seed: 42);

      for (final edge in graph.edges) {
        final u = graph.nodes[edge.from]!;
        final v = graph.nodes[edge.to]!;
        final expectedLen = Haversine.distanceMeters(u.lat, u.lon, v.lat, v.lon);
        expect((edge.length - expectedLen).abs(), lessThan(0.01),
            reason: 'Edge length must match Haversine distance');
      }
    });

    test('10. A* cost equals Dijkstra cost on random start-goal pairs', () {
      final graph = SampleGraphBuilder.build(seed: 42);
      final rng = math.Random(12345);
      final nodeIds = graph.nodes.keys.toList();

      for (int i = 0; i < 20; i++) {
        final start = nodeIds[rng.nextInt(nodeIds.length)];
        var goal = nodeIds[rng.nextInt(nodeIds.length)];
        while (goal == start) {
          goal = nodeIds[rng.nextInt(nodeIds.length)];
        }

        final astarRoute = AStarRouter.findRoute(
          graph: graph,
          startNodeId: start,
          goalNodeId: goal,
        );
        final dijkstraRoute = AStarRouter.findRouteDijkstra(
          graph: graph,
          startNodeId: start,
          goalNodeId: goal,
        );

        expect(astarRoute, isNotNull);
        expect(dijkstraRoute, isNotNull);
        expect((astarRoute!.totalCost - dijkstraRoute!.totalCost).abs(), lessThan(1e-4),
            reason: 'A* and Dijkstra must return identical optimal cost for $start -> $goal');
      }
    });

    test('11. Heuristic admissibility: straightLine / maxClassSpeedFactor <= true remaining cost', () {
      final graph = SampleGraphBuilder.build(seed: 42);

      for (final hospital in graph.hospitals) {
        final goalNode = graph.nodes[hospital.nodeId]!;
        for (final startNode in graph.nodes.values) {
          if (startNode.id == hospital.nodeId) continue;

          final route = AStarRouter.findRoute(
            graph: graph,
            startNodeId: startNode.id,
            goalNodeId: hospital.nodeId,
          );
          expect(route, isNotNull);

          final straightDist = Haversine.distanceMeters(startNode.lat, startNode.lon, goalNode.lat, goalNode.lon);
          final heuristic = straightDist / AppConstants.speedFactorMajor;

          expect(heuristic, lessThanOrEqualTo(route!.totalCost + 1e-4),
              reason: 'Heuristic from node ${startNode.id} to hospital ${hospital.id} must be <= optimal cost');
        }
      }
    });

    test('12. A* routes strictly respect one-way directionality', () {
      final graph = SampleGraphBuilder.build(seed: 42);
      final nodeIds = graph.nodes.keys.toList();

      for (int i = 0; i < 25; i++) {
        final start = nodeIds[i];
        final goal = nodeIds[(i + 13) % nodeIds.length];

        final route = AStarRouter.findRoute(
          graph: graph,
          startNodeId: start,
          goalNodeId: goal,
        );
        expect(route, isNotNull);

        for (int step = 0; step < route!.nodeIds.length - 1; step++) {
          final u = route.nodeIds[step];
          final v = route.nodeIds[step + 1];

          // Find the edge in the graph
          final edge = graph.edges.firstWhere((e) => e.from == u && e.to == v);
          if (edge.direction == RoadDirection.oneWay) {
            expect(edge.permittedFromNode, equals(u),
                reason: 'Traversed edge $u -> $v must match permittedFromNode');
            expect(edge.permittedToNode, equals(v),
                reason: 'Traversed edge $u -> $v must match permittedToNode');
          }
        }
      }
    });

    test('13. Headless simulation completes a full trip on the new random network', () async {
      final graph = SampleGraphBuilder.build(seed: 42);
      final controller = SimulationController();
      controller.setGraph(graph);

      final hospital = graph.hospitals.last;
      const startId = 1;

      controller.selectHospital(hospital);
      controller.selectStartNode(startId);
      controller.setTimeScale(5.0); // 5x speed for fast test

      expect(controller.state.status, equals(SimulationStatus.idle));
      controller.startTrip();
      expect(controller.state.status, equals(SimulationStatus.enRoute));

      // Advance simulation ticks until arrival (max 1000 ticks)
      int ticks = 0;
      while (controller.state.status != SimulationStatus.arrived && ticks < 1000) {
        controller.tick();
        ticks++;
      }

      expect(controller.state.status, equals(SimulationStatus.arrived));
      expect(controller.state.ambulance.distanceTravelledM, greaterThan(200.0));
      controller.dispose();
    });
  });
}
