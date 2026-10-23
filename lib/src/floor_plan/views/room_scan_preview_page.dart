import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../editor_colors.dart';
import 'package:ios_roomplan/src/internal.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class RoomScanPreviewResult {
  final bool scanAgain;
  final File? pdfFile;

  const RoomScanPreviewResult({this.scanAgain = false, this.pdfFile});
}

class RoomScanPreviewPage extends StatefulWidget {
  final String? title;
  final Future<void> Function(File pdfFile)? onSaved;
  final NamedScanResult scan;
  final List<RoomPlanAnnotation> samples;

  const RoomScanPreviewPage({
    super.key,
    this.title,
    this.onSaved,
    required this.scan,
    this.samples = const [],
  });

  @override
  State<RoomScanPreviewPage> createState() => _RoomScanPreviewPageState();
}

class _RoomScanPreviewPageState extends State<RoomScanPreviewPage> {
  static const double _scanFeatureTouchClearance = 32;

  late List<PlanSurfaceSnapshot> _surfaces;
  late final List<PlanSurfaceSnapshot> _originalSurfaces;
  late File _pdfFile;
  List<RoomSampleLocation> _locations = [];
  int? _selectedSurfaceIndex;
  // For walls: which endpoint (0 = start, 1 = end) the user tapped nearest.
  // Resize grows/shrinks this end only, keeping the opposite end fixed.
  int? _selectedWallActiveEnd;
  String? _draggingSampleRefId;
  double _rotationRadians = 0;
  double _scaleStartRotation = 0;
  double _zoom = 1;
  double _scaleStartZoom = 1;
  Offset _panOffset = Offset.zero;
  Offset _scaleStartPan = Offset.zero;
  Offset _scaleStartFocalPoint = Offset.zero;
  bool _isDraggingSample = false;
  bool _isPanningCanvas = false;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _pendingShapeType; // 'wall', 'object', 'door', 'window', 'opening'

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _surfaces =
        widget.scan.surfaceSnapshots ??
        FloorPlanPdfService.surfaceSnapshots(widget.scan.scanResult);
    _originalSurfaces = List.of(_surfaces);
    _pdfFile = widget.scan.pdfFile;
    _loadLocations();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    final savedState = await RoomSampleLocationService.loadStateForPdf(
      _pdfFile,
    );
    final saved = savedState.locations;
    final savedByRef = {for (final item in saved) item.sampleRefId: item};
    final nextLocations = <RoomSampleLocation>[];
    for (var i = 0; i < widget.samples.length; i++) {
      final sample = widget.samples[i];
      final refId = sample.id;
      if (refId.trim().isEmpty) continue;
      final label = _sampleLabel(sample, i);
      final savedLocation = savedByRef[refId];
      nextLocations.add(
        savedLocation?.copyWith(label: label) ??
            RoomSampleLocation(
              sampleRefId: refId,
              label: label,
              x: 0.18 + (i % 4) * 0.18,
              y: 0.18 + (i ~/ 4) * 0.14,
              isPlaced: false,
            ),
      );
    }
    if (!mounted) return;
    setState(() {
      _locations = nextLocations;
      _rotationRadians = savedState.rotationRadians;
      _isLoading = false;
    });
  }

  Future<void> _saveLocations() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });
    var shouldResetSaving = true;
    try {
      final snappedSurfaces = _snapWallCorners(_surfaces);
      final annotatedPdf = await FloorPlanPdfService.create2DFloorPlan(
        widget.scan.scanResult,
        title: widget.title ?? widget.scan.name,
        fileName: widget.title ?? widget.scan.name,
        sampleLocations: _placedLocations,
        rotationRadians: _rotationRadians,
        surfaceSnapshots: snappedSurfaces,
      );
      await FloorPlanPdfService.saveScanGeometry(
        scanResult: widget.scan.scanResult,
        roomName: widget.title ?? widget.scan.name,
        pdfFile: annotatedPdf,
        surfaceSnapshots: snappedSurfaces,
        detectFurniture: widget.scan.detectFurniture,
      );
      await RoomSampleLocationService.saveForPdf(
        pdfFile: annotatedPdf,
        locations: _placedLocations,
        rotationRadians: _rotationRadians,
      );
      await widget.onSaved?.call(annotatedPdf);

      if (!mounted) return;
      shouldResetSaving = false;
      setState(() {
        _isSaving = false;
      });

      Navigator.of(context).pop(RoomScanPreviewResult(pdfFile: annotatedPdf));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save sample locations: $error')),
      );
    } finally {
      if (mounted && shouldResetSaving) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<RoomSampleLocation> get _placedLocations {
    return _locations.where((location) => location.isPlaced).toList();
  }

  void _updateMarker(String sampleRefId, Offset localPosition, Size size) {
    final contentPosition = _toContentPosition(localPosition);
    final displayX = (contentPosition.dx / math.max(size.width, 1)).clamp(
      0.0,
      1.0,
    );
    final displayY = (contentPosition.dy / math.max(size.height, 1)).clamp(
      0.0,
      1.0,
    );
    final storedPoint = _unrotateNormalizedPoint(displayX, displayY);
    final localPoint = _localPointForContentPosition(contentPosition, size);
    setState(() {
      _locations = _locations.map((location) {
        if (location.sampleRefId != sampleRefId) return location;
        return location.copyWith(
          x: storedPoint.dx,
          y: storedPoint.dy,
          isPlaced: true,
          localX: localPoint?.dx,
          localY: localPoint?.dy,
        );
      }).toList();
    });
  }

  Offset? _localPointForContentPosition(Offset contentPosition, Size size) {
    if (_surfaces.isEmpty) return null;
    final rawPoints = _surfaces.expand((surface) => surface.corners()).toList();
    if (rawPoints.isEmpty) return null;
    final rawBounds = _pointsBounds(rawPoints);
    final center = rawBounds.center;
    final rotatedPoints = rawPoints
        .map((point) => _rotateAround(point, center, _rotationRadians))
        .toList();
    final rotatedBounds = _pointsBounds(rotatedPoints).inflate(0.9);
    final scale = math.min(
      size.width / math.max(rotatedBounds.width, 1),
      size.height / math.max(rotatedBounds.height, 1),
    );
    final origin = Offset(
      (size.width - rotatedBounds.width * scale) / 2 -
          rotatedBounds.left * scale,
      (size.height - rotatedBounds.height * scale) / 2 -
          rotatedBounds.top * scale,
    );
    final rotatedModelPoint = Offset(
      (contentPosition.dx - origin.dx) / scale,
      (contentPosition.dy - origin.dy) / scale,
    );
    return _rotateAround(rotatedModelPoint, center, -_rotationRadians);
  }

  Rect _pointsBounds(List<Offset> points) {
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _rotateAround(Offset point, Offset center, double radians) {
    final delta = point - center;
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    return center +
        Offset(
          delta.dx * cosA - delta.dy * sinA,
          delta.dx * sinA + delta.dy * cosA,
        );
  }

  Offset _toContentPosition(Offset localPosition) {
    return (localPosition - _panOffset) / _zoom;
  }

  Offset _fingerClearContentPosition(Offset localPosition) {
    return _toContentPosition(
      localPosition - const Offset(0, _scanFeatureTouchClearance),
    );
  }

  Offset _shapePlacementLocalPosition(Offset localPosition) {
    final type = _pendingShapeType;
    if (type == 'wall' ||
        type == 'door' ||
        type == 'window' ||
        type == 'opening') {
      return localPosition - const Offset(0, _scanFeatureTouchClearance);
    }
    return localPosition;
  }

  void _resetPreviewView() {
    setState(() {
      // View only: zoom, pan and rotation. Geometry edits are untouched.
      _zoom = 1;
      _panOffset = Offset.zero;
      _rotationRadians = 0;
      _selectedSurfaceIndex = null;
      _selectedWallActiveEnd = null;
      _isPanningCanvas = false;
    });
  }

  void _undoEdits() {
    setState(() {
      // Undo any wall/feature edits made in this session.
      _surfaces = List.of(_originalSurfaces);
      _selectedSurfaceIndex = null;
      _selectedWallActiveEnd = null;
      _draggingSampleRefId = null;
      _isDraggingSample = false;
      _isPanningCanvas = false;
      _pendingShapeType = null;
    });
  }

  // --- Shape placement methods ---

  void _startPlacingScanShape(String type) {
    setState(() {
      _pendingShapeType = type;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tap on the room plan to place a $type'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _placeScanShapeAtPosition(Offset contentPosition, Size size) {
    if (_pendingShapeType == null) return;
    final geometry = _previewGeometry(size);
    if (geometry == null) return;
    // Convert screen content position back to world coordinates
    final worldPoint = _contentToWorld(contentPosition, geometry);
    final type = _pendingShapeType!;
    setState(() {
      _surfaces = [
        ..._surfaces,
        PlanSurfaceSnapshot(
          kind: type == 'stairs' ? 'object' : type,
          label: type == 'stairs'
              ? 'Stairs'
              : type[0].toUpperCase() + type.substring(1),
          centerX: worldPoint.dx,
          centerY: worldPoint.dy,
          angle: 0,
          length: type == 'wall' ? 1.0 : (type == 'stairs' ? 1.2 : 0.8),
          depth: type == 'wall'
              ? 0.12
              : (type == 'stairs' ? 0.8 : (type == 'object' ? 0.6 : 0.1)),
        ),
      ];
      _selectedSurfaceIndex = _surfaces.length - 1;
      _pendingShapeType = null;
    });
  }

  /// Convert a screen content position back to world (local room) coordinates.
  Offset _contentToWorld(Offset contentPosition, _PreviewGeometry geometry) {
    // Reverse the painter's mapping: origin + rotated * scale
    // So: rotated = (content - origin) / scale
    // Then unrotate around center
    final rotatedX = (contentPosition.dx - geometry.origin.dx) / geometry.scale;
    final rotatedY = (contentPosition.dy - geometry.origin.dy) / geometry.scale;
    final cosA = math.cos(-_rotationRadians);
    final sinA = math.sin(-_rotationRadians);
    final dx = rotatedX - geometry.center.dx;
    final dy = rotatedY - geometry.center.dy;
    return Offset(
      geometry.center.dx + dx * cosA - dy * sinA,
      geometry.center.dy + dx * sinA + dy * cosA,
    );
  }

  List<PlanSurfaceSnapshot> _snapWallCorners(
    List<PlanSurfaceSnapshot> surfaces,
  ) {
    const snapThreshold = 0.16;
    final wallEntries = <({int index, Offset start, Offset end})>[];
    final endpoints = <({int wallEntryIndex, int endIndex, Offset point})>[];

    for (var i = 0; i < surfaces.length; i++) {
      final surface = surfaces[i];
      if (surface.kind != 'wall') continue;
      final (start, end) = surface.endpoints();
      final wallEntryIndex = wallEntries.length;
      wallEntries.add((index: i, start: start, end: end));
      endpoints.add((
        wallEntryIndex: wallEntryIndex,
        endIndex: 0,
        point: start,
      ));
      endpoints.add((wallEntryIndex: wallEntryIndex, endIndex: 1, point: end));
    }
    if (endpoints.length < 2) return surfaces;

    final parent = List<int>.generate(endpoints.length, (index) => index);
    int find(int value) {
      while (parent[value] != value) {
        parent[value] = parent[parent[value]];
        value = parent[value];
      }
      return value;
    }

    void union(int a, int b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) parent[rootB] = rootA;
    }

    for (var i = 0; i < endpoints.length; i++) {
      for (var j = i + 1; j < endpoints.length; j++) {
        if (endpoints[i].wallEntryIndex == endpoints[j].wallEntryIndex) {
          continue;
        }
        if ((endpoints[i].point - endpoints[j].point).distance <=
            snapThreshold) {
          union(i, j);
        }
      }
    }

    final clusters = <int, List<int>>{};
    for (var i = 0; i < endpoints.length; i++) {
      clusters.putIfAbsent(find(i), () => []).add(i);
    }

    final snappedPoints = <int, Offset>{};
    for (final cluster in clusters.values) {
      if (cluster.length < 2) continue;
      final sum = cluster.fold<Offset>(
        Offset.zero,
        (total, endpointIndex) => total + endpoints[endpointIndex].point,
      );
      final snapped = sum / cluster.length.toDouble();
      for (final endpointIndex in cluster) {
        snappedPoints[endpointIndex] = snapped;
      }
    }
    if (snappedPoints.isEmpty) return surfaces;

    final wallStarts = wallEntries.map((entry) => entry.start).toList();
    final wallEnds = wallEntries.map((entry) => entry.end).toList();
    for (var i = 0; i < endpoints.length; i++) {
      final snapped = snappedPoints[i];
      if (snapped == null) continue;
      final endpoint = endpoints[i];
      if (endpoint.endIndex == 0) {
        wallStarts[endpoint.wallEntryIndex] = snapped;
      } else {
        wallEnds[endpoint.wallEntryIndex] = snapped;
      }
    }

    final updated = List<PlanSurfaceSnapshot>.from(surfaces);
    for (var i = 0; i < wallEntries.length; i++) {
      final start = wallStarts[i];
      final end = wallEnds[i];
      final delta = end - start;
      if (delta.distance < 0.05) continue;
      final original = surfaces[wallEntries[i].index];
      updated[wallEntries[i].index] = original.copyWith(
        centerX: (start.dx + end.dx) / 2,
        centerY: (start.dy + end.dy) / 2,
        angle: math.atan2(delta.dy, delta.dx),
        length: delta.distance,
      );
    }
    return updated;
  }

  void _snapSelectedWall() {
    final selected = _selectedSurface();
    if (selected == null) return;
    if (selected.kind == 'wall') {
      // Wall: just snap angle to nearest right angle
      _updateSelectedSurface((surface) {
        return surface.copyWith(
          angle: surface.angle - _nearestRightAngleDelta(surface.angle),
        );
      });
      return;
    }
    // Object/door/window/opening: snap to nearest wall
    final walls = _surfaces
        .where((s) => s.kind == 'wall' && s != selected)
        .toList();
    if (walls.isEmpty) return;
    // Find nearest wall
    PlanSurfaceSnapshot nearestWall = walls.first;
    double nearestDist = double.infinity;
    for (final wall in walls) {
      final dist = _distanceToWall(selected, wall);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestWall = wall;
      }
    }
    // Project object center onto wall line to find closest point
    final wallCenter = Offset(nearestWall.centerX, nearestWall.centerY);
    final wallDir = Offset(
      math.cos(nearestWall.angle),
      math.sin(nearestWall.angle),
    );
    final objCenter = Offset(selected.centerX, selected.centerY);
    final delta = objCenter - wallCenter;
    final projection = delta.dx * wallDir.dx + delta.dy * wallDir.dy;
    // Clamp to wall length
    final clampedProjection = projection.clamp(
      -nearestWall.length / 2,
      nearestWall.length / 2,
    );
    final snappedCenter = wallCenter + wallDir * clampedProjection;
    _updateSelectedSurface((surface) {
      return surface.copyWith(
        centerX: snappedCenter.dx,
        centerY: snappedCenter.dy,
        angle: nearestWall.angle,
      );
    });
  }

  void _combineSelectedWallSection() {
    final index = _selectedSurfaceIndex;
    if (index == null) return;
    final selected = _surfaces[index];
    if (selected.kind != 'wall') return;

    final selectedDir = Offset(
      math.cos(selected.angle),
      math.sin(selected.angle),
    );
    final selectedNormal = Offset(-selectedDir.dy, selectedDir.dx);
    final selectedCenter = Offset(selected.centerX, selected.centerY);
    final selectedEnds = selected.endpoints();
    final selectedMin = math.min(
      _projectPoint(selectedEnds.$1, selectedDir),
      _projectPoint(selectedEnds.$2, selectedDir),
    );
    final selectedMax = math.max(
      _projectPoint(selectedEnds.$1, selectedDir),
      _projectPoint(selectedEnds.$2, selectedDir),
    );

    const maxAngleDelta = math.pi / 36;
    const maxLineOffset = 0.16;
    const maxGap = 0.30;
    var bestIndex = -1;
    var bestGap = double.infinity;

    for (var i = 0; i < _surfaces.length; i++) {
      if (i == index) continue;
      final candidate = _surfaces[i];
      if (candidate.kind != 'wall') continue;
      if (_smallestAngleDelta(selected.angle, candidate.angle) >
          maxAngleDelta) {
        continue;
      }
      final candidateCenter = Offset(candidate.centerX, candidate.centerY);
      final lineOffset =
          ((candidateCenter - selectedCenter).dx * selectedNormal.dx +
                  (candidateCenter - selectedCenter).dy * selectedNormal.dy)
              .abs();
      if (lineOffset > maxLineOffset) continue;

      final candidateEnds = candidate.endpoints();
      final candidateMin = math.min(
        _projectPoint(candidateEnds.$1, selectedDir),
        _projectPoint(candidateEnds.$2, selectedDir),
      );
      final candidateMax = math.max(
        _projectPoint(candidateEnds.$1, selectedDir),
        _projectPoint(candidateEnds.$2, selectedDir),
      );
      final gap = candidateMin > selectedMax
          ? candidateMin - selectedMax
          : selectedMin > candidateMax
          ? selectedMin - candidateMax
          : 0.0;
      if (gap <= maxGap && gap < bestGap) {
        bestGap = gap;
        bestIndex = i;
      }
    }

    if (bestIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching wall section nearby.')),
      );
      return;
    }

    final other = _surfaces[bestIndex];
    final selectedPair = selected.endpoints();
    final otherPair = other.endpoints();
    final allEndpoints = [
      selectedPair.$1,
      selectedPair.$2,
      otherPair.$1,
      otherPair.$2,
    ];
    var minPoint = allEndpoints.first;
    var maxPoint = allEndpoints.first;
    var minProjection = _projectPoint(minPoint, selectedDir);
    var maxProjection = minProjection;
    for (final point in allEndpoints.skip(1)) {
      final projection = _projectPoint(point, selectedDir);
      if (projection < minProjection) {
        minProjection = projection;
        minPoint = point;
      }
      if (projection > maxProjection) {
        maxProjection = projection;
        maxPoint = point;
      }
    }

    final delta = maxPoint - minPoint;
    if (delta.distance < 0.05) return;
    setState(() {
      final surfaces = [..._surfaces];
      surfaces[index] = selected.copyWith(
        centerX: (minPoint.dx + maxPoint.dx) / 2,
        centerY: (minPoint.dy + maxPoint.dy) / 2,
        angle: math.atan2(delta.dy, delta.dx),
        length: delta.distance,
      );
      surfaces.removeAt(bestIndex);
      _selectedSurfaceIndex = bestIndex < index ? index - 1 : index;
      _surfaces = _snapWallCorners(surfaces);
    });
  }

  double _projectPoint(Offset point, Offset direction) {
    return point.dx * direction.dx + point.dy * direction.dy;
  }

  double _smallestAngleDelta(double a, double b) {
    final diff = (a - b).abs() % math.pi;
    return diff > math.pi / 2 ? math.pi - diff : diff;
  }

  /// Move a selected surface by screen-space delta (same pattern as sample drag).
  void _moveSurfaceByScreenDelta(int index, Offset screenDelta, Size size) {
    if (index < 0 || index >= _surfaces.length) return;
    // Use the same bounds as the painter to get the correct scale
    final bounds = _painterBounds(_surfaces).inflate(0.9);
    final sc = math.min(
      size.width / math.max(bounds.width, 1),
      size.height / math.max(bounds.height, 1),
    );
    // Convert screen delta to world coordinates:
    // screen = world * scale, so world = screen / scale
    final worldDelta = Offset(
      screenDelta.dx / (sc * _zoom),
      screenDelta.dy / (sc * _zoom),
    );
    // Un-rotate to get the delta in unrotated space
    final cosA = math.cos(-_rotationRadians);
    final sinA = math.sin(-_rotationRadians);
    final unrotated = Offset(
      worldDelta.dx * cosA - worldDelta.dy * sinA,
      worldDelta.dx * sinA + worldDelta.dy * cosA,
    );
    setState(() {
      final surfaces = [..._surfaces];
      final s = surfaces[index];
      surfaces[index] = s.copyWith(
        centerX: s.centerX + unrotated.dx,
        centerY: s.centerY + unrotated.dy,
      );
      _surfaces = _snapWallCorners(surfaces);
    });
  }

  Rect _painterBounds(List<PlanSurfaceSnapshot> surfaces) {
    if (surfaces.isEmpty) {
      return const Rect.fromLTRB(-1, -1, 1, 1);
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final s in surfaces) {
      for (final p in s.corners()) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _rotateSelectedWall(double delta) {
    _updateSelectedSurface(
      (surface) => surface.copyWith(angle: surface.angle + delta),
    );
  }

  void _resizeSelectedWall(double delta) {
    final index = _selectedSurfaceIndex;
    if (index == null) return;
    final surface = _surfaces[index];
    if (surface.kind == 'wall') {
      _setSelectedWallLength(surface.length + delta, snapEndpoint: true);
      return;
    }

    if (surface.kind == 'object') {
      final nextLength = math.max(0.2, surface.length + delta);
      final ratio = surface.length <= 0 ? 1.0 : nextLength / surface.length;
      _updateSelectedSurface(
        (surface) => surface.copyWith(
          length: nextLength,
          depth: math.max(0.2, surface.depth * ratio),
        ),
      );
      return;
    }

    _updateSelectedSurface(
      (surface) =>
          surface.copyWith(length: math.max(0.05, surface.length + delta)),
    );
  }

  void _setSelectedWallLength(
    double lengthMeters, {
    bool snapEndpoint = false,
  }) {
    final index = _selectedSurfaceIndex;
    if (index == null) return;
    final surface = _surfaces[index];
    if (surface.kind != 'wall') return;

    final endpoints = surface.endpoints();
    final activeEnd = _selectedWallActiveEnd ?? 0;
    final fixed = activeEnd == 0 ? endpoints.$2 : endpoints.$1;
    final direction = Offset(math.cos(surface.angle), math.sin(surface.angle));
    final towardActive = activeEnd == 0 ? -direction : direction;
    final newLength = math.max(0.05, lengthMeters);
    var newActiveEnd = Offset(
      fixed.dx + towardActive.dx * newLength,
      fixed.dy + towardActive.dy * newLength,
    );

    if (snapEndpoint) {
      const snapThreshold = 0.12;
      var bestSnapDist = snapThreshold;
      Offset? bestSnapPoint;
      for (var i = 0; i < _surfaces.length; i++) {
        if (i == index) continue;
        final other = _surfaces[i];
        if (other.kind != 'wall') continue;
        final otherEnds = other.endpoints();
        for (final otherEnd in [otherEnds.$1, otherEnds.$2]) {
          final d = (newActiveEnd - otherEnd).distance;
          if (d < bestSnapDist) {
            bestSnapDist = d;
            bestSnapPoint = otherEnd;
          }
        }
      }
      if (bestSnapPoint != null) {
        newActiveEnd = bestSnapPoint;
      }
    }

    final adjustedDelta = newActiveEnd - fixed;
    final adjustedLength = math.max(0.05, adjustedDelta.distance);
    final adjustedCenter = Offset(
      fixed.dx + adjustedDelta.dx / 2,
      fixed.dy + adjustedDelta.dy / 2,
    );
    setState(() {
      final surfaces = [..._surfaces];
      surfaces[index] = surface.copyWith(
        centerX: adjustedCenter.dx,
        centerY: adjustedCenter.dy,
        length: adjustedLength,
      );
      _surfaces = _snapWallCorners(surfaces);
    });
  }

  Future<void> _editSelectedWallLength() async {
    final selected = _selectedSurface();
    if (selected == null || selected.kind != 'wall') return;

    final lengthMeters = await showDialog<double>(
      context: context,
      builder: (context) => _WallLengthDialog(
        initialText: _formatFeetInches(selected.length),
        parseLength: _parseFeetInches,
      ),
    );
    if (lengthMeters == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setSelectedWallLength(lengthMeters);
    });
  }

  String _formatFeetInches(double meters) {
    final totalInches = (meters * 39.3700787402).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return inches == 0 ? '$feet\'' : '$feet\' $inches"';
  }

  double? _parseFeetInches(String rawValue) {
    final value = rawValue.trim().toLowerCase();
    if (value.isEmpty) return null;

    final feetMatch = RegExp(
      r"([0-9]+(?:\.[0-9]+)?)\s*(?:'|ft|feet)",
    ).firstMatch(value);
    final inchMatch = RegExp(
      r'([0-9]+(?:\.[0-9]+)?)\s*(?:"|in|inch|inches)',
    ).firstMatch(value);
    if (feetMatch != null || inchMatch != null) {
      final feet = feetMatch == null
          ? 0.0
          : double.tryParse(feetMatch.group(1) ?? '') ?? 0.0;
      final inches = inchMatch == null
          ? 0.0
          : double.tryParse(inchMatch.group(1) ?? '') ?? 0.0;
      final totalFeet = feet + inches / 12;
      return totalFeet > 0 ? totalFeet * 0.3048 : null;
    }

    final compactMatch = RegExp(
      r'^([0-9]+(?:\.[0-9]+)?)(?:\s+([0-9]+(?:\.[0-9]+)?))?$',
    ).firstMatch(value);
    if (compactMatch == null) return null;
    final feet = double.tryParse(compactMatch.group(1) ?? '');
    if (feet == null || feet <= 0) return null;
    final inches = double.tryParse(compactMatch.group(2) ?? '0') ?? 0;
    return (feet + inches / 12) * 0.3048;
  }

  void _deleteSelectedSurface() {
    final index = _selectedSurfaceIndex;
    if (index == null) return;
    final selectedSurface = _surfaces[index];
    if (selectedSurface.kind == 'wall') {
      final wallCount = _surfaces
          .where((surface) => surface.kind == 'wall')
          .length;
      if (wallCount <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('At least one wall is required.')),
        );
        return;
      }
    }
    setState(() {
      final remaining = _surfaces
          .asMap()
          .entries
          .where((entry) => entry.key != index)
          .map((entry) => entry.value)
          .toList();
      _surfaces = selectedSurface.kind == 'wall'
          ? _snapWallCorners(remaining)
          : remaining;
      _selectedSurfaceIndex = null;
      _selectedWallActiveEnd = null;
    });
  }

  void _updateSelectedSurface(
    PlanSurfaceSnapshot Function(PlanSurfaceSnapshot surface) update,
  ) {
    final index = _selectedSurfaceIndex;
    if (index == null) return;
    setState(() {
      final surfaces = [..._surfaces];
      surfaces[index] = update(surfaces[index]);
      _surfaces = surfaces;
    });
  }

  double _nearestRightAngleDelta(double angle) {
    return angle - _nearestRightAngle(angle);
  }

  double _nearestRightAngle(double angle) {
    final quarterTurns = (angle / (math.pi / 2)).round();
    return quarterTurns * math.pi / 2;
  }

  int? _hitTestSurface(Offset localPosition, Size size) {
    if (_surfaces.isEmpty) return null;
    final contentPosition = _toContentPosition(localPosition);
    final fingerClearPosition = _fingerClearContentPosition(localPosition);
    final geometry = _previewGeometry(size);
    if (geometry == null) return null;

    var bestDirectIndex = -1;
    var bestDirectDistance = double.infinity;
    var bestFingerClearIndex = -1;
    var bestFingerClearDistance = double.infinity;
    for (var i = 0; i < _surfaces.length; i++) {
      final surface = _surfaces[i];
      final distance = _surfaceHitDistance(surface, contentPosition, geometry);
      if (distance < bestDirectDistance) {
        bestDirectDistance = distance;
        bestDirectIndex = i;
      }
      if (surface.kind == 'object') continue;
      final fingerClearDistance = _surfaceHitDistance(
        surface,
        fingerClearPosition,
        geometry,
      );
      if (fingerClearDistance < bestFingerClearDistance) {
        bestFingerClearDistance = fingerClearDistance;
        bestFingerClearIndex = i;
      }
    }
    final threshold = 24 / math.max(_zoom, 0.75);
    if (bestDirectIndex >= 0 && bestDirectDistance <= threshold) {
      return bestDirectIndex;
    }
    return bestFingerClearIndex >= 0 && bestFingerClearDistance <= threshold
        ? bestFingerClearIndex
        : null;
  }

  int? _activeEndForTap(int? surfaceIndex, Offset localPosition, Size size) {
    if (surfaceIndex == null) return null;
    final surface = _surfaces[surfaceIndex];
    if (surface.kind != 'wall') return null;
    final geometry = _previewGeometry(size);
    if (geometry == null) return null;
    final endpoints = surface.endpoints();
    final a = _mapPreviewPoint(endpoints.$1, geometry);
    final b = _mapPreviewPoint(endpoints.$2, geometry);
    final directPosition = _toContentPosition(localPosition);
    final directDistance = _distanceToSegment(directPosition, a, b);
    final threshold = 24 / math.max(_zoom, 0.75);
    final contentPosition = directDistance <= threshold
        ? directPosition
        : _fingerClearContentPosition(localPosition);
    return (contentPosition - a).distance <= (contentPosition - b).distance
        ? 0
        : 1;
  }

  /// Distance from a surface center to a wall line.
  double _distanceToWall(
    PlanSurfaceSnapshot surface,
    PlanSurfaceSnapshot wall,
  ) {
    final center = Offset(surface.centerX, surface.centerY);
    final wallStart = Offset(
      wall.centerX - math.cos(wall.angle) * wall.length / 2,
      wall.centerY - math.sin(wall.angle) * wall.length / 2,
    );
    final wallEnd = Offset(
      wall.centerX + math.cos(wall.angle) * wall.length / 2,
      wall.centerY + math.sin(wall.angle) * wall.length / 2,
    );
    return _distanceToSegment(center, wallStart, wallEnd);
  }

  double _surfaceHitDistance(
    PlanSurfaceSnapshot surface,
    Offset contentPosition,
    _PreviewGeometry geometry,
  ) {
    if (surface.kind == 'object') {
      final points = surface
          .corners()
          .map((point) => _mapPreviewPoint(point, geometry))
          .toList();
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      if (path.contains(contentPosition)) return 0;
      var best = double.infinity;
      for (var i = 0; i < points.length; i++) {
        best = math.min(
          best,
          _distanceToSegment(
            contentPosition,
            points[i],
            points[(i + 1) % points.length],
          ),
        );
      }
      return best;
    }

    final endpoints = surface.endpoints();
    final a = _mapPreviewPoint(endpoints.$1, geometry);
    final b = _mapPreviewPoint(endpoints.$2, geometry);
    return _distanceToSegment(contentPosition, a, b);
  }

  _PreviewGeometry? _previewGeometry(Size size) {
    if (_surfaces.isEmpty) return null;
    final rawPoints = _surfaces.expand((surface) => surface.corners()).toList();
    if (rawPoints.isEmpty) return null;
    final rawBounds = _pointsBounds(rawPoints);
    final rotatedPoints = rawPoints
        .map(
          (point) => _rotateAround(point, rawBounds.center, _rotationRadians),
        )
        .toList();
    final bounds = _pointsBounds(rotatedPoints).inflate(0.9);
    final scale = math.min(
      size.width / math.max(bounds.width, 1),
      size.height / math.max(bounds.height, 1),
    );
    final origin = Offset(
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    );
    return _PreviewGeometry(
      center: rawBounds.center,
      origin: origin,
      scale: scale,
    );
  }

  Offset _mapPreviewPoint(Offset point, _PreviewGeometry geometry) {
    final rotated = _rotateAround(point, geometry.center, _rotationRadians);
    return Offset(
      geometry.origin.dx + rotated.dx * geometry.scale,
      geometry.origin.dy + rotated.dy * geometry.scale,
    );
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final segment = b - a;
    final lengthSquared = segment.distanceSquared;
    if (lengthSquared <= 0) return (point - a).distance;
    final t =
        ((point - a).dx * segment.dx + (point - a).dy * segment.dy) /
        lengthSquared;
    final clamped = t.clamp(0.0, 1.0);
    final projection = a + segment * clamped;
    return (point - projection).distance;
  }

  Offset _rotateNormalizedPoint(double x, double y) {
    return _rotateNormalizedByRadians(x, y, _rotationRadians);
  }

  Offset _unrotateNormalizedPoint(double x, double y) {
    return _rotateNormalizedByRadians(x, y, -_rotationRadians);
  }

  Offset _rotateNormalizedByRadians(double x, double y, double radians) {
    final delta = Offset(x - 0.5, y - 0.5);
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    return Offset(
      0.5 + delta.dx * cosA - delta.dy * sinA,
      0.5 + delta.dx * sinA + delta.dy * cosA,
    );
  }

  String _sampleLabel(RoomPlanAnnotation sample, int index) {
    return sample.label.trim().isEmpty ? 'S${index + 1}' : sample.label;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f7f9),
      appBar: AppBar(
        backgroundColor: appColor,
        title: Text(widget.title ?? widget.scan.name),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).pop(const RoomScanPreviewResult(scanAgain: true)),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Start Scan Again'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveLocations,
        backgroundColor: appColor,
        foregroundColor: Colors.white,
        icon: _isSaving
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save),
        label: Text(_isSaving ? 'Saving...' : 'Save'),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: roomPlanAccent))
            : Column(
                children: [
                  _buildPreviewToolbar(),
                  _buildSampleTray(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final size = Size(
                                math.max(constraints.maxWidth, 1),
                                math.max(constraints.maxHeight, 1),
                              );
                              return DragTarget<String>(
                                onAcceptWithDetails: (details) {
                                  final box =
                                      context.findRenderObject() as RenderBox?;
                                  if (box == null) return;
                                  _updateMarker(
                                    details.data,
                                    box.globalToLocal(details.offset),
                                    size,
                                  );
                                  setState(() {
                                    _isDraggingSample = false;
                                  });
                                },
                                builder: (context, candidateData, rejectedData) {
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (details) {
                                      if (_pendingShapeType != null) {
                                        final placementPosition =
                                            _shapePlacementLocalPosition(
                                              details.localPosition,
                                            );
                                        final contentPosition =
                                            _toContentPosition(
                                              placementPosition,
                                            );
                                        _placeScanShapeAtPosition(
                                          contentPosition,
                                          size,
                                        );
                                        return;
                                      }
                                      final surfaceIndex = _hitTestSurface(
                                        details.localPosition,
                                        size,
                                      );
                                      setState(() {
                                        _selectedSurfaceIndex = surfaceIndex;
                                        _selectedWallActiveEnd =
                                            _activeEndForTap(
                                              surfaceIndex,
                                              details.localPosition,
                                              size,
                                            );
                                      });
                                    },
                                    onScaleStart: (details) {
                                      _scaleStartRotation = _rotationRadians;
                                      _scaleStartZoom = _zoom;
                                      _scaleStartPan = _panOffset;
                                      _scaleStartFocalPoint =
                                          details.localFocalPoint;
                                      _isPanningCanvas = false;
                                    },
                                    onScaleUpdate: (details) {
                                      if (details.pointerCount >= 2) {
                                        setState(() {
                                          _rotationRadians =
                                              _scaleStartRotation +
                                              details.rotation;
                                          _zoom =
                                              (_scaleStartZoom * details.scale)
                                                  .clamp(0.75, 4.0);
                                          _panOffset =
                                              _scaleStartPan +
                                              (details.localFocalPoint -
                                                  _scaleStartFocalPoint);
                                        });
                                        return;
                                      }
                                      final refId = _draggingSampleRefId;
                                      if (refId != null) {
                                        _updateMarker(
                                          refId,
                                          details.localFocalPoint,
                                          size,
                                        );
                                        return;
                                      }
                                      if (_isDraggingSample) return;
                                      // Move selected surface by dragging
                                      if (_selectedSurfaceIndex != null) {
                                        if (!_isPanningCanvas &&
                                            (details.localFocalPoint -
                                                        _scaleStartFocalPoint)
                                                    .distance <
                                                12) {
                                          return;
                                        }
                                        _isPanningCanvas = true;
                                        _moveSurfaceByScreenDelta(
                                          _selectedSurfaceIndex!,
                                          details.focalPointDelta,
                                          size,
                                        );
                                        return;
                                      }
                                      if (!_isPanningCanvas &&
                                          (details.localFocalPoint -
                                                      _scaleStartFocalPoint)
                                                  .distance <
                                              12) {
                                        return;
                                      }
                                      setState(() {
                                        _isPanningCanvas = true;
                                        _panOffset += details.focalPointDelta;
                                      });
                                    },
                                    onScaleEnd: (_) {
                                      setState(() {
                                        _draggingSampleRefId = null;
                                        _isDraggingSample = false;
                                        _isPanningCanvas = false;
                                      });
                                    },
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Transform.translate(
                                            offset: _panOffset,
                                            child: Transform.scale(
                                              scale: _zoom,
                                              alignment: Alignment.topLeft,
                                              child: SizedBox(
                                                width: size.width,
                                                height: size.height,
                                                child: Stack(
                                                  children: [
                                                    Positioned.fill(
                                                      child: CustomPaint(
                                                        painter: _RoomPreviewPainter(
                                                          scanResult: widget
                                                              .scan
                                                              .scanResult,
                                                          surfaces: _surfaces,
                                                          locations:
                                                              _placedLocations,
                                                          rotationRadians:
                                                              _rotationRadians,
                                                          selectedSurfaceIndex:
                                                              _selectedSurfaceIndex,
                                                          selectedWallActiveEnd:
                                                              _selectedWallActiveEnd,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        ..._placedLocations.map((location) {
                                          final point = _screenPointForMarker(
                                            location,
                                            size,
                                          );
                                          return Positioned(
                                            left: point.dx - 44,
                                            top: point.dy - 10,
                                            child: _SampleMarker(
                                              location: location,
                                              onPanStart: () {
                                                setState(() {
                                                  _draggingSampleRefId =
                                                      location.sampleRefId;
                                                });
                                              },
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Offset _screenPointForMarker(RoomSampleLocation location, Size size) {
    final point = _rotateNormalizedPoint(location.x, location.y);
    return _panOffset +
        Offset(point.dx * size.width * _zoom, point.dy * size.height * _zoom);
  }

  PlanSurfaceSnapshot? _selectedSurface() {
    final index = _selectedSurfaceIndex;
    if (index == null || index < 0 || index >= _surfaces.length) return null;
    return _surfaces[index];
  }

  Widget _buildPreviewToolbar() {
    final degrees = (_rotationRadians * 180 / math.pi).round();
    final zoomPercent = (_zoom * 100).round();
    final selectedSurface = _selectedSurface();
    final surfaceSelected = selectedSurface != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.screen_rotation_alt, color: roomPlanAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _pendingShapeType != null
                      ? 'Tap on the plan to place a $_pendingShapeType'
                      : surfaceSelected
                      ? '${_surfaceLabel(selectedSurface)} selected · ${_formatSurfaceLength(selectedSurface)} · drag to move, +/− to resize'
                      : 'Tap a surface to select, then drag to move · $degrees° · $zoomPercent%',
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _resetPreviewView,
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: const Text('Reset View'),
                style: TextButton.styleFrom(foregroundColor: roomPlanAccent),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _undoEdits,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Undo Edits'),
                style: TextButton.styleFrom(foregroundColor: roomPlanAccent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PreviewToolButton(
                  label: 'Snap',
                  icon: Icons.straighten,
                  onPressed: surfaceSelected ? _snapSelectedWall : null,
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Length',
                  icon: Icons.edit,
                  onPressed: selectedSurface?.kind == 'wall'
                      ? _editSelectedWallLength
                      : null,
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Combine',
                  icon: Icons.call_merge,
                  onPressed: selectedSurface?.kind == 'wall'
                      ? _combineSelectedWallSection
                      : null,
                ),
                const SizedBox(width: 6),
                _PreviewIconButton(
                  tooltip: 'Rotate left',
                  icon: Icons.rotate_left,
                  onPressed: surfaceSelected
                      ? () => _rotateSelectedWall(-math.pi / 180)
                      : null,
                ),
                const SizedBox(width: 6),
                _PreviewIconButton(
                  tooltip: 'Rotate right',
                  icon: Icons.rotate_right,
                  onPressed: surfaceSelected
                      ? () => _rotateSelectedWall(math.pi / 180)
                      : null,
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Shorten',
                  icon: Icons.remove,
                  onPressed: surfaceSelected
                      ? () => _resizeSelectedWall(-0.1)
                      : null,
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Lengthen',
                  icon: Icons.add,
                  onPressed: surfaceSelected
                      ? () => _resizeSelectedWall(0.1)
                      : null,
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  onPressed: surfaceSelected ? _deleteSelectedSurface : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Shapes toolbar row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Add:',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                _PreviewToolButton(
                  label: 'Object',
                  icon: Icons.square_outlined,
                  onPressed: () => _startPlacingScanShape('object'),
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Stairs',
                  icon: Icons.stairs_outlined,
                  onPressed: () => _startPlacingScanShape('stairs'),
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Door',
                  icon: Icons.door_front_door_outlined,
                  onPressed: () => _startPlacingScanShape('door'),
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Window',
                  icon: Icons.window_outlined,
                  onPressed: () => _startPlacingScanShape('window'),
                ),
                const SizedBox(width: 6),
                _PreviewToolButton(
                  label: 'Opening',
                  icon: Icons.open_in_full,
                  onPressed: () => _startPlacingScanShape('opening'),
                ),
                if (_pendingShapeType != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Tap to place $_pendingShapeType',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSampleTray() {
    if (_locations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: Colors.white,
        child: Text(
          'No samples found for this room.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }
    final placedCount = _locations.where((l) => l.isPlaced).length;
    final unplacedCount = _locations.length - placedCount;
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Icon(
                  unplacedCount > 0
                      ? Icons.room_preferences
                      : Icons.check_circle,
                  size: 15,
                  color: unplacedCount > 0
                      ? roomPlanAccent
                      : const Color(0xff16a34a),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Samples · $placedCount of ${_locations.length} placed',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 66,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              scrollDirection: Axis.horizontal,
              itemCount: _locations.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final location = _locations[index];
                return Draggable<String>(
                  data: location.sampleRefId,
                  onDragStarted: () {
                    setState(() {
                      _isDraggingSample = true;
                    });
                  },
                  onDragEnd: (_) {
                    setState(() {
                      _isDraggingSample = false;
                    });
                  },
                  onDraggableCanceled: (_, __) {
                    setState(() {
                      _isDraggingSample = false;
                    });
                  },
                  feedback: Material(
                    color: Colors.transparent,
                    child: _CadSampleMarker(
                      label: location.label,
                      active: true,
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.4,
                    child: _SampleChip(
                      label: location.label,
                      placed: location.isPlaced,
                    ),
                  ),
                  child: _SampleChip(
                    label: location.label,
                    placed: location.isPlaced,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatSurfaceLength(PlanSurfaceSnapshot surface) {
    return _formatFeetInches(surface.length);
  }

  String _surfaceLabel(PlanSurfaceSnapshot? surface) {
    if (surface == null) return '';
    if (surface.kind == 'object') {
      return surface.label.trim().isEmpty ? 'Furniture' : surface.label;
    }
    return surface.kind[0].toUpperCase() + surface.kind.substring(1);
  }
}

class _WallLengthDialog extends StatefulWidget {
  final String initialText;
  final double? Function(String value) parseLength;

  const _WallLengthDialog({
    required this.initialText,
    required this.parseLength,
  });

  @override
  State<_WallLengthDialog> createState() => _WallLengthDialogState();
}

class _WallLengthDialogState extends State<_WallLengthDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(widget.parseLength(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Wall length'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Length',
            hintText: '12\' 5" or 12.4',
            suffixText: 'ft/in',
          ),
          validator: (value) => widget.parseLength(value ?? '') == null
              ? 'Enter feet/inches, for example 12\' 5".'
              : null,
          onFieldSubmitted: (_) => _apply(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: roomPlanAccent),
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _PreviewToolButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _PreviewToolButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: roomPlanAccent,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _PreviewIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _PreviewIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      color: roomPlanAccent,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PreviewGeometry {
  final Offset center;
  final Offset origin;
  final double scale;

  const _PreviewGeometry({
    required this.center,
    required this.origin,
    required this.scale,
  });
}

class _SampleChip extends StatelessWidget {
  final String label;
  final bool placed;

  const _SampleChip({required this.label, this.placed = false});

  @override
  Widget build(BuildContext context) {
    final color = placed ? const Color(0xff16a34a) : roomPlanAccent;
    final background = placed
        ? const Color(0xfff0fdf4)
        : const Color(0xfffff4ea);
    final border = placed ? const Color(0xff86efac) : const Color(0xffffd7b8);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            placed ? Icons.check_circle : Icons.location_on,
            size: 16,
            color: color,
          ),
          if (!placed) ...[
            const SizedBox(width: 4),
            Icon(Icons.drag_indicator, size: 14, color: Colors.orange.shade400),
          ],
          const SizedBox(width: 6),
          Text(
            placed ? label : label,
            style: TextStyle(
              color: placed ? const Color(0xff14532d) : color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SampleMarker extends StatelessWidget {
  final RoomSampleLocation location;
  final VoidCallback onPanStart;

  const _SampleMarker({required this.location, required this.onPanStart});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPanStart(),
      child: _CadSampleMarker(label: location.label),
    );
  }
}

class _CadSampleMarker extends StatelessWidget {
  final String label;
  final bool active;

  const _CadSampleMarker({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = active ? roomPlanAccent : const Color(0xfff97316);
    return SizedBox(
      width: 96,
      height: 40,
      child: CustomPaint(
        painter: _CadSampleMarkerPainter(color: color),
        child: Align(
          alignment: Alignment.topRight,
          child: Container(
            margin: const EdgeInsets.only(top: 1),
            constraints: const BoxConstraints(maxWidth: 68),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: color, width: 0.8),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff111827),
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CadSampleMarkerPainter extends CustomPainter {
  final Color color;

  const _CadSampleMarkerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.35
      ..style = PaintingStyle.stroke;
    const point = Offset(44, 10);
    canvas.drawCircle(point, 5.5, stroke);
    canvas.drawLine(
      point + const Offset(-8, 0),
      point + const Offset(8, 0),
      stroke,
    );
    canvas.drawLine(
      point + const Offset(0, -8),
      point + const Offset(0, 8),
      stroke,
    );
    canvas.drawLine(point + const Offset(5, -5), const Offset(65, 5), stroke);
    canvas.drawCircle(point, 1.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CadSampleMarkerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RoomPreviewPainter extends CustomPainter {
  final ScanResult scanResult;
  final List<PlanSurfaceSnapshot> surfaces;
  final List<RoomSampleLocation> locations;
  final double rotationRadians;
  final int? selectedSurfaceIndex;
  final int? selectedWallActiveEnd;
  _RoomPreviewPainter({
    required this.scanResult,
    required this.surfaces,
    required this.locations,
    required this.rotationRadians,
    this.selectedSurfaceIndex,
    this.selectedWallActiveEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfffbfbfc),
    );
    _drawGrid(canvas, size);
    if (surfaces.isEmpty) return;

    final bounds = _surfacesBounds(surfaces).inflate(0.9);
    final center = bounds.center;
    final scale = math.min(
      size.width / math.max(bounds.width, 1),
      size.height / math.max(bounds.height, 1),
    );
    final origin = Offset(
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    );

    final wallPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;
    for (var i = 0; i < surfaces.length; i++) {
      final surface = surfaces[i];
      final endpoints = surface.endpoints();
      final a = _mapPoint(endpoints.$1, center, origin, scale);
      final b = _mapPoint(endpoints.$2, center, origin, scale);
      if (surface.kind == 'wall') {
        canvas.drawLine(a, b, wallPaint);
        if (selectedSurfaceIndex == i) {
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = roomPlanAccent
              ..strokeWidth = 8
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.square,
          );
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.square,
          );
          _drawWallEndHandles(canvas, a, b);
        }
      } else if (surface.kind == 'object') {
        final points = surface
            .corners()
            .map((point) => _mapPoint(point, center, origin, scale))
            .toList();
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        path.close();
        // Fill with light grey
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xffe8e8e8)
            ..style = PaintingStyle.fill,
        );
        // Dashed border
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.grey.shade600
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke,
        );
        // Diagonal hatch lines
        _drawHatchFill(canvas, path, points, const Color(0xffcccccc));
        if (_isStairsSurface(surface)) {
          _drawStairsTreads(canvas, points);
        }
        // Label
        if (surface.label.isNotEmpty) {
          final minXp = points.map((p) => p.dx).reduce(math.min);
          final maxXp = points.map((p) => p.dx).reduce(math.max);
          final minYp = points.map((p) => p.dy).reduce(math.min);
          final maxYp = points.map((p) => p.dy).reduce(math.max);
          final center = Offset((minXp + maxXp) / 2, (minYp + maxYp) / 2);
          final tp = TextPainter(
            text: TextSpan(
              text: surface.label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
        }
        if (selectedSurfaceIndex == i) {
          canvas.drawPath(
            path,
            Paint()
              ..color = roomPlanAccent
              ..strokeWidth = 2.2
              ..style = PaintingStyle.stroke,
          );
        }
      } else if (surface.kind == 'door') {
        // Door: two short parallel lines (door leaf) + quarter-circle arc
        final dir = b - a;
        final len = dir.distance;
        if (len > 0.01) {
          final norm = dir / len;
          final perp = Offset(-norm.dy, norm.dx);
          final halfLen = len * 0.42;
          final doorWidth = len * 0.08;
          // White gap behind door
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 8
              ..strokeCap = StrokeCap.square,
          );
          // Door frame lines (two short lines at ends)
          final framePaint = Paint()
            ..color = Colors.black
            ..strokeWidth = 1.5;
          canvas.drawLine(
            a - perp * doorWidth,
            a + perp * doorWidth,
            framePaint,
          );
          canvas.drawLine(
            b - perp * doorWidth,
            b + perp * doorWidth,
            framePaint,
          );
          // Door leaf line
          final leafStart = a + norm * halfLen * 0.15;
          final leafEnd = a + norm * halfLen + perp * halfLen * 0.65;
          canvas.drawLine(
            leafStart,
            leafEnd,
            Paint()
              ..color = Colors.black
              ..strokeWidth = 1.2,
          );
          // Arc showing door swing
          final arcCenter = a;
          final arcRadius = halfLen;
          final arcAngle = math.atan2(perp.dy, perp.dx);
          canvas.drawArc(
            Rect.fromCircle(center: arcCenter, radius: arcRadius),
            arcAngle - math.pi * 0.4,
            math.pi * 0.4,
            false,
            Paint()
              ..color = Colors.black.withValues(alpha: 0.5)
              ..strokeWidth = 0.8
              ..style = PaintingStyle.stroke,
          );
        }
        if (selectedSurfaceIndex == i) {
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = roomPlanAccent
              ..strokeWidth = 8
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.square,
          );
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.square,
          );
          _drawWallEndHandles(canvas, a, b);
        }
      } else if (surface.kind == 'window') {
        // Window: parallel lines with fill
        final dir = b - a;
        final len = dir.distance;
        if (len > 0.01) {
          final norm = dir / len;
          final perp = Offset(-norm.dy, norm.dx);
          final halfWidth = len * 0.06;
          // White background
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 10
              ..strokeCap = StrokeCap.round,
          );
          // Two parallel lines
          final winPaint = Paint()
            ..color = Colors.black
            ..strokeWidth = 1.2;
          canvas.drawLine(a + perp * halfWidth, b + perp * halfWidth, winPaint);
          canvas.drawLine(a - perp * halfWidth, b - perp * halfWidth, winPaint);
          // Center line (glass)
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = Colors.blue.shade300
              ..strokeWidth = 0.8,
          );
        }
        if (selectedSurfaceIndex == i) {
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = roomPlanAccent
              ..strokeWidth = 8
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.square,
          );
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.square,
          );
          _drawWallEndHandles(canvas, a, b);
        }
      } else {
        // Opening: dashed line across wall gap
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.square,
        );
        // Draw dashed line
        final dir = b - a;
        final len = dir.distance;
        if (len > 0.01) {
          final norm = dir / len;
          final dashLen = 0.06;
          final gapLen = 0.04;
          double traveled = 0;
          while (traveled < len) {
            final start = a + norm * traveled;
            final end = a + norm * math.min(traveled + dashLen, len);
            canvas.drawLine(
              start,
              end,
              Paint()
                ..color = Colors.black
                ..strokeWidth = 1.2
                ..strokeCap = StrokeCap.round,
            );
            traveled += dashLen + gapLen;
          }
        }
        if (selectedSurfaceIndex == i) {
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = roomPlanAccent
              ..strokeWidth = 8
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.square,
          );
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.square,
          );
          _drawWallEndHandles(canvas, a, b);
        }
      }
    }
  }

  bool _isStairsSurface(PlanSurfaceSnapshot surface) {
    return surface.kind == 'object' &&
        surface.label.trim().toLowerCase() == 'stairs';
  }

  void _drawStairsTreads(Canvas canvas, List<Offset> corners) {
    if (corners.length < 4) return;
    final paint = Paint()
      ..color = Colors.grey.shade800
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.square;
    for (var i = 1; i <= 5; i++) {
      final t = i / 6;
      final left = Offset.lerp(corners[0], corners[3], t);
      final right = Offset.lerp(corners[1], corners[2], t);
      if (left != null && right != null) {
        canvas.drawLine(left, right, paint);
      }
    }
  }

  void _drawHatchFill(
    Canvas canvas,
    Path path,
    List<Offset> corners,
    Color color,
  ) {
    if (corners.length < 4) return;
    // Compute bounding box of the object
    var minX = corners.map((p) => p.dx).reduce(math.min);
    var maxX = corners.map((p) => p.dx).reduce(math.max);
    var minY = corners.map((p) => p.dy).reduce(math.min);
    var maxY = corners.map((p) => p.dy).reduce(math.max);
    // Clip to path and draw diagonal hatch lines
    canvas.save();
    canvas.clipPath(path);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.6;
    final step = 0.12;
    for (var x = minX - (maxY - minY); x < maxX + (maxY - minY); x += step) {
      canvas.drawLine(Offset(x, minY), Offset(x + (maxY - minY), maxY), paint);
    }
    canvas.restore();
  }

  void _drawWallEndHandles(Canvas canvas, Offset a, Offset b) {
    final activeEnd = selectedWallActiveEnd ?? 0;
    final moving = activeEnd == 0 ? a : b;
    final fixed = activeEnd == 0 ? b : a;
    canvas.drawCircle(
      fixed,
      6,
      Paint()
        ..color = Colors.grey.shade500
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(
      moving,
      6,
      Paint()
        ..color = roomPlanAccent
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      moving,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.5;
    for (var x = 0.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  Rect _surfacesBounds(List<PlanSurfaceSnapshot> surfaces) {
    final rawPoints = surfaces.expand((surface) => surface.corners()).toList();
    final rawBounds = _pointsBounds(rawPoints);
    final points = rawPoints
        .map((point) => _rotatePoint(point, rawBounds.center))
        .toList();
    return _pointsBounds(points);
  }

  Rect _pointsBounds(List<Offset> points) {
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _mapPoint(Offset point, Offset center, Offset origin, double scale) {
    final rotated = _rotatePoint(point, center);
    return Offset(
      origin.dx + rotated.dx * scale,
      origin.dy + rotated.dy * scale,
    );
  }

  Offset _rotatePoint(Offset point, Offset center) {
    final delta = point - center;
    final cosA = math.cos(rotationRadians);
    final sinA = math.sin(rotationRadians);
    return center +
        Offset(
          delta.dx * cosA - delta.dy * sinA,
          delta.dx * sinA + delta.dy * cosA,
        );
  }

  @override
  bool shouldRepaint(covariant _RoomPreviewPainter oldDelegate) {
    return oldDelegate.scanResult != scanResult ||
        oldDelegate.surfaces != surfaces ||
        oldDelegate.locations != locations ||
        oldDelegate.rotationRadians != rotationRadians ||
        oldDelegate.selectedSurfaceIndex != selectedSurfaceIndex ||
        oldDelegate.selectedWallActiveEnd != selectedWallActiveEnd;
  }
}
