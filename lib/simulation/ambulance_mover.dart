import 'dart:math' as math;
import '../algorithms/haversine.dart';
import '../config/constants.dart';
import '../models/ambulance.dart';
import '../models/road_graph.dart';

/// Precomputed route trajectory data for smooth interpolation.
class RouteTrajectory {
  final List<List<double>> points; // [[lat, lon], ...]
  final List<double> cumulativeDistances; // meters from start to point i
  final double totalDistanceMeters;
  final List<int> routeNodeIds;
  final Map<int, double> nodeCumulativeDistances; // nodeId -> meters along route
  final List<List<int>> segmentEdges; // for each segment [k, k+1], [u, v]

  const RouteTrajectory({
    required this.points,
    required this.cumulativeDistances,
    required this.totalDistanceMeters,
    required this.routeNodeIds,
    this.nodeCumulativeDistances = const {},
    this.segmentEdges = const [],
  });

  bool get isEmpty => points.isEmpty;
}

/// Handles ambulance kinematics along the planned route polyline.
class AmbulanceMover {
  /// Builds a dense continuous polyline and precomputes cumulative arc-lengths.
  /// If [startPosition] is provided (e.g. during dynamic rerouting mid-edge),
  /// the polyline starts at [startPosition] along edge (nodeIds[0] -> nodeIds[1])
  /// without creating any phantom shortcuts through empty space.
  static RouteTrajectory buildTrajectory({
    required RoadGraph graph,
    required List<int> nodeIds,
    List<double>? startPosition,
  }) {
    if (nodeIds.isEmpty) {
      return const RouteTrajectory(
        points: [],
        cumulativeDistances: [],
        totalDistanceMeters: 0.0,
        routeNodeIds: [],
        nodeCumulativeDistances: {},
        segmentEdges: [],
      );
    }

    if (nodeIds.length == 1) {
      final node = graph.nodes[nodeIds.first];
      final pt = node != null ? [node.lat, node.lon] : [0.0, 0.0];
      return RouteTrajectory(
        points: [pt],
        cumulativeDistances: [0.0],
        totalDistanceMeters: 0.0,
        routeNodeIds: nodeIds,
        nodeCumulativeDistances: {nodeIds.first: 0.0},
        segmentEdges: const [],
      );
    }

    final points = <List<double>>[];
    final segmentEdges = <List<int>>[];

    // If mid-edge start position provided, add it and connect to nodeIds[1]
    if (startPosition != null && startPosition.length >= 2 && nodeIds.length >= 2) {
      points.add([startPosition[0], startPosition[1]]);
      final u = nodeIds[0];
      final v = nodeIds[1];
      final vNode = graph.nodes[v];
      if (vNode != null) {
        points.add([vNode.lat, vNode.lon]);
        segmentEdges.add([u, v]);
      }

      // Add remaining consecutive edges from index 1 onwards
      for (int i = 1; i < nodeIds.length - 1; i++) {
        final edgeU = nodeIds[i];
        final edgeV = nodeIds[i + 1];
        final vN = graph.nodes[edgeV];
        if (vN == null) continue;
        points.add([vN.lat, vN.lon]);
        segmentEdges.add([edgeU, edgeV]);
      }
    } else {
      // Normal full-path trajectory from nodeIds[0] to nodeIds.last
      for (int i = 0; i < nodeIds.length - 1; i++) {
        final u = nodeIds[i];
        final v = nodeIds[i + 1];
        final uNode = graph.nodes[u];
        final vNode = graph.nodes[v];
        if (uNode == null || vNode == null) continue;

        if (points.isEmpty) {
          points.add([uNode.lat, uNode.lon]);
        }
        points.add([vNode.lat, vNode.lon]);
        segmentEdges.add([u, v]);
      }
    }

    // Precompute cumulative distances along polyline
    final cumulativeDistances = <double>[0.0];
    final nodeCumulativeDistances = <int, double>{};
    double totalDist = 0.0;

    for (int i = 0; i < points.length - 1; i++) {
      final d = Haversine.distanceMeters(
        points[i][0],
        points[i][1],
        points[i + 1][0],
        points[i + 1][1],
      );
      totalDist += d;
      cumulativeDistances.add(totalDist);
    }

    // Map each route node to its cumulative meter distance along the polyline
    for (final nodeId in nodeIds) {
      final n = graph.nodes[nodeId];
      if (n != null) {
        double minD = double.infinity;
        int closestIdx = 0;
        for (int p = 0; p < points.length; p++) {
          final d = Haversine.distanceMeters(points[p][0], points[p][1], n.lat, n.lon);
          if (d < minD) {
            minD = d;
            closestIdx = p;
          }
        }
        nodeCumulativeDistances[nodeId] = cumulativeDistances[closestIdx];
      }
    }

    return RouteTrajectory(
      points: points,
      cumulativeDistances: cumulativeDistances,
      totalDistanceMeters: totalDist,
      routeNodeIds: nodeIds,
      nodeCumulativeDistances: nodeCumulativeDistances,
      segmentEdges: segmentEdges,
    );
  }

  /// Advances the ambulance forward by dt seconds at current speed.
  static Ambulance advance({
    required Ambulance current,
    required RouteTrajectory trajectory,
    required double baseSpeedMps,
    required double dtSeconds,
    required double timeScale,
    RoadGraph? graph,
  }) {
    if (trajectory.points.isEmpty) return current;

    if (trajectory.points.length == 1) {
      return current.copyWith(
        lat: trajectory.points.first[0],
        lon: trajectory.points.first[1],
        totalRouteDistanceM: 0.0,
        distanceTravelledM: 0.0,
      );
    }

    final deltaDistance = baseSpeedMps * dtSeconds * timeScale;
    final newDistance = math.min(
      current.distanceTravelledM + deltaDistance,
      trajectory.totalDistanceMeters,
    );

    // Locate the active polyline segment [k, k+1]
    final cDists = trajectory.cumulativeDistances;
    int k = 0;
    while (k < cDists.length - 2 && cDists[k + 1] < newDistance) {
      k++;
    }

    final segStartDist = cDists[k];
    final segEndDist = cDists[k + 1];
    final segLen = segEndDist - segStartDist;

    final t = segLen > 0.0 ? ((newDistance - segStartDist) / segLen).clamp(0.0, 1.0) : 0.0;

    final p1 = trajectory.points[k];
    final p2 = trajectory.points[k + 1];

    final interpLat = p1[0] + t * (p2[0] - p1[0]);
    final interpLon = p1[1] + t * (p2[1] - p1[1]);

    final heading = Haversine.bearingDegrees(p1[0], p1[1], p2[0], p2[1]);

    int? edgeFrom;
    int? edgeTo;
    if (k < trajectory.segmentEdges.length) {
      edgeFrom = trajectory.segmentEdges[k][0];
      edgeTo = trajectory.segmentEdges[k][1];
    } else if (trajectory.segmentEdges.isNotEmpty) {
      edgeFrom = trajectory.segmentEdges.last[0];
      edgeTo = trajectory.segmentEdges.last[1];
    }

    // Determine current edge congestion factor to modulate effective speed
    double effectiveSpeed = baseSpeedMps;
    if (graph != null && edgeFrom != null && edgeTo != null) {
      final edge = graph.getEdge(edgeFrom, edgeTo) ?? graph.getEdge(edgeTo, edgeFrom);
      if (edge != null && edge.currentCongestion > 1.0) {
        effectiveSpeed = baseSpeedMps / math.sqrt(edge.currentCongestion);
        effectiveSpeed = effectiveSpeed.clamp(
          (AppConstants.minSpeedKmh / 3.6),
          baseSpeedMps,
        );
      }
    }

    return Ambulance(
      lat: interpLat,
      lon: interpLon,
      headingDegrees: heading,
      speedMps: effectiveSpeed,
      distanceTravelledM: newDistance,
      totalRouteDistanceM: trajectory.totalDistanceMeters,
      polylineSegmentIndex: k,
      currentEdgeFrom: edgeFrom,
      currentEdgeTo: edgeTo,
    );
  }
}

