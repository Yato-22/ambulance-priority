import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/sim_state.dart';
import '../models/traffic_signal.dart';
import '../simulation/simulation_controller.dart';
import '../widgets/signal_card.dart';

/// Control Station View: Overview of all traffic signals and simulated LoRa link.
class SignalsScreen extends StatefulWidget {
  const SignalsScreen({super.key});

  @override
  State<SignalsScreen> createState() => _SignalsScreenState();
}

class _SignalsScreenState extends State<SignalsScreen> {
  bool _showLoRaLog = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SimulationController>();
    final state = controller.state;
    final graph = controller.graph;

    final signals = List<TrafficSignal>.from(state.signals);

    // Sort signals: held signal or active signal on top, then by distance to ambulance
    signals.sort((a, b) {
      if (state.status == SimulationStatus.heldAtSignal) {
        if (a.id == state.heldSignalId) return -1;
        if (b.id == state.heldSignalId) return 1;
      }
      if (a.id == state.activeSignalId) return -1;
      if (b.id == state.activeSignalId) return 1;
      final da = a.distanceToAmbulance ?? 999999.0;
      final db = b.distanceToAmbulance ?? 999999.0;
      return da.compareTo(db);
    });

    final totalSignals = signals.length;
    final priorityGreenCount = signals.where((s) => s.state == SignalState.greenPriority).length;
    final overrideCount = signals.where((s) => s.isOverridden).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Traffic Control Station'),
        actions: [
          IconButton(
            icon: Icon(_showLoRaLog ? Icons.rss_feed_rounded : Icons.cell_tower_rounded),
            tooltip: 'LoRa 865 MHz Link Logs',
            onPressed: () {
              setState(() {
                _showLoRaLog = !_showLoRaLog;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. KPI Summary Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildKpiCard(context, 'Total Signals', '$totalSignals', Icons.traffic_rounded, Colors.blueGrey),
                _buildKpiCard(context, 'Priority Green', '$priorityGreenCount', Icons.flash_on_rounded, Colors.green),
                _buildKpiCard(context, 'Overridden', '$overrideCount', Icons.shield_rounded, Colors.purple),
              ],
            ),
          ),
          const Divider(height: 1),

          // 2. Signals List
          Expanded(
            child: ListView.builder(
              itemCount: signals.length,
              itemBuilder: (context, index) {
                final sig = signals[index];
                final isActive = sig.id == state.activeSignalId;
                final isHeld = state.status == SimulationStatus.heldAtSignal && sig.id == state.heldSignalId;

                // Find road name connected to this node
                String? roadName;
                if (graph != null) {
                  final outEdges = graph.adjacency[sig.nodeId];
                  if (outEdges != null && outEdges.isNotEmpty) {
                    roadName = outEdges.first.name;
                  }
                }

                return SignalCard(
                  signal: sig,
                  isActive: isActive,
                  isHeld: isHeld,
                  roadName: roadName,
                  onOverrideChanged: (overrideState) {
                    controller.setSignalOverride(sig.id, overrideState);
                  },
                );
              },
            ),
          ),

          // 3. Collapsible LoRa RF Activity Panel (865 MHz)
          if (_showLoRaLog)
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -3)),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cell_tower_rounded, color: Colors.greenAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'LoRa SX1262 Transceiver Log (${AppConstants.loraFreqLabel})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Loss: ${(controller.loraLink.packetLossProbability * 100).toStringAsFixed(0)}%',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                          onPressed: () => setState(() => _showLoRaLog = false),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: state.loraLogs.isEmpty
                        ? const Center(
                            child: Text(
                              'No LoRa packets transmitted yet.',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: state.loraLogs.length,
                            separatorBuilder: (context, index) => Divider(color: Colors.grey.shade800, height: 6),
                            itemBuilder: (ctx, idx) {
                              final log = state.loraLogs[idx];
                              final isDelivered = log.status.contains('DELIVERED');
                              final timeStr = log.timestamp.toIso8601String().substring(11, 19);

                              return Row(
                                children: [
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade800,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      log.signalId,
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      log.command,
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${log.latencyMs}ms',
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    isDelivered ? Icons.check_circle : Icons.error_outline,
                                    color: isDelivered ? Colors.greenAccent : Colors.redAccent,
                                    size: 14,
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(BuildContext context, String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color),
        ),
        Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
        ),
      ],
    );
  }
}
