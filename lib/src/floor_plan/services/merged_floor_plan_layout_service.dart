import 'dart:convert';
import 'dart:io';

class MergedFloorPlanLayoutEntry {
  final String roomScanPath;
  final double offsetX;
  final double offsetY;
  final double rotation;

  const MergedFloorPlanLayoutEntry({
    required this.roomScanPath,
    required this.offsetX,
    required this.offsetY,
    required this.rotation,
  });

  factory MergedFloorPlanLayoutEntry.fromJson(Map<String, dynamic> json) {
    return MergedFloorPlanLayoutEntry(
      roomScanPath: json['roomScanPath'] as String? ?? '',
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomScanPath': roomScanPath,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'rotation': rotation,
    };
  }
}

class MergedFloorPlanLayoutService {
  static Future<List<MergedFloorPlanLayoutEntry>> loadForPdf(
    File pdfFile,
  ) async {
    final file = File(layoutPathForPdf(pdfFile));
    if (!file.existsSync()) return const [];

    final payload = jsonDecode(await file.readAsString());
    if (payload is! Map<String, dynamic>) return const [];

    final rooms = payload['rooms'];
    if (rooms is! List) return const [];

    return rooms
        .whereType<Map>()
        .map(
          (item) => MergedFloorPlanLayoutEntry.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((item) => item.roomScanPath.trim().isNotEmpty)
        .toList();
  }

  static Future<File> saveForPdf({
    required File pdfFile,
    required List<MergedFloorPlanLayoutEntry> rooms,
    double northRotationRadians = 0,
  }) async {
    final file = File(layoutPathForPdf(pdfFile));
    await file.writeAsString(
      jsonEncode({
        'rooms': rooms.map((item) => item.toJson()).toList(),
        'northRotationRadians': northRotationRadians,
      }),
      flush: true,
    );
    return file;
  }

  static Future<double> loadNorthRotationForPdf(File pdfFile) async {
    final file = File(layoutPathForPdf(pdfFile));
    if (!file.existsSync()) return 0;

    final payload = jsonDecode(await file.readAsString());
    if (payload is! Map<String, dynamic>) return 0;

    return (payload['northRotationRadians'] as num?)?.toDouble() ?? 0;
  }

  static String layoutPathForPdf(File pdfFile) {
    final path = pdfFile.path;
    final basePath = path.toLowerCase().endsWith('.pdf')
        ? path.substring(0, path.length - 4)
        : path;
    return '$basePath.merge_layout.json';
  }
}
