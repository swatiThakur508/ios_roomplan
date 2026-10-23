import 'dart:convert';

import 'package:ios_roomplan/api/room_plan_scanner.dart' as scanner;
import 'package:ios_roomplan/api/models/scan_result.dart';

/// Compatibility facade for callers that used the previous optimized mapper.
/// Parsing is kept in one implementation to prevent the two code paths drifting.
class OptimizedMapper {
  static final Set<String> _categories = <String>{};
  static int _parsedCount = 0;

  static ScanResult? parseScanResult(String? source) {
    if (source == null) return null;
    try {
      _collectCategories(jsonDecode(source));
    } on FormatException {
      // The shared parser reports malformed payloads consistently below.
    }
    _parsedCount++;
    return scanner.parseScanResult(source);
  }

  static Map<String, dynamic> getPerformanceStats() => {
    'category_cache_size': _categories.length,
    'parsed_result_count': _parsedCount,
  };

  static void clearCaches() {
    _categories.clear();
    _parsedCount = 0;
  }

  static void _collectCategories(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key == 'category' && entry.value is String) {
          _categories.add(entry.value as String);
        } else {
          _collectCategories(entry.value);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        _collectCategories(item);
      }
    }
  }
}
