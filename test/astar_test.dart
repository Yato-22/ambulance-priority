import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/astar.dart';
import 'package:ambulance_priority/models/graph_edge.dart';
import 'package:ambulance_priority/models/graph_node.dart';
import 'package:ambulance_priority/models/hospital.dart';
import 'package:ambulance_priority/models/road_graph.dart';

void main() {
  group('A* and Dijkstra Routing Tests', () {
    late RoadGraph simpleGraph;

    setUp(() {
      // 4-node diamond graph:
      // Node 1 (Start): (18.490, 73.820)
      // Node 2 (North path): (18.495, 73.820)
      // Node 3 (South path): (18.485, 73.820)
      // Node 4 (Goal): (18.490, 73.830)
      final nodes = <int, GraphNode>{
        1: const GraphNode(id: 1, lat: 18.490, lon: 73.820),
        2: const GraphNode(id: 2, lat: 18.495, lon: 73.820),
        3: const GraphNode(id: 3, lat: 18.485, lon: 73.820),
        4: const GraphNode(id: 4, lat: 18.490, lon: 73.830),
      };

      final edges = <GraphEdge>[
        // North path: 1 -> 2 -> 4 (len: 100m + 100m = 200m)
        GraphEdge(from: 1, to: 2, length: 100.0, name: 'North Rd 1', baseCongestion: 1.0),
        GraphEdge(from: 2, to: 4, length: 100.0, name: 'North Rd 2', baseCongestion: 1.0),
        // South path: 1 -> 3 -> 4 (len: 150m + 150m = 300m)
        GraphEdge(from: 1, to: 3, length: 150.0, name: 'South Rd 1', baseCongestion: 1.0),
        GraphEdge(from: 3, to: 4, length: 150.0, name: 'South Rd 2', baseCongestion: 1.0),
      ];

      final adj = <int, List<GraphEdge>>{
        1: [edges[0], edges[2]],
        2: [edges[1]],
        3: [edges[3]],
        4: [],
      };

      simpleGraph = RoadGraph(
        meta: {'test': true},
        nodes: nodes,
        edges: edges,
        adjacency: adj,
        hospitals: [const Hospital(id: 'H1', name: 'Test Hosp', nodeId: 4)],
      );
    });

    test('Finds optimal shortest path in simple graph', () {
      final result = AStarRouter.findRoute(
        graph: simpleGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );

      expect(result, isNotNull);
      expect(result!.nodeIds, equals([1, 2, 4]));
      expect(result.totalDistanceMeters, equals(200.0));
      expect(result.totalCost, equals(200.0));
    });

    test('Congestion on shorter path makes longer-but-clear path win', () {
      // Congest North path: 1->2 has congestion 3.0 -> cost 300 + 100 = 400
      // South path cost is 150 + 150 = 300
      simpleGraph.setEdgeCongestion(1, 2, 3.0);

      final result = AStarRouter.findRoute(
        graph: simpleGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );

      expect(result, isNotNull);
      expect(result!.nodeIds, equals([1, 3, 4]));
      expect(result.totalDistanceMeters, equals(300.0));
      expect(result.totalCost, equals(300.0));
    });

    test('Blocked road (congestion >= 50.0) is strictly bypassed', () {
      // Block 1 -> 2 completely
      simpleGraph.blockEdge(1, 2);

      final result = AStarRouter.findRoute(
        graph: simpleGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );

      expect(result, isNotNull);
      expect(result!.nodeIds, equals([1, 3, 4]));
    });

    test('Unreachable goal returns null', () {
      // Block both North and South paths
      simpleGraph.blockEdge(1, 2);
      simpleGraph.blockEdge(1, 3);

      final result = AStarRouter.findRoute(
        graph: simpleGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );

      expect(result, isNull);
    });

    test('A* and Dijkstra produce equivalent optimal cost', () {
      // Reset congestion
      simpleGraph.resetAllCongestion();

      final astarRes = AStarRouter.findRoute(
        graph: simpleGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );
      final dijkstraRes = AStarRouter.findRouteDijkstra(
        graph: simpleGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );

      expect(astarRes, isNotNull);
      expect(dijkstraRes, isNotNull);
      expect(astarRes!.totalCost, equals(dijkstraRes!.totalCost));
      expect(astarRes.totalDistanceMeters, equals(dijkstraRes.totalDistanceMeters));
    });

    test('Trivial path when start equals goal', () {
      final res = AStarRouter.findRoute(
        graph: simpleGraph,
        startNodeId: 1,
        goalNodeId: 1,
      );
      expect(res, isNotNull);
      expect(res!.nodeIds, equals([1]));
      expect(res.totalDistanceMeters, equals(0.0));
    });
  });
}

