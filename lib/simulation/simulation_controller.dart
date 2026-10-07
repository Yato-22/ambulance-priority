import 'dart:async';
import 'package:flutter/foundation.dart';
import '../algorithms/astar.dart';
import '../algorithms/haversine.dart';
import '../config/constants.dart';
import '../models/ambulance.dart';
import '../models/graph_edge.dart';
import '../models/hospital.dart';
import '../models/road_graph.dart';
import '../models/sim_state.dart';
import '../models/traffic_signal.dart';
import 'ambulance_mover.dart';
import 'lora_link_simulator.dart';
import 'signal_manager.dart';

/// Central state controller driving the simulation loop and managing all subsystems.
class SimulationController extends ChangeNotifier {
  RoadGraph? _graph;
  late final LoRaLinkSimulator _loraLink;
  late final SignalManager _signalManager;

  RouteTrajectory _trajectory = const RouteTrajectory(
    points: [],
    cumulativeDistances: [],
    totalDistanceMeters: 0.0,
    routeNodeIds: [],
    nodeCumulativeDistances: {},
  );

  late SimState _state;
  Timer? _timer;

  // Configurable parameters
  double _greenTriggerRadiusM = AppConstants.greenTriggerRadiusM;
  double _ambulanceSpeedKmh = AppConstants.defaultSpeedKmh;
  double _timeScale = 1.0;
  bool _showDijkstraComparison = false;

  SimulationController() {
    _loraLink = LoRaLinkSimulator(packetLossProbability: 0.0);
    _signalManager = SignalManager(
      loraLink: _loraLink,
      onEvent: _recordTimelineEvent,
    );

    // Initial default state
    _state = SimState.initial(
      defaultLat: 18.5000,
      defaultLon: 73.8500,
    );
  }

  // Getters
  SimState get state => _state;
  RoadGraph? get graph => _graph;
  LoRaLinkSimulator get loraLink => _loraLink;
  SignalManager get signalManager => _signalManager;
  double get greenTriggerRadiusM => _greenTriggerRadiusM;
  double get ambulanceSpeedKmh => _ambulanceSpeedKmh;
  double get timeScale => _timeScale;
  bool get showDijkstraComparison => _showDijkstraComparison;

  /// Helper: finds the node farthest (by straight-line Haversine) from a given node.
  int findFarthestNode(int goalNodeId) {
    if (_graph == null) return 1;
    final goalNode = _graph!.nodes[goalNodeId];
    if (goalNode == null) return 1;

    int bestNode = 1;
    double maxDist = -1.0;
    for (final node in _graph!.nodes.values) {
      if (node.id == goalNodeId) continue;
      final d = Haversine.distanceMeters(node.lat, node.lon, goalNode.lat, goalNode.lon);
      if (d > maxDist) {
        maxDist = d;
        bestNode = node.id;
      }
    }
    return bestNode;
  }

  /// Loads the road graph and initializes signals and default start/end points.
  void setGraph(RoadGraph roadGraph) {
    _graph = roadGraph;
    _signalManager.initFromGraph(roadGraph);

    // Default to Lifeline Hospital (H2, opposite end) and farthest start node (Node 1)
    final defaultHospital = roadGraph.hospitals.isNotEmpty
        ? (roadGraph.hospitals.length > 1 ? roadGraph.hospitals[1] : roadGraph.hospitals.first)
        : null;

    final defaultStart = defaultHospital != null
        ? findFarthestNode(defaultHospital.nodeId)
        : (roadGraph.nodes.isNotEmpty ? roadGraph.nodes.keys.first : 1);

    final startNode = roadGraph.nodes[defaultStart];
    final defaultLat = startNode?.lat ?? 18.5000;
    final defaultLon = startNode?.lon ?? 73.8500;

    _state = SimState(
      status: SimulationStatus.idle,
      startNodeId: defaultStart,
      targetHospital: defaultHospital,
      ambulance: Ambulance(lat: defaultLat, lon: defaultLon),
      signals: _signalManager.signals,
      timeScale: _timeScale,
    );

    notifyListeners();
  }

  /// Sets start node (e.g. by tapping on the schematic map).
  void selectStartNode(int nodeId) {
    if (_state.status == SimulationStatus.enRoute) return;
    final node = _graph?.nodes[nodeId];
    if (node == null) return;

    _state = _state.copyWith(
      startNodeId: nodeId,
      ambulance: _state.ambulance.copyWith(
        lat: node.lat,
        lon: node.lon,
        distanceTravelledM: 0.0,
      ),
    );
    notifyListeners();
  }

  /// Selects destination hospital from picker.
  void selectHospital(Hospital hospital) {
    if (_state.status == SimulationStatus.enRoute) return;

    // If current start node matches the hospital, pick the farthest node as start
    var startId = _state.startNodeId;
    if (startId == null || startId == hospital.nodeId) {
      startId = findFarthestNode(hospital.nodeId);
    }
    final startNode = _graph?.nodes[startId];

    _state = _state.copyWith(
      targetHospital: hospital,
      startNodeId: startId,
      ambulance: _state.ambulance.copyWith(
        lat: startNode?.lat ?? _state.ambulance.lat,
        lon: startNode?.lon ?? _state.ambulance.lon,
        distanceTravelledM: 0.0,
      ),
    );
    notifyListeners();
  }

  /// Initiates routing and starts the periodic simulation clock.
  void startTrip() {
    if (_graph == null) return;
    final hospital = _state.targetHospital;
    if (hospital == null) return;

    var startId = _state.startNodeId;
    // Trip setup validation: require start != destination
    if (startId == null || startId == hospital.nodeId) {
      startId = findFarthestNode(hospital.nodeId);
      selectStartNode(startId);
    }

    _state = _state.copyWith(
      status: SimulationStatus.routing,
      elapsedTimeSeconds: 0.0,
      signalsClearedCount: 0,
      oldEtaSeconds: null,
    );
    notifyListeners();

    _computeAndApplyRoute(
      fromNodeId: startId,
      toNodeId: hospital.nodeId,
      isInitial: true,
    );

    if (_state.status == SimulationStatus.enRoute) {
      _startTimer();
    }
  }

  /// Pauses the periodic clock without resetting progress.
  void pauseTrip() {
    _timer?.cancel();
    _state = _state.copyWith(isPaused: true);
    notifyListeners();
  }

  /// Resumes an en-route trip.
  void resumeTrip() {
    if (_state.status == SimulationStatus.enRoute) {
      _state = _state.copyWith(isPaused: false);
      _startTimer();
      notifyListeners();
    }
  }

  /// Fully resets simulation state on NEW TRIP.
  void resetTrip() {
    _timer?.cancel();
    _signalManager.reset();
    _loraLink.clearLogs();

    if (_graph != null) {
      _signalManager.initFromGraph(_graph!);
    }

    final hospital = _state.targetHospital;
    var startId = _state.startNodeId;
    if (hospital != null && (startId == null || startId == hospital.nodeId)) {
      startId = findFarthestNode(hospital.nodeId);
    }
    startId ??= 1;
    final startNode = _graph?.nodes[startId];

    _trajectory = const RouteTrajectory(
      points: [],
      cumulativeDistances: [],
      totalDistanceMeters: 0.0,
      routeNodeIds: [],
      nodeCumulativeDistances: {},
    );

    _state = SimState(
      status: SimulationStatus.idle,
      startNodeId: startId,
      targetHospital: hospital,
      ambulance: Ambulance(
        lat: startNode?.lat ?? 18.5000,
        lon: startNode?.lon ?? 73.8500,
        distanceTravelledM: 0.0,
        totalRouteDistanceM: 0.0,
      ),
      signals: _signalManager.signals,
      activeSignalId: null,
      routeNodeIds: const [],
      routePolyline: const [],
      cumulativeDistances: const [],
      totalRouteDistanceM: 0.0,
      remainingDistanceM: 0.0,
      etaSeconds: 0.0,
      oldEtaSeconds: null,
      elapsedTimeSeconds: 0.0,
      signalsClearedCount: 0,
      timelineEvents: const [],
      loraLogs: const [],
      timeScale: _timeScale,
    );

    // ignore: avoid_print
    print('[SIMULATION] RESET: Returned to IDLE. Cleared counts and timers reset.');
    notifyListeners();
  }

  void setTimeScale(double scale) {
    _timeScale = scale;
    _state = _state.copyWith(timeScale: scale);
    notifyListeners();
  }

  void setTriggerRadius(double radiusM) {
    _greenTriggerRadiusM = radiusM;
    _signalManager.greenTriggerRadiusM = radiusM;
    notifyListeners();
  }

  void setAmbulanceSpeed(double speedKmh) {
    _ambulanceSpeedKmh = speedKmh;
    notifyListeners();
  }

  void setPacketLossProbability(double prob) {
    _loraLink.packetLossProbability = prob.clamp(0.0, 0.3);
    notifyListeners();
  }

  void setShowDijkstraComparison(bool show) {
    _showDijkstraComparison = show;
    notifyListeners();
  }

  void setSignalOverride(String signalId, SignalOverride overrideState) {
    _signalManager.setOverride(signalId, overrideState);
    _state = _state.copyWith(signals: _signalManager.signals);
    notifyListeners();
  }

  /// Blocks a road segment and dynamically triggers A* rerouting if on route.
  void blockRoad(int from, int to) {
    if (_graph == null) return;
    _graph!.blockEdge(from, to);
    _recordTimelineEvent('Road Blocked', 'Edge $from <-> $to marked impassable', 'reroute');
    _handleGraphChange();
  }

  /// Cycles discrete road state on road (from <-> to) through:
  /// open -> moderate -> heavy -> blocked -> open.
  /// Reroutes if active trip is affected.
  RoadState cycleRoadState(int from, int to) {
    if (_graph == null) return RoadState.open;
    final newState = _graph!.cycleRoadState(from, to);
    final edge = _graph!.getEdge(from, to);
    final name = edge?.name.isNotEmpty == true ? edge!.name : 'Road';
    _recordTimelineEvent(
      'Road Updated',
      '$name ($from <-> $to): ${newState.label}',
      'reroute',
    );
    _handleGraphChange();
    return newState;
  }

  /// Sets road state directly across both directions.
  void setRoadState(int from, int to, RoadState state) {
    if (_graph == null) return;
    _graph!.setRoadState(from, to, state);
    final edge = _graph!.getEdge(from, to);
    final name = edge?.name.isNotEmpty == true ? edge!.name : 'Road';
    _recordTimelineEvent(
      'Road State Set',
      '$name ($from <-> $to): ${state.label}',
      'reroute',
    );
    _handleGraphChange();
  }

  /// Sets congestion multiplier and triggers reroute if needed.
  void setCongestion(int from, int to, double factor) {
    if (_graph == null) return;
    _graph!.setEdgeCongestion(from, to, factor);
    _handleGraphChange();
  }

  /// Clears all congestion and blocks, resetting all roads to open.
  void clearAllCongestion() {
    if (_graph == null) return;
    _graph!.resetAllCongestion();
    _recordTimelineEvent('Congestion Cleared', 'All road states reset to open (1.0x)', 'reroute');
    _handleGraphChange();
  }

  /// Randomizes traffic across network: ~15% moderate, 7% heavy, 3% blocked.
  /// Ensures path between start and hospital is never broken.
  void randomizeTraffic() {
    if (_graph == null) return;
    final startNode = _state.startNodeId ?? 1;
    final goalNode = _state.targetHospital?.nodeId ?? 42;
    _graph!.randomizeTraffic(startNodeId: startNode, goalNodeId: goalNode);
    _recordTimelineEvent(
      'Traffic Randomization',
      'Set ~15% moderate, 7% heavy, 3% blocked (start-to-hospital connected)',
      'reroute',
    );
    _handleGraphChange();
  }

  /// Enters NO_ROUTE state when no path is available or route safety validation fails.
  void _enterNoRoute() {
    _timer?.cancel();
    _state = _state.copyWith(
      status: SimulationStatus.noRoute,
      isPaused: true,
      routePolyline: const [],
      routeNodeIds: const [],
      remainingDistanceM: 0.0,
      etaSeconds: 0.0,
    );
    _trajectory = const RouteTrajectory(
      points: [],
      cumulativeDistances: [],
      totalDistanceMeters: 0.0,
      routeNodeIds: [],
      nodeCumulativeDistances: {},
      segmentEdges: [],
    );
    _recordTimelineEvent(
      'No Route Available',
      'No route to hospital: all paths blocked. Clear a road to continue.',
      'reroute',
    );
    notifyListeners();
  }

  /// Checks if current trip needs dynamic A* rerouting, or recovers from NO_ROUTE.
  void _handleGraphChange() {
    if ((_state.status != SimulationStatus.enRoute &&
            _state.status != SimulationStatus.noRoute) ||
        _graph == null) {
      notifyListeners();
      return;
    }

    final hospital = _state.targetHospital;
    if (hospital == null) return;

    _rerouteMidTrip();
  }

  void _rerouteMidTrip() {
    if (_graph == null) return;
    final hospital = _state.targetHospital;
    if (hospital == null) return;

    final amb = _state.ambulance;
    final goalId = hospital.nodeId;

    int? nodeA = amb.currentEdgeFrom;
    int? nodeB = amb.currentEdgeTo;

    if (nodeA == null || nodeB == null) {
      if (_trajectory.routeNodeIds.length >= 2) {
        nodeA = _trajectory.routeNodeIds[0];
        nodeB = _trajectory.routeNodeIds[1];
      } else if (_trajectory.routeNodeIds.isNotEmpty) {
        nodeA = _trajectory.routeNodeIds[0];
        nodeB = _trajectory.routeNodeIds[0];
      } else {
        nodeA = _state.startNodeId ?? 1;
        nodeB = nodeA;
      }
    }

    final nodeAObj = _graph!.nodes[nodeA];
    final nodeBObj = _graph!.nodes[nodeB];
    if (nodeAObj == null || nodeBObj == null) {
      _enterNoRoute();
      return;
    }

    if (nodeA == nodeB) {
      // Ambulance is at a junction
      final res = AStarRouter.findRoute(
        graph: _graph!,
        startNodeId: nodeA,
        goalNodeId: goalId,
      );
      if (res == null ||
          res.nodeIds.length < 2 ||
          !AStarRouter.assertRouteIsValid(_graph!, res.nodeIds)) {
        _enterNoRoute();
        return;
      }

      final newTrajectory = AmbulanceMover.buildTrajectory(
        graph: _graph!,
        nodeIds: res.nodeIds,
      );
      _trajectory = newTrajectory;

      final baseSpeedMps = _ambulanceSpeedKmh / 3.6;
      final etaSec = baseSpeedMps > 0 ? (newTrajectory.totalDistanceMeters / baseSpeedMps) : 0.0;
      final oldEta = _state.etaSeconds;

      final updatedAmbulance = amb.copyWith(
        distanceTravelledM: 0.0,
        totalRouteDistanceM: newTrajectory.totalDistanceMeters,
        polylineSegmentIndex: 0,
        currentEdgeFrom: res.nodeIds[0],
        currentEdgeTo: res.nodeIds[1],
      );

      final wasPausedOrNoRoute = _state.status == SimulationStatus.noRoute || _state.isPaused;

      _state = _state.copyWith(
        status: SimulationStatus.enRoute,
        ambulance: updatedAmbulance,
        routeNodeIds: res.nodeIds,
        routePolyline: newTrajectory.points,
        cumulativeDistances: newTrajectory.cumulativeDistances,
        totalRouteDistanceM: newTrajectory.totalDistanceMeters,
        remainingDistanceM: newTrajectory.totalDistanceMeters,
        etaSeconds: etaSec,
        oldEtaSeconds: oldEta > 0 ? oldEta : null,
        rerouteCount: _state.rerouteCount + 1,
        nodesExpandedAStar: res.nodesExpanded,
        isPaused: false,
      );

      if (wasPausedOrNoRoute) {
        _startTimer();
      }

      _recordTimelineEvent(
        'Dynamic Reroute',
        'Rerouted via A* from junction $nodeA (ETA: ${etaSec.toStringAsFixed(0)}s)',
        'reroute',
      );
      notifyListeners();
      return;
    }

    // Ambulance is mid-edge between nodeA and nodeB
    final distA = Haversine.distanceMeters(amb.lat, amb.lon, nodeAObj.lat, nodeAObj.lon);
    final distB = Haversine.distanceMeters(amb.lat, amb.lon, nodeBObj.lat, nodeBObj.lon);

    // Current edge congestion factor (ignoring blocked state per requirement 2)
    final edgeAB = _graph!.getEdge(nodeA, nodeB) ?? _graph!.getEdge(nodeB, nodeA);
    final edgeFactor = (edgeAB != null && !edgeAB.isBlocked) ? edgeAB.currentCongestion : 1.0;

    final costToA = distA * edgeFactor;
    final costToB = distB * edgeFactor;

    // Evaluate Option A (exit backwards to nodeA)
    RouteResult? resultA;
    double? totalCostA;
    if (nodeA == goalId) {
      totalCostA = costToA;
      resultA = RouteResult(
        nodeIds: [nodeA],
        totalDistanceMeters: distA,
        totalCost: costToA,
        nodesExpanded: 0,
      );
    } else {
      final res = AStarRouter.findRoute(
        graph: _graph!,
        startNodeId: nodeA,
        goalNodeId: goalId,
      );
      if (res != null) {
        totalCostA = costToA + res.totalCost;
        resultA = res;
      }
    }

    // Evaluate Option B (exit forward to nodeB)
    RouteResult? resultB;
    double? totalCostB;
    if (nodeB == goalId) {
      totalCostB = costToB;
      resultB = RouteResult(
        nodeIds: [nodeB],
        totalDistanceMeters: distB,
        totalCost: costToB,
        nodesExpanded: 0,
      );
    } else {
      final res = AStarRouter.findRoute(
        graph: _graph!,
        startNodeId: nodeB,
        goalNodeId: goalId,
      );
      if (res != null) {
        totalCostB = costToB + res.totalCost;
        resultB = res;
      }
    }

    if (resultA == null && resultB == null) {
      _enterNoRoute();
      return;
    }

    final bool chooseA;
    if (resultA != null && resultB != null) {
      chooseA = totalCostA! < totalCostB!;
    } else if (resultA != null) {
      chooseA = true;
    } else {
      chooseA = false;
    }

    final int exitFrom;
    final int exitTo;
    final RouteResult chosenResult;
    final List<int> combinedNodeIds;

    if (chooseA) {
      exitFrom = nodeB;
      exitTo = nodeA;
      chosenResult = resultA!;
      combinedNodeIds = [nodeB, ...resultA.nodeIds];
    } else {
      exitFrom = nodeA;
      exitTo = nodeB;
      chosenResult = resultB!;
      combinedNodeIds = [nodeA, ...resultB.nodeIds];
    }

    final isRouteValid = AStarRouter.assertRouteIsValid(
      _graph!,
      combinedNodeIds,
      currentEdgeFrom: exitFrom,
      currentEdgeTo: exitTo,
    );

    if (!isRouteValid) {
      _enterNoRoute();
      return;
    }

    final newTrajectory = AmbulanceMover.buildTrajectory(
      graph: _graph!,
      nodeIds: combinedNodeIds,
      startPosition: [amb.lat, amb.lon],
    );

    if (newTrajectory.isEmpty) {
      _enterNoRoute();
      return;
    }

    _trajectory = newTrajectory;

    final baseSpeedMps = _ambulanceSpeedKmh / 3.6;
    final etaSec = baseSpeedMps > 0 ? (newTrajectory.totalDistanceMeters / baseSpeedMps) : 0.0;
    final oldEta = _state.etaSeconds;

    final exitNodeObj = _graph!.nodes[exitTo]!;
    final newHeading = Haversine.bearingDegrees(
      amb.lat,
      amb.lon,
      exitNodeObj.lat,
      exitNodeObj.lon,
    );

    final updatedAmbulance = amb.copyWith(
      headingDegrees: newHeading,
      distanceTravelledM: 0.0,
      totalRouteDistanceM: newTrajectory.totalDistanceMeters,
      polylineSegmentIndex: 0,
      currentEdgeFrom: exitFrom,
      currentEdgeTo: exitTo,
    );

    final wasPausedOrNoRoute = _state.status == SimulationStatus.noRoute || _state.isPaused;

    _state = _state.copyWith(
      status: SimulationStatus.enRoute,
      ambulance: updatedAmbulance,
      routeNodeIds: combinedNodeIds,
      routePolyline: newTrajectory.points,
      cumulativeDistances: newTrajectory.cumulativeDistances,
      totalRouteDistanceM: newTrajectory.totalDistanceMeters,
      remainingDistanceM: newTrajectory.totalDistanceMeters,
      etaSeconds: etaSec,
      oldEtaSeconds: oldEta > 0 ? oldEta : null,
      rerouteCount: _state.rerouteCount + 1,
      nodesExpandedAStar: chosenResult.nodesExpanded,
      isPaused: false,
    );

    if (wasPausedOrNoRoute) {
      _startTimer();
    }

    _recordTimelineEvent(
      'Dynamic Reroute',
      'Rerouted via A* exiting via node $exitTo (New ETA: ${etaSec.toStringAsFixed(0)}s)',
      'reroute',
    );

    notifyListeners();
  }

  void _computeAndApplyRoute({
    required int fromNodeId,
    required int toNodeId,
    required bool isInitial,
    double? oldEta,
  }) {
    if (_graph == null) return;

    final astarResult = AStarRouter.findRoute(
      graph: _graph!,
      startNodeId: fromNodeId,
      goalNodeId: toNodeId,
    );

    RouteResult? dijkstraResult;
    if (_showDijkstraComparison) {
      dijkstraResult = AStarRouter.findRouteDijkstra(
        graph: _graph!,
        startNodeId: fromNodeId,
        goalNodeId: toNodeId,
      );
    }

    // Trip setup validation: require at least 2 nodes, >= 500m on initial, and assertRouteIsValid
    if (astarResult == null ||
        astarResult.nodeIds.length < 2 ||
        (isInitial && astarResult.totalDistanceMeters < 500.0) ||
        !AStarRouter.assertRouteIsValid(_graph!, astarResult.nodeIds)) {
      _enterNoRoute();
      return;
    }

    final newTrajectory = AmbulanceMover.buildTrajectory(
      graph: _graph!,
      nodeIds: astarResult.nodeIds,
      startPosition: isInitial ? null : [_state.ambulance.lat, _state.ambulance.lon],
    );
    _trajectory = newTrajectory;

    final baseSpeedMps = _ambulanceSpeedKmh / 3.6;
    final etaSec = baseSpeedMps > 0 ? (newTrajectory.totalDistanceMeters / baseSpeedMps) : 0.0;

    // Debug logging as required by section 4(g)
    final routeSignals = _signalManager.signals
        .where((s) => astarResult.nodeIds.contains(s.nodeId))
        .map((s) => '${s.id} (node ${s.nodeId})')
        .toList();

    // ignore: avoid_print
    print('==================================================');
    // ignore: avoid_print
    print('[SIMULATION] ${isInitial ? "TRIP STARTED" : "DYNAMIC REROUTE"}');
    // ignore: avoid_print
    print('Route Distance: ${newTrajectory.totalDistanceMeters.toStringAsFixed(1)} m');
    // ignore: avoid_print
    print('Route Nodes (${astarResult.nodeIds.length}): ${astarResult.nodeIds}');
    // ignore: avoid_print
    print('Signals on Route (${routeSignals.length}): $routeSignals');
    // ignore: avoid_print
    print('Estimated Trip Time: ${etaSec.toStringAsFixed(0)} s (${(etaSec / 60).toStringAsFixed(1)} min at $_ambulanceSpeedKmh km/h)');
    // ignore: avoid_print
    print('==================================================');

    if (isInitial) {
      final startNode = _graph!.nodes[fromNodeId];
      final amb = Ambulance(
        lat: startNode?.lat ?? _state.ambulance.lat,
        lon: startNode?.lon ?? _state.ambulance.lon,
        speedMps: baseSpeedMps,
        distanceTravelledM: 0.0,
        totalRouteDistanceM: newTrajectory.totalDistanceMeters,
        currentEdgeFrom: astarResult.nodeIds[0],
        currentEdgeTo: astarResult.nodeIds[1],
      );

      _state = _state.copyWith(
        status: SimulationStatus.enRoute,
        ambulance: amb,
        routeNodeIds: astarResult.nodeIds,
        routePolyline: newTrajectory.points,
        cumulativeDistances: newTrajectory.cumulativeDistances,
        totalRouteDistanceM: newTrajectory.totalDistanceMeters,
        remainingDistanceM: newTrajectory.totalDistanceMeters,
        etaSeconds: etaSec,
        elapsedTimeSeconds: 0.0,
        signalsClearedCount: 0,
        nodesExpandedAStar: astarResult.nodesExpanded,
        nodesExpandedDijkstra: dijkstraResult?.nodesExpanded,
        isPaused: false,
      );

      _recordTimelineEvent(
        'Trip Started',
        'Calculated path: ${astarResult.nodeIds.length} nodes, ${astarResult.totalDistanceMeters.toStringAsFixed(0)}m, ${routeSignals.length} signals',
        'route',
      );
    } else {
      // Dynamic reroute mid-trip: seamlessly continue from current position
      final amb = _state.ambulance.copyWith(
        lat: newTrajectory.points.first[0],
        lon: newTrajectory.points.first[1],
        distanceTravelledM: 0.0,
        totalRouteDistanceM: newTrajectory.totalDistanceMeters,
        polylineSegmentIndex: 0,
        currentEdgeFrom: astarResult.nodeIds[0],
        currentEdgeTo: astarResult.nodeIds[1],
      );

      _state = _state.copyWith(
        ambulance: amb,
        routeNodeIds: astarResult.nodeIds,
        routePolyline: newTrajectory.points,
        cumulativeDistances: newTrajectory.cumulativeDistances,
        totalRouteDistanceM: newTrajectory.totalDistanceMeters,
        remainingDistanceM: newTrajectory.totalDistanceMeters,
        etaSeconds: etaSec,
        oldEtaSeconds: oldEta,
        rerouteCount: _state.rerouteCount + 1,
        nodesExpandedAStar: astarResult.nodesExpanded,
        nodesExpandedDijkstra: dijkstraResult?.nodesExpanded,
      );

      _recordTimelineEvent(
        'Dynamic Reroute',
        'Rerouted via A* due to traffic changes (Old ETA: ${oldEta?.toStringAsFixed(0)}s -> New ETA: ${etaSec.toStringAsFixed(0)}s)',
        'reroute',
      );
    }

    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: AppConstants.tickMs),
      (_) => tick(),
    );
  }

  /// Executes a single discrete simulation tick (500ms dt * timeScale).
  /// Synchronous core logic allows both runtime UI timer and headless testing loops.
  void tick() {
    if (_state.status != SimulationStatus.enRoute || _state.isPaused) return;

    final dtSeconds = (AppConstants.tickMs / 1000.0);
    final baseSpeedMps = _ambulanceSpeedKmh / 3.6;

    // 1. Advance ambulance position along route polyline
    final updatedAmbulance = AmbulanceMover.advance(
      current: _state.ambulance,
      trajectory: _trajectory,
      baseSpeedMps: baseSpeedMps,
      dtSeconds: dtSeconds,
      timeScale: _timeScale,
      graph: _graph,
    );

    final remainingDist = updatedAmbulance.remainingDistanceM;
    final effectiveSpeed = updatedAmbulance.speedMps;
    final etaSec = effectiveSpeed > 0 ? (remainingDist / effectiveSpeed) : 0.0;
    final newElapsedTime = _state.elapsedTimeSeconds + (dtSeconds * _timeScale);

    // 2. Update SignalManager with arc-length tracking and hysteresis
    _signalManager.update(
      ambulance: updatedAmbulance,
      routeNodeIds: _trajectory.routeNodeIds,
      dtSeconds: dtSeconds * _timeScale,
      nodeCumulativeDistances: _trajectory.nodeCumulativeDistances,
      distanceTravelledM: updatedAmbulance.distanceTravelledM,
    );

    // 3. State Machine Check for ARRIVAL
    // ARRIVED may ONLY be set when: status is EN_ROUTE, distanceTravelled > 0,
    // and remaining distance < ARRIVAL_RADIUS_M.
    if (updatedAmbulance.distanceTravelledM > 0 &&
        _trajectory.totalDistanceMeters >= 500.0 &&
        (remainingDist <= AppConstants.arrivalRadiusM ||
            updatedAmbulance.distanceTravelledM >= _trajectory.totalDistanceMeters)) {
      _timer?.cancel();
      _signalManager.revertAllPreemptions();

      _state = _state.copyWith(
        status: SimulationStatus.arrived,
        ambulance: updatedAmbulance,
        signals: _signalManager.signals,
        activeSignalId: null,
        remainingDistanceM: 0.0,
        etaSeconds: 0.0,
        elapsedTimeSeconds: newElapsedTime,
        signalsClearedCount: _signalManager.clearedCount,
        loraLogs: _loraLink.logs,
      );

      // ignore: avoid_print
      print('==================================================');
      // ignore: avoid_print
      print('[SIMULATION] ARRIVED AT HOSPITAL: ${_state.targetHospital?.name}');
      // ignore: avoid_print
      print('Total Elapsed Sim-Time: ${newElapsedTime.toStringAsFixed(1)} s');
      // ignore: avoid_print
      print('Total Travelled: ${updatedAmbulance.distanceTravelledM.toStringAsFixed(1)} m');
      // ignore: avoid_print
      print('Signals Cleared: ${_signalManager.clearedCount}');
      // ignore: avoid_print
      print('==================================================');

      _recordTimelineEvent(
        'Arrived at Hospital',
        'Ambulance safely reached ${_state.targetHospital?.name ?? "destination"}. Elapsed: ${newElapsedTime.toStringAsFixed(0)}s. Signals cleared: ${_signalManager.clearedCount}.',
        'arrival',
      );
      notifyListeners();
      return;
    }

    // 4. Normal tick state snapshot update
    _state = _state.copyWith(
      ambulance: updatedAmbulance,
      signals: _signalManager.signals,
      activeSignalId: _signalManager.activeSignalId,
      remainingDistanceM: remainingDist,
      etaSeconds: etaSec,
      elapsedTimeSeconds: newElapsedTime,
      signalsClearedCount: _signalManager.clearedCount,
      loraLogs: _loraLink.logs,
    );

    notifyListeners();
  }

  void _recordTimelineEvent(String title, String description, String type) {
    final event = SimEvent(
      timestamp: DateTime.now(),
      title: title,
      description: description,
      type: type,
    );
    final updatedList = List<SimEvent>.from(_state.timelineEvents)..insert(0, event);
    _state = _state.copyWith(timelineEvents: updatedList);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
