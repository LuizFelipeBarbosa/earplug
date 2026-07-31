/// Short date names, in the one casing each surface starts from.
///
/// Index with `DateTime.weekday - 1` and `DateTime.month - 1`.
library;

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
