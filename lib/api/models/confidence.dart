/// RoomPlan's confidence label for a detected element.
enum Confidence {
  /// RoomPlan reports a high confidence in this detection.
  high,

  /// RoomPlan reports a medium confidence in this detection.
  medium,

  /// RoomPlan reports a low confidence in this detection.
  low;

  /// Converts a RoomPlan confidence string to its enum value.
  /// Unknown or missing values are treated as [Confidence.low].
  static Confidence fromJson(String? value) => switch (value?.toLowerCase()) {
    'high' => Confidence.high,
    'medium' => Confidence.medium,
    _ => Confidence.low,
  };
}

const unknownConfidence = Confidence.low;
