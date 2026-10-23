import 'object_data.dart';
import 'opening_data.dart';
import 'room_dimensions.dart';
import 'wall_data.dart';

/// The surfaces and detected contents of one captured room.
class RoomData {
  const RoomData({
    this.dimensions,
    required this.walls,
    required this.objects,
    required this.doors,
    required this.windows,
    required this.openings,
    this.floor,
    this.ceiling,
  });

  final RoomDimensions? dimensions;
  final List<WallData> walls;
  final List<ObjectData> objects;
  final List<OpeningData> doors;
  final List<OpeningData> windows;
  final List<OpeningData> openings;
  final WallData? floor;
  final WallData? ceiling;

  factory RoomData.fromJson(Map<String, dynamic> json) => RoomData(
    dimensions: json['dimensions'] is Map<String, dynamic>
        ? RoomDimensions.fromJson(json['dimensions'] as Map<String, dynamic>)
        : null,
    walls: _items(json['walls'], WallData.fromJson),
    objects: _items(json['objects'], ObjectData.fromJson),
    doors: _items(json['doors'], OpeningData.fromJson),
    windows: _items(json['windows'], OpeningData.fromJson),
    openings: _items(json['openings'], OpeningData.fromJson),
    floor: json['floor'] is Map<String, dynamic>
        ? WallData.fromJson(json['floor'] as Map<String, dynamic>)
        : null,
    ceiling: json['ceiling'] is Map<String, dynamic>
        ? WallData.fromJson(json['ceiling'] as Map<String, dynamic>)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'dimensions': dimensions?.toJson(),
    'walls': walls.map((item) => item.toJson()).toList(),
    'objects': objects.map((item) => item.toJson()).toList(),
    'doors': doors.map((item) => item.toJson()).toList(),
    'windows': windows.map((item) => item.toJson()).toList(),
    'openings': openings.map((item) => item.toJson()).toList(),
    'floor': floor?.toJson(),
    'ceiling': ceiling?.toJson(),
  };

  RoomData copyWith({
    RoomDimensions? dimensions,
    List<WallData>? walls,
    List<ObjectData>? objects,
    List<OpeningData>? doors,
    List<OpeningData>? windows,
    List<OpeningData>? openings,
    WallData? floor,
    WallData? ceiling,
  }) => RoomData(
    dimensions: dimensions ?? this.dimensions,
    walls: walls ?? this.walls,
    objects: objects ?? this.objects,
    doors: doors ?? this.doors,
    windows: windows ?? this.windows,
    openings: openings ?? this.openings,
    floor: floor ?? this.floor,
    ceiling: ceiling ?? this.ceiling,
  );

  @override
  bool operator ==(Object other) =>
      other is RoomData &&
      other.dimensions == dimensions &&
      _same(other.walls, walls) &&
      _same(other.objects, objects) &&
      _same(other.doors, doors) &&
      _same(other.windows, windows) &&
      _same(other.openings, openings) &&
      other.floor == floor &&
      other.ceiling == ceiling;

  @override
  int get hashCode => Object.hash(
    dimensions,
    Object.hashAll(walls),
    Object.hashAll(objects),
    Object.hashAll(doors),
    Object.hashAll(windows),
    Object.hashAll(openings),
    floor,
    ceiling,
  );

  @override
  String toString() =>
      'RoomData(walls: ${walls.length}, objects: ${objects.length}, '
      'doors: ${doors.length}, windows: ${windows.length})';
}

List<T> _items<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value is List
    ? value.whereType<Map<String, dynamic>>().map(parse).toList(growable: false)
    : <T>[];

bool _same<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
