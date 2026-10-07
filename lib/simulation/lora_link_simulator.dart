import 'dart:async';
import 'dart:math' as math;
import '../config/constants.dart';
import '../models/sim_state.dart';

/// Simulated physical LoRa SX1262 (865 MHz) radio link layer.
///
/// Models over-the-air packet transmission between the Central Control Station
/// and individual Intersection Signal Units.
/// Includes artificial latency (100-300ms), packet loss probability,
/// automatic packet retransmissions (up to 2 retries), and a sliding log buffer.
class LoRaLinkSimulator {
  final math.Random _rng;
  double packetLossProbability; // 0.0 to 0.3
  final List<LoRaPacketLog> _logs = [];
  static const int maxLogs = 50;

  LoRaLinkSimulator({
    this.packetLossProbability = 0.0,
    math.Random? rng,
  }) : _rng = rng ?? math.Random();

  List<LoRaPacketLog> get logs => List.unmodifiable(_logs);

  void clearLogs() {
    _logs.clear();
  }

  /// Sends a command to a traffic signal unit over simulated LoRa RF link.
  /// Calls `onDelivered` when successfully received and acknowledged.
  /// Calls `onFailed` if dropped after exhausting retries.
  Future<bool> sendCommand({
    required String signalId,
    required String command,
    required void Function() onDelivered,
    void Function()? onFailed,
    bool isSync = false,
  }) async {
    int attempts = 0;
    const maxRetries = AppConstants.loraMaxRetries;

    while (attempts <= maxRetries) {
      attempts++;
      final latency = _computeLatencyMs();

      // Check for packet loss on this attempt
      final isDropped = _rng.nextDouble() < packetLossProbability;

      if (!isSync) {
        await Future.delayed(Duration(milliseconds: latency));
      }

      if (isDropped && attempts <= maxRetries) {
        _addLog(LoRaPacketLog(
          timestamp: DateTime.now(),
          direction: 'TX',
          signalId: signalId,
          command: command,
          status: 'DROPPED (RETRYING)',
          latencyMs: latency,
          retryCount: attempts,
        ));
        continue;
      }

      if (isDropped && attempts > maxRetries) {
        _addLog(LoRaPacketLog(
          timestamp: DateTime.now(),
          direction: 'TX',
          signalId: signalId,
          command: command,
          status: 'DROPPED (FAILED)',
          latencyMs: latency,
          retryCount: attempts,
        ));
        onFailed?.call();
        return false;
      }

      // Successful packet delivery & ACK
      _addLog(LoRaPacketLog(
        timestamp: DateTime.now(),
        direction: 'TX->RX',
        signalId: signalId,
        command: command,
        status: attempts > 1 ? 'DELIVERED (RETRIED)' : 'DELIVERED',
        latencyMs: latency,
        retryCount: attempts - 1,
      ));

      onDelivered();
      return true;
    }

    return false;
  }

  int _computeLatencyMs() {
    const minDelay = AppConstants.loraDelayMinMs;
    const maxDelay = AppConstants.loraDelayMaxMs;
    return minDelay + _rng.nextInt(maxDelay - minDelay + 1);
  }

  void _addLog(LoRaPacketLog log) {
    _logs.insert(0, log);
    if (_logs.length > maxLogs) {
      _logs.removeLast();
    }
  }
}
