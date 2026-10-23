import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ios_roomplan/src/internal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math_64.dart';

class FloorPlanPdfService {
  static const String _embeddedGeometryStart =
      '\n%%IOS_ROOMPLAN_JSON_START%%\n';
  static const String _embeddedGeometryEnd = '\n%%IOS_ROOMPLAN_JSON_END%%\n';

  static Future<File> create2DFloorPlan(
    ScanResult scanResult, {
    String? title,
    String? fileName,
    List<RoomSampleLocation> sampleLocations = const [],
    double rotationRadians = 0,
    List<PlanSurfaceSnapshot>? surfaceSnapshots,
    String? logoImageDataUri,
    bool previewOnly = false,
  }) async {
    final surfaces = _validSurfaces(
      surfaceSnapshots?.map((surface) => surface._toPlanSurface()).toList() ??
          _buildSurfaces(scanResult),
    );
    if (surfaces.isEmpty) {
      throw StateError(
        'No room geometry was found. Please complete a RoomPlan scan before creating a 2D floor plan.',
      );
    }
    final document = pw.Document();
    final svg = _FloorPlanSvg(
      scanResult,
      surfaces,
      title: title,
      sampleLocations: sampleLocations,
      rotationRadians: rotationRadians,
      logoImageDataUri: logoImageDataUri,
      previewOnly: previewOnly,
    ).build();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(842, 1122),
        margin: const pw.EdgeInsets.all(20),
        build: (_) =>
            _buildPdfPageContent(svg, previewOnly ? null : logoImageDataUri),
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final safeFileName = _safeFileName(fileName ?? title ?? 'room_plan_2d');
    final file = File(
      '${directory.path}/${safeFileName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    try {
      await file.writeAsBytes(await document.save(), flush: true);
      if (!await file.exists() || await file.length() == 0) {
        throw FileSystemException(
          'The generated floor plan PDF is empty.',
          file.path,
        );
      }
      return file;
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Preserve the PDF generation error if cleanup also fails.
      }
      rethrow;
    }
  }

  static Future<File> createMerged2DFloorPlan(
    List<NamedScanResult> scans, {
    String? title,
    String? fileName,
    String? logoImageDataUri,
  }) async {
    if (scans.isEmpty) {
      throw StateError('Select at least one saved room scan to merge.');
    }

    final document = pw.Document();
    var pageCount = 0;
    for (final scan in scans) {
      final surfaces = _validSurfaces(
        scan.surfaceSnapshots
                ?.map((surface) => surface._toPlanSurface())
                .toList() ??
            _buildSurfaces(scan.scanResult),
      );
      if (surfaces.isEmpty) continue;
      final svg = _FloorPlanSvg(
        scan.scanResult,
        surfaces,
        title: scan.name,
        logoImageDataUri: logoImageDataUri,
      ).build();

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(842, 1122),
          margin: const pw.EdgeInsets.all(20),
          build: (_) => _buildPdfPageContent(svg, logoImageDataUri),
        ),
      );
      pageCount++;
    }

    if (pageCount == 0) {
      throw StateError(
        'No room geometry was found in the selected scans. Re-scan those rooms and try again.',
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final safeFileName = _safeFileName(
      fileName ?? title ?? 'merged_floor_plan',
    );
    final file = File(
      '${directory.path}/${safeFileName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await document.save());
    return file;
  }

  static Future<File> createArrangedMerged2DFloorPlan(
    List<ArrangedScanResult> rooms, {
    String? title,
    String? fileName,
    String? logoImageDataUri,
    double northRotationRadians = 0,
    List<PlacedLetterPosition>? placedLetters,
    bool showMeasurements = true,
  }) async {
    if (rooms.isEmpty) {
      throw StateError('Add at least one saved room scan before saving.');
    }

    final svg = _MergedFloorPlanSvg(
      rooms,
      title: title,
      logoImageDataUri: logoImageDataUri,
      northRotationRadians: northRotationRadians,
      placedLetters: placedLetters,
      showMeasurements: showMeasurements,
    ).build();
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(842, 1122),
        margin: const pw.EdgeInsets.all(20),
        build: (_) => _buildPdfPageContent(svg, logoImageDataUri),
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final safeFileName = _safeFileName(
      fileName ?? title ?? 'merged_floor_plan',
    );
    final file = File(
      '${directory.path}/${safeFileName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await document.save());
    return file;
  }

  static Future<File> saveScanGeometry({
    required ScanResult scanResult,
    required String roomName,
    required File pdfFile,
    List<PlanSurfaceSnapshot>? surfaceSnapshots,
    double rotationRadians = 0,
    bool? detectFurniture,
  }) async {
    final file = File(_scanGeometryPath(pdfFile.path));
    final payload = {
      'roomName': roomName,
      'scanResult': scanResult.toJson(),
      'rotationRadians': rotationRadians,
      if (detectFurniture != null) 'detectFurniture': detectFurniture,
      if (surfaceSnapshots != null)
        'surfaceSnapshots': surfaceSnapshots
            .map((surface) => surface.toJson())
            .toList(),
    };
    final payloadJson = jsonEncode(payload);
    await file.writeAsString(payloadJson, flush: true);
    await _embedScanGeometryInPdf(pdfFile, payloadJson);
    return file;
  }

  static Future<NamedScanResult?> loadScanGeometry(File pdfFile) async {
    final file = File(_scanGeometryPath(pdfFile.path));
    if (!file.existsSync()) {
      final embeddedPayload = await _extractScanGeometryFromPdf(pdfFile);
      if (embeddedPayload == null) return null;
      await file.writeAsString(embeddedPayload, flush: true);
    }

    final payload = jsonDecode(await file.readAsString());
    if (payload is! Map<String, dynamic>) return null;

    final scanJson = payload['scanResult'];
    if (scanJson is! Map<String, dynamic>) return null;

    final sampleState = await RoomSampleLocationService.loadStateForPdf(
      pdfFile,
    );
    final surfacePayload = payload['surfaceSnapshots'];
    final geometryRotationRadians =
        (payload['rotationRadians'] as num?)?.toDouble() ?? 0;
    final rotationRadians = sampleState.rotationRadians != 0
        ? sampleState.rotationRadians
        : geometryRotationRadians;
    final detectFurniture = payload['detectFurniture'] is bool
        ? payload['detectFurniture'] as bool
        : await _defaultDetectFurniture();

    var scanResult = ScanResult.fromJson(scanJson);
    var surfaceSnapshots = surfacePayload is List
        ? _surfaceSnapshotsFromList(surfacePayload)
        : null;
    if (!detectFurniture) {
      // RoomPlan always detects furniture objects; honor the app's
      // "Detect Furniture" setting by excluding them from loaded geometry.
      scanResult = scanResult.copyWith(
        room: scanResult.room.copyWith(objects: const []),
      );
      // Saved surface snapshots are the editor's source of truth. Keep any
      // manually added objects even when RoomPlan furniture detection is off.
    }

    return NamedScanResult(
      name: (payload['roomName'] as String?)?.trim().isNotEmpty == true
          ? payload['roomName'] as String
          : _fallbackNameFromFile(pdfFile),
      scanResult: scanResult,
      pdfFile: pdfFile,
      sampleLocations: sampleState.locations,
      sampleRotationRadians: rotationRadians,
      surfaceSnapshots: surfaceSnapshots,
      detectFurniture: detectFurniture,
    );
  }

  static Future<bool> _defaultDetectFurniture() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_detectFurniturePreferenceKey) ?? false;
  }

  static List<PlanSurfaceSnapshot> _surfaceSnapshotsFromList(List payload) {
    return payload
        .whereType<Map>()
        .map(
          (item) =>
              PlanSurfaceSnapshot.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.kind.trim().isNotEmpty)
        .toList();
  }

  static String geometryPathForPdf(File pdfFile) {
    return _scanGeometryPath(pdfFile.path);
  }

  static const String _detectFurniturePreferenceKey =
      'ios_roomplan.floor_scan_detect_furniture';

  static String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.isEmpty ? 'room_plan_2d' : cleaned;
  }

  static String _scanGeometryPath(String pdfPath) {
    final basePath = pdfPath.toLowerCase().endsWith('.pdf')
        ? pdfPath.substring(0, pdfPath.length - 4)
        : pdfPath;
    return '$basePath.roomplan.json';
  }

  static Future<void> _embedScanGeometryInPdf(
    File pdfFile,
    String payloadJson,
  ) async {
    if (!await pdfFile.exists()) return;
    final bytes = await pdfFile.readAsBytes();
    final markerStart = utf8.encode(_embeddedGeometryStart);
    final cleanBytes = _removeEmbeddedScanGeometry(bytes, markerStart);
    final embeddedPayload = base64Encode(utf8.encode(payloadJson));
    final nextBytes = <int>[
      ...cleanBytes,
      ...utf8.encode(_embeddedGeometryStart),
      ...utf8.encode(embeddedPayload),
      ...utf8.encode(_embeddedGeometryEnd),
    ];
    await pdfFile.writeAsBytes(nextBytes, flush: true);
  }

  static Future<String?> _extractScanGeometryFromPdf(File pdfFile) async {
    if (!await pdfFile.exists()) return null;
    final text = utf8.decode(await pdfFile.readAsBytes(), allowMalformed: true);
    final startIndex = text.lastIndexOf(_embeddedGeometryStart);
    if (startIndex < 0) return null;
    final payloadStart = startIndex + _embeddedGeometryStart.length;
    final endIndex = text.indexOf(_embeddedGeometryEnd, payloadStart);
    if (endIndex < 0) return null;
    final encodedPayload = text.substring(payloadStart, endIndex).trim();
    if (encodedPayload.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(encodedPayload));
    } catch (_) {
      return null;
    }
  }

  static List<int> _removeEmbeddedScanGeometry(
    List<int> bytes,
    List<int> markerStart,
  ) {
    final markerIndex = _lastIndexOfBytes(bytes, markerStart);
    if (markerIndex < 0) return bytes;
    return bytes.sublist(0, markerIndex);
  }

  static int _lastIndexOfBytes(List<int> source, List<int> pattern) {
    if (pattern.isEmpty || source.length < pattern.length) return -1;
    for (var i = source.length - pattern.length; i >= 0; i--) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }

  static List<PlanSurfaceSnapshot> surfaceSnapshots(ScanResult scanResult) {
    return _buildSurfaces(scanResult)
        .map(
          (surface) => PlanSurfaceSnapshot(
            kind: surface.kind.name,
            label: surface.label,
            centerX: surface.centerX,
            centerY: surface.centerZ,
            angle: surface.angle,
            length: surface.length,
            depth: surface.depth,
          ),
        )
        .toList();
  }

  static String _fallbackNameFromFile(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? 'Room Scan'
        : file.uri.pathSegments.last.replaceAll('.pdf', '');
    return name.replaceAll('_', ' ');
  }

  static List<_PlanSurface> _validSurfaces(List<_PlanSurface> surfaces) {
    return surfaces.where((surface) {
      return surface.centerX.isFinite &&
          surface.centerZ.isFinite &&
          surface.angle.isFinite &&
          surface.length.isFinite &&
          surface.depth.isFinite &&
          surface.length > 0 &&
          surface.depth > 0;
    }).toList();
  }

  static List<_PlanSurface> _buildSurfaces(ScanResult scanResult) {
    final room = scanResult.room;
    final nestedDoors = room.walls
        .expand((wall) => wall.openings)
        .where((opening) => opening.type == OpeningType.door);
    final nestedWindows = room.walls
        .expand((wall) => wall.openings)
        .where((opening) => opening.type == OpeningType.window);
    final nestedOpenings = room.walls
        .expand((wall) => wall.openings)
        .where((opening) => opening.type == OpeningType.opening);
    final doors = room.doors.isNotEmpty ? room.doors : nestedDoors;
    final windows = room.windows.isNotEmpty ? room.windows : nestedWindows;
    final openings = room.openings.isNotEmpty ? room.openings : nestedOpenings;

    final surfaces = [
      ...room.walls.map(
        (wall) => _PlanSurface.fromTransform(
          kind: _SurfaceKind.wall,
          label: 'Wall',
          position: wall.position,
          transform: wall.transform,
          length: wall.width,
          depth: 0.02,
        ),
      ),
      ...doors.map(
        (door) => _PlanSurface.fromTransform(
          kind: _SurfaceKind.door,
          label: 'Door',
          position: door.position,
          transform: door.transform,
          length: door.width,
          depth: 0.02,
        ),
      ),
      ...windows.map(
        (window) => _PlanSurface.fromTransform(
          kind: _SurfaceKind.window,
          label: 'Window',
          position: window.position,
          transform: window.transform,
          length: window.width,
          depth: 0.02,
        ),
      ),
      ...openings.map(
        (opening) => _PlanSurface.fromTransform(
          kind: _SurfaceKind.opening,
          label: 'Opening',
          position: opening.position,
          transform: opening.transform,
          length: opening.width,
          depth: 0.02,
        ),
      ),
      ...room.objects.map(
        (object) => _PlanSurface.fromTransform(
          kind: _SurfaceKind.object,
          label: _titleCase(object.category.name),
          position: object.position,
          transform: object.transform,
          length: object.length,
          depth: object.width,
        ),
      ),
    ].where((surface) => surface.length > 0).toList();

    return _withInferredClosingWalls(surfaces);
  }

  static List<_PlanSurface> _withInferredClosingWalls(
    List<_PlanSurface> surfaces,
  ) {
    final walls = surfaces
        .asMap()
        .entries
        .where((entry) => entry.value.kind == _SurfaceKind.wall)
        .toList();
    if (walls.length < 2) return surfaces;

    final endpoints = <({int wallIndex, _Point point})>[];
    for (final entry in walls) {
      final (start, end) = entry.value.endpoints();
      endpoints.add((wallIndex: entry.key, point: start));
      endpoints.add((wallIndex: entry.key, point: end));
    }
    final primaryAxis = _dominantWallAxis(walls.map((entry) => entry.value));
    final secondaryAxis = _Point(-primaryAxis.y, primaryAxis.x);

    final danglingEndpointIndexes = <int>[];
    for (var i = 0; i < endpoints.length; i++) {
      final hasNearbyWallEnd = endpoints.asMap().entries.any((entry) {
        if (entry.key == i || entry.value.wallIndex == endpoints[i].wallIndex) {
          return false;
        }
        return (entry.value.point - endpoints[i].point).length <= 0.28;
      });
      if (!hasNearbyWallEnd) {
        danglingEndpointIndexes.add(i);
      }
    }

    final connectors = <_PlanSurface>[];
    final used = <int>{};
    for (final i in danglingEndpointIndexes) {
      if (used.contains(i)) continue;

      var bestIndex = -1;
      var bestDistance = double.infinity;
      for (final j in danglingEndpointIndexes) {
        if (i == j ||
            used.contains(j) ||
            endpoints[i].wallIndex == endpoints[j].wallIndex) {
          continue;
        }
        final distance = (endpoints[i].point - endpoints[j].point).length;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = j;
        }
      }

      if (bestIndex < 0 || bestDistance < 0.28 || bestDistance > 8.0) {
        continue;
      }

      final start = endpoints[i].point;
      final end = endpoints[bestIndex].point;
      connectors.addAll(
        _closingWallsBetweenAligned(start, end, primaryAxis, secondaryAxis),
      );
      used
        ..add(i)
        ..add(bestIndex);
    }

    if (connectors.isEmpty && endpoints.length >= 4) {
      final hull = _convexHull(
        endpoints.map((endpoint) => endpoint.point).toList(),
      );
      for (var i = 0; i < hull.length; i++) {
        final start = hull[i];
        final end = hull[(i + 1) % hull.length];
        final distance = (start - end).length;
        if (distance < 0.28 || distance > 8.0) continue;
        if (_hasExistingWallBetween(
          walls.map((entry) => entry.value),
          start,
          end,
        )) {
          continue;
        }
        connectors.addAll(
          _closingWallsBetweenAligned(start, end, primaryAxis, secondaryAxis),
        );
      }
    }

    if (connectors.isEmpty) return surfaces;
    return [...surfaces, ...connectors];
  }

  static List<_PlanSurface> _closingWallsBetweenAligned(
    _Point start,
    _Point end,
    _Point primaryAxis,
    _Point secondaryAxis,
  ) {
    final delta = end - start;
    final primaryLength = _dot(delta, primaryAxis);
    final secondaryLength = _dot(delta, secondaryAxis);

    if (secondaryLength.abs() < 0.22 || primaryLength.abs() < 0.22) {
      return [_closingWallBetween(start, end)];
    }

    final primaryFirstCorner = start + primaryAxis * primaryLength;
    final secondaryFirstCorner = start + secondaryAxis * secondaryLength;
    final firstOption = [
      _closingWallBetween(start, primaryFirstCorner),
      _closingWallBetween(primaryFirstCorner, end),
    ];
    final secondOption = [
      _closingWallBetween(start, secondaryFirstCorner),
      _closingWallBetween(secondaryFirstCorner, end),
    ];

    final firstScore = _connectorScore(firstOption);
    final secondScore = _connectorScore(secondOption);
    return (firstScore <= secondScore ? firstOption : secondOption)
        .where((wall) => wall.length >= 0.22)
        .toList();
  }

  static double _connectorScore(List<_PlanSurface> walls) {
    return walls.fold<double>(
      0,
      (score, wall) => score + wall.length + (wall.length < 0.35 ? 4 : 0),
    );
  }

  static _Point _dominantWallAxis(Iterable<_PlanSurface> walls) {
    final wallList = walls.toList();
    if (wallList.isEmpty) return const _Point(1, 0);
    final reference = wallList.reduce((a, b) => a.length >= b.length ? a : b);
    final axis = _Point(math.cos(reference.angle), math.sin(reference.angle));
    final length = axis.length;
    return length == 0 ? const _Point(1, 0) : axis * (1 / length);
  }

  static double _dot(_Point a, _Point b) => a.x * b.x + a.y * b.y;

  static _PlanSurface _closingWallBetween(_Point start, _Point end) {
    final delta = end - start;
    return _PlanSurface(
      kind: _SurfaceKind.wall,
      label: 'Inferred Closing Wall',
      centerX: (start.x + end.x) / 2,
      centerZ: (start.y + end.y) / 2,
      angle: math.atan2(delta.y, delta.x),
      length: delta.length,
      depth: 0.05,
    );
  }

  static bool _hasExistingWallBetween(
    Iterable<_PlanSurface> walls,
    _Point start,
    _Point end,
  ) {
    final candidateMid = _Point((start.x + end.x) / 2, (start.y + end.y) / 2);
    final candidateLength = (end - start).length;
    final candidateAngle = math.atan2(end.y - start.y, end.x - start.x);
    return walls.any((wall) {
      final wallMid = _Point(wall.centerX, wall.centerZ);
      final angleDelta = _smallestAngleDelta(candidateAngle, wall.angle).abs();
      return (wallMid - candidateMid).length < 0.35 &&
          (wall.length - candidateLength).abs() < 0.7 &&
          (angleDelta < math.pi / 12 ||
              (math.pi - angleDelta).abs() < math.pi / 12);
    });
  }

  static List<_Point> _convexHull(List<_Point> points) {
    final unique = <String, _Point>{};
    for (final point in points) {
      unique['${point.x.toStringAsFixed(3)},${point.y.toStringAsFixed(3)}'] =
          point;
    }
    final sorted = unique.values.toList()
      ..sort((a, b) {
        final xCompare = a.x.compareTo(b.x);
        return xCompare != 0 ? xCompare : a.y.compareTo(b.y);
      });
    if (sorted.length <= 2) return sorted;

    final lower = <_Point>[];
    for (final point in sorted) {
      while (lower.length >= 2 &&
          _cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }

    final upper = <_Point>[];
    for (final point in sorted.reversed) {
      while (upper.length >= 2 &&
          _cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }

    return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
  }

  static double _cross(_Point origin, _Point a, _Point b) {
    return (a.x - origin.x) * (b.y - origin.y) -
        (a.y - origin.y) * (b.x - origin.x);
  }

  static double _smallestAngleDelta(double a, double b) {
    var delta = (a - b) % (math.pi * 2);
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta < -math.pi) delta += math.pi * 2;
    return delta;
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return 'Object';
    final spaced = value.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    return spaced
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}

class NamedScanResult {
  final String name;
  final ScanResult scanResult;
  final File pdfFile;
  final List<RoomSampleLocation> sampleLocations;
  final double sampleRotationRadians;
  final List<PlanSurfaceSnapshot>? surfaceSnapshots;
  final bool detectFurniture;

  const NamedScanResult({
    required this.name,
    required this.scanResult,
    required this.pdfFile,
    this.sampleLocations = const [],
    this.sampleRotationRadians = 0,
    this.surfaceSnapshots,
    this.detectFurniture = true,
  });
}

class ArrangedScanResult {
  final NamedScanResult scan;
  final double offsetX;
  final double offsetY;
  final double rotation;
  final List<PlanSurfaceSnapshot>? surfaces;
  final List<RoomSampleLocation> sampleLocations;
  final double sampleRotationRadians;

  const ArrangedScanResult({
    required this.scan,
    required this.offsetX,
    required this.offsetY,
    required this.rotation,
    this.surfaces,
    this.sampleLocations = const [],
    this.sampleRotationRadians = 0,
  });
}

class PlanSurfaceSnapshot {
  final String kind;
  final String label;
  final double centerX;
  final double centerY;
  final double angle;
  final double length;
  final double depth;

  const PlanSurfaceSnapshot({
    required this.kind,
    required this.label,
    required this.centerX,
    required this.centerY,
    required this.angle,
    required this.length,
    required this.depth,
  });

  factory PlanSurfaceSnapshot.fromJson(Map<String, dynamic> json) {
    return PlanSurfaceSnapshot(
      kind: json['kind'] as String? ?? '',
      label: json['label'] as String? ?? '',
      centerX: (json['centerX'] as num?)?.toDouble() ?? 0,
      centerY: (json['centerY'] as num?)?.toDouble() ?? 0,
      angle: (json['angle'] as num?)?.toDouble() ?? 0,
      length: (json['length'] as num?)?.toDouble() ?? 0,
      depth: (json['depth'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'label': label,
      'centerX': centerX,
      'centerY': centerY,
      'angle': angle,
      'length': length,
      'depth': depth,
    };
  }

  PlanSurfaceSnapshot copyWith({
    double? centerX,
    double? centerY,
    double? angle,
    double? length,
    double? depth,
  }) {
    return PlanSurfaceSnapshot(
      kind: kind,
      label: label,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      angle: angle ?? this.angle,
      length: length ?? this.length,
      depth: depth ?? this.depth,
    );
  }

  List<Offset> corners() {
    final direction = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-math.sin(angle), math.cos(angle));
    final halfLength = length / 2;
    final halfDepth = depth / 2;
    final center = Offset(centerX, centerY);
    return [
      center - direction * halfLength - normal * halfDepth,
      center + direction * halfLength - normal * halfDepth,
      center + direction * halfLength + normal * halfDepth,
      center - direction * halfLength + normal * halfDepth,
    ];
  }

  (Offset, Offset) endpoints() {
    final direction = Offset(math.cos(angle), math.sin(angle));
    final center = Offset(centerX, centerY);
    return (
      center - direction * (length / 2),
      center + direction * (length / 2),
    );
  }

  _PlanSurface _toPlanSurface() {
    return _PlanSurface(
      kind: _surfaceKindFromName(kind),
      label: label,
      centerX: centerX,
      centerZ: centerY,
      angle: angle,
      length: length,
      depth: depth,
    );
  }
}

_SurfaceKind _surfaceKindFromName(String name) {
  return _SurfaceKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => _SurfaceKind.object,
  );
}

class PlacedLetterPosition {
  final String letter;
  final double x; // World-space x coordinate
  final double y; // World-space y coordinate

  const PlacedLetterPosition({
    required this.letter,
    required this.x,
    required this.y,
  });
}

class _MergedFloorPlanSvg {
  // Full-page portrait layout for iPad display
  static const double width = 842;
  static const double height =
      1122; // Letter portrait - fits iPad without scroll
  static const double margin = 16;
  static const double titleBlockTop = 960;
  static const double titleBlockBottom = height - margin;
  static const double drawingLeft = 58;
  static const double drawingRight = 784;
  static const double drawingTop = 100;
  static const double drawingBottom = 940;

  final List<ArrangedScanResult> rooms;
  final String? title;
  final String? logoImageDataUri;
  final double northRotationRadians;
  final List<PlacedLetterPosition>? placedLetters;
  final bool showMeasurements;

  _MergedFloorPlanSvg(
    this.rooms, {
    this.title,
    this.logoImageDataUri,
    this.northRotationRadians = 0,
    this.placedLetters,
    this.showMeasurements = true,
  });

  String build() {
    final roomPlans = rooms
        .map(
          (room) => (
            room: room,
            surfaces:
                room.surfaces
                    ?.map((surface) => surface._toPlanSurface())
                    .toList() ??
                FloorPlanPdfService._buildSurfaces(room.scan.scanResult),
          ),
        )
        .where((entry) => entry.surfaces.isNotEmpty)
        .toList();

    if (roomPlans.isEmpty) {
      throw StateError('No room geometry was found in the arranged scans.');
    }

    final bounds = _mergedBounds(roomPlans, placedLetters);
    final scale = math.min(
      (drawingRight - drawingLeft) / math.max(bounds.maxX - bounds.minX, 1),
      (drawingBottom - drawingTop) / math.max(bounds.maxY - bounds.minY, 1),
    );
    final usedWidth = (bounds.maxX - bounds.minX) * scale;
    final usedHeight = (bounds.maxY - bounds.minY) * scale;
    final offsetX =
        drawingLeft +
        ((drawingRight - drawingLeft) - usedWidth) / 2 -
        bounds.minX * scale;
    final offsetY =
        drawingTop +
        ((drawingBottom - drawingTop) - usedHeight) / 2 -
        bounds.minY * scale;

    _Point map(_Point point) {
      return _Point(offsetX + point.x * scale, offsetY + point.y * scale);
    }

    final buffer = StringBuffer();
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">',
    );
    buffer.writeln('<rect width="100%" height="100%" fill="#ffffff"/>');
    _drawSheet(buffer);
    _drawLogo(buffer);
    _drawGrid(buffer);

    for (final entry in roomPlans) {
      _drawRoom(buffer, entry.room, entry.surfaces, map, scale);
    }

    if (placedLetters != null && placedLetters!.isNotEmpty) {
      _drawPlacedLetters(buffer, placedLetters!, map);
    }

    _drawNorthArrow(buffer);
    _drawTitleBlock(buffer);
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  _Bounds _mergedBounds(
    List<({ArrangedScanResult room, List<_PlanSurface> surfaces})> roomPlans,
    List<PlacedLetterPosition>? letters,
  ) {
    final points = <_Point>[];
    for (final entry in roomPlans) {
      final roomCenter = _roomLocalBounds(entry.surfaces).center;
      for (final surface in entry.surfaces) {
        points.addAll(
          surface.corners().map(
            (point) => _arrangedPoint(
              point,
              entry.room.offsetX,
              entry.room.offsetY,
              entry.room.rotation,
              roomCenter,
            ),
          ),
        );
      }
    }

    if (letters != null && letters.isNotEmpty) {
      const letterPadding = 0.65;
      for (final letter in letters) {
        points.addAll([
          _Point(letter.x - letterPadding, letter.y - letterPadding),
          _Point(letter.x + letterPadding, letter.y + letterPadding),
        ]);
      }
    }

    return _Bounds.fromPoints(points);
  }

  void _drawGrid(StringBuffer buffer) {
    for (var x = drawingLeft; x < drawingRight; x += 18) {
      buffer.writeln(
        '<line x1="$x" y1="$drawingTop" x2="$x" y2="$drawingBottom" stroke="#eef0f3" stroke-width="0.3"/>',
      );
    }
    for (var y = drawingTop; y < drawingBottom; y += 18) {
      buffer.writeln(
        '<line x1="$drawingLeft" y1="$y" x2="$drawingRight" y2="$y" stroke="#eef0f3" stroke-width="0.3"/>',
      );
    }
  }

  void _drawSheet(StringBuffer buffer) {
    buffer.writeln(
      '<line x1="$margin" y1="$titleBlockTop" x2="${width - margin}" y2="$titleBlockTop" stroke="#000000" stroke-width="1.3"/>',
    );
  }

  void _drawLogo(StringBuffer buffer) {
    if (_safeImageDataUri(logoImageDataUri) != null) return;
    _drawDefaultLogo(buffer);
  }

  void _drawRoom(
    StringBuffer buffer,
    ArrangedScanResult room,
    List<_PlanSurface> surfaces,
    _Point Function(_Point point) map,
    double scale,
  ) {
    final roomCenter = _roomLocalBounds(surfaces).center;
    final roomBounds = _Bounds.fromPoints(
      surfaces
          .expand((surface) => surface.corners())
          .map(
            (point) => _arrangedPoint(
              point,
              room.offsetX,
              room.offsetY,
              room.rotation,
              roomCenter,
            ),
          ),
    );

    for (final surface in surfaces.where((s) => s.kind == _SurfaceKind.wall)) {
      final (start, end) = surface.endpoints();
      final a = map(
        _arrangedPoint(
          start,
          room.offsetX,
          room.offsetY,
          room.rotation,
          roomCenter,
        ),
      );
      final b = map(
        _arrangedPoint(
          end,
          room.offsetX,
          room.offsetY,
          room.rotation,
          roomCenter,
        ),
      );
      buffer.writeln(
        '<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="#000000" stroke-width="3" stroke-linecap="square"/>',
      );
    }

    var doorIndex = 1;
    var windowIndex = 1;
    var openingIndex = 1;
    for (final surface in surfaces.where((s) => s.kind != _SurfaceKind.wall)) {
      final (start, end) = surface.endpoints();
      final a = map(
        _arrangedPoint(
          start,
          room.offsetX,
          room.offsetY,
          room.rotation,
          roomCenter,
        ),
      );
      final b = map(
        _arrangedPoint(
          end,
          room.offsetX,
          room.offsetY,
          room.rotation,
          roomCenter,
        ),
      );
      if (surface.kind == _SurfaceKind.object) {
        final points = surface
            .corners()
            .map(
              (point) => map(
                _arrangedPoint(
                  point,
                  room.offsetX,
                  room.offsetY,
                  room.rotation,
                  roomCenter,
                ),
              ),
            )
            .toList();
        buffer.writeln(
          '<polygon points="${points.map((p) => '${p.x.toStringAsFixed(2)},${p.y.toStringAsFixed(2)}').join(' ')}" fill="none" stroke="#777777" stroke-width="0.7" stroke-dasharray="4 3"/>',
        );
        final center = map(
          _arrangedPoint(
            _Point(surface.centerX, surface.centerZ),
            room.offsetX,
            room.offsetY,
            room.rotation,
            roomCenter,
          ),
        );
        buffer.writeln(
          '<text x="${center.x}" y="${center.y}" font-family="Helvetica" font-size="8" text-anchor="middle" fill="#555555">${_escape(surface.label)}</text>',
        );
      } else {
        buffer.writeln(
          '<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="#ffffff" stroke-width="7" stroke-linecap="square"/>',
        );
        buffer.writeln(
          '<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="#000000" stroke-width="${surface.kind == _SurfaceKind.opening ? 1.2 : 1.5}" stroke-linecap="square"/>',
        );
        final normal = _normal(surface.angle + room.rotation);
        if (surface.kind == _SurfaceKind.window) {
          buffer.writeln(
            '<line x1="${a.x + normal.x * 3}" y1="${a.y + normal.y * 3}" x2="${b.x + normal.x * 3}" y2="${b.y + normal.y * 3}" stroke="#000000" stroke-width="1.2"/>',
          );
          buffer.writeln(
            '<line x1="${a.x - normal.x * 3}" y1="${a.y - normal.y * 3}" x2="${b.x - normal.x * 3}" y2="${b.y - normal.y * 3}" stroke="#000000" stroke-width="1.2"/>',
          );
          _drawMarkerLabel(
            buffer,
            surface,
            room,
            map,
            'W$windowIndex',
            roomCenter,
          );
          windowIndex++;
        } else if (surface.kind == _SurfaceKind.door) {
          _drawSlidingDoorSymbol(buffer, a, b, normal);
          _drawMarkerLabel(
            buffer,
            surface,
            room,
            map,
            'D$doorIndex',
            roomCenter,
          );
          doorIndex++;
        } else if (surface.kind == _SurfaceKind.opening) {
          buffer.writeln(
            '<line x1="${a.x + normal.x * 7}" y1="${a.y + normal.y * 7}" x2="${a.x - normal.x * 7}" y2="${a.y - normal.y * 7}" stroke="#000000" stroke-width="1"/>',
          );
          buffer.writeln(
            '<line x1="${b.x + normal.x * 7}" y1="${b.y + normal.y * 7}" x2="${b.x - normal.x * 7}" y2="${b.y - normal.y * 7}" stroke="#000000" stroke-width="1"/>',
          );
          _drawMarkerLabel(
            buffer,
            surface,
            room,
            map,
            'O$openingIndex',
            roomCenter,
          );
          openingIndex++;
        }
      }
    }

    _drawSampleLocations(buffer, room, roomBounds, map);
    if (showMeasurements) {
      _drawMeasurements(buffer, room, surfaces, map, roomCenter);
    }

    final center = map(roomBounds.center);
    final area = _areaLabel(room.scan.scanResult, roomBounds);
    buffer.writeln(
      '<rect x="${center.x - 72}" y="${center.y - 24}" width="144" height="42" fill="#ffffff" opacity="0.72"/>',
    );
    buffer.writeln(
      '<text x="${center.x}" y="${center.y - 4}" font-family="Helvetica" font-size="15" font-weight="700" text-anchor="middle" fill="#000000">${_escape(room.scan.name)}</text>',
    );
    if (area != null) {
      buffer.writeln(
        '<text x="${center.x}" y="${center.y + 12}" font-family="Helvetica" font-size="9" text-anchor="middle" fill="#000000">$area</text>',
      );
    }
  }

  void _drawSampleLocations(
    StringBuffer buffer,
    ArrangedScanResult room,
    _Bounds roomBounds,
    _Point Function(_Point point) map,
  ) {
    final locations = room.sampleLocations.isNotEmpty
        ? room.sampleLocations
        : room.scan.sampleLocations;
    if (locations.isEmpty) return;

    final sampleRotation = room.sampleRotationRadians;
    for (final location in locations) {
      final adjusted = location.localX != null && location.localY != null
          ? _Point(location.localX!, location.localY!)
          : _rotatePoint(
              _pointForSampleLocation(location, roomBounds),
              roomBounds.center,
              sampleRotation,
            );
      final point = map(
        _arrangedPoint(
          adjusted,
          room.offsetX,
          room.offsetY,
          room.rotation,
          roomBounds.center,
        ),
      );
      final label = location.label.trim().isNotEmpty
          ? location.label
          : 'Sample';
      final roomCenter = map(roomBounds.center);
      final labelDirection = _labelDirection(point, roomCenter);
      final labelWidth = math
          .min(math.max(label.length * 3.8 + 14, 26), 104)
          .toDouble();
      final labelHeight = 12.0;
      final labelCenter = point + labelDirection * 19;
      final labelX = math.min(
        math.max(labelCenter.x - labelWidth / 2, drawingLeft),
        drawingRight - labelWidth,
      );
      final labelY = math.min(
        math.max(labelCenter.y - labelHeight / 2, drawingTop),
        drawingBottom - labelHeight,
      );
      // Connector line between sample marker and label
      final labelTarget = _Point(labelCenter.x, labelCenter.y);

      buffer.writeln(
        '<line '
        'x1="${point.x}" '
        'y1="${point.y}" '
        'x2="${labelTarget.x}" '
        'y2="${labelTarget.y}" '
        'stroke="#2563eb" '
        'stroke-width="0.8"/>',
      );
      buffer.writeln(
        '<circle '
        'cx="${point.x}" '
        'cy="${point.y}" '
        'r="4.8" '
        'fill="#2563eb" '
        'stroke="#ffffff" '
        'stroke-width="1.5"/>',
      );

      // White center
      buffer.writeln(
        '<circle '
        'cx="${point.x}" '
        'cy="${point.y}" '
        'r="1.8" '
        'fill="#ffffff"/>',
      );

      // Sample label with blue outline
      buffer.writeln(
        '<rect '
        'x="$labelX" '
        'y="$labelY" '
        'width="$labelWidth" '
        'height="$labelHeight" '
        'rx="3" '
        'fill="#ffffff" '
        'opacity="0.96" '
        'stroke="#2563eb" '
        'stroke-width="0.6"/>',
      );

      // Sample number / label
      buffer.writeln(
        '<text '
        'x="${labelX + labelWidth / 2}" '
        'y="${labelY + 8.5}" '
        'font-family="Helvetica" '
        'font-size="6.2" '
        'font-weight="700" '
        'text-anchor="middle" '
        'fill="#111827">'
        '${_escape(label)}'
        '</text>',
      );
    }
  }

  _Point _labelDirection(_Point point, _Point center) {
    final delta = point - center;
    if (delta.length < 0.001) return const _Point(0, -1);
    return delta * (1 / delta.length);
  }

  _Point _pointForSampleLocation(
    RoomSampleLocation location,
    _Bounds roomBounds,
  ) {
    return _Point(
      roomBounds.minX +
          location.x.clamp(0.0, 1.0) * (roomBounds.maxX - roomBounds.minX),
      roomBounds.minY +
          location.y.clamp(0.0, 1.0) * (roomBounds.maxY - roomBounds.minY),
    );
  }

  _Point _rotatePoint(_Point point, _Point center, double radians) {
    final dx = point.x - center.x;
    final dy = point.y - center.y;
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    return _Point(
      center.x + dx * cosA - dy * sinA,
      center.y + dx * sinA + dy * cosA,
    );
  }

  void _drawMarkerLabel(
    StringBuffer buffer,
    _PlanSurface surface,
    ArrangedScanResult room,
    _Point Function(_Point point) map,
    String label,
    _Point roomCenter,
  ) {
    final center = map(
      _arrangedPoint(
        _Point(surface.centerX, surface.centerZ),
        room.offsetX,
        room.offsetY,
        room.rotation,
        roomCenter,
      ),
    );
    final normal = _normal(surface.angle + room.rotation);
    final labelPoint = center + normal * 15;
    buffer.writeln(
      '<rect x="${labelPoint.x - 8}" y="${labelPoint.y - 8}" width="16" height="11" fill="#ffffff" opacity="0.9"/>',
    );
    buffer.writeln(
      '<text x="${labelPoint.x}" y="${labelPoint.y}" font-family="Helvetica" font-size="7" font-weight="700" text-anchor="middle" fill="#000000">${_escape(label)}</text>',
    );
  }

  void _drawMeasurements(
    StringBuffer buffer,
    ArrangedScanResult room,
    List<_PlanSurface> surfaces,
    _Point Function(_Point point) map,
    _Point roomCenter,
  ) {
    for (final surface in surfaces.where(
      (surface) => surface.kind == _SurfaceKind.wall,
    )) {
      final (start, end) = surface.endpoints();
      final a = map(
        _arrangedPoint(
          start,
          room.offsetX,
          room.offsetY,
          room.rotation,
          roomCenter,
        ),
      );
      final b = map(
        _arrangedPoint(
          end,
          room.offsetX,
          room.offsetY,
          room.rotation,
          roomCenter,
        ),
      );
      final normal = _normal(surface.angle + room.rotation);
      final da = a + normal * 20;
      final db = b + normal * 20;
      final mid = _Point((da.x + db.x) / 2, (da.y + db.y) / 2);
      buffer.writeln(
        '<line x1="${da.x}" y1="${da.y}" x2="${db.x}" y2="${db.y}" stroke="#d45b2a" stroke-width="0.75"/>',
      );
      buffer.writeln(
        '<line x1="${da.x}" y1="${da.y}" x2="${a.x}" y2="${a.y}" stroke="#d45b2a" stroke-width="0.45"/>',
      );
      buffer.writeln(
        '<line x1="${db.x}" y1="${db.y}" x2="${b.x}" y2="${b.y}" stroke="#d45b2a" stroke-width="0.45"/>',
      );
      buffer.writeln(
        '<rect x="${mid.x - 20}" y="${mid.y - 10}" width="40" height="14" fill="#ffffff" opacity="0.94"/>',
      );
      buffer.writeln(
        '<text x="${mid.x}" y="${mid.y}" font-family="Helvetica" font-size="9" font-weight="700" text-anchor="middle" fill="#d45b2a">${_formatFeetInches(surface.length)}</text>',
      );
    }
  }

  String? _areaLabel(ScanResult scanResult, _Bounds bounds) {
    final dimensions = scanResult.room.dimensions;
    final squareFeet = dimensions != null && dimensions.floorAreaInSqFeet > 0
        ? dimensions.floorAreaInSqFeet
        : (bounds.maxX - bounds.minX) * (bounds.maxY - bounds.minY) * 10.7639;
    if (squareFeet <= 0) return null;
    return '${squareFeet.toStringAsFixed(2)} sq ft';
  }

  void _drawTitleBlock(StringBuffer buffer) {
    final counts = _mergedCounts();
    final summary = _mergedSummary();
    const centerX = width / 2;
    const blockHeight = titleBlockBottom - titleBlockTop;
    const col1Right = 250.0;
    const col3Left = 600.0;

    // Outer frame
    buffer.writeln(
      '<line x1="$margin" y1="$titleBlockTop" x2="${width - margin}" y2="$titleBlockTop" stroke="#000000" stroke-width="1.3"/>',
    );
    buffer.writeln(
      '<rect x="$margin" y="$titleBlockTop" width="${width - margin * 2}" height="$blockHeight" fill="#fafafa" stroke="#d1d5db" stroke-width="0.8"/>',
    );
    buffer.writeln(
      '<line x1="$col1Right" y1="$titleBlockTop" x2="$col1Right" y2="$titleBlockBottom" stroke="#d1d5db" stroke-width="0.8"/>',
    );
    buffer.writeln(
      '<line x1="$col3Left" y1="$titleBlockTop" x2="$col3Left" y2="$titleBlockBottom" stroke="#d1d5db" stroke-width="0.8"/>',
    );

    // Left column: SCAN SUMMARY
    buffer.writeln(
      '<text x="28" y="${titleBlockTop + 15}" font-family="Helvetica" font-size="9" font-weight="700" fill="#6b7280">SCAN SUMMARY</text>',
    );
    buffer.writeln(
      '<text x="28" y="${titleBlockTop + 32}" font-family="Helvetica" font-size="10" font-weight="700" fill="#111827">Rooms: ${rooms.length}   Walls: ${counts.walls}   Doors: ${counts.doors}</text>',
    );
    buffer.writeln(
      '<text x="28" y="${titleBlockTop + 46}" font-family="Helvetica" font-size="10" font-weight="700" fill="#111827">Windows: ${counts.windows}   Openings: ${counts.openings}</text>',
    );
    buffer.writeln(
      '<text x="28" y="${titleBlockTop + 60}" font-family="Helvetica" font-size="9" font-weight="700" fill="#111827">Sq Ft: ${summary.totalSqFt.toStringAsFixed(0)}   Ext Walls: ${summary.totalExteriorLf.toStringAsFixed(0)} ft</text>',
    );
    var roomY = titleBlockTop + 74;
    for (var i = 0; i < rooms.length && i < 3; i++) {
      final room = rooms[i];
      final roomSqFt = _roomSqFt(room);
      buffer.writeln(
        '<text x="28" y="$roomY" font-family="Helvetica" font-size="8" fill="#374151">${_escape(room.scan.name)}: ${roomSqFt.toStringAsFixed(0)} sq ft</text>',
      );
      roomY += 11;
    }

    // Center column: 2D FLOOR PLAN
    buffer.writeln(
      '<text x="$centerX" y="${titleBlockTop + 18}" font-family="Helvetica" font-size="12" font-weight="700" text-anchor="middle" fill="#111827">2D FLOOR PLAN</text>',
    );
    buffer.writeln(
      '<text x="$centerX" y="${titleBlockTop + 44}" font-family="Helvetica" font-size="20" font-weight="700" text-anchor="middle" fill="#000000">${_escape(title?.trim().isNotEmpty == true ? title!.trim() : 'Merged Floor Plan')}</text>',
    );
    buffer.writeln(
      '<text x="$centerX" y="${titleBlockTop + 62}" font-family="Helvetica" font-size="9" text-anchor="middle" fill="#4b5563">Generated from RoomPlan room scans</text>',
    );
    buffer.writeln(
      '<text x="$centerX" y="${titleBlockTop + 76}" font-family="Helvetica" font-size="8" text-anchor="middle" fill="#9ca3af">Verify critical dimensions on site</text>',
    );

    // Right column: LEGEND + EXHIBIT
    buffer.writeln(
      '<text x="${col3Left + 16}" y="${titleBlockTop + 15}" font-family="Helvetica" font-size="9" font-weight="700" text-anchor="start" fill="#6b7280">LEGEND</text>',
    );
    buffer.writeln(
      '<line x1="${col3Left + 16}" y1="${titleBlockTop + 30}" x2="${col3Left + 56}" y2="${titleBlockTop + 30}" stroke="#000000" stroke-width="3"/>',
    );
    buffer.writeln(
      '<text x="${col3Left + 64}" y="${titleBlockTop + 34}" font-family="Helvetica" font-size="9" fill="#111827">Wall</text>',
    );
    buffer.writeln(
      '<line x1="${col3Left + 16}" y1="${titleBlockTop + 48}" x2="${col3Left + 56}" y2="${titleBlockTop + 48}" stroke="#d45b2a" stroke-width="0.8"/>',
    );
    buffer.writeln(
      '<text x="${col3Left + 64}" y="${titleBlockTop + 52}" font-family="Helvetica" font-size="9" fill="#111827">Measurement</text>',
    );
    buffer.writeln(
      '<circle cx="${col3Left + 24}" cy="${titleBlockTop + 66}" r="4" fill="#2563eb" stroke="#ffffff" stroke-width="1"/>',
    );
    buffer.writeln(
      '<text x="${col3Left + 34}" y="${titleBlockTop + 70}" font-family="Helvetica" font-size="9" fill="#111827">Sample</text>',
    );
    buffer.writeln(
      '<text x="${width - margin - 28}" y="${titleBlockTop + 35}" font-family="Helvetica" font-size="10" font-weight="700" text-anchor="middle" fill="#111827">EXHIBIT</text>',
    );
    buffer.writeln(
      '<text x="${width - margin - 28}" y="${titleBlockTop + 58}" font-family="Helvetica" font-size="18" font-weight="700" text-anchor="middle" fill="#111827">1</text>',
    );
  }

  ({int walls, int doors, int windows, int openings}) _mergedCounts() {
    var walls = 0;
    var doors = 0;
    var windows = 0;
    var openings = 0;
    for (final room in rooms) {
      final scanRoom = room.scan.scanResult.room;
      walls += scanRoom.walls.length;
      doors += scanRoom.doors.length;
      windows += scanRoom.windows.length;
      openings += scanRoom.openings.length;
    }
    return (walls: walls, doors: doors, windows: windows, openings: openings);
  }

  double _roomSqFt(ArrangedScanResult room) {
    final dims = room.scan.scanResult.room.dimensions;
    if (dims != null && dims.floorAreaInSqFeet > 0) {
      return dims.floorAreaInSqFeet;
    }
    // Fallback: compute from bounding box of surfaces
    final surfaces =
        room.surfaces?.map((s) => s._toPlanSurface()).toList() ??
        FloorPlanPdfService._buildSurfaces(room.scan.scanResult);
    if (surfaces.isEmpty) return 0;
    final minX = surfaces.map((s) => s.centerX - s.length / 2).reduce(math.min);
    final maxX = surfaces.map((s) => s.centerX + s.length / 2).reduce(math.max);
    final minZ = surfaces.map((s) => s.centerZ - s.depth / 2).reduce(math.min);
    final maxZ = surfaces.map((s) => s.centerZ + s.depth / 2).reduce(math.max);
    return (maxX - minX) * (maxZ - minZ) * 10.7639;
  }

  ({double totalSqFt, double totalExteriorLf}) _mergedSummary() {
    var totalSqFt = 0.0;
    var totalExteriorLf = 0.0;
    for (final room in rooms) {
      totalSqFt += _roomSqFt(room);
      // Sum all wall lengths as exterior wall linear feet
      final scanRoom = room.scan.scanResult.room;
      for (final wall in scanRoom.walls) {
        totalExteriorLf += wall.width * 3.28084; // meters to feet
      }
    }
    return (totalSqFt: totalSqFt, totalExteriorLf: totalExteriorLf);
  }

  void _drawPlacedLetters(
    StringBuffer buffer,
    List<PlacedLetterPosition> letters,
    _Point Function(_Point point) map,
  ) {
    for (final letter in letters) {
      final mapped = map(_Point(letter.x, letter.y));
      final x = mapped.x;
      final y = mapped.y;
      // Blue circle background
      buffer.writeln(
        '<circle cx="$x" cy="$y" r="16" fill="#ffffff" stroke="#1a73e8" stroke-width="2.5"/>',
      );
      // Blue letter
      buffer.writeln(
        '<text x="$x" y="${y + 6}" font-family="Helvetica" font-size="20" font-weight="900" text-anchor="middle" fill="#1a73e8">${_escape(letter.letter)}</text>',
      );
    }
  }

  void _drawNorthArrow(StringBuffer buffer) {
    // Compass at bottom-left of drawing area, matching reference layout
    final cx = drawingLeft + 22.0;
    final cy = drawingBottom - 42.0;
    final degrees = northRotationRadians * 180 / math.pi;
    final rotated = degrees != 0
        ? ' transform="rotate(${degrees.toStringAsFixed(2)} $cx $cy)"'
        : '';
    buffer.writeln('<g$rotated>');
    buffer.writeln(
      '<path d="M ${cx - 6} ${cy + 3} L $cx ${cy - 20} L ${cx + 6} ${cy + 3} L $cx ${cy - 5} Z" fill="#000000"/>',
    );
    buffer.writeln(
      '<path d="M ${cx - 6} ${cy + 22} L $cx ${cy + 45} L ${cx + 6} ${cy + 22} L $cx ${cy + 30} Z" fill="#000000" opacity="0.3"/>',
    );
    buffer.writeln(
      '<line x1="$cx" y1="${cy - 23}" x2="$cx" y2="${cy + 42}" stroke="#000000" stroke-width="1"/>',
    );
    buffer.writeln(
      '<text x="$cx" y="${cy + 56}" font-family="Helvetica" font-size="10" font-weight="700" text-anchor="middle" fill="#000000">N</text>',
    );
    buffer.writeln('</g>');
  }

  _Bounds _roomLocalBounds(List<_PlanSurface> surfaces) {
    return _Bounds.fromPoints(surfaces.expand((surface) => surface.corners()));
  }

  _Point _arrangedPoint(
    _Point point,
    double offsetX,
    double offsetY,
    double rotation,
    _Point center,
  ) {
    final delta = point - center;
    final cosA = math.cos(rotation);
    final sinA = math.sin(rotation);
    return center +
        _Point(
          delta.x * cosA - delta.y * sinA,
          delta.x * sinA + delta.y * cosA,
        ) +
        _Point(offsetX, offsetY);
  }

  String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  _Point _normal(double angle) {
    return _Point(-math.sin(angle), math.cos(angle));
  }

  String _formatFeetInches(double meters) {
    final totalInches = (meters * 39.3701).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return '$feet\'$inches"';
  }
}

class _Bounds {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const _Bounds({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  factory _Bounds.fromPoints(Iterable<_Point> points) {
    final list = points.toList();
    if (list.isEmpty) {
      return const _Bounds(minX: 0, minY: 0, maxX: 1, maxY: 1);
    }
    return _Bounds(
      minX: list.map((point) => point.x).reduce(math.min),
      minY: list.map((point) => point.y).reduce(math.min),
      maxX: list.map((point) => point.x).reduce(math.max),
      maxY: list.map((point) => point.y).reduce(math.max),
    );
  }

  _Point get center => _Point((minX + maxX) / 2, (minY + maxY) / 2);
}

enum _SurfaceKind { wall, door, window, opening, object }

class _PlanSurface {
  final _SurfaceKind kind;
  final String label;
  final double centerX;
  final double centerZ;
  final double angle;
  final double length;
  final double depth;

  const _PlanSurface({
    required this.kind,
    required this.label,
    required this.centerX,
    required this.centerZ,
    required this.angle,
    required this.length,
    required this.depth,
  });

  factory _PlanSurface.fromTransform({
    required _SurfaceKind kind,
    required String label,
    required Position position,
    required Matrix4? transform,
    required double length,
    required double depth,
  }) {
    final storage = transform?.storage;
    final angle = storage == null ? 0.0 : math.atan2(storage[2], storage[0]);
    return _PlanSurface(
      kind: kind,
      label: label,
      centerX: storage == null ? position.x : storage[12],
      centerZ: storage == null ? position.z : storage[14],
      angle: angle,
      length: math.max(length, 0.05),
      depth: math.max(depth, 0.05),
    );
  }

  List<_Point> corners() {
    final direction = _Point(math.cos(angle), math.sin(angle));
    final normal = _Point(-math.sin(angle), math.cos(angle));
    final halfLength = length / 2;
    final halfDepth = depth / 2;
    final center = _Point(centerX, centerZ);
    return [
      center - direction * halfLength - normal * halfDepth,
      center + direction * halfLength - normal * halfDepth,
      center + direction * halfLength + normal * halfDepth,
      center - direction * halfLength + normal * halfDepth,
    ];
  }

  (_Point, _Point) endpoints() {
    final direction = _Point(math.cos(angle), math.sin(angle));
    final center = _Point(centerX, centerZ);
    return (
      center - direction * (length / 2),
      center + direction * (length / 2),
    );
  }
}

class _FloorPlanSvg {
  // Full-page portrait layout for iPad display
  static const double width = 842;
  static const double height =
      1122; // Letter portrait - fits iPad without scroll
  static const double margin = 16;
  static const double titleBlockTop = 960;
  static const double titleBlockBottom = height - margin;
  static const double drawingTop = 100;
  static const double drawingLeft = 58;
  static const double drawingRight = 784;
  static const double drawingBottom = 940;

  final ScanResult scanResult;
  final List<_PlanSurface> surfaces;
  final String? title;
  final List<RoomSampleLocation> sampleLocations;
  final double rotationRadians;
  final String? logoImageDataUri;
  final bool previewOnly;

  _FloorPlanSvg(
    this.scanResult,
    this.surfaces, {
    this.title,
    this.sampleLocations = const [],
    this.rotationRadians = 0,
    this.logoImageDataUri,
    this.previewOnly = false,
  });

  String build() {
    final transform = _SvgTransform(
      surfaces,
      rotationRadians: rotationRadians,
      autoAlign: !previewOnly,
    );
    final buffer = StringBuffer();
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">',
    );
    buffer.writeln('<rect width="100%" height="100%" fill="#ffffff"/>');
    if (!previewOnly) {
      _drawSheet(buffer);
      _drawLogo(buffer);
    }
    _drawSurfaces(buffer, transform, _SurfaceKind.wall);
    _drawSurfaces(buffer, transform, _SurfaceKind.opening);
    _drawSurfaces(buffer, transform, _SurfaceKind.window);
    _drawSurfaces(buffer, transform, _SurfaceKind.door);
    _drawSurfaces(buffer, transform, _SurfaceKind.object);
    _drawRoomLabel(buffer, transform);
    _drawSampleLocations(buffer);
    _drawMeasurements(buffer, transform);
    if (!previewOnly) {
      _drawNorthArrow(buffer);
      _drawTitleBlock(buffer);
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  void _drawSampleLocations(StringBuffer buffer) {
    if (sampleLocations.isEmpty) return;

    final drawingWidth = drawingRight - drawingLeft;
    final drawingHeight = drawingBottom - drawingTop;
    for (final location in sampleLocations) {
      final point = _rotateNormalizedPoint(
        location.x.clamp(0.0, 1.0),
        location.y.clamp(0.0, 1.0),
        rotationRadians,
      );
      final x = drawingLeft + point.dx * drawingWidth;
      final y = drawingTop + point.dy * drawingHeight;
      final label = location.label.trim().isNotEmpty
          ? location.label
          : 'Sample';
      final labelWidth = math
          .min(math.max(label.length * 4.6 + 18, 30), 140)
          .toDouble();
      final labelX = math.min(
        math.max(x - labelWidth / 2, drawingLeft),
        drawingRight - labelWidth,
      );
      final labelY = math.min(math.max(y + 10, drawingTop), drawingBottom - 16);

      buffer.writeln(
        '<circle cx="$x" cy="$y" r="7" fill="#2563eb" stroke="#ffffff" stroke-width="2"/>',
      );
      buffer.writeln(
        '<path d="M $x ${y + 7} L ${x - 4} ${y + 15} L ${x + 4} ${y + 15} Z" fill="#2563eb"/>',
      );
      buffer.writeln(
        '<rect x="$labelX" y="$labelY" width="$labelWidth" height="14" rx="3" fill="#ffffff" opacity="0.94" stroke="#2563eb" stroke-width="0.7"/>',
      );
      buffer.writeln(
        '<text x="${labelX + labelWidth / 2}" y="${labelY + 10}" font-family="Helvetica" font-size="7" font-weight="700" text-anchor="middle" fill="#111827">${_escape(label)}</text>',
      );
    }
  }

  Offset _rotateNormalizedPoint(double x, double y, double radians) {
    final delta = Offset(x - 0.5, y - 0.5);
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    return Offset(
      0.5 + delta.dx * cosA - delta.dy * sinA,
      0.5 + delta.dx * sinA + delta.dy * cosA,
    );
  }

  void _drawSheet(StringBuffer buffer) {
    buffer.writeln(
      '<line x1="$margin" y1="$titleBlockTop" x2="${width - margin}" y2="$titleBlockTop" stroke="#000000" stroke-width="1.3"/>',
    );
  }

  void _drawLogo(StringBuffer buffer) {
    if (_safeImageDataUri(logoImageDataUri) != null) return;
    _drawDefaultLogo(buffer);
  }

  void _drawSurfaces(
    StringBuffer buffer,
    _SvgTransform transform,
    _SurfaceKind kind,
  ) {
    var markerIndex = 1;
    for (final surface in surfaces.where((surface) => surface.kind == kind)) {
      final points = surface.corners().map(transform.point).toList();
      final style = _styleFor(surface.kind);
      final (start, end) = surface.endpoints();
      final a = transform.point(start);
      final b = transform.point(end);

      if (surface.kind == _SurfaceKind.wall) {
        buffer.writeln(
          '<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="#000000" stroke-width="3" stroke-linecap="square"/>',
        );
        continue;
      }

      if (surface.kind == _SurfaceKind.object) {
        buffer.writeln(
          '<polygon points="${points.map((point) => '${point.x.toStringAsFixed(2)},${point.y.toStringAsFixed(2)}').join(' ')}" fill="none" stroke="#777777" stroke-width="0.7" stroke-dasharray="4 3"/>',
        );
        final center = transform.point(
          _Point(surface.centerX, surface.centerZ),
        );
        buffer.writeln(
          '<text x="${center.x}" y="${center.y}" font-family="Helvetica" font-size="8" text-anchor="middle" fill="#555555">${_escape(surface.label)}</text>',
        );
        continue;
      }

      buffer.writeln(
        '<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="#ffffff" stroke-width="7" stroke-linecap="square"/>',
      );
      buffer.writeln(
        '<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="${style.stroke}" stroke-width="${style.width}" stroke-linecap="square"/>',
      );

      if (surface.kind == _SurfaceKind.window) {
        final normal = transform.normal(surface.angle);
        buffer.writeln(
          '<line x1="${a.x + normal.x * 3}" y1="${a.y + normal.y * 3}" x2="${b.x + normal.x * 3}" y2="${b.y + normal.y * 3}" stroke="#000000" stroke-width="1.2"/>',
        );
        buffer.writeln(
          '<line x1="${a.x - normal.x * 3}" y1="${a.y - normal.y * 3}" x2="${b.x - normal.x * 3}" y2="${b.y - normal.y * 3}" stroke="#000000" stroke-width="1.2"/>',
        );
        _drawMarkerLabel(buffer, transform, surface, 'W$markerIndex');
      }

      if (surface.kind == _SurfaceKind.door) {
        final normal = transform.normal(surface.angle);
        _drawSlidingDoorSymbol(buffer, a, b, normal);
        _drawMarkerLabel(buffer, transform, surface, 'D$markerIndex');
      }

      if (surface.kind == _SurfaceKind.opening) {
        final normal = transform.normal(surface.angle);
        buffer.writeln(
          '<line x1="${a.x + normal.x * 7}" y1="${a.y + normal.y * 7}" x2="${a.x - normal.x * 7}" y2="${a.y - normal.y * 7}" stroke="#000000" stroke-width="1"/>',
        );
        buffer.writeln(
          '<line x1="${b.x + normal.x * 7}" y1="${b.y + normal.y * 7}" x2="${b.x - normal.x * 7}" y2="${b.y - normal.y * 7}" stroke="#000000" stroke-width="1"/>',
        );
        _drawMarkerLabel(buffer, transform, surface, 'O$markerIndex');
      }

      markerIndex++;
    }
  }

  void _drawMarkerLabel(
    StringBuffer buffer,
    _SvgTransform transform,
    _PlanSurface surface,
    String label,
  ) {
    final center = transform.point(_Point(surface.centerX, surface.centerZ));
    final normal = transform.normal(surface.angle);
    final labelPoint = center + normal * 15;
    buffer.writeln(
      '<rect x="${labelPoint.x - 8}" y="${labelPoint.y - 8}" width="16" height="11" fill="#ffffff" opacity="0.9"/>',
    );
    buffer.writeln(
      '<text x="${labelPoint.x}" y="${labelPoint.y}" font-family="Helvetica" font-size="7" font-weight="700" text-anchor="middle" fill="#000000">${_escape(label)}</text>',
    );
  }

  void _drawMeasurements(StringBuffer buffer, _SvgTransform transform) {
    for (final surface in surfaces.where(
      (surface) => surface.kind == _SurfaceKind.wall,
    )) {
      final (start, end) = surface.endpoints();
      final a = transform.point(start);
      final b = transform.point(end);
      final normal = transform.normal(surface.angle);
      final offset = 20.0;
      final da = a + normal * offset;
      final db = b + normal * offset;
      final mid = _Point((da.x + db.x) / 2, (da.y + db.y) / 2);
      buffer.writeln(
        '<line x1="${da.x}" y1="${da.y}" x2="${db.x}" y2="${db.y}" stroke="#ff0000" stroke-width="0.8"/>',
      );
      buffer.writeln(
        '<line x1="${da.x}" y1="${da.y}" x2="${a.x}" y2="${a.y}" stroke="#ff0000" stroke-width="0.5"/>',
      );
      buffer.writeln(
        '<line x1="${db.x}" y1="${db.y}" x2="${b.x}" y2="${b.y}" stroke="#ff0000" stroke-width="0.5"/>',
      );
      buffer.writeln(
        '<rect x="${mid.x - 20}" y="${mid.y - 10}" width="40" height="14" fill="#ffffff" opacity="0.94"/>',
      );
      buffer.writeln(
        '<text x="${mid.x}" y="${mid.y}" font-family="Helvetica" font-size="9" font-weight="700" text-anchor="middle" fill="#ff0000">${_formatFeetInches(surface.length)}</text>',
      );
    }
  }

  void _drawRoomLabel(StringBuffer buffer, _SvgTransform transform) {
    final roomName = title?.trim();
    if (roomName == null || roomName.isEmpty) return;

    final walls = surfaces.where(
      (surface) => surface.kind == _SurfaceKind.wall,
    );
    if (walls.isEmpty) return;

    final wallPoints = walls.expand((surface) => surface.corners()).toList();
    final minX = wallPoints.map((point) => point.x).reduce(math.min);
    final maxX = wallPoints.map((point) => point.x).reduce(math.max);
    final minY = wallPoints.map((point) => point.y).reduce(math.min);
    final maxY = wallPoints.map((point) => point.y).reduce(math.max);
    final center = transform.point(
      _Point((minX + maxX) / 2, (minY + maxY) / 2),
    );
    final area = _roomAreaLabel(maxX - minX, maxY - minY);

    buffer.writeln(
      '<rect x="${center.x - 72}" y="${center.y - 24}" width="144" height="42" fill="#ffffff" opacity="0.72"/>',
    );
    buffer.writeln(
      '<text x="${center.x}" y="${center.y - 4}" font-family="Helvetica" font-size="15" font-weight="700" text-anchor="middle" fill="#000000">${_escape(roomName)}</text>',
    );
    if (area != null) {
      buffer.writeln(
        '<text x="${center.x}" y="${center.y + 13}" font-family="Helvetica" font-size="9" text-anchor="middle" fill="#000000">$area</text>',
      );
    }
  }

  String? _roomAreaLabel(
    double fallbackWidthMeters,
    double fallbackDepthMeters,
  ) {
    final dimensions = scanResult.room.dimensions;
    final squareFeet = dimensions != null && dimensions.floorAreaInSqFeet > 0
        ? dimensions.floorAreaInSqFeet
        : fallbackWidthMeters * fallbackDepthMeters * 10.7639;
    if (squareFeet <= 0) return null;
    return '${squareFeet.toStringAsFixed(2)} sq ft';
  }

  void _drawNorthArrow(StringBuffer buffer) {
    // Compass at bottom-left of drawing area
    final cx = drawingLeft + 22.0;
    final cy = drawingBottom - 42.0;
    buffer.writeln(
      '<path d="M ${cx - 6} ${cy + 3} L $cx ${cy - 20} L ${cx + 6} ${cy + 3} L $cx ${cy - 5} Z" fill="#000000"/>',
    );
    buffer.writeln(
      '<path d="M ${cx - 6} ${cy + 22} L $cx ${cy + 45} L ${cx + 6} ${cy + 22} L $cx ${cy + 30} Z" fill="#000000" opacity="0.3"/>',
    );
    buffer.writeln(
      '<line x1="$cx" y1="${cy - 23}" x2="$cx" y2="${cy + 42}" stroke="#000000" stroke-width="1"/>',
    );
    buffer.writeln(
      '<text x="$cx" y="${cy + 56}" font-family="Helvetica" font-size="10" font-weight="700" text-anchor="middle" fill="#000000">N</text>',
    );
  }

  void _drawTitleBlock(StringBuffer buffer) {
    final dims = scanResult.room.dimensions;
    final sqFt = dims != null && dims.floorAreaInSqFeet > 0
        ? dims.floorAreaInSqFeet
        : 0.0;
    var extWallLf = 0.0;
    for (final wall in scanResult.room.walls) {
      extWallLf += wall.width * 3.28084; // meters to feet
    }

    const left = margin;
    const right = width - margin;
    const top = titleBlockTop;
    const bottom = titleBlockBottom;
    const blockHeight = bottom - top;
    const centerX = width / 2;
    const firstDivider = 280.0;
    const secondDivider = 598.0;

    buffer.writeln(
      '<line x1="$left" y1="$top" x2="$right" y2="$top" stroke="#000000" stroke-width="1.3"/>',
    );
    buffer.writeln(
      '<rect x="$left" y="$top" width="${right - left}" height="$blockHeight" fill="#fafafa" stroke="#d1d5db" stroke-width="0.8"/>',
    );
    buffer.writeln(
      '<line x1="$firstDivider" y1="$top" x2="$firstDivider" y2="$bottom" stroke="#d1d5db" stroke-width="0.8"/>',
    );
    buffer.writeln(
      '<line x1="$secondDivider" y1="$top" x2="$secondDivider" y2="$bottom" stroke="#d1d5db" stroke-width="0.8"/>',
    );

    buffer.writeln(
      '<text x="$centerX" y="${top + 17}" font-family="Helvetica" font-size="12" font-weight="700" text-anchor="middle" fill="#111827">2D FLOOR PLAN</text>',
    );
    buffer.writeln(
      '<text x="$centerX" y="${top + 40}" font-family="Helvetica" font-size="20" font-weight="700" text-anchor="middle" fill="#000000">${_escape(title?.trim().isNotEmpty == true ? title!.trim() : 'Floor Plan')}</text>',
    );
    buffer.writeln(
      '<text x="$centerX" y="${top + 57}" font-family="Helvetica" font-size="9" text-anchor="middle" fill="#4b5563">Generated from RoomPlan scan - verify critical dimensions on site</text>',
    );

    // Scan summary
    buffer.writeln(
      '<text x="28" y="${top + 14}" font-family="Helvetica" font-size="9" font-weight="700" fill="#6b7280">SCAN SUMMARY</text>',
    );
    buffer.writeln(
      '<text x="28" y="${top + 30}" font-family="Helvetica" font-size="10" font-weight="700" fill="#111827">Sq Ft: ${sqFt.toStringAsFixed(0)}</text>',
    );
    buffer.writeln(
      '<text x="120" y="${top + 30}" font-family="Helvetica" font-size="10" font-weight="700" fill="#111827">Ext. Walls: ${extWallLf.toStringAsFixed(1)}\'</text>',
    );
    buffer.writeln(
      '<text x="28" y="${top + 46}" font-family="Helvetica" font-size="10" font-weight="700" fill="#111827">Walls: ${scanResult.room.walls.length}</text>',
    );
    buffer.writeln(
      '<text x="120" y="${top + 46}" font-family="Helvetica" font-size="10" font-weight="700" fill="#111827">Doors: ${scanResult.room.doors.length}</text>',
    );
    buffer.writeln(
      '<text x="200" y="${top + 46}" font-family="Helvetica" font-size="10" font-weight="700" fill="#111827">Windows: ${scanResult.room.windows.length}</text>',
    );
    buffer.writeln(
      '<text x="310" y="${top + 46}" font-family="Helvetica" font-size="10" font-weight="700" fill="#111827">Openings: ${scanResult.room.openings.length}</text>',
    );

    // Exhibit
    buffer.writeln(
      '<text x="${secondDivider + (width - secondDivider) / 2}" y="${top + 33}" font-family="Helvetica" font-size="10" font-weight="700" text-anchor="middle" fill="#111827">EXHIBIT</text>',
    );
    buffer.writeln(
      '<text x="${secondDivider + (width - secondDivider) / 2}" y="${top + 56}" font-family="Helvetica" font-size="18" font-weight="700" text-anchor="middle" fill="#111827">1</text>',
    );
  }

  _SurfaceStyle _styleFor(_SurfaceKind kind) {
    switch (kind) {
      case _SurfaceKind.wall:
        return const _SurfaceStyle('#000000', '#000000', 1);
      case _SurfaceKind.door:
        return const _SurfaceStyle('#ffffff', '#000000', 1.5);
      case _SurfaceKind.window:
        return const _SurfaceStyle('#ffffff', '#000000', 1.5);
      case _SurfaceKind.opening:
        return const _SurfaceStyle('#ffffff', '#000000', 1.2);
      case _SurfaceKind.object:
        return const _SurfaceStyle('#ffffff', '#6b7280', 0.7);
    }
  }

  String _formatFeetInches(double meters) {
    final totalInches = (meters * 39.3701).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return '$feet\'$inches"';
  }

  String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

pw.Widget _buildPdfPageContent(String svg, String? logoImageDataUri) {
  final logoBytes = _imageBytesFromDataUri(logoImageDataUri);
  final svgImage = pw.SvgImage(svg: svg);
  if (logoBytes == null) return svgImage;

  return pw.Stack(
    children: [
      svgImage,
      pw.Positioned(
        left: 28,
        top: 22,
        child: pw.Container(
          width: 104,
          height: 42,
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
        ),
      ),
    ],
  );
}

Uint8List? _imageBytesFromDataUri(String? logoImageDataUri) {
  final value = _safeImageDataUri(logoImageDataUri);
  if (value == null) return null;
  final commaIndex = value.indexOf(',');
  if (commaIndex < 0 || commaIndex == value.length - 1) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

Future<String?> floorPlanLogoDataUriForPath(
  String? imagePath, {
  bool enabled = true,
}) async {
  if (!enabled) return null;

  try {
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) return null;

    final file = File(path);
    if (!file.existsSync()) return null;

    final length = await file.length();
    if (length <= 0 || length > 750 * 1024) return null;

    final bytes = await file.readAsBytes().timeout(const Duration(seconds: 2));
    if (bytes.length < 4) return null;
    final hasPngSignature =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
    final hasJpegSignature = bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (!hasPngSignature && !hasJpegSignature) return null;

    final mimeType = hasJpegSignature ? 'image/jpeg' : 'image/png';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}

String? _safeImageDataUri(String? logoImageDataUri) {
  final value = logoImageDataUri?.trim();
  if (value == null || value.isEmpty) return null;
  return value.startsWith('data:image/') ? value : null;
}

void _drawDefaultLogo(StringBuffer buffer) {
  buffer.writeln('<g transform="translate(28 24)">');
  buffer.writeln(
    '<text x="0" y="20" font-family="Helvetica" font-size="24" font-weight="700" fill="#111827">iSpec</text>',
  );
  buffer.writeln(
    '<text x="65" y="20" font-family="Helvetica" font-size="24" font-weight="700" fill="#f97316">X</text>',
  );
  buffer.writeln(
    '<text x="1" y="34" font-family="Helvetica" font-size="7.5" font-weight="700" fill="#6b7280">ROOMPLAN EXHIBIT</text>',
  );
  buffer.writeln('</g>');
}

class _SvgTransform {
  final double minX;
  final double minZ;
  final double scale;
  final double offsetX;
  final double offsetY;
  final double rotation;

  factory _SvgTransform(
    List<_PlanSurface> surfaces, {
    double rotationRadians = 0,
    bool autoAlign = true,
  }) {
    final rotation =
        (autoAlign ? _dominantRotation(surfaces) : 0) + rotationRadians;
    final points = surfaces
        .expand((surface) => surface.corners())
        .map((point) => _rotate(point, rotation))
        .toList();
    if (points.isEmpty) {
      return _SvgTransform._(
        0,
        0,
        1,
        _FloorPlanSvg.drawingLeft + 16,
        _FloorPlanSvg.drawingBottom - 16,
        rotation,
      );
    }
    final minX = points.map((point) => point.x).reduce(math.min);
    final maxX = points.map((point) => point.x).reduce(math.max);
    final minZ = points.map((point) => point.y).reduce(math.min);
    final maxZ = points.map((point) => point.y).reduce(math.max);
    final modelWidth = math.max(maxX - minX, 0.5);
    final modelHeight = math.max(maxZ - minZ, 0.5);
    final scale = math.min(
      (_FloorPlanSvg.drawingRight - _FloorPlanSvg.drawingLeft - 32) /
          modelWidth,
      (_FloorPlanSvg.drawingBottom - _FloorPlanSvg.drawingTop - 32) /
          modelHeight,
    );
    final offsetX = _FloorPlanSvg.drawingLeft + 16 - minX * scale;
    final offsetY = _FloorPlanSvg.drawingTop + 16 + maxZ * scale;
    return _SvgTransform._(minX, minZ, scale, offsetX, offsetY, rotation);
  }

  const _SvgTransform._(
    this.minX,
    this.minZ,
    this.scale,
    this.offsetX,
    this.offsetY,
    this.rotation,
  );

  _Point point(_Point point) {
    final rotated = _rotate(point, rotation);
    return _Point(rotated.x * scale + offsetX, offsetY - rotated.y * scale);
  }

  double length(double meters) => meters * scale;

  _Point direction(double angle) {
    final alignedAngle = angle + rotation;
    return _Point(math.cos(alignedAngle), -math.sin(alignedAngle));
  }

  _Point normal(double angle) {
    final directionPoint = direction(angle);
    return _Point(-directionPoint.y, directionPoint.x);
  }

  static double _dominantRotation(List<_PlanSurface> surfaces) {
    final walls = surfaces.where(
      (surface) => surface.kind == _SurfaceKind.wall,
    );
    if (walls.isEmpty) return 0;
    final reference = walls.reduce((a, b) => a.length >= b.length ? a : b);
    var angle = reference.angle;
    while (angle > math.pi / 2) {
      angle -= math.pi;
    }
    while (angle < -math.pi / 2) {
      angle += math.pi;
    }
    return -angle;
  }

  static _Point _rotate(_Point point, double angle) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return _Point(
      point.x * cosA - point.y * sinA,
      point.x * sinA + point.y * cosA,
    );
  }
}

class _SurfaceStyle {
  final String fill;
  final String stroke;
  final double width;

  const _SurfaceStyle(this.fill, this.stroke, this.width);
}

void _drawSlidingDoorSymbol(
  StringBuffer buffer,
  _Point a,
  _Point b,
  _Point normal,
) {
  final direction = b - a;
  final unit = direction.length == 0
      ? const _Point(1, 0)
      : _Point(direction.x / direction.length, direction.y / direction.length);
  final trackOffset = 4.0;
  final overlap = math.min(10.0, direction.length * 0.22);

  buffer.writeln(
    '<line x1="${a.x + normal.x * trackOffset}" y1="${a.y + normal.y * trackOffset}" x2="${b.x + normal.x * trackOffset}" y2="${b.y + normal.y * trackOffset}" stroke="#000000" stroke-width="1.1"/>',
  );
  buffer.writeln(
    '<line x1="${a.x - normal.x * trackOffset}" y1="${a.y - normal.y * trackOffset}" x2="${b.x - normal.x * trackOffset}" y2="${b.y - normal.y * trackOffset}" stroke="#000000" stroke-width="1.1"/>',
  );
  buffer.writeln(
    '<line x1="${a.x + normal.x * trackOffset}" y1="${a.y + normal.y * trackOffset}" x2="${a.x - normal.x * trackOffset + unit.x * overlap}" y2="${a.y - normal.y * trackOffset + unit.y * overlap}" stroke="#000000" stroke-width="1.0"/>',
  );
  buffer.writeln(
    '<line x1="${b.x - normal.x * trackOffset}" y1="${b.y - normal.y * trackOffset}" x2="${b.x + normal.x * trackOffset - unit.x * overlap}" y2="${b.y + normal.y * trackOffset - unit.y * overlap}" stroke="#000000" stroke-width="1.0"/>',
  );
}

class _Point {
  final double x;
  final double y;

  const _Point(this.x, this.y);

  _Point operator +(_Point other) => _Point(x + other.x, y + other.y);

  _Point operator -(_Point other) => _Point(x - other.x, y - other.y);

  _Point operator *(double value) => _Point(x * value, y * value);

  double get length => math.sqrt(x * x + y * y);
}
