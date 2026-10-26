/// Base type for errors raised by the RoomPlan plugin.
abstract class RoomPlanException implements Exception {
  /// Creates a RoomPlan exception with a human-readable [message].
  const RoomPlanException(this.message);

  /// Explains why the RoomPlan operation failed.
  final String message;

  @override
  String toString() => 'RoomPlanException: $message';
}

/// Raised when RoomPlan is unavailable on the current OS or hardware.
class RoomPlanNotAvailableException extends RoomPlanException {
  RoomPlanNotAvailableException()
    : super('RoomPlan requires iOS 16 or later and a supported LiDAR device.');
}

/// Raised when a capture operation fails for a RoomPlan-specific reason.
class RoomPlanScanningErrorException extends RoomPlanException {
  /// Creates a scanning error with the native or plugin error [message].
  const RoomPlanScanningErrorException(super.message);
}

/// Raised when camera permission is denied or unavailable.
class RoomPlanPermissionsException extends RoomPlanException {
  RoomPlanPermissionsException()
    : super('Camera access is required. Allow it in the device Settings app.');
}

/// Raised when a user cancels an active room scan.
class ScanCancelledException extends RoomPlanException {
  ScanCancelledException() : super('The room scan was cancelled.');
}

/// Raised when RoomPlan cannot complete a capture.
class ScanFailedException extends RoomPlanException {
  /// Creates a scan failure with additional [details].
  ScanFailedException(String details) : super('Room scan failed: $details');
}

/// Raised when RoomPlan cannot process captured geometry.
class ProcessingFailedException extends RoomPlanException {
  /// Creates a processing failure with additional [details].
  ProcessingFailedException(String details)
    : super('RoomPlan could not process the capture: $details');
}

/// Raised when communication with the native iOS plugin fails.
class NativeChannelException extends RoomPlanException {
  /// Creates a channel failure with additional [details].
  NativeChannelException(String details)
    : super('Native RoomPlan request failed: $details');
}

/// Raised when scan data cannot be decoded into the public data models.
class DataParsingException extends RoomPlanException {
  /// Creates a parsing failure with additional [details].
  DataParsingException(String details)
    : super('RoomPlan data is invalid: $details');
}

/// Raised when the installed iOS version is below RoomPlan's requirement.
class UnsupportedVersionException extends RoomPlanException {
  UnsupportedVersionException() : super('RoomPlan requires iOS 16 or later.');
}

/// Raised when camera permission has not yet been requested.
class CameraPermissionNotDeterminedException extends RoomPlanException {
  CameraPermissionNotDeterminedException()
    : super('Camera permission has not been requested yet.');
}

/// Raised when the camera permission status cannot be determined.
class CameraPermissionUnknownException extends RoomPlanException {
  CameraPermissionUnknownException()
    : super('The camera permission status could not be determined.');
}

/// Raised when ARKit world tracking is unavailable.
class ARKitNotSupportedException extends RoomPlanException {
  ARKitNotSupportedException() : super('ARKit world tracking is unavailable.');
}

/// Raised when the device lacks the hardware required for scanning.
class InsufficientHardwareException extends RoomPlanException {
  InsufficientHardwareException()
    : super('This device does not have the hardware required for RoomPlan.');
}

/// Raised when Low Power Mode prevents a scan from starting.
class LowPowerModeException extends RoomPlanException {
  LowPowerModeException() : super('Turn off Low Power Mode to scan a room.');
}

/// Raised when there is not enough device storage to save a scan.
class InsufficientStorageException extends RoomPlanException {
  InsufficientStorageException()
    : super('There is not enough free storage to save the room scan.');
}

/// Raised when a scan is started while another scan is active.
class SessionInProgressException extends RoomPlanException {
  SessionInProgressException() : super('A room scan is already in progress.');
}

/// Raised when an operation requires a scan that is not active.
class SessionNotRunningException extends RoomPlanException {
  SessionNotRunningException() : super('There is no active room scan.');
}

/// Raised when ARKit loses tracking during capture.
class WorldTrackingFailedException extends RoomPlanException {
  WorldTrackingFailedException()
    : super('RoomPlan lost tracking. Try scanning with more light and detail.');
}

/// Raised when device memory pressure prevents capture or processing.
class MemoryPressureException extends RoomPlanException {
  MemoryPressureException() : super('The device is low on available memory.');
}

/// Raised when the app is backgrounded while scanning requires foreground use.
class BackgroundModeActiveException extends RoomPlanException {
  BackgroundModeActiveException()
    : super('Return to the app to continue the room scan.');
}

/// Raised when thermal conditions prevent a scan from continuing.
class DeviceOverheatingException extends RoomPlanException {
  DeviceOverheatingException()
    : super('The device is too warm to continue scanning.');
}

/// Raised when an operation requires a network connection.
class NetworkRequiredException extends RoomPlanException {
  NetworkRequiredException() : super('A network connection is required.');
}

class TimeoutException extends RoomPlanException {
  TimeoutException(this.operation)
    : super('Timed out while performing $operation.');
  final String operation;
}

/// Raised when scan data is malformed or corrupted.
class DataCorruptedException extends RoomPlanException {
  DataCorruptedException(String details) : super('Invalid scan data: $details');
}

/// Raised when a USDZ or floor plan export fails.
class ExportFailedException extends RoomPlanException {
  ExportFailedException(String details)
    : super('Model export failed: $details');
}

/// Raised when the native preview or capture interface cannot be presented.
class UIErrorException extends RoomPlanException {
  UIErrorException(String details)
    : super('Could not present the scan UI: $details');
}

/// Raised when the native scanning session cannot be started.
class SessionStartFailedException extends RoomPlanException {
  SessionStartFailedException(String details)
    : super('Could not start scanning: $details');
}
