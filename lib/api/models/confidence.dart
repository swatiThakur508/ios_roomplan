/// RoomPlan's confidence label for a detected element.
enum Confidence {
  high,
  medium,
  low;

  static Confidence fromJson(String? value) => switch (value?.toLowerCase()) {
    'high' => Confidence.high,
    'medium' => Confidence.medium,
    _ => Confidence.low,
  };
}

const unknownConfidence = Confidence.low;
