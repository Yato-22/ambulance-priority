import 'ambulance.dart';
import 'hospital.dart';
import 'traffic_signal.dart';

/// Overall state machine status of the ambulance trip simulation.
enum SimulationStatus {
  idle,
  routing,
  enRoute,
  arrived,
  noRoute,
}

/// A timeline milestone event recorded during the simulation (for Hospital screen).
class SimEvent {
  final DateTime timestamp;
  final String title;
  final String description;
  final String type; // 'route', 'signal', 'reroute', 'arrival', 'lora'

  const SimEvent({
    required this.timestamp,
    required this.title,
    required this.description,
    required this.type,
  });
}

/// A log entry representing simulated LoRa SX1262 865 MHz packet transmission.
class LoRaPacketLog {
  final DateTime timestamp;
  final String direction; // 'TX' (Control -> Signal) or 'RX' (Signal -> Control)
  final String signalId;
  final String command; // e.g. 'SET_GREEN_PRIORITY', 'REVERT_NORMAL', 'FORCE_GREEN'
  final String status; // 'DELIVERED', 'ACK', 'DROPPED', 'RETRY'
  final int latencyMs;
  final int retryCount;

  const LoRaPacketLog({
    required this.timestamp,
    required this.direction,
    required this.signalId,
    required this.command,
    required this.status,
    required this.latencyMs,
    this.retryCount = 0,
  });

  @override
  String toString() =>
      '[${timestamp.toIso8601String().substring(11, 19)}] $direction -> $signalId: $command ($status, ${latencyMs}ms)';
}

/// Immutable snapshot of the simulation state consumed by the UI.
class SimState {
  final SimulationStatus status;
  final int? startNodeId;
  final Hospital? targetHospital;
  final Ambulance ambulance;
  final List<TrafficSignal> signals;
  final String? activeSignalId;
  final List<int> routeNodeIds;
  final List<List<double>> routePolyline; // [[lat, lon], ...]
  final List<double> cumulativeDistances; // meters along polyline
  final double totalRouteDistanceM;
  final double remainingDistanceM;
  final double etaSeconds;
  final double? oldEtaSeconds;
  final double elapsedTimeSeconds;
  final int signalsClearedCount;
  final int nodesExpandedAStar;
  final int? nodesExpandedDijkstra;
  final int rerouteCount;
  final bool isPaused;
  final double timeScale;
  final List<SimEvent> timelineEvents;
  final List<LoRaPacketLog> loraLogs;

  const SimState({
    required this.status,
    this.startNodeId,
    this.targetHospital,
    required this.ambulance,
    required this.signals,
    this.activeSignalId,
    this.routeNodeIds = const [],
    this.routePolyline = const [],
    this.cumulativeDistances = const [],
    this.totalRouteDistanceM = 0.0,
    this.remainingDistanceM = 0.0,
    this.etaSeconds = 0.0,
    this.oldEtaSeconds,
    this.elapsedTimeSeconds = 0.0,
    this.signalsClearedCount = 0,
    this.nodesExpandedAStar = 0,
    this.nodesExpandedDijkstra,
    this.rerouteCount = 0,
    this.isPaused = false,
    this.timeScale = 1.0,
    this.timelineEvents = const [],
    this.loraLogs = const [],
  });

  /// Initial idle state.
  factory SimState.initial({
    required double defaultLat,
    required double defaultLon,
    List<TrafficSignal> initialSignals = const [],
  }) {
    return SimState(
      status: SimulationStatus.idle,
      ambulance: Ambulance(lat: defaultLat, lon: defaultLon),
      signals: initialSignals,
    );
  }

  SimState copyWith({
    SimulationStatus? status,
    int? startNodeId,
    Hospital? targetHospital,
    Ambulance? ambulance,
    List<TrafficSignal>? signals,
    String? activeSignalId,
    List<int>? routeNodeIds,
    List<List<double>>? routePolyline,
    List<double>? cumulativeDistances,
    double? totalRouteDistanceM,
    double? remainingDistanceM,
    double? etaSeconds,
    double? oldEtaSeconds,
    double? elapsedTimeSeconds,
    int? signalsClearedCount,
    int? nodesExpandedAStar,
    int? nodesExpandedDijkstra,
    int? rerouteCount,
    bool? isPaused,
    double? timeScale,
    List<SimEvent>? timelineEvents,
    List<LoRaPacketLog>? loraLogs,
  }) {
    return SimState(
      status: status ?? this.status,
      startNodeId: startNodeId ?? this.startNodeId,
      targetHospital: targetHospital ?? this.targetHospital,
      ambulance: ambulance ?? this.ambulance,
      signals: signals ?? this.signals,
      activeSignalId: activeSignalId ?? this.activeSignalId,
      routeNodeIds: routeNodeIds ?? this.routeNodeIds,
      routePolyline: routePolyline ?? this.routePolyline,
      cumulativeDistances: cumulativeDistances ?? this.cumulativeDistances,
      totalRouteDistanceM: totalRouteDistanceM ?? this.totalRouteDistanceM,
      remainingDistanceM: remainingDistanceM ?? this.remainingDistanceM,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      oldEtaSeconds: oldEtaSeconds ?? this.oldEtaSeconds,
      elapsedTimeSeconds: elapsedTimeSeconds ?? this.elapsedTimeSeconds,
      signalsClearedCount: signalsClearedCount ?? this.signalsClearedCount,
      nodesExpandedAStar: nodesExpandedAStar ?? this.nodesExpandedAStar,
      nodesExpandedDijkstra: nodesExpandedDijkstra ?? this.nodesExpandedDijkstra,
      rerouteCount: rerouteCount ?? this.rerouteCount,
      isPaused: isPaused ?? this.isPaused,
      timeScale: timeScale ?? this.timeScale,
      timelineEvents: timelineEvents ?? this.timelineEvents,
      loraLogs: loraLogs ?? this.loraLogs,
    );
  }
}

