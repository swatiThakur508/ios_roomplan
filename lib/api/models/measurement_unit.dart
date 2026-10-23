/// Display unit system for room measurements.
enum MeasurementUnit { metric, imperial }

extension MeasurementUnitLabels on MeasurementUnit {
  String get displayName =>
      this == MeasurementUnit.metric ? 'Metric' : 'Imperial';
  String get lengthUnit => this == MeasurementUnit.metric ? 'm' : 'ft';
  String get areaUnit => this == MeasurementUnit.metric ? 'm²' : 'sq ft';
  String get volumeUnit => this == MeasurementUnit.metric ? 'm³' : 'cu ft';
}

/// Converts and formats SI measurements for presentation.
class UnitConverter {
  static const metersToFeet = 3.28084;
  static const feetToMeters = 0.3048;
  static const sqMetersToSqFeet = 10.7639;
  static const sqFeetToSqMeters = 0.092903;
  static const cuMetersToFeet = 35.3147;
  static const cuFeetToMeters = 0.0283168;

  static double metersToFeetConversion(double value) => value * metersToFeet;
  static double feetToMetersConversion(double value) => value * feetToMeters;
  static double sqMetersToSqFeetConversion(double value) =>
      value * sqMetersToSqFeet;
  static double sqFeetToSqMetersConversion(double value) =>
      value * sqFeetToSqMeters;
  static double cuMetersToCuFeetConversion(double value) =>
      value * cuMetersToFeet;
  static double cuFeetToCuMetersConversion(double value) =>
      value * cuFeetToMeters;

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
