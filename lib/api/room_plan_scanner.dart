import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ios_roomplan/src/internal.dart';
import 'package:ios_roomplan/src/services/room_plan_channel.dart';
import 'package:vector_math/vector_math_64.dart';

/// Starts and stops RoomPlan captures on supported iOS devices.
class RoomPlanScanner {
  RoomPlanScanner({RoomPlanChannel? roomPlanChannel})
    : _channel = roomPlanChannel ?? RoomPlanChannel() {
    _scanUpdates = _channel.scanUpdateStream
        .where((event) => event is String)
        .map((event) => parseScanResult(event as String));
  }

  final RoomPlanChannel _channel;
  late final Stream<ScanResult?> _scanUpdates;
  bool _disposed = false;

  /// Emits the latest room geometry while a capture is active.
  Stream<ScanResult?> get onScanResult => _scanUpdates;

  /// Indicates whether the current device can run RoomPlan.
  static Future<bool> isSupported() => RoomPlanChannel.isSupported();

  /// Opens the native capture interface and returns its final room, if saved.
  ///
  /// Returns `null` when the capture is cancelled.
  Future<ScanResult?> startScanning({ScanConfiguration? configuration}) async {
    _ensureOpen();
    final payload = await _channel.startRoomCapture(
      configuration: configuration,
    );
    if (payload == null) return null;
    if (payload is! String) {
      throw const FormatException('RoomPlan returned an invalid scan result.');
    }
    final result = parseScanResult(payload);
    if (result == null) {
      throw const FormatException('RoomPlan returned unreadable scan data.');
    }
    return result;
  }

  /// Ends the active capture and returns control to the Flutter app.
  Future<void> stopScanning() {
    _ensureOpen();
    return _channel.stopRoomCapture();
  }

  /// Closes the native event stream used by this scanner.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.dispose();
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('RoomPlanScanner has been disposed.');
  }
}

/// Decodes serialized geometry and logs malformed native updates in debug mode.
ScanResult? parseScanResult(String? source) {
  if (source == null || source.isEmpty) return null;
  try {
    return _parseRoomPlanJson(source);
  } on Object catch (error, stackTrace) {
    assert(() {
      debugPrint('Unable to decode RoomPlan data: $error');
      debugPrintStack(stackTrace: stackTrace);
      return true;
    }());
    return null;
  }
}

ScanResult _parseRoomPlanJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('The scan payload must be a JSON object.');
  }
  final root = decoded;
  final roomJson = root['room'] is Map<String, dynamic>
      ? root['room'] as Map<String, dynamic>
      : root;
  final walls = _mapList(roomJson['walls']);
  final objects = _mapList(roomJson['objects']);
  final doors = _mapList(roomJson['doors']);
  final windows = _mapList(roomJson['windows']);
  final openings = _mapList(roomJson['openings']);

  final room = RoomData(
    dimensions: _dimensions(_map(roomJson['dimensions'])),
    walls: walls.map(_wall).toList(),
    objects: objects.map(_object).toList(),
    doors: doors.map((item) => _opening(item, OpeningType.door)).toList(),
    windows: windows.map((item) => _opening(item, OpeningType.window)).toList(),
    openings: openings
        .map((item) => _opening(item, OpeningType.opening))
        .toList(),
    floor: _optionalWall(roomJson['floor']),
    ceiling: _optionalWall(roomJson['ceiling']),
  );

  return ScanResult(
    room: room,
    metadata: _metadata(_map(root['metadata'])),
    confidence: _confidence(_map(root['confidence']), walls, objects),
  );
}

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

WallData? _optionalWall(Object? value) {
  final map = _map(value);
  return map == null ? null : _wall(map);
}

RoomDimensions? _dimensions(Map<String, dynamic>? value) {
  if (value == null) return null;
  final x = _number(value['x']);
  final y = _number(value['y']);
  final z = _number(value['z']);
  return RoomDimensions(length: x, height: y, width: z);
}

double _number(Object? value) => value is num ? value.toDouble() : 0;

Matrix4? _matrix(Object? value) {
  if (value is! List || value.length != 16 || value.any((n) => n is! num)) {
    return null;
  }
  return Matrix4.fromList(value.cast<num>().map((n) => n.toDouble()).toList());
}

Position _position(Matrix4? transform) =>
    Position(transform?.getTranslation() ?? Vector3.zero());

Confidence _elementConfidence(Object? value) => switch (value) {
  'high' => Confidence.high,
  'medium' => Confidence.medium,
  _ => Confidence.low,
};

WallData _wall(Map<String, dynamic> value) {
  final transform = _matrix(value['transform']);
  final dimensions = _dimensions(_map(value['dimensions']));
  final openings = _mapList(value['openings'])
      .map((item) => _opening(item, _openingType(item['category'])))
      .toList(growable: false);
  return WallData(
    uuid: value['uuid']?.toString() ?? '',
    position: _position(transform),
    points: const [],
    width: dimensions?.length ?? _number(value['width']),
    height: dimensions?.height ?? _number(value['height']),
    confidence: _elementConfidence(value['confidence']),
    openings: openings,
    dimensions: dimensions,
    transform: transform,
  );
}

OpeningType _openingType(Object? value) => switch (value?.toString()) {
  'door' => OpeningType.door,
  'window' => OpeningType.window,
  _ => OpeningType.opening,
};

ObjectData _object(Map<String, dynamic> value) {
  final transform = _matrix(value['transform']);
  final dimensions = _dimensions(_map(value['dimensions']));
  return ObjectData(
    uuid: value['uuid']?.toString() ?? '',
    position: _position(transform),
    category: ObjectCategory.values.firstWhere(
      (item) => item.name == value['category'],
      orElse: () => ObjectCategory.unknown,
    ),
    width: dimensions?.width ?? 0,
    height: dimensions?.height ?? 0,
    length: dimensions?.length ?? 0,
    confidence: _elementConfidence(value['confidence']),
    dimensions: dimensions,
    transform: transform,
  );
}

OpeningData _opening(Map<String, dynamic> value, OpeningType type) {
  final transform = _matrix(value['transform']);
  final dimensions = _dimensions(_map(value['dimensions']));
  return OpeningData(
    uuid: value['uuid']?.toString() ?? '',
    type: type,
    position: _position(transform),
    width: dimensions?.length ?? _number(value['width']),
    height: dimensions?.height ?? _number(value['height']),
    confidence: _elementConfidence(value['confidence']),
    dimensions: dimensions,
    transform: transform,
  );
}

ScanMetadata _metadata(Map<String, dynamic>? value) {
  final seconds = _number(value?['session_duration']);
  return ScanMetadata(
    scanDate: DateTime.now(),
    scanDuration: Duration(milliseconds: (seconds * 1000).round()),
    deviceModel: value?['device_model']?.toString() ?? 'Unknown',
    hasLidar: value?['has_lidar'] == true || value?['has_lidar'] == 'true',
  );
}

ScanConfidence _confidence(
  Map<String, dynamic>? value,
  List<Map<String, dynamic>> walls,
  List<Map<String, dynamic>> objects,
) {
  if (value != null && value['overall'] is num) {
    return ScanConfidence(
      overall: _number(value['overall']),
      wallAccuracy: _number(value['wallAccuracy']),
      dimensionAccuracy: _number(value['dimensionAccuracy']),
      warnings: value['warnings'] is List
          ? (value['warnings'] as List).whereType<String>().toList()
          : const [],
    );
  }
  double mean(List<Map<String, dynamic>> values) {
    if (values.isEmpty) return 0;
    final score = values.fold<double>(
      0,
      (total, item) =>
          total +
          switch (item['confidence']) {
            'high' => 1,
            'medium' => .66,
            _ => .33,
          },
    );
    return score / values.length;
  }

  return ScanConfidence(
    overall: mean([...walls, ...objects]),
    wallAccuracy: mean(walls),
    dimensionAccuracy: mean(objects),
  );
}
