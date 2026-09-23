/// Adds whole months, keeping the day where possible: Jan 31 + 1 month
/// becomes Feb 28 (or 29), not March 3.
DateTime addMonths(DateTime date, int months) {
  final firstOfTarget = DateTime(date.year, date.month + months);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  return DateTime(
    firstOfTarget.year,
    firstOfTarget.month,
    date.day > lastDay ? lastDay : date.day,
    date.hour,
    date.minute,
  );
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from today to [date]: 0 = today, negative = in the past.
int daysFromToday(DateTime date) {
  final today = dateOnly(DateTime.now());
  return dateOnly(date).difference(today).inHours ~/ 24;
}

/// "8 months", "1 year 3 months", "12 days".
String describeSpan(DateTime from, DateTime to) {
  var months = (to.year - from.year) * 12 + (to.month - from.month);
  if (to.day < from.day) months -= 1;
  if (months < 1) {
    final days = to.difference(from).inDays;
    return '$days ${days == 1 ? 'day' : 'days'}';
  }
  final years = months ~/ 12;
  final rest = months % 12;
  final parts = [
    if (years > 0) '$years ${years == 1 ? 'year' : 'years'}',
    if (rest > 0) '$rest ${rest == 1 ? 'month' : 'months'}',
  ];
  return parts.join(' ');
}
