import 'package:flutter/material.dart';
import '../models/sim_state.dart';

/// Top banner informing the user of vital simulation milestones.
class StatusBanner extends StatelessWidget {
  final SimState state;

  const StatusBanner({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.status == SimulationStatus.idle) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.blueGrey.shade800,
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Select start location & destination hospital, then press Start Trip.',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (state.status == SimulationStatus.noRoute) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.red.shade900,
        child: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No route to hospital: all paths blocked. Clear a road to continue.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (state.status == SimulationStatus.arrived) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.green.shade800,
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ARRIVED at ${state.targetHospital?.name ?? "Hospital"}! '
                'Total Time: ${state.elapsedTimeSeconds.toStringAsFixed(0)}s | '
                'Cleared Signals: ${state.signalsClearedCount}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // EN ROUTE status
    final hasActivePreemption = state.signals.any((s) => s.isPreempted);
    final activeSig = state.signals.cast<dynamic>().firstWhere(
          (s) => s.id == state.activeSignalId,
          orElse: () => null,
        );

    Color bgColor = Colors.indigo.shade800;
    IconData icon = Icons.emergency_rounded;
    String message = 'Ambulance en route to ${state.targetHospital?.name ?? "Hospital"}';

    if (hasActivePreemption && activeSig != null) {
      bgColor = Colors.teal.shade800;
      icon = Icons.traffic_rounded;
      message = 'EMERGENCY PREEMPTION ACTIVE: Signal ${activeSig.id} cleared via LoRa (865 MHz)';
    } else if (state.rerouteCount > 0 && state.oldEtaSeconds != null) {
      bgColor = Colors.deepOrange.shade800;
      icon = Icons.alt_route_rounded;
      message = 'REROUTED via A*: Congestion bypassed (ETA: ${state.etaSeconds.toStringAsFixed(0)}s)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state.isPaused)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'PAUSED',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

