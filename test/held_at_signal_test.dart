import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/astar.dart';
import 'package:ambulance_priority/config/constants.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/models/road_graph.dart';
import 'package:ambulance_priority/models/sim_state.dart';
import 'package:ambulance_priority/models/traffic_signal.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';

void main() {
  group('Ambulance Hold at Signal Tests', () {
    late RoadGraph graph;
    late SimulationController controller;

    setUp(() {
      graph = SampleGraphBuilder.build();
      controller = SimulationController();
      controller.setGraph(graph);
    });

    tearDown(() {
      controller.dispose();
    });

    test('1. Hold at FORCE_RED: stops at stop line (10m before junction), status is heldAtSignal, speed is 0', () {
      final h2 = graph.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.setTimeScale(1.0);
      controller.setAmbulanceSpeed(40.0);
      controller.startTrip();

      // Find first signal on route
      final routeSignals = controller.signalManager.signals
          .where((s) => controller.state.routeNodeIds.contains(s.nodeId))
          .toList();
      expect(routeSignals, isNotEmpty);
      final testSig = routeSignals.first;

      // Force testSig to RED
      controller.setSignalOverride(testSig.id, SignalOverride.forceRed);

      final routeNodes = controller.state.routeNodeIds;
      final trajectoryDists = controller.state.cumulativeDistances;
      // Get exact polyline distance to testSig node
      int nodeIdx = routeNodes.indexOf(testSig.nodeId);
      final sigDist = trajectoryDists[nodeIdx];

      // Tick until held at signal
      int ticks = 0;
      while (controller.state.status == SimulationStatus.enRoute && ticks < 200) {
        ticks++;
        controller.tick();
      }

      // Verify heldAtSignal
      expect(controller.state.status, equals(SimulationStatus.heldAtSignal));
      expect(controller.state.heldSignalId, equals(testSig.id));
      expect(controller.state.ambulance.speedMps, equals(0.0));

      // Stop line distance is exactly sigDist - 10.0m
      final expectedStopDist = sigDist - AppConstants.stopLineDistanceM;
      expect(
        controller.state.ambulance.distanceTravelledM,
        closeTo(expectedStopDist, 0.5),
      );
      // Ambulance must NEVER have crossed the junction
      expect(controller.state.ambulance.distanceTravelledM, lessThan(sigDist));
    });

    test('2. Resume on Auto / FORCE_GREEN: accelerates, status becomes enRoute, clears signal and logs release event', () {
      final h2 = graph.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.setTimeScale(1.0);
      controller.setAmbulanceSpeed(40.0);
      controller.startTrip();

      final firstSig = controller.signalManager.signals
          .firstWhere((s) => controller.state.routeNodeIds.contains(s.nodeId));

      controller.setSignalOverride(firstSig.id, SignalOverride.forceRed);

      // Advance until held
      while (controller.state.status == SimulationStatus.enRoute) {
        controller.tick();
      }
      expect(controller.state.status, equals(SimulationStatus.heldAtSignal));

      // Advance several ticks while held to accumulate wait time
      for (int i = 0; i < 6; i++) {
        controller.tick();
      }
      expect(controller.state.signalWaitTimeSeconds, greaterThan(2.0));

      // Release override by setting to FORCE_GREEN
      controller.setSignalOverride(firstSig.id, SignalOverride.forceGreen);

      // Verify immediate resume
      expect(controller.state.status, equals(SimulationStatus.enRoute));
      expect(controller.state.heldSignalId, isNull);

      // Advance ticks: ambulance accelerates away
      controller.tick();
      expect(controller.state.ambulance.speedMps, greaterThan(0.0));

      // Check timeline events contains release event
      final releaseEvent = controller.state.timelineEvents.firstWhere(
        (e) => e.title == 'Released at Signal',
      );
      expect(releaseEvent.description, contains('Released at ${firstSig.id}'));
    });

    test('3. 5x speed safety: no overshoot of stop line at 5x speed, never crosses junction', () {
      final h2 = graph.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.setTimeScale(5.0); // 5x speed
      controller.setAmbulanceSpeed(50.0);
      controller.startTrip();

      final firstSig = controller.signalManager.signals
          .firstWhere((s) => controller.state.routeNodeIds.contains(s.nodeId));

      controller.setSignalOverride(firstSig.id, SignalOverride.forceRed);

      int nodeIdx = controller.state.routeNodeIds.indexOf(firstSig.nodeId);
      final sigDist = controller.state.cumulativeDistances[nodeIdx];
      final maxAllowedDist = sigDist - AppConstants.stopLineDistanceM;

      int ticks = 0;
      while (controller.state.status == SimulationStatus.enRoute && ticks < 100) {
        ticks++;
        controller.tick();
        // At every tick, verify distance travelled never exceeded the stop line
        expect(controller.state.ambulance.distanceTravelledM, lessThanOrEqualTo(maxAllowedDist + 0.05));
      }

      expect(controller.state.status, equals(SimulationStatus.heldAtSignal));
      expect(controller.state.ambulance.distanceTravelledM, lessThanOrEqualTo(maxAllowedDist + 0.05));
      expect(controller.state.ambulance.distanceTravelledM, lessThan(sigDist));
    });

    test('4. Reroute around forced-red toggle ON: reroutes via alternative path not containing S5', () {
      final h2 = graph.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.setRerouteAroundForcedRed(true);
      controller.startTrip();

      final initialRoute = List<int>.from(controller.state.routeNodeIds);
      final firstSig = controller.signalManager.signals
          .firstWhere((s) => initialRoute.contains(s.nodeId));

      // Force red on firstSig
      controller.setSignalOverride(firstSig.id, SignalOverride.forceRed);

      // Verify route was recomputed and does NOT contain firstSig.nodeId
      expect(controller.state.status, equals(SimulationStatus.enRoute));
      expect(controller.state.routeNodeIds.contains(firstSig.nodeId), isFalse);
      expect(controller.state.routeNodeIds, isNot(equals(initialRoute)));
      expect(AStarRouter.assertRouteIsValid(graph, controller.state.routeNodeIds), isTrue);
    });

    test('5. Reroute around forced-red fallback: holds at stop line instead of entering NO_ROUTE when no alternative exists', () {
      final h2 = graph.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.startTrip();

      final firstSig = controller.signalManager.signals
          .firstWhere((s) => controller.state.routeNodeIds.contains(s.nodeId));

      // Enable toggle
      controller.setRerouteAroundForcedRed(true);

      // Block all other ways across column/grid
      for (final node in graph.nodes.values) {
        if (node.id != firstSig.nodeId && node.id != 1 && node.id != h2.nodeId) {
          final out = graph.adjacency[node.id] ?? [];
          for (final e in out) {
            if (!controller.state.routeNodeIds.contains(e.from) || !controller.state.routeNodeIds.contains(e.to)) {
              graph.blockEdge(e.from, e.to);
            }
          }
        }
      }

      // Now set firstSig to FORCE_RED
      controller.setSignalOverride(firstSig.id, SignalOverride.forceRed);

      // Must NOT enter NO_ROUTE! Must remain enRoute or heldAtSignal
      expect(controller.state.status, isNot(equals(SimulationStatus.noRoute)));

      // Advance ticks until it holds at the stop line of firstSig
      int ticks = 0;
      while (controller.state.status == SimulationStatus.enRoute && ticks < 200) {
        ticks++;
        controller.tick();
      }

      expect(controller.state.status, equals(SimulationStatus.heldAtSignal));
      expect(controller.state.heldSignalId, equals(firstSig.id));
    });

    test('6. Inside-200m override: approaching S5 (100m out, green active), set FORCE_RED -> stops at stop line', () {
      final h2 = graph.hospitals.firstWhere((h) => h.id == 'H2');
      controller.selectStartNode(1);
      controller.selectHospital(h2);
      controller.setTimeScale(1.0);
      controller.setAmbulanceSpeed(40.0);
      controller.startTrip();

      final firstSig = controller.signalManager.signals
          .firstWhere((s) => controller.state.routeNodeIds.contains(s.nodeId));

      int nodeIdx = controller.state.routeNodeIds.indexOf(firstSig.nodeId);
      final sigDist = controller.state.cumulativeDistances[nodeIdx];

      // Advance until ambulance is within 100m of the signal (inside 200m trigger zone)
      while (controller.state.status == SimulationStatus.enRoute) {
        final distToSig = sigDist - controller.state.ambulance.distanceTravelledM;
        if (distToSig <= 100.0) break;
        controller.tick();
      }

      expect(firstSig.distanceToAmbulance, lessThanOrEqualTo(100.0));
      expect(firstSig.state == SignalState.greenPriority || firstSig.state == SignalState.pendingGreen, isTrue);

      // Preemption was active! Now officer overrides to FORCE_RED
      controller.setSignalOverride(firstSig.id, SignalOverride.forceRed);
      expect(firstSig.overrideState, equals(SignalOverride.forceRed));

      // Advance ticks until ambulance stops
      int ticks = 0;
      while (controller.state.status == SimulationStatus.enRoute && ticks < 50) {
        ticks++;
        controller.tick();
      }

      // Must be held at stop line and NOT cross junction
      expect(controller.state.status, equals(SimulationStatus.heldAtSignal));
      expect(controller.state.heldSignalId, equals(firstSig.id));
      expect(controller.state.ambulance.distanceTravelledM, lessThan(sigDist));
      expect(
        controller.state.ambulance.distanceTravelledM,
        closeTo(sigDist - AppConstants.stopLineDistanceM, 0.5),
      );
    });
  });
}
