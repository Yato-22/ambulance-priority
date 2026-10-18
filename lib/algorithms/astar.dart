import 'package:collection/collection.dart';
import '../config/constants.dart';
import '../models/graph_edge.dart';
import '../models/road_graph.dart';
import 'haversine.dart';

/// Result of a graph pathfinding query.
class RouteResult {
  final List<int> nodeIds;
  final double totalDistanceMeters;
  final double totalCost;
  final int nodesExpanded;

  const RouteResult({
    required this.nodeIds,
    required this.totalDistanceMeters,
    required this.totalCost,
    required this.nodesExpanded,
  });

  @override
  String toString() =>
      'RouteResult(nodes: ${nodeIds.length}, dist: ${totalDistanceMeters.toStringAsFixed(1)}m, '
      'cost: ${totalCost.toStringAsFixed(1)}, expanded: $nodesExpanded)';
}

/// Node record stored in the priority queue for A* / Dijkstra.
class _PriorityItem {
  final int nodeId;
  final double fScore; // g + h
  final double gScore; // accumulated cost

  const _PriorityItem({
    required this.nodeId,
    required this.fScore,
    required this.gScore,
  });
}

/// Pure Dart implementation of A* search and Dijkstra's algorithm.
///
/// Heuristic Admissibility:
///   The heuristic h(n) is the straight-line Haversine distance from node n to the goal
///   divided by the maximum class factor (AppConstants.maxClassSpeedFactor = 1.0).
///   For any edge, the true travel cost is:
///     edge_cost = (edge_length / classSpeedFactor) * congestionFactor
///   Because road length is >= straight-line Euclidean distance,
///   classSpeedFactor <= maxClassSpeedFactor (1.0) so (1 / classSpeedFactor >= 1 / maxClassSpeedFactor),
///   and congestionFactor >= 1.0 (with blocked roads having infinite cost),
///   the minimum edge cost is always >= (straight-line distance / maxClassSpeedFactor).
///   Therefore, h(n) never overestimates the actual remaining cost, ensuring that
///   A* remains strictly admissible and optimal.
class AStarRouter {
  /// Computes the optimal least-congested route using A* search.
  static RouteResult? findRoute({
    required RoadGraph graph,
    required int startNodeId,
    required int goalNodeId,
    Set<int> avoidNodeIds = const {},
  }) {
    return _search(
      graph: graph,
      startNodeId: startNodeId,
      goalNodeId: goalNodeId,
      useHeuristic: true,
      avoidNodeIds: avoidNodeIds,
    );
  }

  /// Computes the shortest route using Dijkstra's algorithm (h(n) = 0).
  /// Used for benchmarking nodes expanded against A*.
  static RouteResult? findRouteDijkstra({
    required RoadGraph graph,
    required int startNodeId,
    required int goalNodeId,
    Set<int> avoidNodeIds = const {},
  }) {
    return _search(
      graph: graph,
      startNodeId: startNodeId,
      goalNodeId: goalNodeId,
      useHeuristic: false,
      avoidNodeIds: avoidNodeIds,
    );
  }

  static RouteResult? _search({
    required RoadGraph graph,
    required int startNodeId,
    required int goalNodeId,
    required bool useHeuristic,
    Set<int> avoidNodeIds = const {},
  }) {
    final startNode = graph.nodes[startNodeId];
    final goalNode = graph.nodes[goalNodeId];

    if (startNode == null || goalNode == null) {
      return null;
    }

    // Trivial case: already at destination
    if (startNodeId == goalNodeId) {
      return RouteResult(
        nodeIds: [startNodeId],
        totalDistanceMeters: 0.0,
        totalCost: 0.0,
        nodesExpanded: 0,
      );
    }

    if (avoidNodeIds.contains(goalNodeId)) {
      return null;
    }

    // Min-heap priority queue keyed by fScore
    final openQueue = PriorityQueue<_PriorityItem>(
      (a, b) => a.fScore.compareTo(b.fScore),
    );

    // best g-score recorded for each node
    final gScore = <int, double>{};
    // cameFrom maps child -> (parent, edge)
    final cameFrom = <int, _CameFromEntry>{};

    gScore[startNodeId] = 0.0;
    final initialH = useHeuristic
        ? (Haversine.distanceMeters(
              startNode.lat,
              startNode.lon,
              goalNode.lat,
              goalNode.lon,
            ) /
            AppConstants.maxClassSpeedFactor)
        : 0.0;

    openQueue.add(
      _PriorityItem(
        nodeId: startNodeId,
        fScore: initialH,
        gScore: 0.0,
      ),
    );

    int nodesExpanded = 0;
    final closedSet = <int>{};

    while (openQueue.isNotEmpty) {
      final currentItem = openQueue.removeFirst();
      final currentId = currentItem.nodeId;

      // Lazy deletion: skip if we already found a cheaper way to this node
      if (closedSet.contains(currentId)) continue;
      if (currentItem.gScore > (gScore[currentId] ?? double.infinity)) continue;

      closedSet.add(currentId);
      nodesExpanded++;

      // Goal reached!
      if (currentId == goalNodeId) {
        return _reconstructPath(
          cameFrom: cameFrom,
          goalId: goalNodeId,
          startId: startNodeId,
          totalCost: currentItem.gScore,
          nodesExpanded: nodesExpanded,
        );
      }

      final outgoingEdges = graph.adjacency[currentId] ?? const <GraphEdge>[];
      for (final edge in outgoingEdges) {
        // Skip blocked roads
        if (edge.isBlocked) {
          continue;
        }

        final neighborId = edge.to;
        if (avoidNodeIds.contains(neighborId)) continue;
        if (closedSet.contains(neighborId)) continue;

        final neighborNode = graph.nodes[neighborId];
        if (neighborNode == null) continue;

        // Effective edge cost = (length / classSpeedFactor) * congestion factor
        final edgeCost = edge.effectiveCost;
        final tentativeG = currentItem.gScore + edgeCost;

        final previousBestG = gScore[neighborId] ?? double.infinity;
        if (tentativeG < previousBestG) {
          gScore[neighborId] = tentativeG;
          cameFrom[neighborId] = _CameFromEntry(parentId: currentId, edge: edge);

          final h = useHeuristic
              ? (Haversine.distanceMeters(
                    neighborNode.lat,
                    neighborNode.lon,
                    goalNode.lat,
                    goalNode.lon,
                  ) /
                  AppConstants.maxClassSpeedFactor)
              : 0.0;

          final f = tentativeG + h;
          openQueue.add(
            _PriorityItem(
              nodeId: neighborId,
              fScore: f,
              gScore: tentativeG,
            ),
          );
        }
      }
    }

    // No path found (destination disconnected or blocked)
    return null;
  }

  static RouteResult _reconstructPath({
    required Map<int, _CameFromEntry> cameFrom,
    required int goalId,
    required int startId,
    required double totalCost,
    required int nodesExpanded,
  }) {
    final path = <int>[goalId];
    double totalDistanceMeters = 0.0;
    int curr = goalId;

    while (curr != startId) {
      final entry = cameFrom[curr];
      if (entry == null) break;
      totalDistanceMeters += entry.edge.length;
      curr = entry.parentId;
      path.add(curr);
    }

    final nodeIds = path.reversed.toList();
    return RouteResult(
      nodeIds: nodeIds,
      totalDistanceMeters: totalDistanceMeters,
      totalCost: totalCost,
      nodesExpanded: nodesExpanded,
    );
  }

  /// Safety validation: verifies that every consecutive pair of nodes in [routeNodeIds]
  /// has a real, valid edge in [graph], and that no edge is blocked.
  ///
  /// The ONLY exception: if [currentEdgeFrom] and [currentEdgeTo] are provided (representing
  /// the road segment the ambulance is currently traversing), that specific edge may be
  /// blocked (e.g. if the user blocked it while the ambulance was on it) so the ambulance
  /// can finish traversing it to an endpoint.
  static bool assertRouteIsValid(
    RoadGraph graph,
    List<int> routeNodeIds, {
    int? currentEdgeFrom,
    int? currentEdgeTo,
    bool throwOnError = false,
  }) {
    if (routeNodeIds.isEmpty) {
      if (throwOnError) throw AssertionError('Route node list is empty');
      return false;
    }
    if (routeNodeIds.length == 1) {
      final valid = graph.nodes.containsKey(routeNodeIds.first);
      if (!valid && throwOnError) {
        throw AssertionError('Node ${routeNodeIds.first} does not exist in graph');
      }
      return valid;
    }

    final currentRoadKey = (currentEdgeFrom != null && currentEdgeTo != null)
        ? RoadGraph.roadKey(currentEdgeFrom, currentEdgeTo)
        : null;

    for (int i = 0; i < routeNodeIds.length - 1; i++) {
      final u = routeNodeIds[i];
      final v = routeNodeIds[i + 1];
      final edge = graph.getEdge(u, v);
      if (edge == null) {
        final reverseEdge = graph.getEdge(v, u);
        if (reverseEdge != null && reverseEdge.direction == RoadDirection.oneWay) {
          if (throwOnError) {
            throw AssertionError(
              'One-way violation: route moves against permitted direction from node $u to node $v (permitted: $v -> $u)',
            );
          }
          return false;
        }
        if (throwOnError) {
          throw AssertionError(
            'Phantom edge detected: no edge exists between node $u and node $v',
          );
        }
        return false;
      }

      if (edge.direction == RoadDirection.oneWay) {
        if (edge.permittedFromNode != null &&
            (edge.permittedFromNode != u || edge.permittedToNode != v)) {
          if (throwOnError) {
            throw AssertionError(
              'One-way violation: route moves against permitted direction from node $u to node $v',
            );
          }
          return false;
        }
      }

      if (edge.isBlocked) {
        final pairKey = RoadGraph.roadKey(u, v);
        final isCurrentEdge = (currentRoadKey != null && pairKey == currentRoadKey);
        if (!isCurrentEdge) {
          if (throwOnError) {
            throw AssertionError('Blocked edge on route: $u <-> $v is blocked');
          }
          return false;
        }
      }
    }

    return true;
  }
}

class _CameFromEntry {
  final int parentId;
  final GraphEdge edge;

  const _CameFromEntry({required this.parentId, required this.edge});
}
