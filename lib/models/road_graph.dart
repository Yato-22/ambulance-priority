import 'dart:convert';
import 'dart:math' as math;
import '../algorithms/haversine.dart';
import '../config/constants.dart';
import 'graph_edge.dart';
import 'graph_node.dart';
import 'hospital.dart';

/// In-memory representation of the road network graph.
class RoadGraph {
  final Map<String, dynamic> meta;
  final Map<int, GraphNode> nodes;
  final List<GraphEdge> edges;
  final Map<int, List<GraphEdge>> adjacency;
  final List<Hospital> hospitals;

  RoadGraph({
    required this.meta,
    required this.nodes,
    required this.edges,
    required this.adjacency,
    required this.hospitals,
  });

  /// Factory constructor to parse the JSON schema produced by `tools/generate_graph.py`.
  factory RoadGraph.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    final rawNodes = json['nodes'] as List<dynamic>? ?? [];
    final nodes = <int, GraphNode>{};
    for (final item in rawNodes) {
      final node = GraphNode.fromJson(item as Map<String, dynamic>);
      nodes[node.id] = node;
    }

    final rawHospitals = json['hospitals'] as List<dynamic>? ?? [];
    final hospitals = rawHospitals
        .map((h) => Hospital.fromJson(h as Map<String, dynamic>))
        .toList();

    final rawEdges = json['edges'] as List<dynamic>? ?? [];
    final edges = <GraphEdge>[];
    final adjacency = <int, List<GraphEdge>>{};

    for (final node in nodes.values) {
      adjacency[node.id] = [];
    }

    for (final item in rawEdges) {
      final edge = GraphEdge.fromJson(item as Map<String, dynamic>);
      edges.add(edge);
      adjacency.putIfAbsent(edge.from, () => []).add(edge);
    }

    return RoadGraph(
      meta: meta,
      nodes: nodes,
      edges: edges,
      adjacency: adjacency,
      hospitals: hospitals,
    );
  }

  /// Parses JSON string directly.
  factory RoadGraph.fromJsonString(String jsonString) {
    final decoded = json.decode(jsonString) as Map<String, dynamic>;
    return RoadGraph.fromJson(decoded);
  }

  /// Finds the node closest to the specified coordinates.
  int findNearestNode(double lat, double lon) {
    if (nodes.isEmpty) {
      throw StateError('Cannot find nearest node in empty graph.');
    }

    int bestNode = nodes.keys.first;
    double minDistance = double.infinity;

    for (final entry in nodes.entries) {
      final d = Haversine.distanceMeters(lat, lon, entry.value.lat, entry.value.lon);
      if (d < minDistance) {
        minDistance = d;
        bestNode = entry.key;
      }
    }

    return bestNode;
  }

  /// Finds the closest directed edge to a tap point (lat, lon).
  /// Computes distance to polyline segments of each edge.
  GraphEdge? findNearestEdge(double lat, double lon, {double maxThresholdM = 150.0}) {
    GraphEdge? closestEdge;
    double minDistance = double.infinity;

    for (final edge in edges) {
      final fromNode = nodes[edge.from];
      final toNode = nodes[edge.to];
      if (fromNode == null || toNode == null) continue;

      final pts = edge.geometry.isNotEmpty
          ? edge.geometry
          : [
              [fromNode.lat, fromNode.lon],
              [toNode.lat, toNode.lon]
            ];

      for (int i = 0; i < pts.length - 1; i++) {
        final d = _pointToSegmentDistanceMeters(
          lat,
          lon,
          pts[i][0],
          pts[i][1],
          pts[i + 1][0],
          pts[i + 1][1],
        );
        if (d < minDistance) {
          minDistance = d;
          closestEdge = edge;
        }
      }
    }

    if (minDistance <= maxThresholdM) {
      return closestEdge;
    }
    return null;
  }

  /// Returns edge between from and to if it exists.
  GraphEdge? getEdge(int from, int to) {
    final outEdges = adjacency[from];
    if (outEdges == null) return null;
    for (final edge in outEdges) {
      if (edge.to == to) return edge;
    }
    return null;
  }

  /// Formats an unordered edge pair key: min(u, v)-max(u, v).
  static String roadKey(int u, int v) {
    final a = math.min(u, v);
    final b = math.max(u, v);
    return '$a-$b';
  }

  /// Sets discrete RoadState for the road between `u` and `v` across BOTH directions.
  void setRoadState(int u, int v, RoadState state) {
    final e1 = getEdge(u, v);
    if (e1 != null) e1.state = state;
    final e2 = getEdge(v, u);
    if (e2 != null) e2.state = state;
  }

  /// Cycles the road state: open -> moderate -> heavy -> blocked -> open.
  /// Updates both directions together and returns the new RoadState.
  RoadState cycleRoadState(int u, int v) {
    final edge = getEdge(u, v) ?? getEdge(v, u);
    final currentState = edge?.state ?? RoadState.open;
    final nextState = currentState.next;
    setRoadState(u, v, nextState);
    return nextState;
  }

  /// Returns the current RoadState of the road connecting `u` and `v`.
  RoadState getRoadState(int u, int v) {
    return getEdge(u, v)?.state ?? getEdge(v, u)?.state ?? RoadState.open;
  }

  /// Sets congestion multiplier for the edge(s) connecting `from` and `to`.
  /// Updates both directions if opposite exists.
  void setEdgeCongestion(int from, int to, double factor) {
    RoadState st = RoadState.open;
    if (factor >= AppConstants.blockedThreshold) {
      st = RoadState.blocked;
    } else if (factor >= AppConstants.ROAD_FACTOR_HEAVY) {
      st = RoadState.heavy;
    } else if (factor >= AppConstants.ROAD_FACTOR_MODERATE) {
      st = RoadState.moderate;
    }
    setRoadState(from, to, st);
  }

  /// Blocks the road between `from` and `to`.
  void blockEdge(int from, int to) {
    setRoadState(from, to, RoadState.blocked);
  }

  /// Unblocks the road between `from` and `to` and resets back to open.
  void unblockEdge(int from, int to) {
    setRoadState(from, to, RoadState.open);
  }

  /// Resets all edges in the graph back to open.
  void resetAllCongestion() {
    for (final edge in edges) {
      edge.resetCongestion();
    }
  }

  /// Checks if an unblocked path currently exists between [startId] and [goalId].
  bool isReachable(int startId, int goalId) {
    if (startId == goalId) return true;
    final visited = <int>{startId};
    final queue = <int>[startId];

    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final edge in adjacency[curr] ?? const <GraphEdge>[]) {
        if (edge.isBlocked) continue;
        if (edge.to == goalId) return true;
        if (!visited.contains(edge.to)) {
          visited.add(edge.to);
          queue.add(edge.to);
        }
      }
    }
    return false;
  }

  /// Sets about 15% of roads to moderate, 7% to heavy, and 3% to blocked using a seeded random,
  /// but ensures the graph never disconnects between the start and the hospital.
  void randomizeTraffic({math.Random? rng, int? startNodeId, int? goalNodeId}) {
    resetAllCongestion();
    final r = rng ?? math.Random(1337);

    final seen = <String>{};
    final pairs = <List<int>>[];
    for (final edge in edges) {
      final key = roadKey(edge.from, edge.to);
      if (!seen.contains(key)) {
        seen.add(key);
        pairs.add([edge.from, edge.to]);
      }
    }

    final start = startNodeId ?? 1;
    final goal = goalNodeId ?? (hospitals.isNotEmpty ? hospitals.first.nodeId : 42);

    for (final pair in pairs) {
      final u = pair[0];
      final v = pair[1];
      final roll = r.nextDouble();

      if (roll < 0.03) {
        // ~3% blocked
        setRoadState(u, v, RoadState.blocked);
        // If blocking this edge disconnects start from hospital, downgrade to heavy
        if (!isReachable(start, goal)) {
          setRoadState(u, v, RoadState.heavy);
        }
      } else if (roll < 0.10) {
        // ~7% heavy (0.03 to 0.10)
        setRoadState(u, v, RoadState.heavy);
      } else if (roll < 0.25) {
        // ~15% moderate (0.10 to 0.25)
        setRoadState(u, v, RoadState.moderate);
      } else {
        setRoadState(u, v, RoadState.open);
      }
    }
  }

  /// Legacy helper delegating to randomizeTraffic.
  void randomizeCongestion(math.Random rng) {
    randomizeTraffic(rng: rng);
  }

  /// Helper: approximate point-to-segment distance in meters.
  static double _pointToSegmentDistanceMeters(
    double pLat,
    double pLon,
    double aLat,
    double aLon,
    double bLat,
    double bLon,
  ) {
    final dAB = Haversine.distanceMeters(aLat, aLon, bLat, bLon);
    if (dAB < 1.0) {
      return Haversine.distanceMeters(pLat, pLon, aLat, aLon);
    }

    // Convert coordinates into local tangent plane approximation in meters
    const mPerLat = 111320.0;
    final mPerLon = 111320.0 * math.cos(aLat * (math.pi / 180.0));

    final ax = 0.0;
    final ay = 0.0;
    final bx = (bLon - aLon) * mPerLon;
    final by = (bLat - aLat) * mPerLat;
    final px = (pLon - aLon) * mPerLon;
    final py = (pLat - aLat) * mPerLat;

    final abx = bx - ax;
    final aby = by - ay;
    final abLenSq = abx * abx + aby * aby;

    final apx = px - ax;
    final apy = py - ay;
    final t = ((apx * abx + apy * aby) / abLenSq).clamp(0.0, 1.0);

    final projX = ax + t * abx;
    final projY = ay + t * aby;

    final dx = px - projX;
    final dy = py - projY;
    return math.sqrt(dx * dx + dy * dy);
  }
}

