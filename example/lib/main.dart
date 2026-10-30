import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ios_roomplan/ios_roomplan.dart';

void main() => runApp(const RoomPlanExampleApp());

class RoomPlanExampleApp extends StatelessWidget {
  const RoomPlanExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RoomPlan capture',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF087E8B),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F7F8),
      useMaterial3: true,
    ),
    home: const RoomPlanCapturePage(),
  );
}

class RoomPlanCapturePage extends StatefulWidget {
  const RoomPlanCapturePage({super.key});

  @override
  State<RoomPlanCapturePage> createState() => _RoomPlanCapturePageState();
}

class _RoomPlanCapturePageState extends State<RoomPlanCapturePage> {
  final _library = RoomPlanScanLibrary();
  final List<SavedRoomScan> _savedScans = [];
  FloorRoomScanResult? _capture;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshLibrary();
  }

  Future<void> _refreshLibrary() async {
    try {
      final scans = await _library.listScans();
      if (mounted)
        setState(() {
          _savedScans
            ..clear()
            ..addAll(scans);
        });
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _scanRoom({bool multiRoom = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await Navigator.of(context).push<FloorRoomScanResult>(
        MaterialPageRoute(
          builder: (_) => FloorRoomScanPage(
            initialName: multiRoom ? 'Home' : 'Room',
            multiRoom: multiRoom,
          ),
        ),
      );
      if (!mounted || result == null) return;
      if (multiRoom) {
        final rooms = result.rooms;
        if (rooms.isEmpty) throw StateError('No room data was returned.');
        final savedModel = await _library.persistOutput(
          result.modelFile,
          fileName: 'room-structure.usdz',
        );
        setState(() {
          _capture = FloorRoomScanResult(
            name: result.name,
            pdfFile: result.pdfFile,
            modelFile: savedModel,
            rooms: rooms,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved a structure containing ${rooms.length} rooms.',
            ),
          ),
        );
        return;
      }
      final scan = result.scanResult;
      if (scan == null)
        throw StateError('The completed scan data was not returned.');
      final saved = await _library.save(
        name: result.name,
        scanResult: scan,
        pdfFile: result.pdfFile,
        modelFile: result.modelFile,
      );
      final durableCapture = FloorRoomScanResult(
        name: saved.name,
        pdfFile: saved.pdfFile!,
        modelFile: saved.modelFile!,
        scanResult: saved.scanResult,
        rooms: [saved.scanResult],
        libraryId: saved.id,
      );
      setState(() {
        _capture = durableCapture;
        _savedScans.insert(0, saved);
      });
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSavedScan(SavedRoomScan saved) async {
    final refreshed = await _library.load(saved.id);
    if (!mounted || refreshed == null) return;
    if (refreshed.pdfFile == null || refreshed.modelFile == null) {
      setState(
        () => _error =
            'This saved entry has scan data but is missing one or both output files.',
      );
      return;
    }
    setState(() {
      _capture = FloorRoomScanResult(
        name: refreshed.name,
        pdfFile: refreshed.pdfFile!,
        modelFile: refreshed.modelFile!,
        scanResult: refreshed.scanResult,
        rooms: [refreshed.scanResult],
        libraryId: refreshed.id,
      );
      _error = null;
    });
  }

  Future<void> _previewModel(File model) async {
    try {
      await RoomPlanModelViewer.preview(model);
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _previewFloorPlan(File pdf) async {
    try {
      await RoomPlanModelViewer.previewFloorPlan(pdf);
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _shareFile(File file) async {
    try {
      final shared = await RoomPlanFileSharing.share(file);
      if (mounted && shared) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File shared')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _rename(SavedRoomScan saved) async {
    final controller = TextEditingController(text: saved.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename scan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Room name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      final updated = await _library.rename(saved.id, name);
      await _refreshLibrary();
      if (mounted && _capture?.libraryId == saved.id) {
        setState(
          () => _capture = FloorRoomScanResult(
            name: updated.name,
            pdfFile: _capture!.pdfFile,
            modelFile: _capture!.modelFile,
            scanResult: updated.scanResult,
            rooms: [updated.scanResult],
            libraryId: updated.id,
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _delete(SavedRoomScan saved) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved scan?'),
        content: Text(
          '“${saved.name}” and its saved files will be removed from this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _library.delete(saved.id);
      if (mounted)
        setState(() {
          _savedScans.removeWhere((scan) => scan.id == saved.id);
          if (_capture?.libraryId == saved.id) _capture = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _copyJson(SavedRoomScan saved) async {
    try {
      await Clipboard.setData(
        ClipboardData(text: await _library.exportJson(saved.id)),
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan JSON copied to clipboard')),
        );
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  Future<void> _exportAllPlans() async {
    if (_savedScans.isEmpty) return;
    try {
      final rooms = <NamedScanResult>[];
      for (final saved in _savedScans) {
        final pdf = saved.pdfFile;
        if (pdf == null) continue;
        rooms.add(
          NamedScanResult(
            name: saved.name,
            scanResult: saved.scanResult,
            pdfFile: pdf,
          ),
        );
      }
      if (rooms.isEmpty)
        throw StateError('No saved floor plan files are available.');
      final pdf = await FloorPlanPdfService.createMerged2DFloorPlan(
        rooms,
        title: 'Saved room scans',
        fileName: 'saved_room_scans',
      );
      if (mounted) await _previewFloorPlan(pdf);
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  String _readableError(Object error) {
    final text = error.toString();
    if (text.contains('RoomPlanException:')) {
      return text.replaceFirst('RoomPlanException: ', '');
    }
    return 'Could not complete the room capture: $text';
  }

  @override
  Widget build(BuildContext context) {
    final capture = _capture;
    final rooms = capture == null
        ? const <ScanResult>[]
        : capture.rooms.isNotEmpty
        ? capture.rooms
        : capture.scanResult == null
        ? const <ScanResult>[]
        : [capture.scanResult!];
    final quality = rooms.isEmpty
        ? null
        : RoomPlanScanQuality.fromScan(rooms.first);
    return Scaffold(
      appBar: AppBar(
        title: const Text('RoomPlan Studio'),
        centerTitle: false,
        backgroundColor: const Color(0xFFF4F7F8),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0xFF123B4A), Color(0xFF087E8B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x260C5260),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Capture your space',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Turn real rooms into shareable 2D plans and 3D models.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const _SupportPill(
                        label: 'LiDAR · iOS 16+',
                        prominent: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.view_in_ar_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Choose a scan',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ScanActionCard(
            icon: Icons.weekend_rounded,
            title: 'Single room',
            description: 'Create one room plan and a 3D model',
            badge: 'iOS 16+',
            enabled: !_busy,
            onTap: _scanRoom,
          ),
          const SizedBox(height: 10),
          _ScanActionCard(
            icon: Icons.door_sliding_rounded,
            title: 'Connected rooms',
            description: 'Scan room by room and merge one 3D structure',
            badge: 'iOS 17+',
            enabled: !_busy,
            onTap: () => _scanRoom(multiRoom: true),
          ),
          if (capture != null && capture.rooms.length > 1)
            Card(
              margin: const EdgeInsets.only(top: 12),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.domain_outlined),
                title: const Text('Merged structure verified'),
                subtitle: Text(
                  '${capture.rooms.length} rooms are in the captured structure and exported together in one USDZ file.',
                ),
              ),
            ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline_rounded),
                title: const Text('Capture couldn’t finish'),
                subtitle: Text(_error!),
                isThreeLine: true,
              ),
            ),
          ],
          if (capture != null) ...[
            const SizedBox(height: 24),
            Text(capture.name, style: Theme.of(context).textTheme.titleLarge),
            if (quality != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan review: ${quality.wallCount} walls detected',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      ...quality.suggestions.map(
                        (tip) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• $tip'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (capture.pdfFile.existsSync()) ...[
              _SavedFileCard(
                title: '2D floor plan (PDF)',
                file: capture.pdfFile,
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _previewFloorPlan(capture.pdfFile),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Preview 2D floor plan'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _shareFile(capture.pdfFile),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share floor plan'),
              ),
            ],
            if (capture.modelFile.existsSync()) ...[
              _SavedFileCard(
                title: capture.rooms.length > 1
                    ? 'Merged 3D structure · ${capture.rooms.length} rooms'
                    : '3D room model (USDZ)',
                file: capture.modelFile,
              ),
              if (capture.rooms.length > 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'In Quick Look, drag to orbit and pinch out to view the full structure if the first room fills the screen.',
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _previewModel(capture.modelFile),
                icon: const Icon(Icons.threed_rotation),
                label: const Text('Preview 3D model'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _shareFile(capture.modelFile),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share 3D model'),
              ),
            ],
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Saved scans (${_savedScans.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_savedScans.length > 1)
                IconButton(
                  tooltip: 'Create a PDF with one page per saved room',
                  onPressed: _exportAllPlans,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
            ],
          ),
          if (_savedScans.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Completed scans saved here will remain available between app launches.',
              ),
            ),
          ..._savedScans.map(
            (saved) => Card(
              child: ListTile(
                onTap: () => _openSavedScan(saved),
                leading: const Icon(Icons.meeting_room_outlined),
                title: Text(saved.name),
                subtitle: Text(
                  '${saved.scanResult.room.walls.length} walls · ${saved.createdAt.toLocal()}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    switch (action) {
                      case 'rename':
                        _rename(saved);
                        break;
                      case 'json':
                        _copyJson(saved);
                        break;
                      case 'delete':
                        _delete(saved);
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(
                      value: 'json',
                      child: Text('Copy JSON export'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedFileCard extends StatelessWidget {
  final String title;
  final File file;

  const _SavedFileCard({required this.title, required this.file});

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.check_circle_outline),
      title: Text(title),
      subtitle: SelectableText(file.path),
    ),
  );
}

class _SupportPill extends StatelessWidget {
  const _SupportPill({required this.label, this.prominent = false});

  final String label;
  final bool prominent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: prominent
          ? Colors.white.withValues(alpha: 0.14)
          : Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(30),
      border: prominent
          ? Border.all(color: Colors.white.withValues(alpha: 0.28))
          : null,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Text(
        label,
        style: TextStyle(
          color: prominent
              ? Colors.white
              : Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _ScanActionCard extends StatelessWidget {
  const _ScanActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _SupportPill(label: badge),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ],
        ),
      ),
    ),
  );
}
