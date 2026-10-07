import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/haversine.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/sim_state.dart';
import 'package:ambulance_priority/models/traffic_signal.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';

void main() {
  group('Simulation Engine & Signal Preemption Tests', () {
    late SimulationController controller;

    setUp(() {
      controller = SimulationController();
      final graph = SampleGraphBuilder.build();
      controller.setGraph(graph);
    });

    test('Trip setup validation: requires start != destination and route length >= 500m', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectHospital(h2);

      // Force startNodeId == h2.nodeId
      controller.selectStartNode(h2.nodeId);

      // Starting trip must automatically fix startNode to farthest node
      controller.startTrip();

      expect(controller.state.status, equals(SimulationStatus.enRoute));
      expect(controller.state.startNodeId, isNot(equals(h2.nodeId)));
      expect(controller.state.totalRouteDistanceM, greaterThanOrEqualTo(500.0));
      expect(controller.state.ambulance.distanceTravelledM, equals(0.0));
    });

    test('Route for default start (Node 1) to Hospital H2 (Node 42) passes through at least 3 signals', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.startTrip();

      final routeSignals = controller.signalManager.signals
          .where((s) => controller.state.routeNodeIds.contains(s.nodeId))
          .toList();

      // ignore: avoid_print
      print('Route contains ${routeSignals.length} signals: ${routeSignals.map((s) => s.id).toList()}');
      expect(routeSignals.length, greaterThanOrEqualTo(3));
    });

    test('Full headless trip: elapsed sim-time > 60s, all route signals preempted and cleared', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);

      // Run at 2x speed for faster testing execution while recording simulated time
      controller.setTimeScale(2.0);
      controller.setAmbulanceSpeed(40.0);

      controller.startTrip();

      final routeSignals = controller.signalManager.signals
          .where((s) => controller.state.routeNodeIds.contains(s.nodeId))
          .map((s) => s.id)
          .toSet();

      final signalsSeenPreempted = <String>{};
      int maxTicks = 800;
      int ticks = 0;

      while (controller.state.status == SimulationStatus.enRoute && ticks < maxTicks) {
        ticks++;
        controller.tick();

        for (final sig in controller.state.signals) {
          if (routeSignals.contains(sig.id) &&
              (sig.state == SignalState.greenPriority || sig.state == SignalState.pendingGreen)) {
            signalsSeenPreempted.add(sig.id);
          }
        }
      }

      // 1. Status ends ARRIVED
      expect(controller.state.status, equals(SimulationStatus.arrived));

      // 2. Elapsed sim-time > 60s (at 40 km/h over ~2.3km route, takes ~200s)
      expect(controller.state.elapsedTimeSeconds, greaterThan(60.0));

      // 3. Every signal on the route reached GREEN_PRIORITY
      expect(signalsSeenPreempted.length, equals(routeSignals.length));

      // 4. signalsCleared == number of signals on route
      expect(controller.state.signalsClearedCount, equals(routeSignals.length));

      // 5. All signals returned to normal cycle afterward
      for (final sig in controller.state.signals) {
        expect(
          sig.state != SignalState.greenPriority && sig.state != SignalState.pendingGreen,
          isTrue,
        );
      }
    });

    test('Dynamic reroute mid-trip: blocks upcoming road, computes new path without teleportation', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.setTimeScale(1.0);
      controller.setAmbulanceSpeed(40.0);

      controller.startTrip();

      // Advance 10 ticks along route
      for (int i = 0; i < 10; i++) {
        controller.tick();
      }

      final posBeforeBlock = controller.state.ambulance;
      final initialRoute = List<int>.from(controller.state.routeNodeIds);

      // Block an edge further ahead on the route (e.g. between 3rd and 4th node on route)
      expect(initialRoute.length, greaterThan(4));
      final blockFrom = initialRoute[2];
      final blockTo = initialRoute[3];

      controller.blockRoad(blockFrom, blockTo);

      // Verify rerouting occurred
      expect(controller.state.status, equals(SimulationStatus.enRoute));
      expect(controller.state.rerouteCount, greaterThanOrEqualTo(1));

      // Tick once after reroute
      controller.tick();
      final posAfterTick = controller.state.ambulance;

      // Assert no teleporting: distance jumped between ticks < 2x normal per-tick distance
      final jumpMeters = Haversine.distanceMeters(
        posBeforeBlock.lat,
        posBeforeBlock.lon,
        posAfterTick.lat,
        posAfterTick.lon,
      );
      final maxExpectedStepM = (40.0 / 3.6) * 0.5 * 2.0; // 2x normal per-tick distance
      expect(jumpMeters, lessThan(maxExpectedStepM + 5.0));

      // Trip still arrives at destination
      int ticks = 0;
      while (controller.state.status == SimulationStatus.enRoute && ticks < 800) {
        ticks++;
        controller.tick();
      }
      expect(controller.state.status, equals(SimulationStatus.arrived));
    });

    test('Manual override: FORCE_RED blocks priority green until override is cleared', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.startTrip();

      // Find first signal on the route
      final firstSig = controller.signalManager.signals.firstWhere(
        (s) => controller.state.routeNodeIds.contains(s.nodeId),
      );

      // Officer sets FORCE_RED
      controller.setSignalOverride(firstSig.id, SignalOverride.forceRed);

      // Advance until ambulance is within 100m of this signal
      int ticks = 0;
      while (ticks < 100) {
        ticks++;
        controller.tick();
        final d = firstSig.distanceToAmbulance ?? 999.0;
        if (d <= 150.0) break;
      }

      // Signal must stay strictly RED while under override
      expect(firstSig.state, equals(SignalState.red));

      // Clear override: should immediately trigger preemption because ambulance is within radius
      controller.setSignalOverride(firstSig.id, SignalOverride.none);
      controller.tick();

      expect(
        firstSig.state == SignalState.pendingGreen || firstSig.state == SignalState.greenPriority,
        isTrue,
      );
    });

    test('NEW TRIP fully restores initial IDLE state and clears event logs and banners', () {
      final h2 = controller.graph!.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.startTrip();

      // Run until arrived
      while (controller.state.status == SimulationStatus.enRoute) {
        controller.tick();
      }
      expect(controller.state.status, equals(SimulationStatus.arrived));

      // Call resetTrip() (NEW TRIP)
      controller.resetTrip();

      expect(controller.state.status, equals(SimulationStatus.idle));
      expect(controller.state.ambulance.distanceTravelledM, equals(0.0));
      expect(controller.state.elapsedTimeSeconds, equals(0.0));
      expect(controller.state.signalsClearedCount, equals(0));
      expect(controller.state.routeNodeIds.isEmpty, isTrue);
      expect(controller.state.timelineEvents.isEmpty, isTrue);
    });
  });
}
