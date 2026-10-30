import 'dart:io';

import 'scan_result.dart';

/// The captured rooms and merged USDZ export for one multi-room scan.
class MultiRoomScanResult {
  const MultiRoomScanResult({required this.rooms, required this.modelFile});

  /// Individual RoomPlan results in the order they were scanned.
  final List<ScanResult> rooms;

  /// Merged structure model exported by Apple's RoomPlan framework.
  final File modelFile;
}
