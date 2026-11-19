import 'package:dio/dio.dart';

/// The server's `{ "error": "..." }` message when there is one, else [fallback].
/// Port of apiErrorMessage in apps/mobile/lib/vendor-context.tsx.
String apiErrorMessage(Object err, String fallback) {
  if (err is DioException) {
    final data = err.response?.data;
    if (data is Map && data['error'] is String) {
      final error = data['error'] as String;
      final details = data['details'];
      final issues = details is Map ? details['issues'] : null;
      if (issues is List && issues.isNotEmpty) return '$error: ${issues.join('; ')}';
      return error;
    }
  }
  return fallback;
}

/// No response at all: offline, DNS failure or timeout (as opposed to a server error).
bool isNetworkError(Object err) => err is DioException && err.response == null;
