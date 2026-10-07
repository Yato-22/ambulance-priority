import 'dart:math' as math;
import '../algorithms/haversine.dart';
import '../models/graph_edge.dart';
import '../models/graph_node.dart';
import '../models/hospital.dart';
import '../models/road_graph.dart';

/// Procedurally generates a reproducible, realistic road network graph for simulation.
/// Uses a fixed seed so the network geometry, signals, and base congestion are identical every run.
class SampleGraphBuilder {
  static const int rows = 6;
  static const int cols = 7;
  static const int totalNodes = rows * cols; // 42 nodes
  static const double baseSpacingM = 300.0;
  static const double centerLat = 18.5000;
  static const double centerLon = 73.8500;

  static RoadGraph build() {
    final rng = math.Random(42);

    const mPerLat = 111320.0;
    final mPerLon = 111320.0 * math.cos(centerLat * (math.pi / 180.0));

    // 1. Build 6x7 Nodes with jitter (+-40m)
    final nodes = <int, GraphNode>{};
    final nodeGrid = List.generate(rows, (_) => List<int>.filled(cols, 0));

    // Signal assignment: 12 junctions well-spread including the central corridors
    final signalCoords = <math.Point<int>>{
      const math.Point(0, 3), // Central top
      const math.Point(1, 1),
      const math.Point(1, 3),
      const math.Point(1, 5),
      const math.Point(2, 2),
      const math.Point(2, 4),
      const math.Point(3, 1),
      const math.Point(3, 3),
      const math.Point(3, 5),
      const math.Point(4, 2),
      const math.Point(4, 4),
      const math.Point(5, 3), // Central bottom
    };

    var signalCounter = 1;
    var nodeId = 1;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        nodeGrid[r][c] = nodeId;

        // Centered grid coordinate offsets in meters
        final yOffsetM = (r - (rows - 1) / 2.0) * baseSpacingM;
        final xOffsetM = (c - (cols - 1) / 2.0) * baseSpacingM;

        // Add small jitter (+-40m) to break artificial grid appearance
        final jitterYM = (rng.nextDouble() * 80.0) - 40.0;
        final jitterXM = (rng.nextDouble() * 80.0) - 40.0;

        final lat = centerLat + ((yOffsetM + jitterYM) / mPerLat);
        final lon = centerLon + ((xOffsetM + jitterXM) / mPerLon);

        final isSignal = signalCoords.contains(math.Point(r, c));
        final sigId = isSignal ? 'S$signalCounter' : null;
        if (isSignal) signalCounter++;

        nodes[nodeId] = GraphNode(
          id: nodeId,
          lat: lat,
          lon: lon,
          hasSignal: isSignal,
          signalId: sigId,
          signalSource: isSignal ? 'grid_junction' : null,
        );

        nodeId++;
      }
    }

    // 2. Candidate Undirected Edges (Grid + 3 Diagonal Shortcuts)
    final candidateEdges = <Set<int>>[];
    void addCandidate(int u, int v) {
      if (u == v) return;
      final pair = {u, v};
      if (!candidateEdges.any((e) => e.contains(u) && e.contains(v))) {
        candidateEdges.add(pair);
      }
    }

    // Horizontal edges
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols - 1; c++) {
        addCandidate(nodeGrid[r][c], nodeGrid[r][c + 1]);
      }
    }

    // Vertical edges
    for (int r = 0; r < rows - 1; r++) {
      for (int c = 0; c < cols; c++) {
        addCandidate(nodeGrid[r][c], nodeGrid[r + 1][c]);
      }
    }

    // 3 Diagonal Shortcut Roads
    addCandidate(nodeGrid[1][1], nodeGrid[2][2]);
    addCandidate(nodeGrid[3][4], nodeGrid[4][5]);
    addCandidate(nodeGrid[2][4], nodeGrid[3][3]);

    // 3. Remove ~12% of edges at random while ensuring the graph remains fully connected
    final totalInitialEdges = candidateEdges.length;
    final targetRemovals = (totalInitialEdges * 0.12).round();

    // Shuffle candidates for random selection
    final candidatesToTry = List<Set<int>>.from(candidateEdges)..shuffle(rng);
    final activeEdges = List<Set<int>>.from(candidateEdges);

    int removed = 0;
    for (final edgeToRemove in candidatesToTry) {
      if (removed >= targetRemovals) break;

      // Trial removal
      activeEdges.removeWhere(
        (e) => e.contains(edgeToRemove.first) && e.contains(edgeToRemove.last),
      );

      // Verify graph connectivity from node 1
      if (_isFullyConnected(activeEdges, totalNodes)) {
        removed++;
      } else {
        // Restore edge if removal breaks connectivity
        activeEdges.add(edgeToRemove);
      }
    }

    // 4. Build Directed GraphEdges with lengths, street names, and base congestion
    final edges = <GraphEdge>[];
    final adjacency = <int, List<GraphEdge>>{};
    for (final n in nodes.keys) {
      adjacency[n] = [];
    }

    final streetNames = [
      'Station Expressway',
      'Central Boulevard',
      'Metro Link Road',
      'Kothrud Spine',
      'Riverfront Avenue',
      'Hospital Access Way',
      'Emergency Corridor',
      'Parkview Road',
      'Highland Avenue',
      'Civic Center Road',
      'West End Highway',
      'Airport Connector',
    ];

    int nameIndex = 0;
    for (final pair in activeEdges) {
      final u = pair.first;
      final v = pair.last;
      final uNode = nodes[u]!;
      final vNode = nodes[v]!;

      final length = Haversine.distanceMeters(uNode.lat, uNode.lon, vNode.lat, vNode.lon);
      final roadName = streetNames[nameIndex % streetNames.length];
      nameIndex++;

      // All roads start as RoadState.open (grey)
      final e1 = GraphEdge(
        from: u,
        to: v,
        length: length,
        name: roadName,
        state: RoadState.open,
        geometry: [
          [uNode.lat, uNode.lon],
          [vNode.lat, vNode.lon]
        ],
      );

      final e2 = GraphEdge(
        from: v,
        to: u,
        length: length,
        name: roadName,
        state: RoadState.open,
        geometry: [
          [vNode.lat, vNode.lon],
          [uNode.lat, uNode.lon]
        ],
      );

      edges.add(e1);
      edges.add(e2);
      adjacency[u]!.add(e1);
      adjacency[v]!.add(e2);
    }

    // 5. Place 2 Hospitals on opposite ends of the grid
    // H1: "City Hospital" at Node 1 (Row 0, Col 0 - top left)
    // H2: "Lifeline Hospital" at Node 42 (Row 5, Col 6 - bottom right)
    final hospitals = [
      Hospital(
        id: 'H1',
        name: 'City Hospital',
        nodeId: nodeGrid[0][0], // Node 1
      ),
      Hospital(
        id: 'H2',
        name: 'Lifeline Hospital',
        nodeId: nodeGrid[rows - 1][cols - 1], // Node 42
      ),
    ];

    return RoadGraph(
      meta: {
        'generator': 'SampleGraphBuilder',
        'rows': rows,
        'cols': cols,
        'nodes': totalNodes,
        'signals': 12,
        'hospitals': 2,
        'seed': 42,
      },
      nodes: nodes,
      edges: edges,
      adjacency: adjacency,
      hospitals: hospitals,
    );
  }

  /// Verifies that all [totalNodes] are reachable using simple breadth-first search.
  static bool _isFullyConnected(List<Set<int>> activeEdges, int totalNodes) {
    final adj = <int, List<int>>{};
    for (int i = 1; i <= totalNodes; i++) {
      adj[i] = [];
    }
    for (final edge in activeEdges) {
      final u = edge.first;
      final v = edge.last;
      adj[u]?.add(v);
      adj[v]?.add(u);
    }

    final visited = <int>{};
    final queue = <int>[1];
    visited.add(1);

    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final neighbor in adj[curr] ?? const <int>[]) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          queue.add(neighbor);
        }
      }
    }

    return visited.length == totalNodes;
  }
}
