import 'package:vector_math/vector_math_64.dart';

import 'confidence.dart';
import 'position.dart';
import 'room_dimensions.dart';

enum OpeningType { door, window, opening }

/// A doorway, window, or other opening detected in a room.
class OpeningData {
  const OpeningData({
    required this.uuid,
    required this.type,
    required this.position,
    required this.width,
    required this.height,
    required this.confidence,
    this.dimensions,
    this.transform,
  });

  final String uuid;
  final OpeningType type;
  final Position position;
  final double width;
  final double height;
  final Confidence confidence;
  final RoomDimensions? dimensions;
  final Matrix4? transform;

  factory OpeningData.fromJson(Map<String, dynamic> json) {
    final dimensionJson = _map(json['dimensions']);
    final dimensions = dimensionJson == null
        ? null
        : RoomDimensions.fromJson(dimensionJson);
    final transform = _matrix(json['transform']);
    return OpeningData(
      uuid: json['uuid']?.toString() ?? '',
      type: OpeningType.values.firstWhere(
        (value) => value.name == (json['type'] ?? json['category']),
        orElse: () => OpeningType.opening,
      ),
      position: transform == null
          ? Position.fromCoordinates(0, 0, 0)
          : Position(transform.getTranslation()),
      width: dimensions?.length ?? _number(json['width']),
      height: dimensions?.height ?? _number(json['height']),
      confidence: Confidence.fromJson(json['confidence']?.toString() ?? ''),
      dimensions: dimensions,
      transform: transform,
    );
  }

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'type': type.name,
    'position': position.toJson(),
    'width': width,
    'height': height,
    'confidence': confidence.name,
    'dimensions': dimensions?.toJson(),
    'transform': transform?.storage.toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is OpeningData &&
      other.uuid == uuid &&
      other.type == type &&
      other.position == position &&
      other.width == width &&
      other.height == height &&
      other.confidence == confidence &&
      other.dimensions == dimensions;

  @override
  int get hashCode =>
      Object.hash(uuid, type, position, width, height, confidence, dimensions);

  @override
  String toString() =>
      'OpeningData(type: ${type.name}, width: $width, height: $height)';
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

Matrix4? _matrix(Object? value) =>
    value is List && value.length == 16 && value.every((item) => item is num)
    ? Matrix4.fromList(
        value.cast<num>().map((item) => item.toDouble()).toList(),
      )
    : null;

double _number(Object? value) => value is num ? value.toDouble() : 0;
