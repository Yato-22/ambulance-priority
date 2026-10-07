import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../simulation/simulation_controller.dart';

/// Settings & Tunable Parameters Screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SimulationController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulation Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Preemption & Kinematics
          const Text(
            'Emergency Preemption & Speed',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Green Trigger Radius:'),
                      Text(
                        '${controller.greenTriggerRadiusM.toStringAsFixed(0)} m',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    min: 100,
                    max: 400,
                    divisions: 12,
                    value: controller.greenTriggerRadiusM,
                    onChanged: (val) => controller.setTriggerRadius(val),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ambulance Base Speed:'),
                      Text(
                        '${controller.ambulanceSpeedKmh.toStringAsFixed(0)} km/h',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    min: AppConstants.minSpeedKmh,
                    max: AppConstants.maxSpeedKmh,
                    divisions: 12,
                    value: controller.ambulanceSpeedKmh,
                    onChanged: (val) => controller.setAmbulanceSpeed(val),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section 2: Hardware LoRa SX1262 Simulation
          const Text(
            'LoRa SX1262 Link Simulation (865 MHz)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Packet Loss Probability:'),
                      Text(
                        '${(controller.loraLink.packetLossProbability * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    min: 0.0,
                    max: 0.30,
                    divisions: 10,
                    value: controller.loraLink.packetLossProbability,
                    onChanged: (val) => controller.setPacketLossProbability(val),
                  ),
                  Text(
                    'Simulated latency per packet: ${AppConstants.loraDelayMinMs}-${AppConstants.loraDelayMaxMs} ms. '
                    'Retransmissions up to ${AppConstants.loraMaxRetries} retries.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section 3: Algorithm Evaluation
          const Text(
            'Algorithm Evaluation',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          Card(
            child: SwitchListTile(
              title: const Text('Compare A* vs Dijkstra'),
              subtitle: const Text('Runs Dijkstra in parallel and displays comparative nodes-expanded count'),
              value: controller.showDijkstraComparison,
              onChanged: (val) => controller.setShowDijkstraComparison(val),
            ),
          ),

          const SizedBox(height: 20),

          // Section 4: Network & Congestion Actions
          const Text(
            'Road Network Controls',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shuffle_rounded, color: Colors.orange),
                  title: const Text('Random Traffic'),
                  subtitle: const Text('Sets ~15% moderate, 7% heavy, 3% blocked (guaranteed connected)'),
                  onTap: () {
                    controller.randomizeTraffic();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Randomized traffic: 15% moderate, 7% heavy, 3% blocked.')),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.clear_all_rounded, color: Colors.blue),
                  title: const Text('Clear All Congestion'),
                  subtitle: const Text('Sets all roads back to open (1.0x)'),
                  onTap: () {
                    controller.clearAllCongestion();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All road congestion cleared (all roads open).')),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded, color: Colors.red),
                  title: const Text('Full Simulation Reset'),
                  subtitle: const Text('Restores start position, cancels trips, clears logs'),
                  onTap: () {
                    controller.resetTrip();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Simulation reset to initial state.')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

