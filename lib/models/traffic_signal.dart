/// Operational state of a traffic signal.
enum SignalState {
  red,
  green,
  pendingGreen,
  greenPriority,
}

/// Manual override commanded from the Control Station.
enum SignalOverride {
  none,
  forceGreen,
  forceRed,
}

/// Represents a traffic signal unit (with simulated LoRa SX1262 transceivers).
class TrafficSignal {
  final String id;
  final int nodeId;
  final double lat;
  final double lon;
  final String signalSource;

  SignalState state;
  SignalOverride overrideState;
  double? distanceToAmbulance;
  DateTime lastStateChange;
  double cycleElapsedSeconds;

  TrafficSignal({
    required this.id,
    required this.nodeId,
    required this.lat,
    required this.lon,
    this.signalSource = 'osm',
    this.state = SignalState.red,
    this.overrideState = SignalOverride.none,
    this.distanceToAmbulance,
    DateTime? lastStateChange,
    this.cycleElapsedSeconds = 0.0,
  }) : lastStateChange = lastStateChange ?? DateTime.now();

  bool get isPreempted => state == SignalState.greenPriority || state == SignalState.pendingGreen;
  bool get isOverridden => overrideState != SignalOverride.none;

  TrafficSignal copyWith({
    SignalState? state,
    SignalOverride? overrideState,
    double? distanceToAmbulance,
    DateTime? lastStateChange,
    double? cycleElapsedSeconds,
  }) {
    return TrafficSignal(
      id: id,
      nodeId: nodeId,
      lat: lat,
      lon: lon,
      signalSource: signalSource,
      state: state ?? this.state,
      overrideState: overrideState ?? this.overrideState,
      distanceToAmbulance: distanceToAmbulance ?? this.distanceToAmbulance,
      lastStateChange: lastStateChange ?? this.lastStateChange,
      cycleElapsedSeconds: cycleElapsedSeconds ?? this.cycleElapsedSeconds,
    );
  }

  @override
  String toString() =>
      'TrafficSignal(id: $id, node: $nodeId, state: ${state.name}, override: ${overrideState.name})';
}
