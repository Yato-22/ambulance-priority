import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/astar.dart';
import 'package:ambulance_priority/config/constants.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/graph_edge.dart';
import 'package:ambulance_priority/models/graph_node.dart';
import 'package:ambulance_priority/models/hospital.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/widgets/schematic_graph_painter.dart';

void main() {
  group('Discrete RoadState & Congestion Tests', () {
    test('Cycle test: tapping the same road 4 times returns it to open, and both directions always share the same state', () {
      final graph = SampleGraphBuilder.build();
      const u = 1;
      const v = 2;

      final e1 = graph.getEdge(u, v);
      final e2 = graph.getEdge(v, u);
      expect(e1, isNotNull);
      expect(e2, isNotNull);

      // Initially open
      expect(e1!.state, equals(RoadState.open));
      expect(e2!.state, equals(RoadState.open));
      expect(e1.currentCongestion, equals(AppConstants.ROAD_FACTOR_OPEN));
      expect(e2.currentCongestion, equals(AppConstants.ROAD_FACTOR_OPEN));

      // Tap 1: open -> moderate (2.0x)
      final state1 = graph.cycleRoadState(u, v);
      expect(state1, equals(RoadState.moderate));
      expect(e1.state, equals(RoadState.moderate));
      expect(e2.state, equals(RoadState.moderate));
      expect(e1.currentCongestion, equals(AppConstants.ROAD_FACTOR_MODERATE));
      expect(e2.currentCongestion, equals(AppConstants.ROAD_FACTOR_MODERATE));

      // Tap 2 (opposite direction call): moderate -> heavy (4.0x)
      final state2 = graph.cycleRoadState(v, u);
      expect(state2, equals(RoadState.heavy));
      expect(e1.state, equals(RoadState.heavy));
      expect(e2.state, equals(RoadState.heavy));
      expect(e1.currentCongestion, equals(AppConstants.ROAD_FACTOR_HEAVY));
      expect(e2.currentCongestion, equals(AppConstants.ROAD_FACTOR_HEAVY));

      // Tap 3: heavy -> blocked
      final state3 = graph.cycleRoadState(u, v);
      expect(state3, equals(RoadState.blocked));
      expect(e1.state, equals(RoadState.blocked));
      expect(e2.state, equals(RoadState.blocked));
      expect(e1.isBlocked, isTrue);
      expect(e2.isBlocked, isTrue);

      // Tap 4: blocked -> open
      final state4 = graph.cycleRoadState(u, v);
      expect(state4, equals(RoadState.open));
      expect(e1.state, equals(RoadState.open));
      expect(e2.state, equals(RoadState.open));
      expect(e1.currentCongestion, equals(1.0));
      expect(e2.currentCongestion, equals(1.0));
      expect(e1.isBlocked, isFalse);
      expect(e2.isBlocked, isFalse);
    });

    test('A* test: a heavy road (factor 4) is avoided when a path of up to 4x cost exists, and a blocked road is never used', () {
      // 4-node diamond graph:
      // Node 1 (Start) -> Node 2 -> Node 4 (Goal) [North path: 100m + 100m = 200m base]
      // Node 1 (Start) -> Node 3 -> Node 4 (Goal) [South path: 250m + 250m = 500m base]
      final nodes = <int, GraphNode>{
        1: const GraphNode(id: 1, lat: 18.490, lon: 73.820),
        2: const GraphNode(id: 2, lat: 18.495, lon: 73.820),
        3: const GraphNode(id: 3, lat: 18.485, lon: 73.820),
        4: const GraphNode(id: 4, lat: 18.490, lon: 73.830),
      };

      final edges = <GraphEdge>[
        GraphEdge(from: 1, to: 2, length: 100.0, name: 'North 1', state: RoadState.open),
        GraphEdge(from: 2, to: 4, length: 100.0, name: 'North 2', state: RoadState.open),
        GraphEdge(from: 1, to: 3, length: 250.0, name: 'South 1', state: RoadState.open),
        GraphEdge(from: 3, to: 4, length: 250.0, name: 'South 2', state: RoadState.open),
      ];

      final adj = <int, List<GraphEdge>>{
        1: [edges[0], edges[2]],
        2: [edges[1]],
        3: [edges[3]],
        4: [],
      };

      final testGraph = RoadGraph(
        meta: {'test': true},
        nodes: nodes,
        edges: edges,
        adjacency: adj,
        hospitals: [const Hospital(id: 'H1', name: 'Test Hosp', nodeId: 4)],
      );

      // Initially, North path (200m) is optimal over South path (500m)
      final initialRoute = AStarRouter.findRoute(
        graph: testGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );
      expect(initialRoute, isNotNull);
      expect(initialRoute!.nodeIds, equals([1, 2, 4]));
      expect(initialRoute.totalCost, equals(200.0));

      // Make North road 1->2 and 2->4 HEAVY (factor 4.0x):
      // Cost of North path becomes (100 * 4) + (100 * 4) = 800.
      // South path cost is 250 + 250 = 500 < 800.
      testGraph.setRoadState(1, 2, RoadState.heavy);
      testGraph.setRoadState(2, 4, RoadState.heavy);

      final routeWithHeavy = AStarRouter.findRoute(
        graph: testGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );
      expect(routeWithHeavy, isNotNull);
      // North path avoided! South path wins
      expect(routeWithHeavy!.nodeIds, equals([1, 3, 4]));
      expect(routeWithHeavy.totalCost, equals(500.0));

      // Now BLOCK South road 1->3:
      testGraph.setRoadState(1, 3, RoadState.blocked);

      final routeWithBlockedSouth = AStarRouter.findRoute(
        graph: testGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );
      expect(routeWithBlockedSouth, isNotNull);
      // Even though North is heavy (800 cost), blocked South is NEVER used!
      expect(routeWithBlockedSouth!.nodeIds, equals([1, 2, 4]));
      expect(routeWithBlockedSouth.totalCost, equals(800.0));

      // Block North path as well -> completely disconnected
      testGraph.setRoadState(1, 2, RoadState.blocked);
      final noRoute = AStarRouter.findRoute(
        graph: testGraph,
        startNodeId: 1,
        goalNodeId: 4,
      );
      expect(noRoute, isNull);
    });

    test('Hit-test test: with zoom 2x and an offset pan, a tap near a road selects that road', () {
      final graph = SampleGraphBuilder.build();
      final projection = CanvasProjection.fromGraph(graph, width: 1000.0, height: 900.0);

      // Find an existing edge in the graph
      final targetEdge = graph.edges.first;
      final uNode = graph.nodes[targetEdge.from]!;
      final vNode = graph.nodes[targetEdge.to]!;

      final p1 = projection.toCanvas(uNode.lat, uNode.lon);
      final p2 = projection.toCanvas(vNode.lat, vNode.lon);

      // Midpoint of the road segment in scene (canvas) coordinates
      final sceneMidpoint = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);

      // Setup TransformationController with 2x zoom and an offset pan of (120, 80)
      const zoom = 2.0;
      const panOffset = Offset(120.0, 80.0);
      final transController = TransformationController(
        Matrix4.translationValues(panOffset.dx, panOffset.dy, 0.0) *
            Matrix4.diagonal3Values(zoom, zoom, 1.0),
      );

      // The screen/viewport position of the road midpoint
      final screenRoadPoint = Offset(
        (sceneMidpoint.dx * zoom) + panOffset.dx,
        (sceneMidpoint.dy * zoom) + panOffset.dy,
      );

      // Tap 10 screen pixels away (within the 20 screen pixels tolerance)
      final screenTapNear = Offset(screenRoadPoint.dx + 6.0, screenRoadPoint.dy + 8.0);
      final distanceOnScreen = math.sqrt(6.0 * 6.0 + 8.0 * 8.0); // exactly 10.0 screen pixels
      expect(distanceOnScreen, lessThanOrEqualTo(20.0));

      // Convert tap position to scene coordinates via controller.toScene
      final sceneTap = transController.toScene(screenTapNear);

      // Verify tolerance formula: 20 screen px / zoom scale
      final zoomScale = transController.value.getMaxScaleOnAxis();
      expect(zoomScale, equals(2.0));
      final toleranceInScene = 20.0 / zoomScale; // 10 scene pixels

      // Verify hit test selects this road
      double minPixelDist = double.infinity;
      GraphEdge? hitEdge;

      for (final edge in graph.edges) {
        final u = graph.nodes[edge.from]!;
        final v = graph.nodes[edge.to]!;
        final ep1 = projection.toCanvas(u.lat, u.lon);
        final ep2 = projection.toCanvas(v.lat, v.lon);

        final d = _pointToSeg(sceneTap, ep1, ep2);
        if (d < minPixelDist) {
          minPixelDist = d;
          hitEdge = edge;
        }
      }

      expect(hitEdge, isNotNull);
      expect(minPixelDist, lessThanOrEqualTo(toleranceInScene));
      expect(RoadGraph.roadKey(hitEdge!.from, hitEdge.to), equals(RoadGraph.roadKey(targetEdge.from, targetEdge.to)));

      // Tap far away (50 screen pixels away > 20px tolerance)
      final screenTapFar = Offset(screenRoadPoint.dx + 50.0, screenRoadPoint.dy + 50.0);
      final sceneTapFar = transController.toScene(screenTapFar);
      final distFar = _pointToSeg(sceneTapFar, p1, p2);
      expect(distFar, greaterThan(toleranceInScene));
    });
  });
}

double _pointToSeg(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final ap = p - a;
  final abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (abLenSq == 0) return (p - a).distance;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / abLenSq).clamp(0.0, 1.0);
  final proj = Offset(a.dx + (t * ab.dx), a.dy + (t * ab.dy));
  return (p - proj).distance;
}

