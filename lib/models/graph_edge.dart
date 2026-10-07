import 'package:flutter/material.dart';
import '../config/constants.dart';

/// 4 discrete operational road states for traffic congestion and blockages.
enum RoadState {
  open,
  moderate,
  heavy,
  blocked;

  /// Congestion multiplier used for traversal cost.
  double get factor {
    switch (this) {
      case RoadState.open:
        return AppConstants.ROAD_FACTOR_OPEN;
      case RoadState.moderate:
        return AppConstants.ROAD_FACTOR_MODERATE;
      case RoadState.heavy:
        return AppConstants.ROAD_FACTOR_HEAVY;
      case RoadState.blocked:
        return AppConstants.blockedThreshold;
    }
  }

  /// Schematic rendering color.
  Color get color {
    switch (this) {
      case RoadState.open:
        return const Color(0xFF607D8B); // Slate grey
      case RoadState.moderate:
        return const Color(0xFFFF9800); // Amber orange
      case RoadState.heavy:
        return const Color(0xFFE53935); // Solid red
      case RoadState.blocked:
        return const Color(0xFFD32F2F); // Impassable red
    }
  }

  /// User-friendly label with multiplier.
  String get label {
    switch (this) {
      case RoadState.open:
        return 'Open (1.0x)';
      case RoadState.moderate:
        return 'Moderate (2.0x)';
      case RoadState.heavy:
        return 'Heavy (4.0x)';
      case RoadState.blocked:
        return 'Blocked';
    }
  }

  /// Cycles: open -> moderate -> heavy -> blocked -> open.
  RoadState get next {
    switch (this) {
      case RoadState.open:
        return RoadState.moderate;
      case RoadState.moderate:
        return RoadState.heavy;
      case RoadState.heavy:
        return RoadState.blocked;
      case RoadState.blocked:
        return RoadState.open;
    }
  }
}

/// Represents a directed street segment connecting two graph nodes.
class GraphEdge {
  final int from;
  final int to;
  final double length;
  final String name;
  RoadState state;
  final bool oneway;
  final List<List<double>> geometry; // [[lat, lon], ...]

  GraphEdge({
    required this.from,
    required this.to,
    required this.length,
    required this.name,
    this.state = RoadState.open,
    this.oneway = false,
    List<List<double>>? geometry,
    double? baseCongestion,
    double? currentCongestion,
  }) : geometry = geometry ?? const [] {
    if (currentCongestion != null && currentCongestion >= AppConstants.blockedThreshold) {
      state = RoadState.blocked;
    } else if (currentCongestion != null && currentCongestion >= AppConstants.ROAD_FACTOR_HEAVY) {
      state = RoadState.heavy;
    } else if (currentCongestion != null && currentCongestion >= AppConstants.ROAD_FACTOR_MODERATE) {
      state = RoadState.moderate;
    }
  }

  bool get isBlocked => state == RoadState.blocked;

  /// Effective congestion multiplier.
  double get currentCongestion => state.factor;

  set currentCongestion(double val) {
    if (val >= AppConstants.blockedThreshold) {
      state = RoadState.blocked;
    } else if (val >= AppConstants.ROAD_FACTOR_HEAVY) {
      state = RoadState.heavy;
    } else if (val >= AppConstants.ROAD_FACTOR_MODERATE) {
      state = RoadState.moderate;
    } else {
      state = RoadState.open;
    }
  }

  double get baseCongestion => 1.0;

  /// Effective cost used for A* routing: length * congestion factor.
  double get effectiveCost => isBlocked ? double.infinity : length * state.factor;

  /// Resets dynamic congestion back to open.
  void resetCongestion() {
    state = RoadState.open;
  }

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    final rawGeom = json['geometry'] as List<dynamic>?;
    final geom = rawGeom == null
        ? <List<double>>[]
        : rawGeom.map((pt) {
            final coords = pt as List<dynamic>;
            return [(coords[0] as num).toDouble(), (coords[1] as num).toDouble()];
          }).toList();

    RoadState st = RoadState.open;
    if (json['state'] != null) {
      final sStr = json['state'].toString();
      st = RoadState.values.firstWhere(
        (e) => e.name == sStr,
        orElse: () => RoadState.open,
      );
    } else {
      final cong = (json['current_congestion'] as num?)?.toDouble() ??
          (json['base_congestion'] as num?)?.toDouble() ??
          1.0;
      if (cong >= AppConstants.blockedThreshold) {
        st = RoadState.blocked;
      } else if (cong >= AppConstants.ROAD_FACTOR_HEAVY) {
        st = RoadState.heavy;
      } else if (cong >= AppConstants.ROAD_FACTOR_MODERATE) {
        st = RoadState.moderate;
      }
    }

    return GraphEdge(
      from: json['from'] as int,
      to: json['to'] as int,
      length: (json['length'] as num).toDouble(),
      name: (json['name'] as String?) ?? '',
      state: st,
      oneway: json['oneway'] as bool? ?? false,
      geometry: geom,
    );
  }

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'length': length,
        'name': name,
        'state': state.name,
        'current_congestion': currentCongestion,
        'oneway': oneway,
        'geometry': geometry,
      };

  @override
  String toString() =>
      'GraphEdge($from -> $to, len: ${length}m, state: ${state.name}, cong: ${currentCongestion.toStringAsFixed(1)})';
}
