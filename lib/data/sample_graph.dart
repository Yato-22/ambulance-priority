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

    // 4. Classify Roads as Major vs Minor
    // Main grid corridors: horizontal rows 0, 2, 5, vertical columns 1, 3, 5, plus diagonal shortcuts
    bool isMajorRoad(int u, int v) {
      final uR = (u - 1) ~/ cols;
      final uC = (u - 1) % cols;
      final vR = (v - 1) ~/ cols;
      final vC = (v - 1) % cols;

      // Diagonals
      if (uR != vR && uC != vC) return true;
      // Main arterial rows (Hospital access corridors and central corridor)
      if (uR == vR && (uR == 0 || uR == 2 || uR == 5)) return true;
      // Main arterial columns
      if (uC == vC && (uC == 1 || uC == 3 || uC == 5)) return true;

      return false;
    }

    // 5. Select roughly 20% of roads as one-way while strictly preserving strong connectivity
    final directedAdj = <int, List<int>>{};
    for (int i = 1; i <= totalNodes; i++) {
      directedAdj[i] = [];
    }
    for (final pair in activeEdges) {
      final u = pair.first;
      final v = pair.last;
      directedAdj[u]!.add(v);
      directedAdj[v]!.add(u);
    }

    final targetOneWays = (activeEdges.length * 0.20).round();
    final oneWayRoads = <String, List<int>>{}; // roadKey -> [fromNode, toNode]

    // Candidates to try making one-way: minor streets deterministically shuffled
    final candidatesForOneWay = activeEdges
        .where((e) => !isMajorRoad(e.first, e.last))
        .toList();

    candidatesForOneWay.shuffle(rng);

    for (final pair in candidatesForOneWay) {
      if (oneWayRoads.length >= targetOneWays) break;

      final u = pair.first;
      final v = pair.last;
      final forwardFirst = rng.nextBool();
      final fromCandidate = forwardFirst ? u : v;
      final toCandidate = forwardFirst ? v : u;

      // Try direction: fromCandidate -> toCandidate (remove reverse edge: toCandidate -> fromCandidate)
      directedAdj[toCandidate]!.remove(fromCandidate);

      if (_isStronglyConnected(directedAdj, totalNodes)) {
        oneWayRoads[RoadGraph.roadKey(u, v)] = [fromCandidate, toCandidate];
      } else {
        // Restore
        directedAdj[toCandidate]!.add(fromCandidate);

        // Try opposite direction: toCandidate -> fromCandidate
        directedAdj[fromCandidate]!.remove(toCandidate);
        if (_isStronglyConnected(directedAdj, totalNodes)) {
          oneWayRoads[RoadGraph.roadKey(u, v)] = [toCandidate, fromCandidate];
        } else {
          // Restore (keep two-way)
          directedAdj[fromCandidate]!.add(toCandidate);
        }
      }
    }

    // 6. Build Directed GraphEdges with lengths, street names, road classes, and directions
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

      final key = RoadGraph.roadKey(u, v);
      final isMajor = isMajorRoad(u, v);
      final roadClass = isMajor ? RoadClass.major : RoadClass.minor;
      final oneWayInfo = oneWayRoads[key];

      if (oneWayInfo != null) {
        final fromNodeId = oneWayInfo[0];
        final toNodeId = oneWayInfo[1];
        final fromNode = nodes[fromNodeId]!;
        final toNode = nodes[toNodeId]!;

        final e = GraphEdge(
          from: fromNodeId,
          to: toNodeId,
          length: length,
          name: roadName,
          state: RoadState.open,
          direction: RoadDirection.oneWay,
          roadClass: roadClass,
          permittedFromNode: fromNodeId,
          permittedToNode: toNodeId,
          geometry: [
            [fromNode.lat, fromNode.lon],
            [toNode.lat, toNode.lon]
          ],
        );
        edges.add(e);
        adjacency[fromNodeId]!.add(e);
      } else {
        final e1 = GraphEdge(
          from: u,
          to: v,
          length: length,
          name: roadName,
          state: RoadState.open,
          direction: RoadDirection.twoWay,
          roadClass: roadClass,
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
          direction: RoadDirection.twoWay,
          roadClass: roadClass,
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
    }

    // 7. Place 2 Hospitals on opposite ends of the grid
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
        'one_way_count': oneWayRoads.length,
        'two_way_count': activeEdges.length - oneWayRoads.length,
      },
      nodes: nodes,
      edges: edges,
      adjacency: adjacency,
      hospitals: hospitals,
    );
  }

  /// Verifies strong connectivity for directed travel: every junction can reach every other junction.
  static bool _isStronglyConnected(Map<int, List<int>> directedAdj, int totalNodes) {
    // 1. Forward reachability from node 1
    final visitedForward = <int>{};
    final queueForward = <int>[1];
    visitedForward.add(1);

    while (queueForward.isNotEmpty) {
      final curr = queueForward.removeAt(0);
      for (final next in directedAdj[curr] ?? const <int>[]) {
        if (!visitedForward.contains(next)) {
          visitedForward.add(next);
          queueForward.add(next);
        }
      }
    }

    if (visitedForward.length != totalNodes) return false;

    // 2. Backward reachability to node 1 (using reversed edges)
    final revAdj = <int, List<int>>{};
    for (int i = 1; i <= totalNodes; i++) {
      revAdj[i] = [];
    }
    for (final entry in directedAdj.entries) {
      final u = entry.key;
      for (final v in entry.value) {
        revAdj[v]?.add(u);
      }
    }

    final visitedBackward = <int>{};
    final queueBackward = <int>[1];
    visitedBackward.add(1);

    while (queueBackward.isNotEmpty) {
      final curr = queueBackward.removeAt(0);
      for (final next in revAdj[curr] ?? const <int>[]) {
        if (!visitedBackward.contains(next)) {
          visitedBackward.add(next);
          queueBackward.add(next);
        }
      }
    }

    return visitedBackward.length == totalNodes;
  }

  /// Verifies that all [totalNodes] are reachable using simple breadth-first search on undirected edges.
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
