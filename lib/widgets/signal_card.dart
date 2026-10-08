import 'package:flutter/material.dart';
import '../models/traffic_signal.dart';

/// Control card for an individual traffic signal unit used in the Control Station screen.
class SignalCard extends StatelessWidget {
  final TrafficSignal signal;
  final bool isActive;
  final bool isHeld;
  final String? roadName;
  final void Function(SignalOverride override) onOverrideChanged;

  const SignalCard({
    super.key,
    required this.signal,
    this.isActive = false,
    this.isHeld = false,
    this.roadName,
    required this.onOverrideChanged,
  });

  @override
  Widget build(BuildContext context) {
    Color stateBadgeColor;
    String stateLabel;
    IconData stateIcon;

    switch (signal.state) {
      case SignalState.greenPriority:
        stateBadgeColor = const Color(0xFF00E676);
        stateLabel = 'PRIORITY GREEN';
        stateIcon = Icons.flash_on_rounded;
        break;
      case SignalState.pendingGreen:
        stateBadgeColor = Colors.amber.shade700;
        stateLabel = 'LORA PENDING';
        stateIcon = Icons.sync_rounded;
        break;
      case SignalState.green:
        stateBadgeColor = Colors.green.shade600;
        stateLabel = 'NORMAL GREEN';
        stateIcon = Icons.check_circle_outline;
        break;
      case SignalState.red:
        stateBadgeColor = Colors.red.shade600;
        stateLabel = 'NORMAL RED';
        stateIcon = Icons.stop_circle_outlined;
        break;
    }

    final distanceStr = signal.distanceToAmbulance != null
        ? '${signal.distanceToAmbulance!.toStringAsFixed(0)} m'
        : 'N/A';

    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Card(
      elevation: (isActive || isHeld) ? 4 : 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isHeld
              ? (isLight ? const Color(0xFFDC2626) : Colors.redAccent)
              : (isActive
                  ? (isLight ? const Color(0xFF0D9488) : Colors.tealAccent.shade700)
                  : (signal.isOverridden
                      ? (isLight ? const Color(0xFF9333EA) : Colors.purpleAccent)
                      : (isLight ? theme.colorScheme.outlineVariant : Colors.transparent))),
          width: (isActive || isHeld) ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLight ? theme.colorScheme.primaryContainer : Colors.blueGrey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    signal.id,
                    style: TextStyle(
                      color: isLight ? theme.colorScheme.onPrimaryContainer : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roadName?.isNotEmpty == true ? roadName! : 'Node #${signal.nodeId} Junction',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Source: ${signal.signalSource} • Lat: ${signal.lat.toStringAsFixed(4)}, Lon: ${signal.lon.toStringAsFixed(4)}',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: stateBadgeColor.withValues(alpha: isLight ? 0.12 : 0.15),
                    border: Border.all(color: stateBadgeColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(stateIcon, color: stateBadgeColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        stateLabel,
                        style: TextStyle(
                          color: stateBadgeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.directions_car_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Distance to Ambulance: ',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                Text(
                  distanceStr,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: (signal.distanceToAmbulance ?? 999) < 200
                        ? (isLight ? const Color(0xFF16A34A) : Colors.green.shade700)
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (isHeld)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isLight ? const Color(0xFFFEF3C7) : Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: isLight ? const Color(0xFFD97706) : Colors.amber.shade800),
                    ),
                    child: Text(
                      'Ambulance waiting',
                      style: TextStyle(
                        color: isLight ? const Color(0xFF92400E) : Colors.amber.shade900,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isLight ? const Color(0xFFCCFBF1) : Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: isLight ? const Color(0xFF0D9488) : Colors.teal.shade400),
                    ),
                    child: Text(
                      'ACTIVE ON ROUTE',
                      style: TextStyle(
                        color: isLight ? const Color(0xFF115E59) : Colors.teal.shade800,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                const Text(
                  'Manual Override:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                SegmentedButton<SignalOverride>(
                  segments: const [
                    ButtonSegment<SignalOverride>(
                      value: SignalOverride.none,
                      label: Text('Auto', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment<SignalOverride>(
                      value: SignalOverride.forceGreen,
                      label: Text('Green', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment<SignalOverride>(
                      value: SignalOverride.forceRed,
                      label: Text('Red', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {signal.overrideState},
                  onSelectionChanged: (Set<SignalOverride> selection) {
                    onOverrideChanged(selection.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

