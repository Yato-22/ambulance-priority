import 'package:flutter/material.dart';
import '../models/sim_state.dart';

/// Top banner informing the user of vital simulation milestones.
class StatusBanner extends StatelessWidget {
  final SimState state;

  const StatusBanner({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (state.status == SimulationStatus.idle) {
      final bgColor = isLight ? const Color(0xFFE2E8F0) : Colors.blueGrey.shade800;
      final textColor = isLight ? const Color(0xFF1E293B) : Colors.white;
      final iconColor = isLight ? const Color(0xFF334155) : Colors.white;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: bgColor,
        child: Row(
          children: [
            Icon(Icons.info_outline, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Select start location & destination hospital, then press Start Trip.',
                style: TextStyle(color: textColor, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (state.status == SimulationStatus.noRoute) {
      final bgColor = isLight ? const Color(0xFFFEE2E2) : Colors.red.shade900;
      final textColor = isLight ? const Color(0xFF991B1B) : Colors.white;
      final iconColor = isLight ? const Color(0xFFDC2626) : Colors.white;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: bgColor,
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No route to hospital: all paths blocked. Clear a road to continue.',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (state.status == SimulationStatus.arrived) {
      final bgColor = isLight ? const Color(0xFFDCFCE7) : Colors.green.shade800;
      final textColor = isLight ? const Color(0xFF166534) : Colors.white;
      final iconColor = isLight ? const Color(0xFF16A34A) : Colors.white;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: bgColor,
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ARRIVED at ${state.targetHospital?.name ?? "Hospital"}! '
                'Total Time: ${state.elapsedTimeSeconds.toStringAsFixed(0)}s | '
                'Cleared Signals: ${state.signalsClearedCount}',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (state.status == SimulationStatus.heldAtSignal) {
      final heldSig = state.signals.cast<dynamic>().firstWhere(
            (s) => s.id == state.heldSignalId,
            orElse: () => null,
          );
      final isForced = heldSig?.isOverridden == true;
      final bannerText = isForced
          ? 'HELD at ${state.heldSignalId ?? "signal"}: signal forced RED by control station'
          : 'HELD at ${state.heldSignalId ?? "signal"}: waiting for green signal';

      final bgColor = isLight ? const Color(0xFFFEF3C7) : Colors.amber.shade900;
      final textColor = isLight ? const Color(0xFF92400E) : Colors.white;
      final iconColor = isLight ? const Color(0xFFD97706) : Colors.white;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: bgColor,
        child: Row(
          children: [
            Icon(Icons.pause_circle_filled_rounded, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                bannerText,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            if (state.isPaused)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFFDE68A) : Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PAUSED',
                  style: TextStyle(
                    color: isLight ? const Color(0xFF78350F) : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
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

    Color bgColor = isLight ? const Color(0xFFDBEAFE) : Colors.indigo.shade800;
    Color textColor = isLight ? const Color(0xFF1E40AF) : Colors.white;
    Color iconColor = isLight ? const Color(0xFF2563EB) : Colors.white;
    IconData icon = Icons.emergency_rounded;
    String message = 'Ambulance en route to ${state.targetHospital?.name ?? "Hospital"}';

    if (hasActivePreemption && activeSig != null) {
      bgColor = isLight ? const Color(0xFFCCFBF1) : Colors.teal.shade800;
      textColor = isLight ? const Color(0xFF115E59) : Colors.white;
      iconColor = isLight ? const Color(0xFF0D9488) : Colors.white;
      icon = Icons.traffic_rounded;
      message = 'EMERGENCY PREEMPTION ACTIVE: Signal ${activeSig.id} cleared via LoRa (865 MHz)';
    } else if (state.rerouteCount > 0 && state.oldEtaSeconds != null) {
      bgColor = isLight ? const Color(0xFFFFEDD5) : Colors.deepOrange.shade800;
      textColor = isLight ? const Color(0xFF9A3412) : Colors.white;
      iconColor = isLight ? const Color(0xFFEA580C) : Colors.white;
      icon = Icons.alt_route_rounded;
      message = 'REROUTED via A*: Congestion bypassed (ETA: ${state.etaSeconds.toStringAsFixed(0)}s)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state.isPaused)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isLight ? const Color(0xFFFDE68A) : Colors.amber.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'PAUSED',
                style: TextStyle(
                  color: isLight ? const Color(0xFF78350F) : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

