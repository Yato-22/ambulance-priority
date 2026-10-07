import 'dart:math' as math;
import '../config/constants.dart';

/// Pure Dart implementation of the Haversine formula for calculating
/// great-circle distances between two geographic points on Earth.
///
/// Formula:
///   a = sin²(Δφ/2) + cos(φ1) * cos(φ2) * sin²(Δλ/2)
///   c = 2 * atan2(√a, √(1−a))
///   d = R * c
///
/// Time complexity: O(1).
/// No Flutter dependencies.
class Haversine {
  static const double earthRadiusMeters = AppConstants.earthRadiusMeters;

  /// Calculates the distance in meters between two lat/lon pairs.
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    // If coordinates are identical, avoid rounding drift and return 0
    if (lat1 == lat2 && lon1 == lon2) {
      return 0.0;
    }

    final phi1 = _degToRad(lat1);
    final phi2 = _degToRad(lat2);
    final deltaPhi = _degToRad(lat2 - lat1);
    final deltaLambda = _degToRad(lon2 - lon1);

    final sinHalfDeltaPhi = math.sin(deltaPhi / 2.0);
    final sinHalfDeltaLambda = math.sin(deltaLambda / 2.0);

    final a = sinHalfDeltaPhi * sinHalfDeltaPhi +
        math.cos(phi1) * math.cos(phi2) * sinHalfDeltaLambda * sinHalfDeltaLambda;

    // Guard against floating point precision out of bounds [-1, 1]
    final clampedA = a.clamp(0.0, 1.0);
    final c = 2.0 * math.atan2(math.sqrt(clampedA), math.sqrt(1.0 - clampedA));

    return earthRadiusMeters * c;
  }

  /// Calculates initial bearing in degrees (0..360) from point 1 to point 2.
  static double bearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = _degToRad(lat1);
    final phi2 = _degToRad(lat2);
    final deltaLambda = _degToRad(lon2 - lon1);

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

    final theta = math.atan2(y, x);
    final deg = (theta * 180.0 / math.pi + 360.0) % 360.0;
    return deg;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}

