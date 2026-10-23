import 'package:vector_math/vector_math_64.dart';

import 'confidence.dart';
import 'position.dart';
import 'room_dimensions.dart';

enum ObjectCategory {
  storage,
  table,
  sofa,
  chair,
  bed,
  sink,
  toilet,
  oven,
  refrigerator,
  stove,
  washerDryer,
  unknown;

  static ObjectCategory fromJson(String value) {
    final normalized = value.replaceAll('_', '').toLowerCase();
    return ObjectCategory.values.firstWhere(
      (category) => category.name.toLowerCase() == normalized,
      orElse: () => ObjectCategory.unknown,
    );
  }
}

/// A piece of furniture or appliance identified in the scan.
class ObjectData {
  const ObjectData({
    required this.uuid,
    required this.position,
    required this.category,
    required this.width,
    required this.height,
    required this.length,
    required this.confidence,
    this.dimensions,
    this.transform,
  });

  final String uuid;
  final Position position;
  final ObjectCategory category;
  final double width;
  final double height;
  final double length;
  final Confidence confidence;
  final RoomDimensions? dimensions;
  final Matrix4? transform;

  factory ObjectData.fromJson(Map<String, dynamic> json) {
    final rawDimensions = json['dimensions'];
    final dimensions = rawDimensions is Map<String, dynamic>
        ? RoomDimensions.fromJson(rawDimensions)
        : null;
    final transform = _matrix(json['transform']);
    return ObjectData(
      uuid: json['uuid']?.toString() ?? '',
      position: transform == null
          ? Position.fromCoordinates(0, 0, 0)
          : Position(transform.getTranslation()),
      category: ObjectCategory.fromJson(json['category']?.toString() ?? ''),
      width: dimensions?.width ?? _number(json['width']),
      height: dimensions?.height ?? _number(json['height']),
      length: dimensions?.length ?? _number(json['length']),
      confidence: Confidence.fromJson(json['confidence']?.toString() ?? ''),
      dimensions: dimensions,
      transform: transform,
    );
  }

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'position': position.toJson(),
    'category': category.name,
    'width': width,
    'height': height,
    'length': length,
    'confidence': confidence.name,
    'dimensions': dimensions?.toJson(),
    'transform': transform?.storage.toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is ObjectData &&
      other.uuid == uuid &&
      other.position == position &&
      other.category == category &&
      other.width == width &&
      other.height == height &&
      other.length == length &&
      other.confidence == confidence &&
      other.dimensions == dimensions;

  @override
  int get hashCode => Object.hash(
    uuid,
    position,
    category,
    width,
    height,
    length,
    confidence,
    dimensions,
  );
}

Matrix4? _matrix(Object? value) =>
    value is List && value.length == 16 && value.every((item) => item is num)
    ? Matrix4.fromList(
        value.cast<num>().map((item) => item.toDouble()).toList(),
      )
    : null;

double _number(Object? value) => value is num ? value.toDouble() : 0;
