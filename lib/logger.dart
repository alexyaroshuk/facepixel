import 'package:flutter/foundation.dart';

/// Professional logging utility that only logs in debug mode.
/// Use this instead of print() throughout the app.
class AppLogger {
  static const String _prefix = '[FacePixel]';

  /// Log an info message (debug builds only)
  static void info(String message, [String? tag]) {
    if (kDebugMode) {
      final tagStr = tag != null ? ' [$tag]' : '';
      debugPrint('$_prefix$tagStr: $message');
    }
  }

  /// Log an error message (debug builds only)
  static void error(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      final tagStr = tag != null ? ' [$tag]' : '';
      debugPrint('$_prefix$tagStr ERROR: $message');
      if (error != null) {
        debugPrint('  Exception: $error');
      }
      if (stackTrace != null) {
        debugPrint('  Stack trace: $stackTrace');
      }
    }
  }

  /// Log a warning message (debug builds only)
  static void warning(String message, [String? tag]) {
    if (kDebugMode) {
      final tagStr = tag != null ? ' [$tag]' : '';
      debugPrint('$_prefix$tagStr WARNING: $message');
    }
  }

  /// Log a debug message (debug builds only)
  static void debug(String message, [String? tag]) {
    if (kDebugMode) {
      final tagStr = tag != null ? ' [$tag]' : '';
      debugPrint('$_prefix$tagStr DEBUG: $message');
    }
  }
}
