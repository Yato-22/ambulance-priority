import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../algorithms/astar.dart';
import '../models/sim_state.dart';
import '../simulation/simulation_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/schematic_graph_painter.dart';

/// Hospital Screen: Emergency Department Dashboard for patient reception preparation.
class HospitalScreen extends StatelessWidget {
  final VoidCallback? onTapMap;

  const HospitalScreen({super.key, this.onTapMap});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SimulationController>();
    final state = controller.state;
    final hospital = state.targetHospital;

    final etaMin = (state.etaSeconds / 60).floor();
    final etaSec = (state.etaSeconds % 60).floor();
    final etaCountdown = etaMin > 0 ? '$etaMin min $etaSec sec' : '$etaSec sec';

    String prepMessage = 'Awaiting incoming ambulance dispatch...';
    Color prepColor = Colors.blueGrey;

    if (state.status == SimulationStatus.enRoute) {
      if (state.etaSeconds <= 60) {
        prepMessage = 'IMMINENT ARRIVAL (< 1 min): Trauma Bay 1 Ready. Resuscitation Team on Bay.';
        prepColor = Colors.red.shade700;
      } else if (state.etaSeconds <= 180) {
        prepMessage = 'Ambulance incoming in ~$etaMin min: Trauma team alerted. OT on standby.';
        prepColor = Colors.orange.shade800;
      } else {
        prepMessage = 'Ambulance dispatched. Traffic signals actively preempted via LoRa.';
        prepColor = Colors.indigo.shade700;
      }
    } else if (state.status == SimulationStatus.arrived) {
      prepMessage = 'Ambulance arrived at Emergency Bay! Transferring patient to Emergency Ward.';
      prepColor = Colors.green.shade800;
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final mapColors = Theme.of(context).extension<MapColors>() ??
        (isLight ? MapColors.light : MapColors.dark);

    return Scaffold(
      appBar: AppBar(
        title: Text(hospital?.name ?? 'Emergency Ward Reception'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Big ETA Countdown Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLight
                      ? [const Color(0xFFD6E4F5), const Color(0xFFE8F1FA)]
                      : [Colors.indigo.shade900, Colors.blueGrey.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: isLight
                    ? Border.all(color: const Color(0xFFCBD5E1))
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: isLight ? Colors.black.withValues(alpha: 0.06) : Colors.black26,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'ESTIMATED TIME OF ARRIVAL',
                          style: TextStyle(
                            color: isLight ? const Color(0xFF475569) : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: state.status == SimulationStatus.arrived
                              ? Colors.green
                              : (state.status == SimulationStatus.heldAtSignal
                                  ? (isLight ? const Color(0xFFDC2626) : Colors.redAccent.shade700)
                                  : (state.status == SimulationStatus.enRoute
                                      ? (isLight ? const Color(0xFFD97706) : Colors.amber.shade700)
                                      : (isLight ? const Color(0xFF64748B) : Colors.grey))),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.status == SimulationStatus.heldAtSignal
                              ? 'HELD AT SIGNAL'
                              : state.status.name.toUpperCase(),
                          style: TextStyle(
                            color: state.status == SimulationStatus.heldAtSignal || isLight
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.status == SimulationStatus.arrived ? 'ARRIVED' : etaCountdown,
                    style: TextStyle(
                      color: isLight ? const Color(0xFF1E293B) : Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Remaining Distance: ${(state.remainingDistanceM / 1000).toStringAsFixed(2)} km • '
                    'Signals Cleared: ${state.signalsClearedCount}',
                    style: TextStyle(
                      color: isLight ? const Color(0xFF475569) : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // 2. Patient Prep Clinical Alert Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isLight ? prepColor.withValues(alpha: 0.1) : prepColor.withValues(alpha: 0.12),
                border: Border.all(color: prepColor),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.medical_services_rounded, color: prepColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      prepMessage,
                      style: TextStyle(color: prepColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. Mini Schematic Route Overview (fixed height 260px, compact mode, live repaint)
            if (controller.graph != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isLight ? Theme.of(context).colorScheme.outlineVariant : Colors.grey.shade700,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 260,
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: onTapMap,
                          behavior: HitTestBehavior.opaque,
                          child: CustomPaint(
                            painter: SchematicGraphPainter(
                              graph: controller.graph!,
                              ambulance: state.ambulance,
                              signals: state.signals,
                              activeSignalId: state.activeSignalId,
                              triggerRadiusM: controller.greenTriggerRadiusM,
                              routeNodeIds: state.routeNodeIds,
                              routePolyline: state.routePolyline,
                              startNodeId: state.startNodeId,
                              targetHospital: state.targetHospital,
                              isEnRoute: state.status == SimulationStatus.enRoute ||
                                  state.status == SimulationStatus.heldAtSignal,
                              isHeldAtSignal: state.status == SimulationStatus.heldAtSignal,
                              heldSignalId: state.heldSignalId,
                              compact: true,
                              mapColors: mapColors,
                              repaint: controller,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 4. Algorithm Metrics / Dijkstra Comparison
            _buildSearchEfficiencyCard(context, controller, state),

            // 5. Trip Milestone Event Timeline
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Trip Milestones Timeline',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${state.timelineEvents.length} events', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
            ),

            if (state.timelineEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('No trip events recorded yet. Start a trip to track milestones.'),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: state.timelineEvents.length,
                separatorBuilder: (context, index) => const Divider(height: 12),
                itemBuilder: (ctx, idx) {
                  final event = state.timelineEvents[idx];
                  IconData icon = Icons.circle;
                  Color iconColor = Colors.grey;

                  switch (event.type) {
                    case 'route':
                      icon = Icons.alt_route_rounded;
                      iconColor = Colors.blue;
                      break;
                    case 'signal':
                      icon = Icons.traffic_rounded;
                      iconColor = Colors.green;
                      break;
                    case 'reroute':
                      icon = Icons.warning_rounded;
                      iconColor = Colors.deepOrange;
                      break;
                    case 'arrival':
                      icon = Icons.check_circle_rounded;
                      iconColor = Colors.teal;
                      break;
                    case 'lora':
                      icon = Icons.cell_tower_rounded;
                      iconColor = Colors.purple;
                      break;
                  }

                  final timeStr = event.timestamp.toIso8601String().substring(11, 19);

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: iconColor.withValues(alpha: 0.15),
                      child: Icon(icon, color: iconColor, size: 16),
                    ),
                    title: Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(event.description, style: const TextStyle(fontSize: 12)),
                    trailing: Text(timeStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  );
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEfficiencyCard(
    BuildContext context,
    SimulationController controller,
    SimState state,
  ) {
    if (!controller.showDijkstraComparison) return const SizedBox.shrink();

    int astarNodes;
    int dijkstraNodes;
    double astarCostVal;
    double dijkstraCostVal;

    if (state.nodesExpandedDijkstra != null) {
      astarNodes = state.nodesExpandedAStar;
      dijkstraNodes = state.nodesExpandedDijkstra!;
      astarCostVal = state.astarCost ?? 0.0;
      dijkstraCostVal = state.dijkstraCost ?? 0.0;
    } else if (controller.graph != null && state.targetHospital != null) {
      final startId = state.startNodeId ?? 1;
      final goalId = state.targetHospital!.nodeId;
      final aRes = AStarRouter.findRoute(
        graph: controller.graph!,
        startNodeId: startId,
        goalNodeId: goalId,
      );
      final dRes = AStarRouter.findRouteDijkstra(
        graph: controller.graph!,
        startNodeId: startId,
        goalNodeId: goalId,
      );
      if (aRes != null && dRes != null) {
        astarNodes = aRes.nodesExpanded;
        dijkstraNodes = dRes.nodesExpanded;
        astarCostVal = aRes.totalCost;
        dijkstraCostVal = dRes.totalCost;
      } else {
        return const SizedBox.shrink();
      }
    } else {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final diff = dijkstraNodes - astarNodes;
    final String effortText;
    if (dijkstraNodes > 0 && diff > 0) {
      final pct = ((diff / dijkstraNodes) * 100).round();
      effortText = 'A* explored $pct% fewer nodes';
    } else {
      effortText = 'Same effort on this graph';
    }

    final costDiff = (astarCostVal - dijkstraCostVal).abs();
    final bool isCostMismatch = costDiff > 1e-6;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Center(
            child: Text(
              'Search efficiency (same route, same cost)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Two columns: A* and Dijkstra
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'A*',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$astarNodes',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'nodes expanded',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 48,
                width: 1,
                color: colorScheme.outlineVariant,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Dijkstra',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dijkstraNodes',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'nodes expanded',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 10),

          // Third line: efficiency percentage
          Center(
            child: Text(
              effortText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Fourth line: Route cost comparison
          if (isCostMismatch)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade700),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Route cost mismatch: A* = ${astarCostVal.toStringAsFixed(2)}, Dijkstra = ${dijkstraCostVal.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            Center(
              child: Text(
                'Route cost: A* = ${astarCostVal.toStringAsFixed(1)}, Dijkstra = ${dijkstraCostVal.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
