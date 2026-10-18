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

/// Directionality of the road segment.
enum RoadDirection {
  twoWay,
  oneWay;
}

/// Functional classification of the road.
enum RoadClass {
  major,
  minor;

  /// Speed factor applied to ambulance travel speed on this road class.
  double get speedFactor {
    switch (this) {
      case RoadClass.major:
        return AppConstants.speedFactorMajor;
      case RoadClass.minor:
        return AppConstants.speedFactorMinor;
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
  final RoadDirection direction;
  final RoadClass roadClass;
  final int? permittedFromNode;
  final int? permittedToNode;
  final List<List<double>> geometry; // [[lat, lon], ...]

  GraphEdge({
    required this.from,
    required this.to,
    required this.length,
    required this.name,
    this.state = RoadState.open,
    RoadDirection? direction,
    this.roadClass = RoadClass.major,
    int? permittedFromNode,
    int? permittedToNode,
    bool? oneway,
    List<List<double>>? geometry,
    double? baseCongestion,
    double? currentCongestion,
  })  : direction = direction ?? ((oneway == true) ? RoadDirection.oneWay : RoadDirection.twoWay),
        permittedFromNode = permittedFromNode ??
            ((direction == RoadDirection.oneWay || oneway == true) ? from : null),
        permittedToNode = permittedToNode ??
            ((direction == RoadDirection.oneWay || oneway == true) ? to : null),
        geometry = geometry ?? const [] {
    if (currentCongestion != null && currentCongestion >= AppConstants.blockedThreshold) {
      state = RoadState.blocked;
    } else if (currentCongestion != null && currentCongestion >= AppConstants.ROAD_FACTOR_HEAVY) {
      state = RoadState.heavy;
    } else if (currentCongestion != null && currentCongestion >= AppConstants.ROAD_FACTOR_MODERATE) {
      state = RoadState.moderate;
    }
  }

  bool get isBlocked => state == RoadState.blocked;
  bool get oneway => direction == RoadDirection.oneWay;
  bool get isOneWay => direction == RoadDirection.oneWay;
  bool get isTwoWay => direction == RoadDirection.twoWay;
  bool get isMajor => roadClass == RoadClass.major;
  bool get isMinor => roadClass == RoadClass.minor;

  /// Speed factor associated with this road's class.
  double get classSpeedFactor => roadClass.speedFactor;

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

  /// Effective cost used for A* routing: travel time = (length / classSpeedFactor) * congestion factor.
  /// Blocked roads are never used (infinite cost).
  double get effectiveCost =>
      isBlocked ? double.infinity : (length / classSpeedFactor) * state.factor;

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

    final dirStr = json['direction']?.toString();
    final direction = dirStr != null
        ? RoadDirection.values.firstWhere(
            (d) => d.name == dirStr,
            orElse: () => (json['oneway'] == true ? RoadDirection.oneWay : RoadDirection.twoWay),
          )
        : (json['oneway'] == true ? RoadDirection.oneWay : RoadDirection.twoWay);

    final classStr = json['road_class']?.toString() ?? json['class']?.toString();
    final rClass = classStr != null
        ? RoadClass.values.firstWhere(
            (c) => c.name == classStr,
            orElse: () => RoadClass.major,
          )
        : RoadClass.major;

    return GraphEdge(
      from: json['from'] as int,
      to: json['to'] as int,
      length: (json['length'] as num).toDouble(),
      name: (json['name'] as String?) ?? '',
      state: st,
      direction: direction,
      roadClass: rClass,
      permittedFromNode: json['permitted_from'] as int?,
      permittedToNode: json['permitted_to'] as int?,
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
        'direction': direction.name,
        'road_class': roadClass.name,
        'oneway': oneway,
        'permitted_from': permittedFromNode,
        'permitted_to': permittedToNode,
        'geometry': geometry,
      };

  @override
  String toString() =>
      'GraphEdge($from -> $to, len: ${length}m, class: ${roadClass.name}, dir: ${direction.name}, state: ${state.name}, cong: ${currentCongestion.toStringAsFixed(1)})';
}
