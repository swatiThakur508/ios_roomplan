import 'package:vector_math/vector_math_64.dart';

import 'confidence.dart';
import 'opening_data.dart';
import 'position.dart';
import 'room_dimensions.dart';

/// A wall or horizontal surface detected in a room.
class WallData {
  const WallData({
    required this.uuid,
    required this.position,
    required this.points,
    required this.width,
    required this.height,
    required this.confidence,
    required this.openings,
    this.dimensions,
    this.transform,
  });

  final String uuid;
  final Position position;
  final List<Position> points;
  final double width;
  final double height;
  final Confidence confidence;
  final List<OpeningData> openings;
  final RoomDimensions? dimensions;
  final Matrix4? transform;

  factory WallData.fromJson(Map<String, dynamic> json) {
    final rawDimensions = json['dimensions'];
    final dimensions = rawDimensions is Map<String, dynamic>
        ? RoomDimensions.fromJson(rawDimensions)
        : null;
    final transform = _matrix(json['transform']);
    return WallData(
      uuid: json['uuid']?.toString() ?? '',
      position: transform == null
          ? Position.fromJson(_map(json['position']))
          : Position(transform.getTranslation()),
      points: _maps(
        json['points'],
      ).map(Position.fromJson).toList(growable: false),
      width: dimensions?.length ?? _number(json['width']),
      height: dimensions?.height ?? _number(json['height']),
      confidence: Confidence.fromJson(json['confidence']?.toString() ?? ''),
      openings: _maps(
        json['openings'],
      ).map(OpeningData.fromJson).toList(growable: false),
      dimensions: dimensions,
      transform: transform,
    );
  }

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'position': position.toJson(),
    'points': points.map((point) => point.toJson()).toList(),
    'width': width,
    'height': height,
    'confidence': confidence.name,
    'openings': openings.map((item) => item.toJson()).toList(),
    'dimensions': dimensions?.toJson(),
    'transform': transform?.storage.toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is WallData &&
      other.uuid == uuid &&
      other.position == position &&
      _same(other.points, points) &&
      other.width == width &&
      other.height == height &&
      other.confidence == confidence &&
      _same(other.openings, openings) &&
      other.dimensions == dimensions;

  @override
  int get hashCode => Object.hash(
    uuid,
    position,
    Object.hashAll(points),
    width,
    height,
    confidence,
    Object.hashAll(openings),
    dimensions,
  );
}

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

Matrix4? _matrix(Object? value) =>
    value is List && value.length == 16 && value.every((item) => item is num)
    ? Matrix4.fromList(
        value.cast<num>().map((item) => item.toDouble()).toList(),
      )
    : null;

double _number(Object? value) => value is num ? value.toDouble() : 0;

bool _same<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
