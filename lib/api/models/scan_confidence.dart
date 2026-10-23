/// Summary confidence reported for one RoomPlan result.
class ScanConfidence {
  const ScanConfidence({
    required this.overall,
    required this.wallAccuracy,
    required this.dimensionAccuracy,
    this.warnings = const [],
  });

  final double overall;
  final double wallAccuracy;
  final double dimensionAccuracy;
  final List<String> warnings;

  factory ScanConfidence.fromJson(Map<String, dynamic> json) => ScanConfidence(
    overall: _number(json['overall']),
    wallAccuracy: _number(json['wallAccuracy']),
    dimensionAccuracy: _number(json['dimensionAccuracy']),
    warnings: json['warnings'] is List
        ? (json['warnings'] as List).whereType<String>().toList()
        : const [],
  );

  Map<String, dynamic> toJson() => {
    'overall': overall,
    'wallAccuracy': wallAccuracy,
    'dimensionAccuracy': dimensionAccuracy,
    'warnings': warnings,
  };

  ScanConfidence copyWith({
    double? overall,
    double? wallAccuracy,
    double? dimensionAccuracy,
    List<String>? warnings,
  }) => ScanConfidence(
    overall: overall ?? this.overall,
    wallAccuracy: wallAccuracy ?? this.wallAccuracy,
    dimensionAccuracy: dimensionAccuracy ?? this.dimensionAccuracy,
    warnings: warnings ?? this.warnings,
  );

  @override
  bool operator ==(Object other) =>
      other is ScanConfidence &&
      other.overall == overall &&
      other.wallAccuracy == wallAccuracy &&
      other.dimensionAccuracy == dimensionAccuracy &&
      _same(other.warnings, warnings);

  @override
  int get hashCode => Object.hash(
    overall,
    wallAccuracy,
    dimensionAccuracy,
    Object.hashAll(warnings),
  );
}

double _number(Object? value) => value is num ? value.toDouble() : 0;

bool _same<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
