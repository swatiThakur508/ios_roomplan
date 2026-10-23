/// Base type for errors raised by the RoomPlan plugin.
abstract class RoomPlanException implements Exception {
  const RoomPlanException(this.message);
  final String message;

  @override
  String toString() => 'RoomPlanException: $message';
}

class RoomPlanNotAvailableException extends RoomPlanException {
  RoomPlanNotAvailableException()
    : super('RoomPlan requires iOS 16 or later and a supported LiDAR device.');
}

class RoomPlanScanningErrorException extends RoomPlanException {
  const RoomPlanScanningErrorException(super.message);
}

class RoomPlanPermissionsException extends RoomPlanException {
  RoomPlanPermissionsException()
    : super('Camera access is required. Allow it in the device Settings app.');
}

class ScanCancelledException extends RoomPlanException {
  ScanCancelledException() : super('The room scan was cancelled.');
}

class ScanFailedException extends RoomPlanException {
  ScanFailedException(String details) : super('Room scan failed: $details');
}

class ProcessingFailedException extends RoomPlanException {
  ProcessingFailedException(String details)
    : super('RoomPlan could not process the capture: $details');
}

class NativeChannelException extends RoomPlanException {
  NativeChannelException(String details)
    : super('Native RoomPlan request failed: $details');
}

class DataParsingException extends RoomPlanException {
  DataParsingException(String details)
    : super('RoomPlan data is invalid: $details');
}

class UnsupportedVersionException extends RoomPlanException {
  UnsupportedVersionException() : super('RoomPlan requires iOS 16 or later.');
}

class CameraPermissionNotDeterminedException extends RoomPlanException {
  CameraPermissionNotDeterminedException()
    : super('Camera permission has not been requested yet.');
}

class CameraPermissionUnknownException extends RoomPlanException {
  CameraPermissionUnknownException()
    : super('The camera permission status could not be determined.');
}

class ARKitNotSupportedException extends RoomPlanException {
  ARKitNotSupportedException() : super('ARKit world tracking is unavailable.');
}

class InsufficientHardwareException extends RoomPlanException {
  InsufficientHardwareException()
    : super('This device does not have the hardware required for RoomPlan.');
}

class LowPowerModeException extends RoomPlanException {
  LowPowerModeException() : super('Turn off Low Power Mode to scan a room.');
}

class InsufficientStorageException extends RoomPlanException {
  InsufficientStorageException()
    : super('There is not enough free storage to save the room scan.');
}

class SessionInProgressException extends RoomPlanException {
  SessionInProgressException() : super('A room scan is already in progress.');
}

class SessionNotRunningException extends RoomPlanException {
  SessionNotRunningException() : super('There is no active room scan.');
}

class WorldTrackingFailedException extends RoomPlanException {
  WorldTrackingFailedException()
    : super('RoomPlan lost tracking. Try scanning with more light and detail.');
}

class MemoryPressureException extends RoomPlanException {
  MemoryPressureException() : super('The device is low on available memory.');
}

class BackgroundModeActiveException extends RoomPlanException {
  BackgroundModeActiveException()
    : super('Return to the app to continue the room scan.');
}

class DeviceOverheatingException extends RoomPlanException {
  DeviceOverheatingException()
    : super('The device is too warm to continue scanning.');
}

class NetworkRequiredException extends RoomPlanException {
  NetworkRequiredException() : super('A network connection is required.');
}

class TimeoutException extends RoomPlanException {
  TimeoutException(this.operation)
    : super('Timed out while performing $operation.');
  final String operation;
}

class DataCorruptedException extends RoomPlanException {
  DataCorruptedException(String details) : super('Invalid scan data: $details');
}

class ExportFailedException extends RoomPlanException {
  ExportFailedException(String details)
    : super('Model export failed: $details');
}

class UIErrorException extends RoomPlanException {
  UIErrorException(String details)
    : super('Could not present the scan UI: $details');
}

class SessionStartFailedException extends RoomPlanException {
  SessionStartFailedException(String details)
    : super('Could not start scanning: $details');
}
