import 'room_data.dart';
import 'scan_confidence.dart';
import 'scan_metadata.dart';

/// The room geometry and scan details returned by a completed capture.
class ScanResult {
  const ScanResult({
    required this.room,
    required this.metadata,
    required this.confidence,
  });

  final RoomData room;
  final ScanMetadata metadata;
  final ScanConfidence confidence;

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
    room: RoomData.fromJson(_object(json['room'])),
    metadata: ScanMetadata.fromJson(_object(json['metadata'])),
    confidence: ScanConfidence.fromJson(_object(json['confidence'])),
  );

  Map<String, dynamic> toJson() => {
    'room': room.toJson(),
    'metadata': metadata.toJson(),
    'confidence': confidence.toJson(),
  };

  ScanResult copyWith({
    RoomData? room,
    ScanMetadata? metadata,
    ScanConfidence? confidence,
  }) => ScanResult(
    room: room ?? this.room,
    metadata: metadata ?? this.metadata,
    confidence: confidence ?? this.confidence,
  );

  @override
  bool operator ==(Object other) =>
      other is ScanResult &&
      other.room == room &&
      other.metadata == metadata &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(room, metadata, confidence);

  @override
  String toString() =>
      'ScanResult(room: $room, metadata: $metadata, confidence: $confidence)';
}

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};
