import 'package:vector_math/vector_math_64.dart';

/// A point in the scanned room's local coordinate space, measured in meters.
class Position {
  const Position(this.vector);

  Position.fromCoordinates(double x, double y, double z)
    : vector = Vector3(x, y, z);

  final Vector3 vector;
  double get x => vector.x;
  double get y => vector.y;
  double get z => vector.z;

  factory Position.fromJson(Map<String, dynamic> json) =>
      Position.fromCoordinates(
        _number(json['x']),
        _number(json['y']),
        _number(json['z']),
      );

  Map<String, double> toJson() => {'x': x, 'y': y, 'z': z};

  @override
  bool operator ==(Object other) =>
      other is Position && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Position(x: $x, y: $y, z: $z)';
}

double _number(Object? value) => value is num ? value.toDouble() : 0;
