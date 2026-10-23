import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ios_roomplan/src/floor_plan/services/floor_plan_pdf_service.dart';
import 'package:ios_roomplan/src/floor_plan/services/merged_floor_plan_layout_service.dart';
import '../editor_colors.dart';

const _connectorWallLabel = 'Generated Connector Wall';
const _maxConnectorWallLength = 0.75;

class MergedFloorPlanEditorResult {
  final File pdfFile;

  const MergedFloorPlanEditorResult({required this.pdfFile});
}

class MergedFloorPlanEditorPage extends StatefulWidget {
  final String title;
  final String? logoImageDataUri;
  final List<NamedScanResult> scans;
  final List<MergedFloorPlanLayoutEntry> initialLayout;
  final double initialNorthRotation;

  const MergedFloorPlanEditorPage({
    super.key,
    required this.title,
    this.logoImageDataUri,
    required this.scans,
    this.initialLayout = const [],
    this.initialNorthRotation = 0,
  });

  @override
  State<MergedFloorPlanEditorPage> createState() =>
      _MergedFloorPlanEditorPageState();
}

class _MergedFloorPlanEditorPageState extends State<MergedFloorPlanEditorPage> {
  late final List<_EditableRoom> _rooms;
  int _selectedIndex = 0;
  double _canvasZoom = 1;
  Offset _canvasPanOffset = Offset.zero;
  bool _isPanningCanvas = false;
  bool _isSaving = false;
  bool _showMeasurements = true;
  double _northRotationRadians = 0;
  _WallSelection? _selectedWall;
  // Letter placement (A, B, C, D)
  final List<_PlacedLetter> _placedLetters = [];
  int _draggingLetterIndex = -1;

  @override
  void initState() {
    super.initState();
    _rooms = _initialRooms(widget.scans);
    _northRotationRadians = widget.initialNorthRotation;
    final firstPlacedIndex = _rooms.indexWhere((room) => room.isPlaced);
    _selectedIndex = firstPlacedIndex >= 0 ? firstPlacedIndex : 0;
  }

  List<_EditableRoom> _initialRooms(List<NamedScanResult> scans) {
    final rooms = <_EditableRoom>[];
    final hasSavedLayout = widget.initialLayout.isNotEmpty;
    final savedLayoutByPath = {
      for (final item in widget.initialLayout) item.roomScanPath: item,
    };
    for (var i = 0; i < scans.length; i++) {
      final savedLayout = savedLayoutByPath[scans[i].pdfFile.path];
      rooms.add(
        _EditableRoom(
          scan: scans[i],
          surfaces:
              scans[i].surfaceSnapshots ??
              FloorPlanPdfService.surfaceSnapshots(scans[i].scanResult),
          offset: savedLayout == null
              ? Offset((i % 2) * 4.8, (i ~/ 2) * 3.8)
              : Offset(savedLayout.offsetX, savedLayout.offsetY),
          rotation: savedLayout?.rotation ?? scans[i].sampleRotationRadians,
          isPlaced: !hasSavedLayout || savedLayout != null,
        ),
      );
    }
    return rooms;
  }

  Future<void> _saveMergedPlan() async {
    if (_isSaving) return;
    final unplacedCount = _rooms.where((room) => !room.isPlaced).length;
    if (unplacedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Drag $unplacedCount new room${unplacedCount == 1 ? '' : 's'} from the bottom tray onto the floor plan before saving.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _isSaving = true;
    });

    try {
      final arranged = _rooms
          .where((room) => room.isPlaced)
          .map(
            (room) => ArrangedScanResult(
              scan: room.scan,
              offsetX: room.offset.dx,
              offsetY: room.offset.dy,
              rotation: room.rotation,
              surfaces: room.surfaces,
              sampleLocations: room.scan.sampleLocations,
              sampleRotationRadians: 0,
            ),
          )
          .toList();
      final logoImageDataUri = widget.logoImageDataUri;

      // Pass world-space coordinates directly; PDF uses the same map() as rooms
      final letterPositions = _placedLetters.map((letter) {
        return PlacedLetterPosition(
          letter: letter.letter,
          x: letter.position.dx,
          y: letter.position.dy,
        );
      }).toList();

      final file = await FloorPlanPdfService.createArrangedMerged2DFloorPlan(
        arranged,
        title: widget.title,
        fileName: '${widget.title}_merged_floor_plan',
        logoImageDataUri: logoImageDataUri,
        northRotationRadians: _northRotationRadians,
        placedLetters: letterPositions.isNotEmpty ? letterPositions : null,
        showMeasurements: _showMeasurements,
      );
      await MergedFloorPlanLayoutService.saveForPdf(
        pdfFile: file,
        rooms: _rooms
            .where((room) => room.isPlaced)
            .map(
              (room) => MergedFloorPlanLayoutEntry(
                roomScanPath: room.scan.pdfFile.path,
                offsetX: room.offset.dx,
                offsetY: room.offset.dy,
                rotation: room.rotation,
              ),
            )
            .toList(),
        northRotationRadians: _northRotationRadians,
      );

      if (!mounted) return;
      Navigator.of(context).pop(MergedFloorPlanEditorResult(pdfFile: file));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save merged floor plan: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _rotateNorth(double delta) {
    setState(() {
      _northRotationRadians = (_northRotationRadians + delta) % (math.pi * 2);
      if (_northRotationRadians < 0) _northRotationRadians += math.pi * 2;
    });
  }

  void _resetNorth() {
    setState(() {
      _northRotationRadians = 0;
    });
  }

  // Letter placement — tap canvas to place at that position
  // Stores which letter is pending placement
  String? _pendingLetter;

  void _addLetter(String letter) {
    setState(() {
      _pendingLetter = letter;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tap anywhere on the floor plan to place letter $letter'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _placeLetterAtPosition(Offset canvasPoint) {
    if (_pendingLetter == null) return;
    setState(() {
      _placedLetters.removeWhere((l) => l.letter == _pendingLetter);
      _placedLetters.add(
        _PlacedLetter(letter: _pendingLetter!, position: canvasPoint),
      );
      _pendingLetter = null;
    });
  }

  void _resetLetters() {
    setState(() {
      _placedLetters.clear();
    });
  }

  void _rotateSelected(double delta) {
    if (!_rooms[_selectedIndex].isPlaced) return;
    setState(() {
      final room = _rooms[_selectedIndex];
      _rooms[_selectedIndex] = room.copyWith(rotation: room.rotation + delta);
    });
  }

  void _nudgeSelected(Offset delta) {
    if (!_rooms[_selectedIndex].isPlaced) return;
    setState(() {
      final room = _rooms[_selectedIndex];
      _rooms[_selectedIndex] = room.copyWith(offset: room.offset + delta);
    });
  }

  void _snapSelectedRoomToPlan() {
    if (!_rooms[_selectedIndex].isPlaced) return;
    setState(() {
      final room = _rooms[_selectedIndex];
      final wallAngles = room.surfaces
          .where((surface) => surface.kind == 'wall')
          .map((surface) => _normalizeAngle(surface.angle + room.rotation))
          .toList();
      if (wallAngles.isEmpty) return;
      final dominant = wallAngles.reduce(
        (a, b) => _axisError(a) <= _axisError(b) ? a : b,
      );
      _rooms[_selectedIndex] = room.copyWith(
        rotation: room.rotation - _nearestRightAngleDelta(dominant),
      );
    });
  }

  void _cleanMergedPlan() {
    setState(() {
      for (var i = 0; i < _rooms.length; i++) {
        if (!_rooms[i].isPlaced) continue;
        _rooms[i] = _snapWallCornersInRoom(_straightenRoom(_rooms[i]));
      }
      _addMissingConnectorWalls();
      _selectedWall = null;
    });
  }

  _EditableRoom _snapWallCornersInRoom(_EditableRoom room) {
    return room.copyWith(surfaces: _snapWallSurfaceCorners(room.surfaces));
  }

  List<PlanSurfaceSnapshot> _snapWallSurfaceCorners(
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

  _EditableRoom _straightenRoom(_EditableRoom room) {
    final wallAngles = room.surfaces
        .where((surface) => surface.kind == 'wall')
        .map((surface) => _normalizeAngle(surface.angle + room.rotation))
        .toList();
    if (wallAngles.isEmpty) return room;

    final dominant = wallAngles.reduce(
      (a, b) => _axisError(a) <= _axisError(b) ? a : b,
    );
    final rotation = room.rotation - _nearestRightAngleDelta(dominant);
    final surfaces = room.surfaces.map((surface) {
      if (surface.kind != 'wall') return surface;
      final worldAngle = surface.angle + rotation;
      return surface.copyWith(
        angle: surface.angle - _nearestRightAngleDelta(worldAngle),
      );
    }).toList();
    return room.copyWith(rotation: rotation, surfaces: surfaces);
  }

  void _addMissingConnectorWalls() {
    final endpoints = <_WallEndpoint>[];
    for (var roomIndex = 0; roomIndex < _rooms.length; roomIndex++) {
      final room = _rooms[roomIndex];
      if (!room.isPlaced) continue;
      for (
        var surfaceIndex = 0;
        surfaceIndex < room.surfaces.length;
        surfaceIndex++
      ) {
        final surface = room.surfaces[surfaceIndex];
        if (surface.kind != 'wall' || surface.label == _connectorWallLabel) {
          continue;
        }
        final wallEndpoints = surface.endpoints();
        endpoints.add(
          _WallEndpoint(
            roomIndex: roomIndex,
            point: room.map(wallEndpoints.$1),
          ),
        );
        endpoints.add(
          _WallEndpoint(
            roomIndex: roomIndex,
            point: room.map(wallEndpoints.$2),
          ),
        );
      }
    }

    final connectorsByRoom = <int, List<PlanSurfaceSnapshot>>{};
    for (var i = 0; i < endpoints.length; i++) {
      for (var j = i + 1; j < endpoints.length; j++) {
        final a = endpoints[i];
        final b = endpoints[j];
        if (a.roomIndex == b.roomIndex) continue;

        final delta = b.point - a.point;
        final distance = delta.distance;
        if (distance < 0.12 || distance > _maxConnectorWallLength) continue;

        final connectorAngle = math.atan2(delta.dy, delta.dx);
        if (_axisError(connectorAngle) > math.pi / 18) continue;

        final room = _rooms[a.roomIndex];
        final localCenter = room.unmap(
          Offset((a.point.dx + b.point.dx) / 2, (a.point.dy + b.point.dy) / 2),
        );
        final localAngle = _nearestRightAngle(connectorAngle) - room.rotation;
        final connector = PlanSurfaceSnapshot(
          kind: 'wall',
          label: _connectorWallLabel,
          centerX: localCenter.dx,
          centerY: localCenter.dy,
          angle: localAngle,
          length: distance,
          depth: 0.05,
        );

        final exists = (connectorsByRoom[a.roomIndex] ?? const []).any(
          (item) => _connectorMatches(item, connector),
        );
        if (!exists) {
          connectorsByRoom.putIfAbsent(a.roomIndex, () => []).add(connector);
        }
      }
    }

    for (final entry in connectorsByRoom.entries) {
      final room = _rooms[entry.key];
      final existingManual = room.surfaces
          .where((surface) => surface.label != _connectorWallLabel)
          .toList();
      _rooms[entry.key] = room.copyWith(
        surfaces: [...existingManual, ...entry.value],
      );
    }
  }

  // ── Auto-snap: align wall endpoints when rooms are close ──
  static const double _snapThreshold = 0.2; // metres

  /// After the user finishes dragging a room, find the closest pair of
  /// wall endpoints (one from the dragged room, one from any other placed
  /// room) and shift the dragged room so they align perfectly.
  bool _isRoomSnapSurface(PlanSurfaceSnapshot surface) {
    return surface.kind == 'wall' ||
        surface.kind == 'door' ||
        surface.kind == 'opening';
  }

  List<Offset> _roomSnapAnchors(
    _EditableRoom room,
    PlanSurfaceSnapshot surface,
  ) {
    final (a, b) = surface.endpoints();
    final anchors = <Offset>[room.map(a), room.map(b)];
    if (surface.kind == 'door' || surface.kind == 'opening') {
      anchors.add(room.map(Offset(surface.centerX, surface.centerY)));
    }
    return anchors;
  }

  void _autoSnapRoom(int draggedIndex) {
    final dragged = _rooms[draggedIndex];
    if (!dragged.isPlaced) return;

    final otherEndpoints = <({int roomIndex, Offset point})>[];
    final draggedEndpoints = <Offset>[];

    for (var ri = 0; ri < _rooms.length; ri++) {
      final room = _rooms[ri];
      if (!room.isPlaced) continue;
      for (final surface in room.surfaces) {
        if (!_isRoomSnapSurface(surface)) continue;
        final anchors = _roomSnapAnchors(room, surface);
        if (ri == draggedIndex) {
          draggedEndpoints.addAll(anchors);
        } else {
          otherEndpoints.addAll(
            anchors.map((point) => (roomIndex: ri, point: point)),
          );
        }
      }
    }

    if (draggedEndpoints.isEmpty || otherEndpoints.isEmpty) return;
    // Find the closest pair
    double bestDist = _snapThreshold;
    Offset? bestDraggedPt;
    Offset? bestOtherPt;

    for (final dp in draggedEndpoints) {
      for (final other in otherEndpoints) {
        final d = (dp - other.point).distance;
        if (d < bestDist) {
          bestDist = d;
          bestDraggedPt = dp;
          bestOtherPt = other.point;
        }
      }
    }

    if (bestDraggedPt == null || bestOtherPt == null) return;

    // Shift the dragged room so the two endpoints align
    final shift = bestOtherPt - bestDraggedPt;
    _rooms[draggedIndex] = dragged.copyWith(offset: dragged.offset + shift);
  }

  void _deleteSelectedWall() {
    final selection = _selectedWall;
    if (selection == null) return;
    if (selection.roomIndex < 0 || selection.roomIndex >= _rooms.length) return;
    final room = _rooms[selection.roomIndex];
    if (selection.wallIndex < 0 ||
        selection.wallIndex >= room.surfaces.length) {
      return;
    }
    if (room.surfaces[selection.wallIndex].kind != 'wall') return;

    setState(() {
      final surfaces = List<PlanSurfaceSnapshot>.from(room.surfaces)
        ..removeAt(selection.wallIndex);
      _rooms[selection.roomIndex] = room.copyWith(surfaces: surfaces);
      _selectedWall = null;
    });
  }

  void _resetLayout() {
    setState(() {
      _rooms
        ..clear()
        ..addAll(_initialRooms(widget.scans));
      final firstPlacedIndex = _rooms.indexWhere((room) => room.isPlaced);
      _selectedIndex = firstPlacedIndex >= 0 ? firstPlacedIndex : 0;
      _canvasZoom = 1;
      _canvasPanOffset = Offset.zero;
      _selectedWall = null;
    });
  }

  void _zoomCanvas(double delta) {
    setState(() {
      _canvasZoom = (_canvasZoom + delta).clamp(0.6, 3.5);
    });
  }

  void _resetCanvasView() {
    setState(() {
      _canvasZoom = 1;
      _canvasPanOffset = Offset.zero;
    });
  }

  void _placeRoomOnCanvas(int roomIndex, Offset localPosition, Size size) {
    final scale = _canvasScale(size);
    final origin = _canvasOrigin(size, scale);
    final worldPoint = Offset(
      (localPosition.dx - origin.dx) / scale,
      (localPosition.dy - origin.dy) / scale,
    );
    setState(() {
      final room = _rooms[roomIndex];
      _rooms[roomIndex] = room.copyWith(
        offset: _offsetForRoomCenter(room, worldPoint),
        isPlaced: true,
      );
      _selectedIndex = roomIndex;
    });
    // Auto-snap: connect to nearby wall endpoints
    _autoSnapRoom(roomIndex);
    setState(() {});
  }

  Offset _offsetForRoomCenter(_EditableRoom room, Offset worldCenter) {
    return worldCenter - room.localBounds.center;
  }

  Widget _buildEditorToolbar(_EditableRoom selectedRoom) {
    final zoomPercent = (_canvasZoom * 100).round();
    final northDeg = (_northRotationRadians * 180 / math.pi).round() % 360;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Instruction
          Row(
            children: [
              Icon(Icons.touch_app, color: roomPlanAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap a room to select, then drag or use tools below.',
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Selection pill + reset
          Row(
            children: [
              Expanded(
                child: _SelectionPill(
                  icon: Icons.meeting_room,
                  label: selectedRoom.scan.name,
                  detail: _selectedWall == null
                      ? 'Room selected'
                      : 'Wall selected',
                  color: roomPlanAccent,
                ),
              ),
              const SizedBox(width: 8),
              _IconToolButton(
                tooltip: 'Reset layout',
                icon: Icons.restart_alt,
                onPressed: _resetLayout,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // View tools
          _ToolSection(
            title: 'View',
            children: [
              _IconToolButton(
                tooltip: 'Zoom out',
                icon: Icons.zoom_out,
                onPressed: () => _zoomCanvas(-0.15),
              ),
              _IconToolButton(
                tooltip: 'Zoom in',
                icon: Icons.zoom_in,
                onPressed: () => _zoomCanvas(0.15),
              ),
              _TextToolButton(
                label: 'Reset $zoomPercent%',
                icon: Icons.center_focus_strong,
                onPressed: _resetCanvasView,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Measurements',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _showMeasurements,
                onChanged: (value) => setState(() => _showMeasurements = value),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // North tools
          _ToolSection(
            title: 'North $northDeg\u00B0',
            children: [
              _IconToolButton(
                tooltip: 'Rotate left',
                icon: Icons.rotate_left,
                onPressed: () => _rotateNorth(-math.pi / 12),
              ),
              _IconToolButton(
                tooltip: 'Rotate right',
                icon: Icons.rotate_right,
                onPressed: () => _rotateNorth(math.pi / 12),
              ),
              _TextToolButton(
                label: 'Reset',
                icon: Icons.explore_off_outlined,
                onPressed: _resetNorth,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Room tools
          _ToolSection(
            title: 'Room',
            children: [
              _IconToolButton(
                tooltip: 'Nudge left',
                icon: Icons.keyboard_arrow_left,
                onPressed: () => _nudgeSelected(const Offset(-0.1, 0)),
              ),
              _IconToolButton(
                tooltip: 'Nudge right',
                icon: Icons.keyboard_arrow_right,
                onPressed: () => _nudgeSelected(const Offset(0.1, 0)),
              ),
              _IconToolButton(
                tooltip: 'Rotate left',
                icon: Icons.rotate_left,
                onPressed: () => _rotateSelected(-math.pi / 18),
              ),
              _IconToolButton(
                tooltip: 'Rotate right',
                icon: Icons.rotate_right,
                onPressed: () => _rotateSelected(math.pi / 18),
              ),
              _TextToolButton(
                label: 'Snap',
                icon: Icons.grid_4x4,
                onPressed: _snapSelectedRoomToPlan,
              ),
              _TextToolButton(
                label: 'Clean',
                icon: Icons.auto_fix_high,
                onPressed: _cleanMergedPlan,
              ),
              _TextToolButton(
                label: 'Delete wall',
                icon: Icons.delete_outline,
                onPressed: _selectedWall == null ? null : _deleteSelectedWall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Letters
          _ToolSection(
            title: 'Letters',
            children: [
              _IconToolButton(
                tooltip: 'Place A',
                icon: Icons.abc,
                label: 'A',
                onPressed: () => _addLetter('A'),
              ),
              _IconToolButton(
                tooltip: 'Place B',
                icon: Icons.abc,
                label: 'B',
                onPressed: () => _addLetter('B'),
              ),
              _IconToolButton(
                tooltip: 'Place C',
                icon: Icons.abc,
                label: 'C',
                onPressed: () => _addLetter('C'),
              ),
              _IconToolButton(
                tooltip: 'Place D',
                icon: Icons.abc,
                label: 'D',
                onPressed: () => _addLetter('D'),
              ),
              if (_placedLetters.isNotEmpty)
                _TextToolButton(
                  label: 'Clear',
                  icon: Icons.delete_outline,
                  onPressed: _resetLetters,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnplacedRoomsHint() {
    final count = _rooms.where((room) => !room.isPlaced).length;
    if (count == 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xfffff4ea),
      child: Row(
        children: [
          Icon(Icons.open_with, color: Colors.orange.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count new room${count == 1 ? '' : 's'} need placement. Drag the orange room chip from the bottom tray onto the floor plan, then save.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoom = _rooms[_selectedIndex];
    return Scaffold(
      backgroundColor: const Color(0xfff6f7f9),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: appColor,
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveMergedPlan,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildEditorToolbar(selectedRoom),
            _buildUnplacedRoomsHint(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = Size(
                    math.max(constraints.maxWidth - 24, 1),
                    math.max(constraints.maxHeight - 24, 1),
                  );
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: DragTarget<int>(
                          onAcceptWithDetails: (details) {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            _placeRoomOnCanvas(
                              details.data,
                              box.globalToLocal(details.offset),
                              canvasSize,
                            );
                          },
                          builder: (context, candidateData, rejectedData) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) {
                                // Place shape if pending
                                // Place letter if pending
                                if (_pendingLetter != null) {
                                  final scale = _canvasScale(canvasSize);
                                  final origin = _canvasOrigin(
                                    canvasSize,
                                    scale,
                                  );
                                  final worldPoint = Offset(
                                    (details.localPosition.dx - origin.dx) /
                                        scale,
                                    (details.localPosition.dy - origin.dy) /
                                        scale,
                                  );
                                  _placeLetterAtPosition(worldPoint);
                                  return;
                                }
                                final wallHit = _wallHitTest(
                                  details.localPosition,
                                  canvasSize,
                                );
                                if (wallHit != null) {
                                  setState(() {
                                    _selectedIndex = wallHit.roomIndex;
                                    _selectedWall = wallHit;
                                  });
                                  return;
                                }
                                final hit = _hitTest(
                                  details.localPosition,
                                  canvasSize,
                                );
                                if (hit != null) {
                                  setState(() {
                                    _selectedIndex = hit.roomIndex;
                                    _selectedWall = null;
                                  });
                                } else {
                                  setState(() {
                                    _selectedWall = null;
                                  });
                                }
                              },
                              onPanStart: (details) {
                                final letterIdx = _letterHitTest(
                                  details.localPosition,
                                  canvasSize,
                                );
                                if (letterIdx >= 0) {
                                  setState(() {
                                    _draggingLetterIndex = letterIdx;
                                    _isPanningCanvas = false;
                                  });
                                  return;
                                }
                                final hit = _hitTest(
                                  details.localPosition,
                                  canvasSize,
                                );
                                if (hit != null) {
                                  setState(() {
                                    _selectedIndex = hit.roomIndex;
                                    _selectedWall = null;
                                    _isPanningCanvas = false;
                                  });
                                } else {
                                  setState(() {
                                    _selectedWall = null;
                                    _isPanningCanvas = true;
                                  });
                                }
                              },
                              onPanUpdate: (details) {
                                if (_draggingLetterIndex >= 0) {
                                  final scale = _canvasScale(canvasSize);
                                  final origin = _canvasOrigin(
                                    canvasSize,
                                    scale,
                                  );
                                  setState(() {
                                    final letter =
                                        _placedLetters[_draggingLetterIndex];
                                    _placedLetters[_draggingLetterIndex] =
                                        _PlacedLetter(
                                          letter: letter.letter,
                                          position: Offset(
                                            (details.localPosition.dx -
                                                    origin.dx) /
                                                scale,
                                            (details.localPosition.dy -
                                                    origin.dy) /
                                                scale,
                                          ),
                                        );
                                  });
                                  return;
                                }
                                if (_isPanningCanvas) {
                                  setState(() {
                                    _canvasPanOffset += details.delta;
                                  });
                                  return;
                                }
                                if (!_rooms[_selectedIndex].isPlaced) return;
                                final scale = _canvasScale(canvasSize);
                                setState(() {
                                  final room = _rooms[_selectedIndex];
                                  _rooms[_selectedIndex] = room.copyWith(
                                    offset:
                                        room.offset +
                                        Offset(
                                          details.delta.dx / scale,
                                          details.delta.dy / scale,
                                        ),
                                  );
                                });
                              },
                              onPanEnd: (_) {
                                // Auto-snap dragged room to nearby wall endpoints
                                _autoSnapRoom(_selectedIndex);
                                setState(() {
                                  _draggingLetterIndex = -1;
                                  _isPanningCanvas = false;
                                });
                              },
                              onPanCancel: () {
                                setState(() {
                                  _draggingLetterIndex = -1;
                                  _isPanningCanvas = false;
                                });
                              },
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: _MergedFloorPlanPainter(
                                  rooms: _rooms,
                                  selectedIndex: _selectedIndex,
                                  isDropActive: candidateData.isNotEmpty,
                                  northRotationRadians: _northRotationRadians,
                                  zoom: _canvasZoom,
                                  panOffset: _canvasPanOffset,
                                  placedLetters: _placedLetters,
                                  selectedWall: _selectedWall,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              height: 74,
              child: ListView.separated(
                padding: const EdgeInsets.all(10),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final selected = index == _selectedIndex;
                  final room = _rooms[index];
                  if (!room.isPlaced) {
                    return Draggable<int>(
                      data: index,
                      feedback: Material(
                        color: Colors.transparent,
                        child: _RoomTrayChip(
                          index: index,
                          label: room.scan.name,
                          selected: false,
                          placed: false,
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: _RoomTrayChip(
                          index: index,
                          label: room.scan.name,
                          selected: false,
                          placed: false,
                        ),
                      ),
                      child: _RoomTrayChip(
                        index: index,
                        label: room.scan.name,
                        selected: false,
                        placed: false,
                      ),
                    );
                  }
                  return ChoiceChip(
                    selected: selected,
                    avatar: CircleAvatar(
                      backgroundColor: selected ? Colors.white : roomPlanAccent,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: selected ? roomPlanAccent : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    label: Text(
                      _rooms[index].scan.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: _rooms.length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Returns letter index if tapped on a letter, otherwise -1
  int _letterHitTest(Offset point, Size size) {
    final scale = _canvasScale(size);
    final origin = _canvasOrigin(size, scale);
    for (var i = _placedLetters.length - 1; i >= 0; i--) {
      final pos = Offset(
        origin.dx + _placedLetters[i].position.dx * scale,
        origin.dy + _placedLetters[i].position.dy * scale,
      );
      if ((point - pos).distance < 18) return i;
    }
    return -1;
  }

  _WallSelection? _wallHitTest(Offset point, Size size) {
    final scale = _canvasScale(size);
    final origin = _canvasOrigin(size, scale);
    const hitPadding = 10.0;

    for (var roomIndex = _rooms.length - 1; roomIndex >= 0; roomIndex--) {
      final room = _rooms[roomIndex];
      if (!room.isPlaced) continue;
      for (
        var wallIndex = room.surfaces.length - 1;
        wallIndex >= 0;
        wallIndex--
      ) {
        final surface = room.surfaces[wallIndex];
        if (surface.kind != 'wall') continue;
        final endpoints = surface.endpoints();
        final a = _mapCanvasPoint(room.map(endpoints.$1), origin, scale);
        final b = _mapCanvasPoint(room.map(endpoints.$2), origin, scale);
        if (_distanceToSegment(point, a, b) <= hitPadding) {
          return _WallSelection(roomIndex: roomIndex, wallIndex: wallIndex);
        }
      }
    }
    return null;
  }

  Offset _mapCanvasPoint(Offset point, Offset origin, double scale) {
    return Offset(origin.dx + point.dx * scale, origin.dy + point.dy * scale);
  }

  _RoomHit? _hitTest(Offset point, Size size) {
    final scale = _canvasScale(size);
    final origin = _canvasOrigin(size, scale);
    for (var i = _rooms.length - 1; i >= 0; i--) {
      if (!_rooms[i].isPlaced) continue;
      final bounds = _rooms[i].bounds;
      final mappedBounds = Rect.fromLTRB(
        origin.dx + bounds.left * scale,
        origin.dy + bounds.top * scale,
        origin.dx + bounds.right * scale,
        origin.dy + bounds.bottom * scale,
      ).inflate(12);
      if (mappedBounds.contains(point)) {
        return _RoomHit(i);
      }
    }
    return null;
  }

  double _canvasScale(Size size) {
    final bounds = _roomsBounds(_rooms).inflate(1.2);
    final baseScale = math.min(
      size.width / math.max(bounds.width, 1),
      size.height / math.max(bounds.height, 1),
    );
    return baseScale * _canvasZoom;
  }

  Offset _canvasOrigin(Size size, double scale) {
    final bounds = _roomsBounds(_rooms).inflate(1.2);
    return Offset(
          (size.width - bounds.width * scale) / 2 - bounds.left * scale,
          (size.height - bounds.height * scale) / 2 - bounds.top * scale,
        ) +
        _canvasPanOffset;
  }
}

class _SelectionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final Color color;

  const _SelectionPill({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomTrayChip extends StatelessWidget {
  final int index;
  final String label;
  final bool selected;
  final bool placed;

  const _RoomTrayChip({
    required this.index,
    required this.label,
    required this.selected,
    required this.placed,
  });

  @override
  Widget build(BuildContext context) {
    final color = placed ? roomPlanAccent : Colors.orange.shade700;
    return Container(
      height: 42,
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.16)
            : placed
            ? Colors.white
            : const Color(0xfffff4ea),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? color : color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: color,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              placed ? label : '$label - drag to add',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _MergedFloorPlanPainter extends CustomPainter {
  final List<_EditableRoom> rooms;
  final int selectedIndex;
  final bool isDropActive;
  final double northRotationRadians;
  final double zoom;
  final Offset panOffset;
  final List<_PlacedLetter> placedLetters;
  final _WallSelection? selectedWall;

  _MergedFloorPlanPainter({
    required this.rooms,
    required this.selectedIndex,
    this.isDropActive = false,
    this.northRotationRadians = 0,
    this.zoom = 1,
    this.panOffset = Offset.zero,
    this.placedLetters = const [],
    this.selectedWall,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = _roomsBounds(rooms).inflate(1.2);
    final baseScale = math.min(
      size.width / math.max(bounds.width, 1),
      size.height / math.max(bounds.height, 1),
    );
    final scale = baseScale * zoom;
    final origin =
        Offset(
          (size.width - bounds.width * scale) / 2 - bounds.left * scale,
          (size.height - bounds.height * scale) / 2 - bounds.top * scale,
        ) +
        panOffset;

    _drawGrid(canvas, size);
    _drawNorthArrow(canvas, size);
    if (isDropActive) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = roomPlanAccent.withValues(alpha: 0.07),
      );
    }
    for (var i = 0; i < rooms.length; i++) {
      if (!rooms[i].isPlaced) continue;
      _drawRoom(canvas, rooms[i], i, i == selectedIndex, origin, scale, size);
    }
    // Draw placed letters
    for (final letter in placedLetters) {
      _drawLetter(canvas, letter, origin, scale);
    }
  }

  void _drawLetter(
    Canvas canvas,
    _PlacedLetter letter,
    Offset origin,
    double scale,
  ) {
    final pos = Offset(
      origin.dx + letter.position.dx * scale,
      origin.dy + letter.position.dy * scale,
    );
    // Fixed screen-pixel size, not scaled with room geometry
    const double radius = 14;
    // Background circle
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = const Color(0xff1a1a2e)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    // Letter text
    final textPainter = TextPainter(
      text: TextSpan(
        text: letter.letter,
        style: const TextStyle(
          color: Color(0xff1a1a2e),
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      pos - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawNorthArrow(Canvas canvas, Size size) {
    // Compass at bottom-left of canvas
    final cx = 42.0;
    final cy = size.height - 60.0;
    final compassScale = 0.55;

    final fill = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.square;

    void triangle(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, fill);
    }

    final rawNorth = Offset(0, -24 * compassScale);
    final rawSouth = Offset(0, 24 * compassScale);
    final rotatedNorth = _rotateScreen(rawNorth, northRotationRadians);
    final rotatedSouth = _rotateScreen(rawSouth, northRotationRadians);

    // North triangle
    final northTip = Offset(cx + rotatedNorth.dx, cy + rotatedNorth.dy);
    final northBaseLeft = Offset(
      cx +
          rotatedSouth.dx * 0.15 -
          rotatedNorth.dx * 0.35 +
          rotatedNorth.dx * 0.5,
      cy +
          rotatedSouth.dy * 0.15 -
          rotatedNorth.dy * 0.35 +
          rotatedNorth.dy * 0.5,
    );
    final northBaseRight = Offset(
      cx -
          rotatedSouth.dx * 0.15 +
          rotatedNorth.dx * 0.35 +
          rotatedNorth.dx * 0.5,
      cy -
          rotatedSouth.dy * 0.15 +
          rotatedNorth.dy * 0.35 +
          rotatedNorth.dy * 0.5,
    );
    triangle([northBaseLeft, northTip, northBaseRight]);

    // South triangle (lighter)
    final southPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.fill;
    final southTip = Offset(cx + rotatedSouth.dx, cy + rotatedSouth.dy);
    final southBaseLeft = Offset(
      cx +
          rotatedNorth.dx * 0.15 -
          rotatedSouth.dx * 0.35 +
          rotatedSouth.dx * 0.5,
      cy +
          rotatedNorth.dy * 0.15 -
          rotatedSouth.dy * 0.35 +
          rotatedSouth.dy * 0.5,
    );
    final southBaseRight = Offset(
      cx -
          rotatedNorth.dx * 0.15 +
          rotatedSouth.dx * 0.35 +
          rotatedSouth.dx * 0.5,
      cy -
          rotatedNorth.dy * 0.15 +
          rotatedSouth.dy * 0.35 +
          rotatedSouth.dy * 0.5,
    );
    final southPath = Path()
      ..moveTo(southBaseLeft.dx, southBaseLeft.dy)
      ..lineTo(southTip.dx, southTip.dy)
      ..lineTo(southBaseRight.dx, southBaseRight.dy)
      ..close();
    canvas.drawPath(southPath, southPaint);

    // Center line
    canvas.drawLine(
      Offset(cx + rotatedNorth.dx * 0.5, cy + rotatedNorth.dy * 0.5),
      Offset(cx + rotatedSouth.dx * 0.5, cy + rotatedSouth.dy * 0.5),
      line,
    );

    // N label
    final labelOffset = _rotateScreen(
      Offset(0, -34 * compassScale),
      northRotationRadians,
    );
    final labelCenter = Offset(cx + labelOffset.dx, cy + labelOffset.dy);
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      labelCenter - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  Offset _rotateScreen(Offset point, double radians) {
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    return Offset(
      point.dx * cosA + point.dy * sinA,
      -point.dx * sinA + point.dy * cosA,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfffbfbfc),
    );
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

  void _drawRoom(
    Canvas canvas,
    _EditableRoom room,
    int roomIndex,
    bool selected,
    Offset origin,
    double scale,
    Size size,
  ) {
    final highlight = Paint()
      ..color = (selected ? Colors.blue : Colors.transparent).withValues(
        alpha: 0.12,
      )
      ..style = PaintingStyle.fill;
    final bounds = room.bounds;
    canvas.drawRect(
      Rect.fromLTRB(
        origin.dx + bounds.left * scale,
        origin.dy + bounds.top * scale,
        origin.dx + bounds.right * scale,
        origin.dy + bounds.bottom * scale,
      ),
      highlight,
    );
    if (selected) {
      final selectedRect = Rect.fromLTRB(
        origin.dx + bounds.left * scale,
        origin.dy + bounds.top * scale,
        origin.dx + bounds.right * scale,
        origin.dy + bounds.bottom * scale,
      ).inflate(10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(selectedRect, const Radius.circular(6)),
        Paint()
          ..color = Colors.blue.shade700
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    final wallPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = selected ? 5 : 4
      ..strokeCap = StrokeCap.square;
    final selectedWallPaint = Paint()
      ..color = Colors.orange.shade700
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.square;
    final featurePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.2;
    final objectPaint = Paint()
      ..color = Colors.grey.shade700
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (
      var surfaceIndex = 0;
      surfaceIndex < room.surfaces.length;
      surfaceIndex++
    ) {
      final surface = room.surfaces[surfaceIndex];
      final endpoints = surface.endpoints();
      final a = _mapPoint(room.map(endpoints.$1), origin, scale);
      final b = _mapPoint(room.map(endpoints.$2), origin, scale);
      if (surface.kind == 'wall') {
        final isSelectedWall =
            selectedWall?.roomIndex == roomIndex &&
            selectedWall?.wallIndex == surfaceIndex;
        canvas.drawLine(a, b, isSelectedWall ? selectedWallPaint : wallPaint);
      } else if (surface.kind == 'object') {
        final path = Path();
        final points = surface
            .corners()
            .map((point) => _mapPoint(room.map(point), origin, scale))
            .toList();
        if (points.isNotEmpty) {
          path.moveTo(points.first.dx, points.first.dy);
          for (final point in points.skip(1)) {
            path.lineTo(point.dx, point.dy);
          }
          path.close();
          canvas.drawPath(path, objectPaint);
        }
      } else {
        final clearPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.square;
        canvas.drawLine(a, b, clearPaint);
        canvas.drawLine(a, b, featurePaint);
      }
    }

    _drawSampleLocations(canvas, room, origin, scale);
    _drawRoomNameLabel(canvas, room, selected, origin, scale, size);
  }

  void _drawRoomNameLabel(
    Canvas canvas,
    _EditableRoom room,
    bool selected,
    Offset origin,
    double scale,
    Size size,
  ) {
    // CAD-style tag: a compact pill anchored to the room's top edge with a
    // short leader line. It stays readable for small geometries instead of
    // covering them with a large centered box.
    final bounds = room.bounds;
    final anchor = _mapPoint(
      Offset(bounds.center.dx, bounds.top),
      origin,
      scale,
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: room.scan.name,
        style: TextStyle(
          color: selected ? Colors.blue.shade800 : Colors.black87,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 140);
    final labelWidth = textPainter.width + 16;
    final labelHeight = textPainter.height + 9;
    final minX = labelWidth / 2 + 3;
    final maxX = math.max(size.width - labelWidth / 2 - 3, minX);
    var labelCenter = Offset(anchor.dx, anchor.dy - labelHeight / 2 - 8);
    labelCenter = Offset(
      labelCenter.dx.clamp(minX, maxX),
      math.max(labelCenter.dy, labelHeight / 2 + 3),
    );
    final labelRect = Rect.fromCenter(
      center: labelCenter,
      width: labelWidth,
      height: labelHeight,
    );
    const labelRadius = Radius.circular(5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect.translate(0, 1.2), labelRadius),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawLine(
      Offset(labelCenter.dx, labelRect.bottom),
      anchor,
      Paint()
        ..color = selected ? Colors.blue.shade600 : Colors.grey.shade500
        ..strokeWidth = 0.9,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, labelRadius),
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, labelRadius),
      Paint()
        ..color = selected ? Colors.blue.shade600 : Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.2 : 0.8,
    );
    textPainter.paint(
      canvas,
      Offset(
        labelCenter.dx - textPainter.width / 2,
        labelCenter.dy - textPainter.height / 2,
      ),
    );
  }

  Offset _mapPoint(Offset point, Offset origin, double scale) {
    return Offset(origin.dx + point.dx * scale, origin.dy + point.dy * scale);
  }

  void _drawSampleLocations(
    Canvas canvas,
    _EditableRoom room,
    Offset origin,
    double scale,
  ) {
    final locations = room.scan.sampleLocations;
    if (locations.isEmpty) return;

    final bounds = room.localBounds;
    final fillPaint = Paint()..color = const Color(0xfff97316);
    final strokePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke;
    final center = _mapPoint(room.bounds.center, origin, scale);

    for (final location in locations) {
      final adjusted = location.localX != null && location.localY != null
          ? Offset(location.localX!, location.localY!)
          : _rotateAround(
              Offset(
                bounds.left + location.x.clamp(0.0, 1.0) * bounds.width,
                bounds.top + location.y.clamp(0.0, 1.0) * bounds.height,
              ),
              bounds.center,
              0,
            );
      final point = _mapPoint(room.map(adjusted), origin, scale);
      canvas.drawCircle(point, 5.5, fillPaint);
      canvas.drawCircle(point, 5.5, strokePaint);
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
      final textPainter = TextPainter(
        text: TextSpan(
          text: location.label,
          style: const TextStyle(
            color: Color(0xff111827),
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 70);
      final labelDirection = _labelDirection(point, center);
      final labelCenter = point + labelDirection * 22;
      final labelRect = Rect.fromCenter(
        center: labelCenter,
        width: math.max(textPainter.width + 10, 24),
        height: textPainter.height + 7,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        Paint()..color = Colors.white.withValues(alpha: 0.96),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        Paint()
          ..color = const Color(0xfff97316)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      textPainter.paint(
        canvas,
        Offset(
          labelRect.center.dx - textPainter.width / 2,
          labelRect.center.dy - textPainter.height / 2,
        ),
      );
    }
  }

  Offset _labelDirection(Offset point, Offset center) {
    final delta = point - center;
    if (delta.distance < 0.001) return const Offset(0, -1);
    return delta / delta.distance;
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

  @override
  bool shouldRepaint(covariant _MergedFloorPlanPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.isDropActive != isDropActive ||
        oldDelegate.northRotationRadians != northRotationRadians ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.placedLetters != placedLetters ||
        oldDelegate.selectedWall != selectedWall ||
        !_sameRooms(oldDelegate.rooms, rooms);
  }

  static bool _sameRooms(List<_EditableRoom> a, List<_EditableRoom> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

class _EditableRoom {
  final NamedScanResult scan;
  final List<PlanSurfaceSnapshot> surfaces;
  final Offset offset;
  final double rotation;
  final bool isPlaced;

  const _EditableRoom({
    required this.scan,
    required this.surfaces,
    required this.offset,
    required this.rotation,
    this.isPlaced = true,
  });

  _EditableRoom copyWith({
    List<PlanSurfaceSnapshot>? surfaces,
    Offset? offset,
    double? rotation,
    bool? isPlaced,
  }) {
    return _EditableRoom(
      scan: scan,
      surfaces: surfaces ?? this.surfaces,
      offset: offset ?? this.offset,
      rotation: rotation ?? this.rotation,
      isPlaced: isPlaced ?? this.isPlaced,
    );
  }

  Rect get bounds {
    final points = surfaces
        .expand((surface) => surface.corners())
        .map(map)
        .toList();
    if (points.isEmpty) return Rect.fromLTWH(offset.dx, offset.dy, 1, 1);
    final minX = points.map((point) => point.dx).reduce(math.min);
    final maxX = points.map((point) => point.dx).reduce(math.max);
    final minY = points.map((point) => point.dy).reduce(math.min);
    final maxY = points.map((point) => point.dy).reduce(math.max);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect get localBounds {
    final points = surfaces.expand((surface) => surface.corners()).toList();
    if (points.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    final minX = points.map((point) => point.dx).reduce(math.min);
    final maxX = points.map((point) => point.dx).reduce(math.max);
    final minY = points.map((point) => point.dy).reduce(math.min);
    final maxY = points.map((point) => point.dy).reduce(math.max);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset map(Offset point) {
    final center = localBounds.center;
    final delta = point - center;
    final cosA = math.cos(rotation);
    final sinA = math.sin(rotation);
    return center +
        Offset(
          delta.dx * cosA - delta.dy * sinA,
          delta.dx * sinA + delta.dy * cosA,
        ) +
        offset;
  }

  Offset unmap(Offset point) {
    final center = localBounds.center;
    final translated = point - offset - center;
    final cosA = math.cos(-rotation);
    final sinA = math.sin(-rotation);
    return center +
        Offset(
          translated.dx * cosA - translated.dy * sinA,
          translated.dx * sinA + translated.dy * cosA,
        );
  }
}

Rect _roomsBounds(List<_EditableRoom> rooms) {
  final placedRooms = rooms.where((room) => room.isPlaced).toList();
  if (placedRooms.isEmpty) return const Rect.fromLTWH(0, 0, 8, 6);
  var bounds = placedRooms.first.bounds;
  for (final room in placedRooms.skip(1)) {
    bounds = bounds.expandToInclude(room.bounds);
  }
  return bounds;
}

class _RoomHit {
  final int roomIndex;

  const _RoomHit(this.roomIndex);
}

class _WallSelection {
  final int roomIndex;
  final int wallIndex;

  const _WallSelection({required this.roomIndex, required this.wallIndex});

  @override
  bool operator ==(Object other) {
    return other is _WallSelection &&
        other.roomIndex == roomIndex &&
        other.wallIndex == wallIndex;
  }

  @override
  int get hashCode => Object.hash(roomIndex, wallIndex);
}

class _WallEndpoint {
  final int roomIndex;
  final Offset point;

  const _WallEndpoint({required this.roomIndex, required this.point});
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final segment = b - a;
  final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared == 0) return (point - a).distance;
  final t =
      (((point.dx - a.dx) * segment.dx + (point.dy - a.dy) * segment.dy) /
              lengthSquared)
          .clamp(0.0, 1.0);
  final projection = a + segment * t;
  return (point - projection).distance;
}

double _normalizeAngle(double angle) {
  var normalized = angle % (math.pi * 2);
  if (normalized < 0) normalized += math.pi * 2;
  return normalized;
}

double _nearestRightAngleDelta(double angle) {
  final nearest = (angle / (math.pi / 2)).round() * (math.pi / 2);
  var delta = angle - nearest;
  while (delta > math.pi) {
    delta -= math.pi * 2;
  }
  while (delta < -math.pi) {
    delta += math.pi * 2;
  }
  return delta;
}

double _nearestRightAngle(double angle) {
  return (angle / (math.pi / 2)).round() * (math.pi / 2);
}

double _axisError(double angle) {
  return _nearestRightAngleDelta(angle).abs();
}

bool _connectorMatches(PlanSurfaceSnapshot a, PlanSurfaceSnapshot b) {
  return (Offset(a.centerX, a.centerY) - Offset(b.centerX, b.centerY))
              .distance <
          0.08 &&
      (a.length - b.length).abs() < 0.08 &&
      _nearestRightAngleDelta(a.angle - b.angle).abs() < math.pi / 36;
}

class _ToolSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ToolSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ],
    );
  }
}

class _IconToolButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;

  const _IconToolButton({
    required this.tooltip,
    required this.icon,
    this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: label != null ? 44 : 38,
        height: 34,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: label != null
              ? Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.blueGrey,
                  ),
                )
              : Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _TextToolButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _TextToolButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _PlacedLetter {
  final String letter;
  final Offset position;

  const _PlacedLetter({required this.letter, required this.position});

  _PlacedLetter copyWith({Offset? position}) {
    return _PlacedLetter(letter: letter, position: position ?? this.position);
  }
}
