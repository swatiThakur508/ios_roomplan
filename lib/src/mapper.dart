import 'package:ios_roomplan/api/models/scan_result.dart';
import 'package:ios_roomplan/api/room_plan_scanner.dart' as scanner;

export 'performance/optimized_mapper.dart' show OptimizedMapper;

/// Decodes data produced by RoomPlan into the public room model.
ScanResult? parseScanResult(String? jsonResult) =>
    scanner.parseScanResult(jsonResult);

/// Kept as a source-compatible alias for applications using the old helper.
ScanResult? parseScanResultLegacy(String? jsonResult) =>
    scanner.parseScanResult(jsonResult);
