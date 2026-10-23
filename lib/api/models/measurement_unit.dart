/// Display unit system for room measurements.
enum MeasurementUnit {
  /// Uses meters, square meters, and cubic meters.
  metric,

  /// Uses feet, square feet, and cubic feet.
  imperial,
}

extension MeasurementUnitLabels on MeasurementUnit {
  /// Human-readable name of this unit system.
  String get displayName =>
      this == MeasurementUnit.metric ? 'Metric' : 'Imperial';

  /// Abbreviation used for lengths in this system.
  String get lengthUnit => this == MeasurementUnit.metric ? 'm' : 'ft';

  /// Abbreviation used for areas in this system.
  String get areaUnit => this == MeasurementUnit.metric ? 'm²' : 'sq ft';

  /// Abbreviation used for volumes in this system.
  String get volumeUnit => this == MeasurementUnit.metric ? 'm³' : 'cu ft';
}

/// Converts and formats SI measurements for presentation.
class UnitConverter {
  /// Number of feet in one meter.
  static const metersToFeet = 3.28084;

  /// Number of meters in one foot.
  static const feetToMeters = 0.3048;

  /// Number of square feet in one square meter.
  static const sqMetersToSqFeet = 10.7639;

  /// Number of square meters in one square foot.
  static const sqFeetToSqMeters = 0.092903;

  /// Number of cubic feet in one cubic meter.
  static const cuMetersToFeet = 35.3147;

  /// Number of cubic meters in one cubic foot.
  static const cuFeetToMeters = 0.0283168;

  /// Converts [value] from meters to feet.
  static double metersToFeetConversion(double value) => value * metersToFeet;

  /// Converts [value] from feet to meters.
  static double feetToMetersConversion(double value) => value * feetToMeters;

  /// Converts [value] from square meters to square feet.
  static double sqMetersToSqFeetConversion(double value) =>
      value * sqMetersToSqFeet;

  /// Converts [value] from square feet to square meters.
  static double sqFeetToSqMetersConversion(double value) =>
      value * sqFeetToSqMeters;

  /// Converts [value] from cubic meters to cubic feet.
  static double cuMetersToCuFeetConversion(double value) =>
      value * cuMetersToFeet;

  /// Converts [value] from cubic feet to cubic meters.
  static double cuFeetToCuMetersConversion(double value) =>
      value * cuFeetToMeters;

  /// Formats a length in [unit], rounded to [decimals] decimal places.
  static String formatLength(
    double meters,
    MeasurementUnit unit, {
    int decimals = 2,
  }) {
    final value = unit == MeasurementUnit.metric
        ? meters
        : metersToFeetConversion(meters);
    return '${value.toStringAsFixed(decimals)}${unit.lengthUnit}';
  }

  /// Formats an area in [unit], rounded to [decimals] decimal places.
  static String formatArea(
    double squareMeters,
    MeasurementUnit unit, {
    int decimals = 2,
  }) {
    final value = unit == MeasurementUnit.metric
        ? squareMeters
        : sqMetersToSqFeetConversion(squareMeters);
    return '${value.toStringAsFixed(decimals)}${unit.areaUnit}';
  }

  /// Formats a volume in [unit], rounded to [decimals] decimal places.
  static String formatVolume(
    double cubicMeters,
    MeasurementUnit unit, {
    int decimals = 2,
  }) {
    final value = unit == MeasurementUnit.metric
        ? cubicMeters
        : cuMetersToCuFeetConversion(cubicMeters);
    return '${value.toStringAsFixed(decimals)}${unit.volumeUnit}';
  }
}
