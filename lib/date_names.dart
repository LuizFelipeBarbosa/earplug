/// Short date names, in the one casing each surface starts from.
///
/// Index with `DateTime.weekday - 1` and `DateTime.month - 1`.
library;

import 'package:flutter/material.dart' show TimeOfDay;

const List<String> weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The shouted form the flyer typography uses.
final List<String> weekdayNamesUpper = [
  for (final name in weekdayNames) name.toUpperCase(),
];

/// The shouted form the flyer typography uses.
final List<String> monthNamesUpper = [
  for (final name in monthNames) name.toUpperCase(),
];

/// "8PM" / "9:30PM" — the form the rest of the app stores doors times in.
String timeLabel(TimeOfDay t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minutes = t.minute == 0
      ? ''
      : ':${t.minute.toString().padLeft(2, '0')}';
  return '$hour$minutes${t.hour < 12 ? 'AM' : 'PM'}';
}
