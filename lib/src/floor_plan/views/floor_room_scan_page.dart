import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ios_roomplan/api/room_plan_scanner.dart';
import 'package:ios_roomplan/src/internal.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The PDF and USDZ files created by a completed [FloorRoomScanPage] scan.
class FloorRoomScanResult {
  /// Creates a scan result from its name and generated output files.
  final String name;

  /// The 2D floor plan PDF saved in the app's documents directory.
  final File pdfFile;

  /// The native 3D room model exported as a USDZ in the temporary directory.
  final File modelFile;

  /// Processed room geometry and scan metadata, available for saving or review.
  final ScanResult? scanResult;

  /// Optional ID assigned by [RoomPlanScanLibrary] when the scan is saved.
  final String? libraryId;

  /// Per-room results when the page was opened in multi-room mode.
  final List<ScanResult> rooms;

  const FloorRoomScanResult({
    required this.name,
    required this.pdfFile,
    required this.modelFile,
    this.scanResult,
    this.libraryId,
    this.rooms = const [],
  });
}

/// Scans a real room and saves its 2D floor plan PDF and 3D USDZ model.
class FloorRoomScanPage extends StatefulWidget {
  /// The suggested name used for the saved floor plan and scan result.
  final String initialName;

  /// Scans connected rooms into one native USDZ structure when true.
  /// Requires iOS 17 or later. The default single-room mode supports iOS 16.
  final bool multiRoom;

  /// Presents the iOS RoomPlan scanning workflow.
  ///
  /// The scan requires iOS 16 or later and a supported LiDAR-equipped device.
  const FloorRoomScanPage({
    super.key,
    required this.initialName,
    this.multiRoom = false,
  });

  @override
  State<FloorRoomScanPage> createState() => _FloorRoomScanPageState();
}

class _FloorRoomScanPageState extends State<FloorRoomScanPage> {
  bool _includeFurniture = false;
  bool _includeDoors = true;
  bool _includeWindows = true;
  double _minimumConfidence = 0.0;

  late RoomPlanScanner _scanner;
  StreamSubscription<ScanResult?>? _scanSubscription;
  bool _isSupported = false;
  bool _isCheckingSupport = true;
  bool _isBusy = false;
  bool _isSaving = false;
  bool _isCancelling = false;
  String _status = 'Checking device support…';
  int _wallCount = 0;

  @override
  void initState() {
    super.initState();
    _scanner = RoomPlanScanner();
    _scanSubscription = _scanner.onScanResult.listen(
      (result) {
        if (!mounted || result == null) return;
        setState(() {
          _wallCount = result.room.walls.length;
          _status = 'Scanning room…';
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _status = _errorMessage(error));
      },
    );
    _checkSupport();
  }

  @override
  void dispose() {
    if (_isBusy) unawaited(_scanner.stopScanning().catchError((_) {}));
    _scanSubscription?.cancel();
    _scanner.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _checkSupport() async {
    try {
      final supported = widget.multiRoom
          ? await RoomPlanScanner.isMultiRoomSupported()
          : await RoomPlanScanner.isSupported();
      if (!mounted) return;
      setState(() {
        _isSupported = supported;
        _isCheckingSupport = false;
        _status = supported
            ? 'Ready to scan'
            : widget.multiRoom
            ? 'Multi-room scanning requires iOS 17 or later and a supported LiDAR device.'
            : 'Room scanning requires iOS 16 or later and a supported LiDAR device.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCheckingSupport = false;
        _status = _errorMessage(error);
      });
    }
  }

  Future<void> _startScan() async {
    if (_isBusy || !_isSupported) return;
    File? generatedModelFile;
    File? generatedPdfFile;
    setState(() {
      _isBusy = true;
      _isCancelling = false;
      _wallCount = 0;
      _status = 'Starting room scan…';
    });

    try {
      await WakelockPlus.enable();
      final List<ScanResult> scans;
      final File modelFile;
      if (widget.multiRoom) {
        final structure = await _scanner.startMultiRoomScanning();
        scans = structure.rooms.map(_applyOutputSettings).toList();
        modelFile = structure.modelFile;
      } else {
        final rawScan = await _scanner.startScanning();
        if (rawScan == null) {
          if (mounted) {
            setState(() => _status = 'Scan cancelled. You can start again.');
          }
          return;
        }
        scans = [_applyOutputSettings(rawScan)];
        modelFile = await RoomPlanModelViewer.exportLastCapture();
      }
      generatedModelFile = modelFile;
      if (!mounted) return;
      if (scans.any((scan) => scan.room.walls.isEmpty)) {
        throw const FormatException(
          'One or more rooms have no detected walls. Scan again, moving slowly and keeping the room boundaries in view.',
        );
      }

      setState(() => _isSaving = true);
      setState(() => _status = 'Creating the 2D floor plan…');
      final name = widget.initialName.trim().isEmpty
          ? (widget.multiRoom ? 'Room Structure' : 'Room Scan')
          : widget.initialName.trim();
      final pdfFile = widget.multiRoom
          ? await FloorPlanPdfService.createMultiRoom2DFloorPlan(
              scans,
              title: name,
              fileName: name,
            )
          : await FloorPlanPdfService.create2DFloorPlan(
              scans.single,
              title: name,
              fileName: name,
              previewOnly: true,
            );
      generatedPdfFile = pdfFile;
      await _validateOutput(modelFile, '3D model');
      await _validateOutput(pdfFile, '2D floor plan');
      if (!mounted) return;
      Navigator.of(context).pop(
        FloorRoomScanResult(
          name: name,
          pdfFile: pdfFile,
          modelFile: modelFile,
          scanResult: widget.multiRoom ? null : scans.single,
          rooms: scans,
        ),
      );
    } catch (error) {
      if (_isCancelling && error is RoomPlanException) {
        if (mounted) {
          setState(() => _status = 'Scan cancelled. You can start again.');
        }
      } else if (mounted) {
        setState(() => _status = _errorMessage(error));
      }
      await _deleteIfPresent(generatedPdfFile);
      await _deleteIfPresent(generatedModelFile);
    } finally {
      await WakelockPlus.disable();
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isSaving = false;
          _isCancelling = false;
        });
      }
    }
  }

  ScanResult _applyOutputSettings(ScanResult scan) {
    bool meetsConfidence(Confidence confidence) {
      final score = switch (confidence) {
        Confidence.high => 1.0,
        Confidence.medium => 0.65,
        Confidence.low => 0.35,
      };
      return score >= _minimumConfidence;
    }

    final room = scan.room;
    final walls = room.walls.map((wall) {
      final openings = wall.openings.where((opening) {
        final typeEnabled = switch (opening.type) {
          OpeningType.door => _includeDoors,
          OpeningType.window => _includeWindows,
          OpeningType.opening => _includeDoors || _includeWindows,
        };
        return typeEnabled && meetsConfidence(opening.confidence);
      }).toList();
      return WallData(
        uuid: wall.uuid,
        position: wall.position,
        points: wall.points,
        width: wall.width,
        height: wall.height,
        confidence: wall.confidence,
        openings: openings,
        dimensions: wall.dimensions,
        transform: wall.transform,
      );
    }).toList();
    final doors = _includeDoors
        ? room.doors.where((item) => meetsConfidence(item.confidence)).toList()
        : const <OpeningData>[];
    final windows = _includeWindows
        ? room.windows
              .where((item) => meetsConfidence(item.confidence))
              .toList()
        : const <OpeningData>[];
    final openings = room.openings.where((item) {
      final typeEnabled = switch (item.type) {
        OpeningType.door => _includeDoors,
        OpeningType.window => _includeWindows,
        OpeningType.opening => _includeDoors || _includeWindows,
      };
      return typeEnabled && meetsConfidence(item.confidence);
    }).toList();
    final objects = _includeFurniture
        ? room.objects
              .where((item) => meetsConfidence(item.confidence))
              .toList()
        : const <ObjectData>[];

    return scan.copyWith(
      room: room.copyWith(
        walls: walls,
        doors: doors,
        windows: windows,
        openings: openings,
        objects: objects,
      ),
    );
  }

  Future<void> _cancelScan() async {
    if (!_isBusy || _isCancelling) return;
    setState(() {
      _isCancelling = true;
      _status = 'Cancelling scan…';
    });
    try {
      await _scanner.stopScanning();
    } catch (error) {
      if (mounted) {
        setState(() {
          _isCancelling = false;
          _status = _errorMessage(error);
        });
      }
    }
  }

  Future<void> _validateOutput(File file, String label) async {
    if (!await file.exists()) {
      throw FileSystemException('$label was not created.', file.path);
    }
    if (await file.length() == 0) {
      throw FileSystemException('$label is empty.', file.path);
    }
  }

  Future<void> _deleteIfPresent(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Preserve the original scan or save error for the user.
    }
  }

  String _errorMessage(Object error) {
    if (error is RoomPlanException) return error.message;
    if (error is UnsupportedError) return error.message ?? error.toString();
    return 'Could not save the room scan: $error';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_isBusy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Scan room')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _isBusy ? Icons.view_in_ar : Icons.room_preferences,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(_status, textAlign: TextAlign.center),
                if (!_isBusy) ...[
                  const SizedBox(height: 16),
                  _buildScanSettings(context),
                ],
                if (_isBusy && !_isCancelling) ...[
                  const SizedBox(height: 8),
                  Text('Walls found: $_wallCount', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isCheckingSupport || !_isSupported || _isBusy
                      ? null
                      : _startScan,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_isCheckingSupport ? 'Checking…' : 'Start scan'),
                ),
                if (_isBusy && !_isSaving) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isCancelling ? null : _cancelScan,
                    icon: const Icon(Icons.close),
                    label: Text(_isCancelling ? 'Cancelling…' : 'Cancel scan'),
                  ),
                ],
                if (!_isSupported && !_isCheckingSupport) ...[
                  const SizedBox(height: 12),
                  Text(
                    'RoomPlan scanning needs a supported LiDAR-equipped iPhone or iPad running iOS 16 or later.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildScanSettings(BuildContext context) => Card(
    child: ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.tune),
      title: const Text('Scan settings'),
      subtitle: const Text('Choose what to include in the saved floor plan'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Furniture'),
          value: _includeFurniture,
          onChanged: (value) => setState(() => _includeFurniture = value),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Doors'),
          value: _includeDoors,
          onChanged: (value) => setState(() => _includeDoors = value),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Windows'),
          value: _includeWindows,
          onChanged: (value) => setState(() => _includeWindows = value),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Minimum detection confidence: ${_confidenceLabel()}'),
        ),
        Slider(
          value: _minimumConfidence,
          divisions: 2,
          label: _confidenceLabel(),
          onChanged: (value) => setState(() => _minimumConfidence = value),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'LiDAR accuracy is determined by your device and RoomPlan. The app cannot set sensor precision. Scan slowly, keep surfaces visible, and use good lighting. These options filter the saved 2D plan; the exported USDZ keeps the native capture.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  String _confidenceLabel() => switch (_minimumConfidence) {
    0 => 'All',
    0.5 => 'Medium and high',
    _ => 'High only',
  };
}
