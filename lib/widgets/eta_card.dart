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

    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isLight ? BorderSide(color: theme.colorScheme.outlineVariant) : BorderSide.none,
      ),
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
                    color: isLight ? const Color(0xFFFEE2E2) : const Color(0x33EF4444),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.emergency_rounded,
                    color: isLight ? const Color(0xFFDC2626) : const Color(0xFFF87171),
                    size: 28,
                  ),
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
                        state.status == SimulationStatus.heldAtSignal
                            ? 'Waiting: ${state.signalWaitTimeSeconds.toStringAsFixed(0)}s • Time: ${state.elapsedTimeSeconds.toStringAsFixed(0)}s'
                            : 'Speed: ${state.ambulance.speedKmh.toStringAsFixed(0)} km/h • Time: ${state.elapsedTimeSeconds.toStringAsFixed(0)}s',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      etaText,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      distText,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
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
                        state.status == SimulationStatus.heldAtSignal
                            ? Icons.pause_circle_rounded
                            : (activeSignal?.state == SignalState.greenPriority
                                ? Icons.check_circle_rounded
                                : Icons.traffic_rounded),
                        color: state.status == SimulationStatus.heldAtSignal
                            ? Colors.redAccent
                            : (activeSignal?.state == SignalState.greenPriority
                                ? Colors.green
                                : Colors.orange),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          state.status == SimulationStatus.heldAtSignal
                              ? 'HELD AT ${state.heldSignalId ?? activeSignal?.id ?? "SIGNAL"}'
                              : (activeSignal != null
                                  ? 'Next: ${activeSignal.id} (${activeSignal.distanceToAmbulance?.toStringAsFixed(0) ?? "?"}m)'
                                  : 'No signals ahead'),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: state.status == SimulationStatus.heldAtSignal
                                ? Colors.redAccent.shade700
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: state.status == SimulationStatus.heldAtSignal
                        ? Colors.red.shade700
                        : (activeSignal?.state == SignalState.greenPriority
                            ? Colors.green.shade600
                            : (activeSignal?.state == SignalState.pendingGreen
                                ? Colors.amber.shade700
                                : Colors.grey.shade700)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    state.status == SimulationStatus.heldAtSignal
                        ? 'HELD AT ${state.heldSignalId ?? activeSignal?.id ?? "SIGNAL"}'
                        : (activeSignal?.state == SignalState.greenPriority
                            ? 'PRIORITY GREEN'
                            : (activeSignal?.state == SignalState.pendingGreen
                                ? 'LORA REQ...'
                                : 'CLEARED: ${state.signalsClearedCount}')),
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

