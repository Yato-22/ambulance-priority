/// Represents the state of the emergency ambulance.
class Ambulance {
  final double lat;
  final double lon;
  final double headingDegrees;
  final double speedMps;
  final double distanceTravelledM;
  final double totalRouteDistanceM;
  final int polylineSegmentIndex;
  final int? currentEdgeFrom;
  final int? currentEdgeTo;

  const Ambulance({
    required this.lat,
    required this.lon,
    this.headingDegrees = 0.0,
    this.speedMps = 11.11, // ~40 km/h
    this.distanceTravelledM = 0.0,
    this.totalRouteDistanceM = 0.0,
    this.polylineSegmentIndex = 0,
    this.currentEdgeFrom,
    this.currentEdgeTo,
  });

  double get speedKmh => speedMps * 3.6;

  double get progressFraction => totalRouteDistanceM > 0
      ? (distanceTravelledM / totalRouteDistanceM).clamp(0.0, 1.0)
      : 0.0;

  double get remainingDistanceM =>
      (totalRouteDistanceM - distanceTravelledM).clamp(0.0, double.infinity);

  Ambulance copyWith({
    double? lat,
    double? lon,
    double? headingDegrees,
    double? speedMps,
    double? distanceTravelledM,
    double? totalRouteDistanceM,
    int? polylineSegmentIndex,
    int? currentEdgeFrom,
    int? currentEdgeTo,
  }) {
    return Ambulance(
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      speedMps: speedMps ?? this.speedMps,
      distanceTravelledM: distanceTravelledM ?? this.distanceTravelledM,
      totalRouteDistanceM: totalRouteDistanceM ?? this.totalRouteDistanceM,
      polylineSegmentIndex: polylineSegmentIndex ?? this.polylineSegmentIndex,
      currentEdgeFrom: currentEdgeFrom ?? this.currentEdgeFrom,
      currentEdgeTo: currentEdgeTo ?? this.currentEdgeTo,
    );
  }

  @override
  String toString() =>
      'Ambulance(lat: $lat, lon: $lon, speed: ${speedKmh.toStringAsFixed(1)} km/h, '
      'prog: ${(progressFraction * 100).toStringAsFixed(1)}%)';
}

