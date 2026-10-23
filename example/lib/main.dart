import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ios_roomplan/ios_roomplan.dart';

void main() => runApp(const RoomPlanExampleApp());

class RoomPlanExampleApp extends StatelessWidget {
  const RoomPlanExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RoomPlan capture',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const RoomPlanCapturePage(),
  );
}

class RoomPlanCapturePage extends StatefulWidget {
  const RoomPlanCapturePage({super.key});

  @override
  State<RoomPlanCapturePage> createState() => _RoomPlanCapturePageState();
}

class _RoomPlanCapturePageState extends State<RoomPlanCapturePage> {
  FloorRoomScanResult? _capture;
  bool _busy = false;
  String? _error;

  Future<void> _scanRoom() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await Navigator.of(context).push<FloorRoomScanResult>(
        MaterialPageRoute(
          builder: (_) => const FloorRoomScanPage(initialName: 'Room'),
        ),
      );
      if (!mounted || result == null) return;
      setState(() => _capture = result);
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('RoomPlan capture')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Scan a real room to save its 2D floor plan and 3D model.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _scanRoom,
            icon: const Icon(Icons.view_in_ar),
            label: Text(_busy ? 'Scanning…' : 'Scan room'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),
          ],
          if (capture != null) ...[
            const SizedBox(height: 24),
            Text(capture.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _SavedFileCard(title: '2D floor plan (PDF)', file: capture.pdfFile),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _previewFloorPlan(capture.pdfFile),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Preview 2D floor plan'),
            ),
            _SavedFileCard(
              title: '3D room model (USDZ)',
              file: capture.modelFile,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _previewModel(capture.modelFile),
              icon: const Icon(Icons.threed_rotation),
              label: const Text('Preview 3D model'),
            ),
          ],
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
