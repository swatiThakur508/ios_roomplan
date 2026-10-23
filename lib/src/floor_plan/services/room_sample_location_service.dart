import 'dart:convert';
import 'dart:io';

class RoomSampleLocationState {
  final double rotationRadians;
  final List<RoomSampleLocation> locations;

  const RoomSampleLocationState({
    required this.rotationRadians,
    required this.locations,
  });
}

class RoomSampleLocation {
  final String sampleRefId;
  final String label;
  final double x;
  final double y;
  final bool isPlaced;
  final double? localX;
  final double? localY;

  const RoomSampleLocation({
    required this.sampleRefId,
    required this.label,
    required this.x,
    required this.y,
    this.isPlaced = true,
    this.localX,
    this.localY,
  });

  factory RoomSampleLocation.fromJson(Map<String, dynamic> json) {
    return RoomSampleLocation(
      sampleRefId: json['sampleRefId'] as String? ?? '',
      label: json['label'] as String? ?? 'Sample',
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.5,
      isPlaced: json['isPlaced'] as bool? ?? true,
      localX: (json['localX'] as num?)?.toDouble(),
      localY: (json['localY'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sampleRefId': sampleRefId,
      'label': label,
      'x': x,
      'y': y,
      'isPlaced': isPlaced,
      'localX': localX,
      'localY': localY,
    };
  }

  RoomSampleLocation copyWith({
    String? label,
    double? x,
    double? y,
    bool? isPlaced,
    double? localX,
    double? localY,
  }) {
    return RoomSampleLocation(
      sampleRefId: sampleRefId,
      label: label ?? this.label,
      x: x ?? this.x,
      y: y ?? this.y,
      isPlaced: isPlaced ?? this.isPlaced,
      localX: localX ?? this.localX,
      localY: localY ?? this.localY,
    );
  }
}

class RoomSampleLocationService {
  static Future<RoomSampleLocationState> loadStateForPdf(File pdfFile) async {
    final file = File(locationPathForPdf(pdfFile));
    if (!file.existsSync()) {
      return const RoomSampleLocationState(rotationRadians: 0, locations: []);
    }

    final payload = jsonDecode(await file.readAsString());
    if (payload is List) {
      return RoomSampleLocationState(
        rotationRadians: 0,
        locations: _locationsFromList(payload),
      );
    }
    if (payload is! Map<String, dynamic>) {
      return const RoomSampleLocationState(rotationRadians: 0, locations: []);
    }

    final locationsPayload = payload['locations'];
    return RoomSampleLocationState(
      rotationRadians:
          (payload['rotationRadians'] as num?)?.toDouble() ??
          ((payload['rotationTurns'] as num?)?.toDouble() ?? 0) *
              1.5707963267948966,
      locations: locationsPayload is List
          ? _locationsFromList(locationsPayload)
          : [],
    );
  }

  static Future<List<RoomSampleLocation>> loadForPdf(File pdfFile) async {
    return (await loadStateForPdf(pdfFile)).locations;
  }

  static Future<File> saveForPdf({
    required File pdfFile,
    required List<RoomSampleLocation> locations,
    double rotationRadians = 0,
  }) async {
    final file = File(locationPathForPdf(pdfFile));
    await file.writeAsString(
      jsonEncode({
        'rotationRadians': rotationRadians,
        'locations': locations.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );
    return file;
  }

  static List<RoomSampleLocation> _locationsFromList(List payload) {
    return payload
        .whereType<Map>()
        .map(
          (item) =>
              RoomSampleLocation.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.sampleRefId.trim().isNotEmpty)
        .toList();
  }

  static String locationPathForPdf(File pdfFile) {
    final path = pdfFile.path;
    final basePath = path.toLowerCase().endsWith('.pdf')
        ? path.substring(0, path.length - 4)
        : path;
    return '$basePath.sample_locations.json';
  }
}
