import 'dart:io';

import 'package:flutter/services.dart';

/// Presents the iOS share sheet for a generated PDF or USDZ file.
class RoomPlanFileSharing {
  static const _channel = MethodChannel('ios_roomplan/method_channel');

  /// Opens the system share sheet and returns whether the user completed a
  /// share action. Returns false when the user dismisses it.
  static Future<bool> share(File file) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('File sharing through this API requires iOS.');
    }
    if (!await file.exists() || await file.length() == 0) {
      throw FileSystemException('The file to share is missing or empty.', file.path);
    }
    return await _channel.invokeMethod<bool>('shareFile', {'path': file.path}) ??
        false;
  }
}
