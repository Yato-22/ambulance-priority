import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/models/ambulance.dart';
import 'package:ambulance_priority/models/graph_node.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/models/traffic_signal.dart';
import 'package:ambulance_priority/simulation/lora_link_simulator.dart';
import 'package:ambulance_priority/simulation/signal_manager.dart';

void main() {
  group('SignalManager Logic Tests', () {
    late RoadGraph graph;
    late LoRaLinkSimulator lora;
    late SignalManager manager;

    setUp(() {
      lora = LoRaLinkSimulator(packetLossProbability: 0.0);
      manager = SignalManager(loraLink: lora, triggerRadius: 200.0);

      // Graph with two signal nodes:
      // Node 1: (18.4900, 73.8200) - Start
      // Node 2: (18.4910, 73.8200) - Signal S1
      // Node 3: (18.4930, 73.8200) - Signal S2
      final nodes = <int, GraphNode>{
        1: const GraphNode(id: 1, lat: 18.4900, lon: 73.8200),
        2: const GraphNode(
          id: 2,
          lat: 18.4910,
          lon: 73.8200,
          hasSignal: true,
          signalId: 'S1',
        ),
        3: const GraphNode(
          id: 3,
          lat: 18.4930,
          lon: 73.8200,
          hasSignal: true,
          signalId: 'S2',
        ),
      };

      graph = RoadGraph(
        meta: {},
        nodes: nodes,
        edges: [],
        adjacency: {},
        hospitals: [],
      );

      manager.initFromGraph(graph);
    });

    test('Signal triggers pending/green priority when ambulance enters 200m radius', () {
      final s1 = manager.signals.firstWhere((s) => s.id == 'S1');
      expect(s1.overrideState, equals(SignalOverride.none));

      // S1 is at (18.4910, 73.8200). Place ambulance ~100m away at (18.4901, 73.8200)
      final amb = const Ambulance(lat: 18.4901, lon: 73.8200);

      manager.update(
        ambulance: amb,
        routeNodeIds: [1, 2, 3],
        dtSeconds: 0.5,
      );

      // S1 should have entered pendingGreen or greenPriority
      expect(
        s1.state == SignalState.pendingGreen || s1.state == SignalState.greenPriority,
        isTrue,
      );
    });

    test('Manual override takes absolute precedence over ambulance proximity', () {
      final s1 = manager.signals.firstWhere((s) => s.id == 'S1');
      // Officer sets FORCE_RED
      manager.setOverride('S1', SignalOverride.forceRed);
      expect(s1.overrideState, equals(SignalOverride.forceRed));

      // Place ambulance 50m away from S1
      final amb = const Ambulance(lat: 18.4905, lon: 73.8200);

      manager.update(
        ambulance: amb,
        routeNodeIds: [1, 2, 3],
        dtSeconds: 0.5,
      );

      // Signal must stay strictly RED
      expect(s1.state, equals(SignalState.red));
    });

    test('Signal reverts to normal cycle when distance increases (ambulance passes)', () {
      final s1 = manager.signals.firstWhere((s) => s.id == 'S1');
      s1.state = SignalState.greenPriority;

      // Ambulance was at (18.4909, 73.8200) (~11m from S1)
      final amb1 = const Ambulance(lat: 18.4909, lon: 73.8200);
      manager.update(
        ambulance: amb1,
        routeNodeIds: [2, 3],
        dtSeconds: 0.5,
      );

      // Now ambulance moves further away to (18.4915, 73.8200) (distance increased significantly > 50m)
      final amb2 = const Ambulance(lat: 18.4915, lon: 73.8200);
      manager.update(
        ambulance: amb2,
        routeNodeIds: [3], // S1 passed, now heading to S2
        dtSeconds: 0.5,
      );

      expect(manager.clearedCount, greaterThanOrEqualTo(1));
    });
  });
}
