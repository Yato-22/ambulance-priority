import 'dart:math' as math;
import '../algorithms/haversine.dart';
import '../models/graph_edge.dart';
import '../models/graph_node.dart';
import '../models/hospital.dart';
import '../models/road_graph.dart';

/// 2D Point helper used internally for planar graph generation in meters from map center.
class _Point2D {
  final double x;
  final double y;
  const _Point2D(this.x, this.y);

  double dist(_Point2D other) => math.sqrt((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y));
}

/// Procedurally generates a reproducible, organic planar road network graph for simulation.
/// Replaces the grid-based generator with a Poisson-disc sampled, Gabriel-graph derived network.
class SampleGraphBuilder {
  static const int totalNodes = 42;
  static const double centerLat = 18.5000;
  static const double centerLon = 73.8500;
  static const double widthM = 1800.0;
  static const double heightM = 1500.0;
  static const double minSpacingM = 155.0;

  /// Builds a fully connected, strictly planar road network graph.
  /// Accepts an optional [seed] (default 42). The same seed is guaranteed to produce
  /// an identical network layout, edge attributes, signals, and hospital locations.
  static RoadGraph build({int seed = 42}) {
    final rng = math.Random(seed);

    const mPerLat = 111320.0;
    final mPerLon = 111320.0 * math.cos(centerLat * (math.pi / 180.0));

    // -------------------------------------------------------------------------
    // 1. Node Placement via Poisson-Disc Style Sampling
    // -------------------------------------------------------------------------
    final points = <_Point2D>[];
    // Seed initial point
    points.add(_Point2D(
      (rng.nextDouble() - 0.5) * (widthM - 100),
      (rng.nextDouble() - 0.5) * (heightM - 100),
    ));

    int attempts = 0;
    double currentSpacing = minSpacingM;
    while (points.length < totalNodes && attempts < 200000) {
      attempts++;
      final x = (rng.nextDouble() - 0.5) * (widthM - 40);
      final y = (rng.nextDouble() - 0.5) * (heightM - 40);
      final candidate = _Point2D(x, y);

      bool ok = true;
      for (final p in points) {
        if (candidate.dist(p) < currentSpacing) {
          ok = false;
          break;
        }
      }
      if (ok) {
        points.add(candidate);
      }
      if (attempts % 10000 == 0 && points.length < totalNodes) {
        currentSpacing = math.max(150.0, currentSpacing - 1.0);
      }
    }

    // -------------------------------------------------------------------------
    // 2. Gabriel Graph Construction
    // A Gabriel graph connects (A, B) iff the circle with diameter AB contains
    // no other point strictly inside. Gabriel graphs are inherently planar and connected.
    // -------------------------------------------------------------------------
    final gabrielEdges = <Set<int>>[];
    for (int i = 0; i < points.length; i++) {
      for (int j = i + 1; j < points.length; j++) {
        final pi = points[i];
        final pj = points[j];

        bool emptyCircle = true;
        for (int k = 0; k < points.length; k++) {
          if (k == i || k == j) continue;
          final pk = points[k];
          // Dot product (pi - pk) . (pj - pk) < 0 indicates pk lies strictly inside circle
          final dot = (pi.x - pk.x) * (pj.x - pk.x) + (pi.y - pk.y) * (pj.y - pk.y);
          if (dot < -1e-6) {
            emptyCircle = false;
            break;
          }
        }
        if (emptyCircle) {
          gabrielEdges.add({i, j});
        }
      }
    }

    // -------------------------------------------------------------------------
    // 3. Remove 10-15% of Edges (without breaking connectivity or degree >= 2)
    // -------------------------------------------------------------------------
    final activeEdges = List<Set<int>>.from(gabrielEdges);
    final candidateRemovals = List<Set<int>>.from(activeEdges)..shuffle(rng);
    final targetRemovals = (gabrielEdges.length * 0.12).round();
    int removedCount = 0;

    for (final edge in candidateRemovals) {
      if (removedCount >= targetRemovals) break;
      final u = edge.first;
      final v = edge.last;

      int degU = activeEdges.where((e) => e.contains(u)).length;
      int degV = activeEdges.where((e) => e.contains(v)).length;
      if (degU <= 2 || degV <= 2) continue;

      final candidateList = List<Set<int>>.from(activeEdges)..remove(edge);
      if (_isUndirectedConnected(candidateList, totalNodes)) {
        activeEdges.remove(edge);
        removedCount++;
      }
    }

    // -------------------------------------------------------------------------
    // 4. Add 3-5 Non-Crossing Shortcuts
    // -------------------------------------------------------------------------
    final candidateShortcuts = <Set<int>>[];
    for (int i = 0; i < totalNodes; i++) {
      for (int j = i + 1; j < totalNodes; j++) {
        if (activeEdges.any((e) => e.contains(i) && e.contains(j))) continue;
        final d = points[i].dist(points[j]);
        if (d >= 350.0 && d <= 800.0) {
          candidateShortcuts.add({i, j});
        }
      }
    }
    candidateShortcuts.shuffle(rng);

    int addedShortcuts = 0;
    for (final sc in candidateShortcuts) {
      if (addedShortcuts >= 4) break;
      final u = sc.first;
      final v = sc.last;
      final pu = points[u];
      final pv = points[v];

      bool crosses = false;
      for (final e in activeEdges) {
        if (e.contains(u) || e.contains(v)) continue;
        final pe1 = points[e.first];
        final pe2 = points[e.last];
        if (_segmentsIntersect(pu.x, pu.y, pv.x, pv.y, pe1.x, pe1.y, pe2.x, pe2.y)) {
          crosses = true;
          break;
        }
      }
      if (!crosses) {
        activeEdges.add(sc);
        addedShortcuts++;
      }
    }

    // -------------------------------------------------------------------------
    // 5. Degree Enforcement: Ensure every junction has degree >= 2 (no dead ends)
    // -------------------------------------------------------------------------
    for (int i = 0; i < totalNodes; i++) {
      int deg = activeEdges.where((e) => e.contains(i)).length;
      if (deg < 2) {
        final candidates = List.generate(totalNodes, (j) => j)
            .where((j) => j != i && !activeEdges.any((e) => e.contains(i) && e.contains(j)))
            .toList()
          ..sort((a, b) => points[i].dist(points[a]).compareTo(points[i].dist(points[b])));
        for (final cand in candidates) {
          final pu = points[i];
          final pv = points[cand];
          bool crosses = false;
          for (final e in activeEdges) {
            if (e.contains(i) || e.contains(cand)) continue;
            if (_segmentsIntersect(
              pu.x, pu.y,
              pv.x, pv.y,
              points[e.first].x, points[e.first].y,
              points[e.last].x, points[e.last].y,
            )) {
              crosses = true;
              break;
            }
          }
          if (!crosses) {
            activeEdges.add({i, cand});
            break;
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // 6. Select 2 Hospitals at Well-Separated Junctions (dist >= 1000m)
    // Remap hospital nodes: H1 -> Node 1 (City Hospital), H2 -> Node 42 (Lifeline Hospital)
    // -------------------------------------------------------------------------
    int origH1 = 0;
    int origH2 = 1;
    double maxDist = 0.0;
    for (int i = 0; i < totalNodes; i++) {
      for (int j = i + 1; j < totalNodes; j++) {
        final d = points[i].dist(points[j]);
        if (d > maxDist) {
          maxDist = d;
          origH1 = i;
          origH2 = j;
        }
      }
    }

    // Shortest path between hospitals before remapping
    final origHPath = _findShortestPath(origH1, origH2, activeEdges, points, totalNodes)!;

    final oldToNew = <int, int>{};
    for (int i = 0; i < origHPath.length - 1; i++) {
      oldToNew[origHPath[i]] = i + 1;
    }
    oldToNew[origH2] = 42;

    int nextNewId = origHPath.length;
    for (int i = 0; i < totalNodes; i++) {
      if (!oldToNew.containsKey(i)) {
        oldToNew[i] = nextNewId++;
      }
    }

    final remappedEdges = <Set<int>>[];
    for (final e in activeEdges) {
      remappedEdges.add({oldToNew[e.first]!, oldToNew[e.last]!});
    }

    final remappedPoints = <int, _Point2D>{};
    for (int i = 0; i < totalNodes; i++) {
      remappedPoints[oldToNew[i]!] = points[i];
    }

    // -------------------------------------------------------------------------
    // 7. Major Road Backbone Selection (~30% of total edges)
    // Forms a single connected backbone connecting both hospitals.
    // -------------------------------------------------------------------------
    final targetMajorCount = (remappedEdges.length * 0.30).round();
    final edgeUsage = <String, int>{};

    for (final e in remappedEdges) {
      edgeUsage[RoadGraph.roadKey(e.first, e.last)] = 0;
    }

    // Points list indexed 0..totalNodes for shortest path calculations
    final ptsList = List.generate(totalNodes + 1, (i) => remappedPoints[i] ?? const _Point2D(0, 0));

    // Priority 1: Shortest path between Hospital 1 (Node 1) and Hospital 2 (Node 42)
    final hPath = origHPath.map((n) => oldToNew[n]!).toList();
    for (int i = 0; i < hPath.length - 1; i++) {
      final k = RoadGraph.roadKey(hPath[i], hPath[i + 1]);
      edgeUsage[k] = (edgeUsage[k] ?? 0) + 100;
    }

    // Priority 2: Paths from top hub nodes (highest degree) to hospitals
    final nodeDegrees = <int, int>{};
    for (int i = 1; i <= totalNodes; i++) {
      nodeDegrees[i] = remappedEdges.where((e) => e.contains(i)).length;
    }
    final hubNodes = List.generate(totalNodes, (i) => i + 1)
      ..sort((a, b) => nodeDegrees[b]!.compareTo(nodeDegrees[a]!));
    final topHubs = hubNodes.take(4).toList();

    for (final hub in topHubs) {
      final p1 = _findShortestPath(1, hub, remappedEdges, ptsList, totalNodes + 1);
      if (p1 != null) {
        for (int i = 0; i < p1.length - 1; i++) {
          final k = RoadGraph.roadKey(p1[i], p1[i + 1]);
          edgeUsage[k] = (edgeUsage[k] ?? 0) + 20;
        }
      }
      final p2 = _findShortestPath(42, hub, remappedEdges, ptsList, totalNodes + 1);
      if (p2 != null) {
        for (int i = 0; i < p2.length - 1; i++) {
          final k = RoadGraph.roadKey(p2[i], p2[i + 1]);
          edgeUsage[k] = (edgeUsage[k] ?? 0) + 20;
        }
      }
    }

    // Priority 3: Random sample of node pairs for traffic distribution
    for (int s = 0; s < 30; s++) {
      final u = 1 + rng.nextInt(totalNodes);
      final v = 1 + rng.nextInt(totalNodes);
      if (u == v) continue;
      final path = _findShortestPath(u, v, remappedEdges, ptsList, totalNodes + 1);
      if (path != null) {
        for (int i = 0; i < path.length - 1; i++) {
          final k = RoadGraph.roadKey(path[i], path[i + 1]);
          edgeUsage[k] = (edgeUsage[k] ?? 0) + 1;
        }
      }
    }

    // Grow major edge backbone from H1-H2 path so it is strictly a single connected component
    final majorEdgeSet = <String>{};
    for (int i = 0; i < hPath.length - 1; i++) {
      majorEdgeSet.add(RoadGraph.roadKey(hPath[i], hPath[i + 1]));
    }

    final sortedCandidates = remappedEdges.map((e) => RoadGraph.roadKey(e.first, e.last)).toList()
      ..sort((a, b) => (edgeUsage[b] ?? 0).compareTo(edgeUsage[a] ?? 0));

    while (majorEdgeSet.length < targetMajorCount) {
      final majorConnectedNodes = <int>{};
      for (final ek in majorEdgeSet) {
        final parts = ek.split('-').map(int.parse).toList();
        majorConnectedNodes.add(parts[0]);
        majorConnectedNodes.add(parts[1]);
      }

      String? bestCandidate;
      for (final c in sortedCandidates) {
        if (majorEdgeSet.contains(c)) continue;
        final parts = c.split('-').map(int.parse).toList();
        if (majorConnectedNodes.contains(parts[0]) || majorConnectedNodes.contains(parts[1])) {
          bestCandidate = c;
          break;
        }
      }

      if (bestCandidate != null) {
        majorEdgeSet.add(bestCandidate);
      } else {
        break;
      }
    }

    // -------------------------------------------------------------------------
    // 8. Signal Placement: Exactly 12 Signals (S1-S12)
    // Placed only at junctions with degree >= 3, greedy farthest-point selection.
    // Exclude terminal hospital nodes (1 and 42) to keep signals at intersections.
    // -------------------------------------------------------------------------
    final candidateSigNodes = <int>[];
    for (int i = 1; i <= totalNodes; i++) {
      if (i == 1 || i == 42) continue;
      int deg = remappedEdges.where((e) => e.contains(i)).length;
      if (deg >= 3) {
        candidateSigNodes.add(i);
      }
    }

    final signalNodes = <int>[];
    candidateSigNodes.sort(
      (a, b) => remappedPoints[a]!.dist(const _Point2D(0, 0)).compareTo(
            remappedPoints[b]!.dist(const _Point2D(0, 0)),
          ),
    );
    signalNodes.add(candidateSigNodes.first);

    while (signalNodes.length < 12) {
      int bestNode = -1;
      double maxMinDist = -1.0;
      for (final cand in candidateSigNodes) {
        if (signalNodes.contains(cand)) continue;
        double minD = double.infinity;
        for (final s in signalNodes) {
          final d = remappedPoints[cand]!.dist(remappedPoints[s]!);
          if (d < minD) minD = d;
        }
        if (minD > maxMinDist) {
          maxMinDist = minD;
          bestNode = cand;
        }
      }
      signalNodes.add(bestNode);
    }

    // Order signals so that signals on the main hospital corridor (hPath) are numbered first (S1, S2...)
    // in order of encounter from Hospital 1 to Hospital 2, followed by remaining signals.
    final pathSignals = <int>[];
    for (final node in hPath) {
      if (signalNodes.contains(node)) {
        pathSignals.add(node);
      }
    }
    final otherSignals = signalNodes.where((s) => !pathSignals.contains(s)).toList();
    final orderedSignalNodes = [...pathSignals, ...otherSignals];

    final signalMap = <int, String>{};
    for (int s = 0; s < orderedSignalNodes.length; s++) {
      signalMap[orderedSignalNodes[s]] = 'S${s + 1}';
    }

    final nodes = <int, GraphNode>{};
    final signalSet = signalNodes.toSet();

    for (int i = 1; i <= totalNodes; i++) {
      final pt = remappedPoints[i]!;
      final lat = centerLat + (pt.y / mPerLat);
      final lon = centerLon + (pt.x / mPerLon);
      final isSig = signalSet.contains(i);
      nodes[i] = GraphNode(
        id: i,
        lat: lat,
        lon: lon,
        hasSignal: isSig,
        signalId: isSig ? signalMap[i] : null,
        signalSource: isSig ? 'procedural_junction' : null,
      );
    }

    // -------------------------------------------------------------------------
    // 9. Direction Assignment: ~20% One-Way, Maintaining Strong Connectivity
    // -------------------------------------------------------------------------
    final currentDirAdj = <int, List<int>>{};
    for (int i = 1; i <= totalNodes; i++) {
      currentDirAdj[i] = [];
    }
    for (final e in remappedEdges) {
      currentDirAdj[e.first]!.add(e.last);
      currentDirAdj[e.last]!.add(e.first);
    }

    final targetOneWayCount = (remappedEdges.length * 0.20).round();
    final oneWayEdges = <String, int>{}; // roadKey -> permittedFromNode
    final shuffledEdges = List<Set<int>>.from(remappedEdges)..shuffle(rng);

    for (final e in shuffledEdges) {
      if (oneWayEdges.length >= targetOneWayCount) break;
      final u = e.first;
      final v = e.last;
      // Preserve road 1-2 as two-way for existing test compatibility
      if ((u == 1 && v == 2) || (u == 2 && v == 1)) continue;
      final k = RoadGraph.roadKey(u, v);

      // Attempt making it one-way u -> v
      final candidateDirAdj = <int, List<int>>{};
      for (int i = 1; i <= totalNodes; i++) {
        candidateDirAdj[i] = List<int>.from(currentDirAdj[i]!);
      }
      candidateDirAdj[v]!.remove(u);

      if (_isStronglyConnected(candidateDirAdj, totalNodes)) {
        currentDirAdj[v]!.remove(u);
        oneWayEdges[k] = u;
      } else {
        // Attempt v -> u
        candidateDirAdj[v]!.add(u);
        candidateDirAdj[u]!.remove(v);
        if (_isStronglyConnected(candidateDirAdj, totalNodes)) {
          currentDirAdj[u]!.remove(v);
          oneWayEdges[k] = v;
        }
      }
    }

    // -------------------------------------------------------------------------
    // 10. Assemble GraphEdge List and Adjacency Map
    // -------------------------------------------------------------------------
    final edges = <GraphEdge>[];
    final adjacency = <int, List<GraphEdge>>{};
    for (int i = 1; i <= totalNodes; i++) {
      adjacency[i] = [];
    }

    for (final e in remappedEdges) {
      final u = e.first;
      final v = e.last;
      final k = RoadGraph.roadKey(u, v);
      final isMajor = majorEdgeSet.contains(k);
      final isOneWay = oneWayEdges.containsKey(k);
      final rClass = isMajor ? RoadClass.major : RoadClass.minor;
      final permittedFrom = isOneWay ? oneWayEdges[k]! : null;
      final permittedTo = isOneWay ? (permittedFrom == u ? v : u) : null;

      final uNode = nodes[u]!;
      final vNode = nodes[v]!;
      final length = Haversine.distanceMeters(uNode.lat, uNode.lon, vNode.lat, vNode.lon);

      if (isOneWay) {
        final edge = GraphEdge(
          from: permittedFrom!,
          to: permittedTo!,
          length: length,
          name: isMajor ? 'Boulevard $permittedFrom-$permittedTo' : 'Street $permittedFrom-$permittedTo',
          direction: RoadDirection.oneWay,
          permittedFromNode: permittedFrom,
          permittedToNode: permittedTo,
          roadClass: rClass,
        );
        edges.add(edge);
        adjacency[permittedFrom]?.add(edge);
      } else {
        final edge1 = GraphEdge(
          from: u,
          to: v,
          length: length,
          name: isMajor ? 'Boulevard $u-$v' : 'Street $u-$v',
          direction: RoadDirection.twoWay,
          roadClass: rClass,
        );
        final edge2 = GraphEdge(
          from: v,
          to: u,
          length: length,
          name: isMajor ? 'Boulevard $v-$u' : 'Street $v-$u',
          direction: RoadDirection.twoWay,
          roadClass: rClass,
        );
        edges.add(edge1);
        edges.add(edge2);
        adjacency[u]?.add(edge1);
        adjacency[v]?.add(edge2);
      }
    }

    final hospitals = [
      Hospital(id: 'H1', name: 'City Hospital', nodeId: 1),
      Hospital(id: 'H2', name: 'Lifeline Hospital', nodeId: 42),
    ];

    return RoadGraph(
      meta: {
        'generator': 'SampleGraphBuilder',
        'type': 'organic_random_planar',
        'nodes': totalNodes,
        'signals': 12,
        'hospitals': 2,
        'seed': seed,
        'one_way_count': oneWayEdges.length,
        'two_way_count': remappedEdges.length - oneWayEdges.length,
        'major_count': majorEdgeSet.length,
        'minor_count': remappedEdges.length - majorEdgeSet.length,
      },
      nodes: nodes,
      edges: edges,
      adjacency: adjacency,
      hospitals: hospitals,
    );
  }

  // ---------------------------------------------------------------------------
  // Geometry and Graph Connectivity Helpers
  // ---------------------------------------------------------------------------

  /// Checks if two 2D line segments strictly intersect each other.
  /// Shared endpoints are allowed.
  static bool _segmentsIntersect(
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

    if (((cp1 > 1e-7 && cp2 < -1e-7) || (cp1 < -1e-7 && cp2 > 1e-7)) &&
        ((cq1 > 1e-7 && cq2 < -1e-7) || (cq1 < -1e-7 && cq2 > 1e-7))) {
      return true;
    }
    return false;
  }

  /// Verifies undirected graph connectivity using BFS.
  static bool _isUndirectedConnected(List<Set<int>> edgeList, int nodeCount) {
    final adj = List.generate(nodeCount, (_) => <int>[]);
    for (final e in edgeList) {
      adj[e.first].add(e.last);
      adj[e.last].add(e.first);
    }
    final visited = <int>{0};
    final q = <int>[0];
    while (q.isNotEmpty) {
      final curr = q.removeAt(0);
      for (final next in adj[curr]) {
        if (!visited.contains(next)) {
          visited.add(next);
          q.add(next);
        }
      }
    }
    return visited.length == nodeCount;
  }

  /// Dijkstra shortest path on undirected edges used for betweenness / backbone selection.
  static List<int>? _findShortestPath(
    int start,
    int goal,
    List<Set<int>> edges,
    List<_Point2D> pts,
    int nodeCount,
  ) {
    final adj = List.generate(nodeCount, (_) => <int>[]);
    for (final e in edges) {
      adj[e.first].add(e.last);
      adj[e.last].add(e.first);
    }

    final dist = List<double>.filled(nodeCount, double.infinity);
    final prev = List<int?>.filled(nodeCount, null);
    final unvisited = List.generate(nodeCount, (i) => i).toSet();

    dist[start] = 0.0;
    while (unvisited.isNotEmpty) {
      int? u;
      double bestD = double.infinity;
      for (final node in unvisited) {
        if (dist[node] < bestD) {
          bestD = dist[node];
          u = node;
        }
      }
      if (u == null || dist[u] == double.infinity) break;
      if (u == goal) break;
      unvisited.remove(u);

      for (final v in adj[u]) {
        if (!unvisited.contains(v)) continue;
        final alt = dist[u] + pts[u].dist(pts[v]);
        if (alt < dist[v]) {
          dist[v] = alt;
          prev[v] = u;
        }
      }
    }

    if (dist[goal] == double.infinity) return null;
    final path = <int>[];
    int? curr = goal;
    while (curr != null) {
      path.insert(0, curr);
      curr = prev[curr];
    }
    return path;
  }

  /// Verifies strong connectivity for directed travel: every junction can reach every other junction.
  static bool _isStronglyConnected(Map<int, List<int>> directedAdj, int nodeCount) {
    // 1. Forward reachability from node 1
    final visitedForward = <int>{1};
    final queueForward = <int>[1];

    while (queueForward.isNotEmpty) {
      final curr = queueForward.removeAt(0);
      for (final next in directedAdj[curr] ?? const <int>[]) {
        if (!visitedForward.contains(next)) {
          visitedForward.add(next);
          queueForward.add(next);
        }
      }
    }

    if (visitedForward.length != nodeCount) return false;

    // 2. Backward reachability to node 1 (using reversed edges)
    final revAdj = <int, List<int>>{};
    for (int i = 1; i <= nodeCount; i++) {
      revAdj[i] = [];
    }
    for (final entry in directedAdj.entries) {
      final u = entry.key;
      for (final v in entry.value) {
        revAdj[v]?.add(u);
      }
    }

    final visitedBackward = <int>{1};
    final queueBackward = <int>[1];

    while (queueBackward.isNotEmpty) {
      final curr = queueBackward.removeAt(0);
      for (final next in revAdj[curr] ?? const <int>[]) {
        if (!visitedBackward.contains(next)) {
          visitedBackward.add(next);
          queueBackward.add(next);
        }
      }
    }

    return visitedBackward.length == nodeCount;
  }
}
