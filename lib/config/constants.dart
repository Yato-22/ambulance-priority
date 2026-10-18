/// Central configuration constants for the LoRa-based Ambulance Priority prototype.
class AppConstants {
  // Distance thresholds (meters)
  static const double greenTriggerRadiusM = 200.0;
  static const double arrivalRadiusM = 15.0;
  static const double revertHysteresisM = 5.0;
  static const double stopLineDistanceM = 10.0;
  // ignore: constant_identifier_names
  static const double STOP_LINE_DISTANCE_M = 10.0;
  static const double stopRampDistanceM = 40.0;

  // Ambulance movement
  static const double defaultSpeedKmh = 40.0;
  static const double minSpeedKmh = 20.0;
  static const double maxSpeedKmh = 80.0;

  // Simulation loop
  static const int tickMs = 500;

  // Congestion & routing factors (as specified in requirements)
  // ignore: constant_identifier_names
  static const double ROAD_FACTOR_OPEN = 1.0;
  // ignore: constant_identifier_names
  static const double ROAD_FACTOR_MODERATE = 2.0;
  // ignore: constant_identifier_names
  static const double ROAD_FACTOR_HEAVY = 4.0;
  static const double roadFactorOpen = 1.0;
  static const double roadFactorModerate = 2.0;
  static const double roadFactorHeavy = 4.0;
  static const double blockedThreshold = 50.0;
  static const double minCongestionFactor = 1.0;
  static const double maxRandomCongestionFactor = 2.0;

  // Road class speed factors
  static const double speedFactorMajor = 1.0;
  static const double speedFactorMinor = 0.6;
  static const double maxClassSpeedFactor = 1.0;

  // Signal timing
  static const int normalCycleSeconds = 20;

  // LoRa Hardware Simulation (SX1262 at 865 MHz)
  static const int loraDelayMinMs = 100;
  static const int loraDelayMaxMs = 300;
  static const int loraMaxRetries = 2;
  static const String loraFreqLabel = "865 MHz";

  // Earth radius in meters for Haversine
  static const double earthRadiusMeters = 6371000.0;
}

