import 'dart:math' as math;
import '../algorithms/haversine.dart';
import '../config/constants.dart';
import '../models/ambulance.dart';
import '../models/road_graph.dart';
import '../models/traffic_signal.dart';
import 'lora_link_simulator.dart';

/// Callback signature for simulation milestone events.
typedef SignalEventCallback = void Function(
    String title, String description, String type);

/// Manages traffic signal states, preemption triggers, hysteresis revert logic,
/// and manual overrides communicated over the simulated LoRa RF link.
class SignalManager {
  final Map<String, TrafficSignal> _signals = {};
  final LoRaLinkSimulator loraLink;
  final SignalEventCallback? onEvent;

  double greenTriggerRadiusM = AppConstants.greenTriggerRadiusM;
  double revertHysteresisM = AppConstants.revertHysteresisM;

  // Track previous distance and consecutive increase count per signal
  final Map<String, double> _prevDistances = {};
  final Map<String, int> _increaseCounts = {};
  final Set<String> _clearedSignalIds = {};

  String? _activeSignalId;
  int _clearedCount = 0;

  SignalManager({
    required this.loraLink,
    this.onEvent,
    double? triggerRadius,
  }) : greenTriggerRadiusM = triggerRadius ?? AppConstants.greenTriggerRadiusM;

  List<TrafficSignal> get signals => _signals.values.toList();
  String? get activeSignalId => _activeSignalId;
  int get clearedCount => _clearedCount;
  Set<String> get clearedSignalIds => Set.unmodifiable(_clearedSignalIds);

  /// Initializes signals from the RoadGraph with staggered initial cycle offsets.
  void initFromGraph(RoadGraph graph) {
    _signals.clear();
    _prevDistances.clear();
    _increaseCounts.clear();
    _clearedSignalIds.clear();
    _activeSignalId = null;
    _clearedCount = 0;

    final rng = math.Random(1337);

    for (final node in graph.nodes.values) {
      if (node.hasSignal && node.signalId != null) {
        // Stagger initial cycle offset so lights don't change all at once
        final randomOffset = rng.nextDouble() * (AppConstants.normalCycleSeconds * 2.0);
        final initialIsGreen = randomOffset > AppConstants.normalCycleSeconds;

        final sig = TrafficSignal(
          id: node.signalId!,
          nodeId: node.id,
          lat: node.lat,
          lon: node.lon,
          signalSource: node.signalSource ?? 'osm',
          state: initialIsGreen ? SignalState.green : SignalState.red,
          cycleElapsedSeconds: randomOffset % AppConstants.normalCycleSeconds,
        );
        _signals[sig.id] = sig;
      }
    }
  }

  /// Reset all signals to clean initial state.
  void reset() {
    _prevDistances.clear();
    _increaseCounts.clear();
    _clearedSignalIds.clear();
    _activeSignalId = null;
    _clearedCount = 0;
    for (final sig in _signals.values) {
      sig.overrideState = SignalOverride.none;
      sig.state = SignalState.red;
      sig.distanceToAmbulance = null;
    }
  }

  /// Manually override an individual signal (Force Green, Force Red, or Auto).
  void setOverride(String signalId, SignalOverride overrideState) {
    final signal = _signals[signalId];
    if (signal == null) return;

    signal.overrideState = overrideState;
    if (overrideState == SignalOverride.forceGreen) {
      signal.state = SignalState.green;
      loraLink.sendCommand(
        signalId: signalId,
        command: 'FORCE_GREEN (OVERRIDE)',
        onDelivered: () {
          signal.state = SignalState.green;
        },
      );
      onEvent?.call('Signal Override', 'Signal $signalId forced GREEN by officer', 'lora');
    } else if (overrideState == SignalOverride.forceRed) {
      signal.state = SignalState.red;
      loraLink.sendCommand(
        signalId: signalId,
        command: 'FORCE_RED (OVERRIDE)',
        onDelivered: () {
          signal.state = SignalState.red;
        },
      );
      onEvent?.call('Signal Override', 'Signal $signalId forced RED by officer', 'lora');
    } else {
      // Reverted to Auto
      loraLink.sendCommand(
        signalId: signalId,
        command: 'AUTO_MODE_RESTORED',
        onDelivered: () {},
      );
      onEvent?.call('Signal Auto', 'Signal $signalId restored to automatic control', 'lora');
    }
  }

  /// Primary simulation tick logic: updates normal cycles and evaluates preemption triggers.
  void update({
    required Ambulance ambulance,
    required List<int> routeNodeIds,
    required double dtSeconds,
    Map<int, double>? nodeCumulativeDistances,
    double? distanceTravelledM,
  }) {
    // 1. Advance normal cycle for non-preempted, non-overridden signals
    for (final sig in _signals.values) {
      if (sig.isOverridden) {
        // Enforce override
        if (sig.overrideState == SignalOverride.forceGreen) {
          sig.state = SignalState.green;
        } else if (sig.overrideState == SignalOverride.forceRed) {
          sig.state = SignalState.red;
        }
        continue;
      }

      if (sig.state == SignalState.greenPriority || sig.state == SignalState.pendingGreen) {
        // Preemption pauses the normal cycle timer
        continue;
      }

      // Normal cycle timing
      sig.cycleElapsedSeconds += dtSeconds;
      if (sig.cycleElapsedSeconds >= AppConstants.normalCycleSeconds) {
        sig.cycleElapsedSeconds = 0.0;
        sig.state = (sig.state == SignalState.red) ? SignalState.green : SignalState.red;
      }
    }

    // 2. Compute Haversine distance to ambulance for all signals
    for (final sig in _signals.values) {
      final d = Haversine.distanceMeters(
        ambulance.lat,
        ambulance.lon,
        sig.lat,
        sig.lon,
      );
      sig.distanceToAmbulance = d;
    }

    // 3. Identify signals located along the route IN ROUTE ORDER
    final upcomingSignalsOnRoute = <TrafficSignal>[];
    for (final nodeId in routeNodeIds) {
      for (final sig in _signals.values) {
        if (sig.nodeId == nodeId && !_clearedSignalIds.contains(sig.id)) {
          if (!upcomingSignalsOnRoute.contains(sig)) {
            // Check if not already passed along polyline
            if (nodeCumulativeDistances != null && distanceTravelledM != null) {
              final sigDist = nodeCumulativeDistances[sig.nodeId];
              if (sigDist != null && distanceTravelledM > sigDist + revertHysteresisM) {
                continue; // already passed
              }
            }
            upcomingSignalsOnRoute.add(sig);
          }
        }
      }
    }

    // Active signal is the nearest upcoming signal ahead on the route
    TrafficSignal? activeSig;
    if (upcomingSignalsOnRoute.isNotEmpty) {
      activeSig = upcomingSignalsOnRoute.first;
    }
    _activeSignalId = activeSig?.id;

    // 4. Evaluate Green Preemption Trigger
    if (activeSig != null && !activeSig.isOverridden) {
      final directDist = activeSig.distanceToAmbulance ?? double.infinity;
      double routeDist = double.infinity;
      if (nodeCumulativeDistances != null && distanceTravelledM != null) {
        final nodeDist = nodeCumulativeDistances[activeSig.nodeId];
        if (nodeDist != null) {
          routeDist = nodeDist - distanceTravelledM;
        }
      }

      final isWithinTriggerZone = directDist <= greenTriggerRadiusM ||
          (routeDist >= -revertHysteresisM && routeDist <= greenTriggerRadiusM);

      if (isWithinTriggerZone &&
          activeSig.state != SignalState.greenPriority &&
          activeSig.state != SignalState.pendingGreen) {
        // Set pending state immediately
        activeSig.state = SignalState.pendingGreen;
        final targetSig = activeSig;
        loraLink.sendCommand(
          signalId: targetSig.id,
          command: 'SET_GREEN_PRIORITY',
          onDelivered: () {
            if (targetSig.state == SignalState.pendingGreen &&
                targetSig.overrideState == SignalOverride.none) {
              targetSig.state = SignalState.greenPriority;
              targetSig.lastStateChange = DateTime.now();
              // ignore: avoid_print
              print('[PREEMPTION] Signal ${targetSig.id} (Node ${targetSig.nodeId}) -> GREEN_PRIORITY via LoRa');
            }
          },
        );
        onEvent?.call(
          'Emergency Preemption',
          'Ambulance within ${directDist.toStringAsFixed(0)}m of Signal ${targetSig.id} - Requesting Green via LoRa',
          'signal',
        );
      }
    }

    // 5. Evaluate Revert Trigger with Hysteresis and segment-crossing check
    for (final sig in _signals.values) {
      if (sig.state == SignalState.greenPriority || sig.state == SignalState.pendingGreen) {
        final currentDist = sig.distanceToAmbulance ?? double.infinity;
        final prevDist = _prevDistances[sig.id] ?? currentDist;

        if (currentDist > prevDist + 0.1) {
          _increaseCounts[sig.id] = (_increaseCounts[sig.id] ?? 0) + 1;
        } else {
          _increaseCounts[sig.id] = 0;
        }

        final deltaIncrease = currentDist - prevDist;
        final isDistanceGrowing = deltaIncrease >= revertHysteresisM ||
            (_increaseCounts[sig.id] ?? 0) >= 2;

        bool passedAlongRoute = false;
        if (nodeCumulativeDistances != null && distanceTravelledM != null) {
          final sigNodeDist = nodeCumulativeDistances[sig.nodeId];
          if (sigNodeDist != null) {
            passedAlongRoute = distanceTravelledM > (sigNodeDist + revertHysteresisM);
          }
        }

        final isNoLongerOnRoute = !routeNodeIds.contains(sig.nodeId);

        if (passedAlongRoute || isDistanceGrowing || isNoLongerOnRoute) {
          _revertSignal(sig);
        }

        _prevDistances[sig.id] = currentDist;
      } else {
        _prevDistances[sig.id] = sig.distanceToAmbulance ?? double.infinity;
      }
    }
  }

  void _revertSignal(TrafficSignal sig) {
    if (_clearedSignalIds.contains(sig.id)) return;
    _clearedSignalIds.add(sig.id);
    _clearedCount++;
    _increaseCounts[sig.id] = 0;
    sig.state = SignalState.red;
    sig.cycleElapsedSeconds = 0.0;
    sig.lastStateChange = DateTime.now();

    loraLink.sendCommand(
      signalId: sig.id,
      command: 'REVERT_NORMAL_CYCLE',
      onDelivered: () {
        if (!sig.isOverridden) {
          sig.state = SignalState.red; // Safe transition back to normal
        }
      },
    );

    // ignore: avoid_print
    print('[REVERT] Signal ${sig.id} (Node ${sig.nodeId}) -> NORMAL_CYCLE. Cleared total: $_clearedCount');

    onEvent?.call(
      'Signal Cleared',
      'Ambulance passed Signal ${sig.id} - Reverting to normal cycle via LoRa',
      'signal',
    );
  }

  /// Reverts any active preemptions (e.g. when simulation finishes or resets).
  void revertAllPreemptions() {
    for (final sig in _signals.values) {
      if (sig.state == SignalState.greenPriority || sig.state == SignalState.pendingGreen) {
        sig.state = SignalState.red;
      }
    }
  }
}
