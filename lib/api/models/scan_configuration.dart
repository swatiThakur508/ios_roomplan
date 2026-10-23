/// Options sent alongside a request to start a capture.
class ScanConfiguration {
  const ScanConfiguration({
    this.quality = ScanQuality.balanced,
    this.timeoutSeconds,
    this.enableRealtimeUpdates = true,
    this.detectFurniture = true,
    this.detectDoors = true,
    this.detectWindows = true,
    this.minimumConfidence = 0.5,
    this.enableAdvancedSurfaceDetection = false,
  }) : assert(minimumConfidence >= 0 && minimumConfidence <= 1);

  const ScanConfiguration.fast({
    this.timeoutSeconds = 60,
    this.enableRealtimeUpdates = false,
    this.detectFurniture = false,
    this.detectDoors = true,
    this.detectWindows = true,
    this.minimumConfidence = 0.3,
    this.enableAdvancedSurfaceDetection = false,
  }) : quality = ScanQuality.fast;

  const ScanConfiguration.accurate({
    this.timeoutSeconds = 300,
    this.enableRealtimeUpdates = true,
    this.detectFurniture = true,
    this.detectDoors = true,
    this.detectWindows = true,
    this.minimumConfidence = 0.8,
    this.enableAdvancedSurfaceDetection = true,
  }) : quality = ScanQuality.high;

  const ScanConfiguration.minimal({
    this.timeoutSeconds = 120,
    this.enableRealtimeUpdates = false,
    this.detectFurniture = false,
    this.detectDoors = false,
    this.detectWindows = false,
    this.minimumConfidence = 0.7,
    this.enableAdvancedSurfaceDetection = false,
  }) : quality = ScanQuality.balanced;

  final ScanQuality quality;
  final int? timeoutSeconds;
  final bool enableRealtimeUpdates;
  final bool detectFurniture;
  final bool detectDoors;
  final bool detectWindows;
  final double minimumConfidence;
  final bool enableAdvancedSurfaceDetection;

  Map<String, dynamic> toMap() => {
    'quality': quality.name,
    'timeoutSeconds': timeoutSeconds,
    'enableRealtimeUpdates': enableRealtimeUpdates,
    'detectFurniture': detectFurniture,
    'detectDoors': detectDoors,
    'detectWindows': detectWindows,
    'minimumConfidence': minimumConfidence,
    'enableAdvancedSurfaceDetection': enableAdvancedSurfaceDetection,
  };

  factory ScanConfiguration.fromMap(Map<String, dynamic> map) {
    final qualityName = map['quality'];
    return ScanConfiguration(
      quality: ScanQuality.values.firstWhere(
        (item) => item.name == qualityName,
        orElse: () => ScanQuality.balanced,
      ),
      timeoutSeconds: map['timeoutSeconds'] is int
          ? map['timeoutSeconds'] as int
          : null,
      enableRealtimeUpdates: map['enableRealtimeUpdates'] as bool? ?? true,
      detectFurniture: map['detectFurniture'] as bool? ?? true,
      detectDoors: map['detectDoors'] as bool? ?? true,
      detectWindows: map['detectWindows'] as bool? ?? true,
      minimumConfidence: (map['minimumConfidence'] as num?)?.toDouble() ?? .5,
      enableAdvancedSurfaceDetection:
          map['enableAdvancedSurfaceDetection'] as bool? ?? false,
    );
  }

  ScanConfiguration copyWith({
    ScanQuality? quality,
    int? timeoutSeconds,
    bool? enableRealtimeUpdates,
    bool? detectFurniture,
    bool? detectDoors,
    bool? detectWindows,
    double? minimumConfidence,
    bool? enableAdvancedSurfaceDetection,
  }) => ScanConfiguration(
    quality: quality ?? this.quality,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    enableRealtimeUpdates: enableRealtimeUpdates ?? this.enableRealtimeUpdates,
    detectFurniture: detectFurniture ?? this.detectFurniture,
    detectDoors: detectDoors ?? this.detectDoors,
    detectWindows: detectWindows ?? this.detectWindows,
    minimumConfidence: minimumConfidence ?? this.minimumConfidence,
    enableAdvancedSurfaceDetection:
        enableAdvancedSurfaceDetection ?? this.enableAdvancedSurfaceDetection,
  );

  @override
  bool operator ==(Object other) =>
      other is ScanConfiguration &&
      other.quality == quality &&
      other.timeoutSeconds == timeoutSeconds &&
      other.enableRealtimeUpdates == enableRealtimeUpdates &&
      other.detectFurniture == detectFurniture &&
      other.detectDoors == detectDoors &&
      other.detectWindows == detectWindows &&
      other.minimumConfidence == minimumConfidence &&
      other.enableAdvancedSurfaceDetection == enableAdvancedSurfaceDetection;

  @override
  int get hashCode => Object.hash(
    quality,
    timeoutSeconds,
    enableRealtimeUpdates,
    detectFurniture,
    detectDoors,
    detectWindows,
    minimumConfidence,
    enableAdvancedSurfaceDetection,
  );
}

enum ScanQuality {
  fast,
  balanced,
  high;

  String get description => switch (this) {
    ScanQuality.fast => 'Fast scanning with lower accuracy',
    ScanQuality.balanced =>
      'Balanced scanning with moderate accuracy and speed',
    ScanQuality.high => 'High-quality scanning with maximum accuracy',
  };
}
