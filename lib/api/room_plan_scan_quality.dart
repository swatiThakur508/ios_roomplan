import 'models/confidence.dart';
import 'models/scan_result.dart';

/// Practical review hints calculated from the detections in a RoomPlan scan.
///
/// This is a completeness aid, not a sensor-accuracy measurement. It cannot
/// identify surfaces that RoomPlan failed to detect.
class RoomPlanScanQuality {
  const RoomPlanScanQuality({
    required this.wallCount,
    required this.elementCount,
    required this.lowConfidenceCount,
    required this.suggestions,
  });

  final int wallCount;
  final int elementCount;
  final int lowConfidenceCount;
  final List<String> suggestions;

  /// Whether the scan includes wall geometry usable for a floor plan.
  bool get hasFloorPlanGeometry => wallCount > 0;

  /// Fraction of detected elements labeled low confidence, from 0 to 1.
  double get lowConfidenceRatio =>
      elementCount == 0 ? 0 : lowConfidenceCount / elementCount;

  /// Builds user-facing suggestions from the scan's detected geometry.
  factory RoomPlanScanQuality.fromScan(ScanResult scan) {
    final room = scan.room;
    final confidences = <Confidence>[
      ...room.walls.map((item) => item.confidence),
      ...room.objects.map((item) => item.confidence),
      ...room.doors.map((item) => item.confidence),
      ...room.windows.map((item) => item.confidence),
      ...room.openings.map((item) => item.confidence),
    ];
    final lowCount = confidences.where((value) => value == Confidence.low).length;
    final tips = <String>[];

    if (room.walls.isEmpty) {
      tips.add('No walls were detected. Scan again and keep the room boundaries in view.');
    } else if (room.walls.length < 3) {
      tips.add('Few walls were detected. Review the outline and scan any missing sides again.');
    }

    if (confidences.isNotEmpty && lowCount / confidences.length >= 0.3) {
      tips.add('Several detections have low confidence. Review the plan and rescan unclear areas.');
    } else if (lowCount > 0) {
      tips.add('Some detections have low confidence. Check those details before relying on them.');
    }

    if (tips.isEmpty) {
      tips.add('Review the plan for missed details and verify critical measurements on site.');
    }

    return RoomPlanScanQuality(
      wallCount: room.walls.length,
      elementCount: confidences.length,
      lowConfidenceCount: lowCount,
      suggestions: List.unmodifiable(tips),
    );
  }
}
