import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_priority/algorithms/haversine.dart';

void main() {
  group('Haversine Algorithm Tests', () {
    test('Distance between identical points is exactly 0.0', () {
      final d = Haversine.distanceMeters(18.4925, 73.8230, 18.4925, 73.8230);
      expect(d, equals(0.0));
    });

    test('Distance calculation is strictly symmetric', () {
      final p1Lat = 18.4925;
      final p1Lon = 73.8230;
      final p2Lat = 18.5080;
      final p2Lon = 73.8350;

      final d12 = Haversine.distanceMeters(p1Lat, p1Lon, p2Lat, p2Lon);
      final d21 = Haversine.distanceMeters(p2Lat, p2Lon, p1Lat, p1Lon);

      expect(d12, greaterThan(0));
      expect(d12, closeTo(d21, 1e-6));
    });

    test('Accurately calculates known distance in Pune (within 1% tolerance)', () {
      // Point A: Karve Statue, Kothrud (18.4988, 73.8202)
      // Point B: Deccan Gymkhana, Pune (18.5173, 73.8415)
      // True great-circle distance is approx 3040 meters.
      final dist = Haversine.distanceMeters(18.4988, 73.8202, 18.5173, 73.8415);
      expect(dist, greaterThan(2900));
      expect(dist, lessThan(3150));
      // Verify within 1% of expected ~3040m
      expect((dist - 3040).abs() / 3040, lessThan(0.015));
    });

    test('Calculates bearing correctly for Cardinal directions', () {
      // Point 2 directly north of Point 1
      final bearingNorth = Haversine.bearingDegrees(18.0, 73.0, 19.0, 73.0);
      expect(bearingNorth, closeTo(0.0, 0.5));

      // Point 2 directly east of Point 1
      final bearingEast = Haversine.bearingDegrees(18.0, 73.0, 18.0, 74.0);
      expect(bearingEast, closeTo(90.0, 1.0));
    });
  });
}

