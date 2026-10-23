import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:ios_roomplan/src/internal.dart';

/// Sends scan commands to the iOS RoomPlan implementation and receives updates.
class RoomPlanChannel {
  RoomPlanChannel({MethodChannel? channel, EventChannel? eventChannel})
    : _methods = channel ?? const MethodChannel('ios_roomplan/method_channel'),
      _events =
          eventChannel ?? const EventChannel('ios_roomplan/event_channel') {
    _eventSubscription = _events.receiveBroadcastStream().listen(
      _updates.add,
      onError: _updates.addError,
    );
  }

  final MethodChannel _methods;
  final EventChannel _events;
  final StreamController<dynamic> _updates =
      StreamController<dynamic>.broadcast();
  final StreamController<Map<String, dynamic>> _results =
      StreamController<Map<String, dynamic>>.broadcast();
  late final StreamSubscription<dynamic> _eventSubscription;
  bool _disposed = false;

  Stream<dynamic> get scanUpdateStream => _updates.stream;
  Stream<Map<String, dynamic>> get scanResultStream => _results.stream;

  Future<dynamic> startRoomCapture({ScanConfiguration? configuration}) async {
    _ensureOpen();
    try {
      return await _methods.invokeMethod<dynamic>(
        'startRoomCapture',
        configuration?.toMap(),
      );
    } on PlatformException catch (error) {
      throw _translate(error);
    }
  }

  Future<void> stopRoomCapture() async {
    _ensureOpen();
    try {
      await _methods.invokeMethod<void>('stopRoomCapture');
    } on PlatformException catch (error) {
      throw NativeChannelException(_describe(error));
    }
  }

  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      return await const MethodChannel(
            'ios_roomplan/method_channel',
          ).invokeMethod<bool>('isSupported') ??
          false;
    } on PlatformException catch (error) {
      throw NativeChannelException(_describe(error));
    }
  }

  static Exception _translate(PlatformException error) {
    final message = _describe(error);
    return switch (error.code) {
      'camera_permission_denied' => RoomPlanPermissionsException(),
      'camera_permission_not_determined' =>
        CameraPermissionNotDeterminedException(),
      'camera_permission_unknown' => CameraPermissionUnknownException(),
      'CANCELED' => ScanCancelledException(),
      'not_available' ||
      'roomplan_not_supported' => RoomPlanNotAvailableException(),
      'unsupported_version' => UnsupportedVersionException(),
      'arkit_not_supported' => ARKitNotSupportedException(),
      'insufficient_hardware' => InsufficientHardwareException(),
      'low_power_mode' => LowPowerModeException(),
      'insufficient_storage' => InsufficientStorageException(),
      'session_in_progress' => SessionInProgressException(),
      'session_not_running' => SessionNotRunningException(),
      'world_tracking_failed' => WorldTrackingFailedException(),
      'memory_pressure' => MemoryPressureException(),
      'background_mode_active' => BackgroundModeActiveException(),
      'device_overheating' => DeviceOverheatingException(),
      'network_required' => NetworkRequiredException(),
      'timeout' => TimeoutException(error.message ?? 'Room scan timed out.'),
      'data_corrupted' ||
      'serialization_error' ||
      'data_not_found' => DataCorruptedException(message),
      'export_failed' => ExportFailedException(message),
      'ui_error' => UIErrorException(message),
      'session_start_failed' => SessionStartFailedException(message),
      'scan_failed' || 'native_error' => ScanFailedException(message),
      'processing_failed' => ProcessingFailedException(message),
      _ => NativeChannelException(message),
    };
  }

  static String _describe(PlatformException error) {
    final detail = error.details;
    return [
      error.message ?? error.code,
      if (detail != null && detail.toString().isNotEmpty) detail.toString(),
    ].join(' ');
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('RoomPlanChannel has been disposed.');
  }

  /// Releases the event subscription and closes the streams.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_eventSubscription.cancel());
    unawaited(_updates.close());
    unawaited(_results.close());
  }
}
