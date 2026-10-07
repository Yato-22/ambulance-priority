import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sim_state.dart';
import '../simulation/simulation_controller.dart';
import '../widgets/schematic_graph_painter.dart';

/// Hospital Screen: Emergency Department Dashboard for patient reception preparation.
class HospitalScreen extends StatelessWidget {
  const HospitalScreen({super.key});

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
                  colors: [Colors.indigo.shade900, Colors.blueGrey.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ESTIMATED TIME OF ARRIVAL',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: state.status == SimulationStatus.arrived
                              ? Colors.green
                              : (state.status == SimulationStatus.enRoute ? Colors.amber.shade700 : Colors.grey),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.status.name.toUpperCase(),
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.status == SimulationStatus.arrived ? 'ARRIVED' : etaCountdown,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Remaining Distance: ${(state.remainingDistanceM / 1000).toStringAsFixed(2)} km • '
                    'Signals Cleared: ${state.signalsClearedCount}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            // 2. Patient Prep Clinical Alert Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: prepColor.withValues(alpha: 0.12),
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

            // 3. Mini Schematic Route Overview
            if (controller.graph != null)
              Container(
                height: 180,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade700),
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  size: const Size(double.infinity, 180),
                  painter: SchematicGraphPainter(
                    graph: controller.graph!,
                    projection: CanvasProjection.fromGraph(
                      controller.graph!,
                      width: 360,
                      height: 180,
                    ),
                    ambulance: state.ambulance,
                    signals: state.signals,
                    activeSignalId: state.activeSignalId,
                    triggerRadiusM: controller.greenTriggerRadiusM,
                    routeNodeIds: state.routeNodeIds,
                    routePolyline: state.routePolyline,
                    startNodeId: state.startNodeId,
                    targetHospital: state.targetHospital,
                    isEnRoute: state.status == SimulationStatus.enRoute,
                  ),
                ),
              ),

            // 4. Algorithm Metrics / Dijkstra Comparison
            if (controller.showDijkstraComparison && state.nodesExpandedDijkstra != null)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('A* Nodes Expanded', style: TextStyle(fontSize: 12, color: Colors.purple)),
                        Text('${state.nodesExpandedAStar}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Dijkstra Nodes Expanded', style: TextStyle(fontSize: 12, color: Colors.purple)),
                        Text('${state.nodesExpandedDijkstra}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                  ],
                ),
              ),

            // 5. Trip Milestone Event Timeline
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 20),
                  const SizedBox(width: 8),
                  const Text('Trip Milestones Timeline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
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
}
