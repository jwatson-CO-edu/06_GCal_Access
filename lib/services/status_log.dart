import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart'
    show DetailedApiRequestError, ApiRequestError;
import 'package:googleapis_auth/googleapis_auth.dart'
    show ServerRequestFailedException;

enum StatusLevel { info, error }

class StatusEntry {
  StatusEntry(this.level, this.text) : time = DateTime.now();
  final StatusLevel level;
  final String text;
  final DateTime time;

  String get stamp {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

/// Human-readable text for a Dart exception or a Google API/auth error,
/// including the HTTP status code and Google's error reasons when present.
String formatError(Object e) {
  if (e is DetailedApiRequestError) {
    final reasons = [
      for (final d in e.errors)
        [
          if (d.reason != null) d.reason,
          if (d.domain != null) d.domain,
        ].join('/'),
    ].where((s) => s.isNotEmpty).join(', ');
    return 'Google API error ${e.status ?? '?'}: ${e.message ?? 'no message'}'
        '${reasons.isEmpty ? '' : ' [$reasons]'}';
  }
  if (e is ApiRequestError) return 'Google API error: ${e.message}';
  if (e is ServerRequestFailedException) {
    return 'Google auth error ${e.statusCode ?? '?'}: ${e.message}'
        '${e.responseContent == null ? '' : ' (${e.responseContent})'}';
  }
  return '${e.runtimeType}: $e';
}

/// Shared message log shown in the status panel at the bottom of the window.
class StatusLog extends ChangeNotifier {
  static const _max = 500;
  final entries = <StatusEntry>[];

  void info(String message) => _add(StatusLevel.info, message);

  void error(Object e, [StackTrace? stack, String? context]) {
    var text = formatError(e);
    if (context != null) text = '$context: $text';
    if (stack != null) {
      final frame = stack
          .toString()
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      if (frame.isNotEmpty) text = '$text\n    at ${frame.trim()}';
    }
    _add(StatusLevel.error, text);
  }

  void clear() {
    entries.clear();
    scheduleMicrotask(notifyListeners);
  }

  void _add(StatusLevel level, String text) {
    entries.add(StatusEntry(level, text));
    if (entries.length > _max) entries.removeRange(0, entries.length - _max);
    // Deferred so errors raised mid-build don't re-enter the widget tree.
    scheduleMicrotask(notifyListeners);
  }
}
