import 'dart:io';

import 'package:ios_roomplan/api/room_plan_scanner.dart';

class RoomPlanAvailabilityService {
  static Future<bool>? _supportFuture;

  static Future<bool> isSupported() {
    return _supportFuture ??= _checkSupport();
  }

  static Future<bool> _checkSupport() async {
    if (!Platform.isIOS) return false;

    try {
      return await RoomPlanScanner.isSupported();
    } catch (_) {
      return false;
    }
  }
}
