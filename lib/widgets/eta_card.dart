import 'package:flutter/material.dart';
import '../models/sim_state.dart';
import '../models/traffic_signal.dart';

/// Floating telemetry overlay card on the map screen showing live ETA and signals.
class EtaCard extends StatelessWidget {
  final SimState state;

  const EtaCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.status == SimulationStatus.idle) {
      return const SizedBox.shrink();
    }

    final etaMin = (state.etaSeconds / 60).floor();
    final etaSec = (state.etaSeconds % 60).floor();
    final etaText = etaMin > 0 ? '${etaMin}m ${etaSec}s' : '${etaSec}s';

    final distText = state.remainingDistanceM > 1000
        ? '${(state.remainingDistanceM / 1000).toStringAsFixed(2)} km'
        : '${state.remainingDistanceM.toStringAsFixed(0)} m';

    final activeSignal = state.signals.cast<TrafficSignal?>().firstWhere(
          (s) => s?.id == state.activeSignalId,
          orElse: () => null,
        );

    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.emergency_rounded, color: Colors.red, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.targetHospital?.name ?? 'Emergency Route',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Speed: ${state.ambulance.speedKmh.toStringAsFixed(0)} km/h • Time: ${state.elapsedTimeSeconds.toStringAsFixed(0)}s',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      etaText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Colors.indigo,
                      ),
                    ),
                    Text(
                      distText,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        activeSignal?.state == SignalState.greenPriority
                            ? Icons.check_circle_rounded
                            : Icons.traffic_rounded,
                        color: activeSignal?.state == SignalState.greenPriority
                            ? Colors.green
                            : Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        activeSignal != null
                            ? 'Next: ${activeSignal.id} (${activeSignal.distanceToAmbulance?.toStringAsFixed(0) ?? "?"}m)'
                            : 'No signals ahead',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeSignal?.state == SignalState.greenPriority
                        ? Colors.green.shade600
                        : (activeSignal?.state == SignalState.pendingGreen
                            ? Colors.amber.shade700
                            : Colors.grey.shade700),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    activeSignal?.state == SignalState.greenPriority
                        ? 'PRIORITY GREEN'
                        : (activeSignal?.state == SignalState.pendingGreen
                            ? 'LORA REQ...'
                            : 'CLEARED: ${state.signalsClearedCount}'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

