import 'dart:math' as math;

import 'models.dart';

const _durationKey = 'timerDuration';
const defaultTimerDuration = 15 * 60;

int loadTimerDuration(LocalStore store) {
  try {
    final seconds = int.tryParse(store.read(_durationKey) ?? '');
    if (seconds != null && seconds >= 1 && seconds <= 43200) return seconds;
  } catch (_) {
    // Unavailable preferences fall back to the first-run duration.
  }
  return defaultTimerDuration;
}

Future<bool> saveTimerDuration(LocalStore store, int seconds) async {
  try {
    return await store.write(_durationKey, '$seconds');
  } catch (_) {
    return false;
  }
}

String formatCountdown(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = seconds ~/ 60 % 60;
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return hours == 0 ? '$minutes:$tail' : '$hours:${minutes.toString().padLeft(2, '0')}:$tail';
}

final _digits = RegExp(r'^\d+$');

int? _field(String value) {
  final text = value.trim();
  if (text.isEmpty) return 0;
  return _digits.hasMatch(text) ? int.tryParse(text) : null;
}

int? parseTimerDuration(String minutes, String seconds) {
  final min = _field(minutes);
  final sec = _field(seconds);
  if (min == null || sec == null || min > 720 || sec > 59) return null;
  final total = min * 60 + sec;
  return total >= 1 && total <= 43200 ? total : null;
}

String formatRemaining(num seconds) {
  final rounded = math.max(0, seconds.ceil());
  return [rounded ~/ 60, rounded % 60].map((n) => '$n'.padLeft(2, '0')).join(':');
}

/// Null means no write; the caller deduplicates the five-second steps.
int? fadeBrightness(int brightness, num remaining, bool enabled) =>
    !enabled || remaining > 55 || remaining <= 0
    ? null
    : math.max(1, (brightness * (remaining / 5).ceil() / 12).round());
