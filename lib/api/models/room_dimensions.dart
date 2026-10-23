import 'measurement_unit.dart';

/// Measured room extents in meters.
class RoomDimensions {
  const RoomDimensions({
    required this.width,
    required this.height,
    required this.length,
  });

  final double width;
  final double height;
  final double length;

  factory RoomDimensions.fromJson(Map<String, dynamic> json) => RoomDimensions(
    length: _number(json['length']),
    width: _number(json['width']),
    height: _number(json['height']),
  );

  Map<String, double> toJson() => {
    'length': length,
    'width': width,
    'height': height,
  };

  RoomDimensions copyWith({double? length, double? width, double? height}) =>
      RoomDimensions(
        length: length ?? this.length,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  double get volume => length * width * height;
  double get floorArea => length * width;
  double get perimeter => 2 * (length + width);
  double get lengthInFeet => UnitConverter.metersToFeetConversion(length);
  double get widthInFeet => UnitConverter.metersToFeetConversion(width);
  double get heightInFeet => UnitConverter.metersToFeetConversion(height);
  double get floorAreaInSqFeet =>
      UnitConverter.sqMetersToSqFeetConversion(floorArea);
  double get volumeInCuFeet => UnitConverter.cuMetersToCuFeetConversion(volume);
  double get perimeterInFeet => UnitConverter.metersToFeetConversion(perimeter);

  String getFormattedLength(MeasurementUnit unit, {int decimals = 2}) =>
      UnitConverter.formatLength(length, unit, decimals: decimals);
  String getFormattedWidth(MeasurementUnit unit, {int decimals = 2}) =>
      UnitConverter.formatLength(width, unit, decimals: decimals);
  String getFormattedHeight(MeasurementUnit unit, {int decimals = 2}) =>
      UnitConverter.formatLength(height, unit, decimals: decimals);
  String getFormattedFloorArea(MeasurementUnit unit, {int decimals = 2}) =>
      UnitConverter.formatArea(floorArea, unit, decimals: decimals);
  String getFormattedVolume(MeasurementUnit unit, {int decimals = 2}) =>
      UnitConverter.formatVolume(volume, unit, decimals: decimals);
  String getFormattedPerimeter(MeasurementUnit unit, {int decimals = 2}) =>
      UnitConverter.formatLength(perimeter, unit, decimals: decimals);

  String toStringWithUnit(MeasurementUnit unit) =>
      'RoomDimensions(length: ${getFormattedLength(unit)}, '
      'width: ${getFormattedWidth(unit)}, height: ${getFormattedHeight(unit)})';

  @override
  bool operator ==(Object other) =>
      other is RoomDimensions &&
      other.length == length &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(length, width, height);

  @override
  String toString() =>
      'RoomDimensions(length: ${length}m, width: ${width}m, height: ${height}m)';
}

double _number(Object? value) => value is num ? value.toDouble() : 0;
