import 'package:flutter/material.dart';
import '../models/traffic_signal.dart';

/// Interactive Map Marker widget visualizing individual traffic signal units.
class SignalMarkerWidget extends StatelessWidget {
  final TrafficSignal signal;
  final bool isActive;
  final VoidCallback? onTap;

  const SignalMarkerWidget({
    super.key,
    required this.signal,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bulbColor;
    IconData icon;
    bool isPriority = false;

    switch (signal.state) {
      case SignalState.greenPriority:
        bulbColor = const Color(0xFF00E676); // Bright green A400
        icon = Icons.priority_high_rounded;
        isPriority = true;
        break;
      case SignalState.pendingGreen:
        bulbColor = Colors.amber.shade700;
        icon = Icons.sync_rounded;
        break;
      case SignalState.green:
        bulbColor = Colors.green.shade600;
        icon = Icons.circle;
        break;
      case SignalState.red:
        bulbColor = Colors.red.shade600;
        icon = Icons.circle;
        break;
    }

    final isOverridden = signal.isOverridden;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isOverridden ? Colors.purple.shade900 : Colors.black87,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isPriority
                    ? const Color(0xFF00E676)
                    : (isOverridden ? Colors.purpleAccent : Colors.white24),
                width: isPriority || isOverridden ? 1.5 : 0.5,
              ),
            ),
            child: Text(
              signal.id,
              style: TextStyle(
                color: isPriority ? const Color(0xFF00E676) : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
              border: Border.all(
                color: isOverridden ? Colors.purpleAccent : (isPriority ? Colors.white : Colors.grey.shade700),
                width: isPriority ? 2.5 : (isOverridden ? 2.0 : 1.5),
              ),
              boxShadow: [
                if (isPriority)
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.8),
                    blurRadius: 10,
                    spreadRadius: 3,
                  ),
                if (isOverridden)
                  BoxShadow(
                    color: Colors.purpleAccent.withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: bulbColor,
                size: isPriority ? 16 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

