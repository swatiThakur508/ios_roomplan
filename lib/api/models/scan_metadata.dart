/// Device and timing information associated with a room capture.
class ScanMetadata {
  const ScanMetadata({
    required this.scanDate,
    required this.scanDuration,
    required this.deviceModel,
    required this.hasLidar,
  });

  final DateTime scanDate;
  final Duration scanDuration;
  final String deviceModel;
  final bool hasLidar;

  factory ScanMetadata.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['scanDate']?.toString() ?? '');
    final duration = json['scanDuration'];
    final seconds = duration is num
        ? duration.toDouble()
        : double.tryParse(duration?.toString() ?? '') ?? 0;
    return ScanMetadata(
      scanDate: date ?? DateTime.now(),
      scanDuration: Duration(microseconds: (seconds * 1000000).round()),
      deviceModel: json['deviceModel']?.toString() ?? 'Unknown',
      hasLidar: json['hasLidar'] == true || json['hasLidar'] == 'true',
    );
  }

  Map<String, dynamic> toJson() => {
    'scanDate': scanDate.toIso8601String(),
    'scanDuration': scanDuration.inMicroseconds / 1000000,
    'deviceModel': deviceModel,
    'hasLidar': hasLidar,
  };

  ScanMetadata copyWith({
    DateTime? scanDate,
    Duration? scanDuration,
    String? deviceModel,
    bool? hasLidar,
  }) => ScanMetadata(
    scanDate: scanDate ?? this.scanDate,
    scanDuration: scanDuration ?? this.scanDuration,
    deviceModel: deviceModel ?? this.deviceModel,
    hasLidar: hasLidar ?? this.hasLidar,
  );

  @override
  bool operator ==(Object other) =>
      other is ScanMetadata &&
      other.scanDate == scanDate &&
      other.scanDuration == scanDuration &&
      other.deviceModel == deviceModel &&
      other.hasLidar == hasLidar;

  @override
  int get hashCode =>
      Object.hash(scanDate, scanDuration, deviceModel, hasLidar);
}
