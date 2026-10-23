import 'dart:io';
import 'package:flutter/services.dart';

/// Exports native capture geometry and opens local USDZ files in Quick Look.
/// Native exports represent the capture before Flutter canvas edits.
class RoomPlanModelViewer {
  static const _channel = MethodChannel('ios_roomplan/method_channel');

  /// Exports the latest completed capture in this process as a USDZ file.
  static Future<File> exportLastCapture() async {
    if (!Platform.isIOS) throw UnsupportedError('USDZ export requires iOS.');
    final path = await _channel.invokeMethod<String>('exportLastCapture');
    if (path == null || path.trim().isEmpty) {
      throw StateError('No exported model path was returned.');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('The exported 3D model was not created.', path);
    }
    if (await file.length() == 0) {
      throw FileSystemException('The exported 3D model is empty.', path);
    }
    return file;
  }

  /// Presents a local 3D model. Completes once the viewer is presented.
  static Future<void> preview(File model) async {
    if (!Platform.isIOS) throw UnsupportedError('3D preview requires iOS.');
    if (!await model.exists()) {
      throw FileSystemException(
        'The 3D model file does not exist.',
        model.path,
      );
    }
    if (await model.length() == 0) {
      throw FileSystemException('The 3D model file is empty.', model.path);
    }
    await _channel.invokeMethod<void>('previewModel', {'path': model.path});
  }

  /// Opens a local floor plan PDF in the iOS Quick Look viewer.
  static Future<void> previewFloorPlan(File pdf) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Floor plan preview requires iOS.');
    }
    if (!await pdf.exists()) {
      throw FileSystemException('The floor plan PDF does not exist.', pdf.path);
    }
    if (await pdf.length() == 0) {
      throw FileSystemException('The floor plan PDF is empty.', pdf.path);
    }
    await _channel.invokeMethod<void>('previewFloorPlan', {'path': pdf.path});
  }
}
