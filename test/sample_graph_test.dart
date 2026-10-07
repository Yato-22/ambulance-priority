import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/astar.dart';
import 'package:ambulance_priority/data/sample_graph.dart';

void main() {
  group('SampleGraphBuilder Procedural Tests', () {
    test('Builds fully connected 6x7 graph with 42 nodes and positive edge lengths', () {
      final graph = SampleGraphBuilder.build();

      expect(graph.nodes.length, equals(42));
      expect(graph.hospitals.length, equals(2));
      expect(graph.hospitals[0].name, equals('City Hospital'));
      expect(graph.hospitals[1].name, equals('Lifeline Hospital'));

      // Count traffic signals
      final signals = graph.nodes.values.where((n) => n.hasSignal).toList();
      expect(signals.length, equals(12));

      // Assert all edges have length > 0
      for (final edge in graph.edges) {
        expect(edge.length, greaterThan(0.0));
        expect(edge.baseCongestion, greaterThanOrEqualTo(1.0));
      }

      // Assert connectivity between opposite corners (Node 1 to Node 42) via A*
      final route = AStarRouter.findRoute(
        graph: graph,
        startNodeId: 1,
        goalNodeId: 42,
      );
      expect(route, isNotNull);
      expect(route!.nodeIds.first, equals(1));
      expect(route.nodeIds.last, equals(42));
      expect(route.totalDistanceMeters, greaterThan(1500.0));
    });

    test('Seed is strictly deterministic across multiple builds', () {
      final g1 = SampleGraphBuilder.build();
      final g2 = SampleGraphBuilder.build();

      expect(g1.edges.length, equals(g2.edges.length));
      for (int i = 0; i < g1.edges.length; i++) {
        expect(g1.edges[i].from, equals(g2.edges[i].from));
        expect(g1.edges[i].to, equals(g2.edges[i].to));
        expect(g1.edges[i].length, equals(g2.edges[i].length));
      }
    });
  });
}

