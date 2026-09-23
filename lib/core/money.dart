import 'dart:math';

import 'package:intl/intl.dart';

/// All money in Tidewise is stored as whole integers in the currency's
/// smallest unit ("minor units"): 1234.50 USD is stored as 123450,
/// 5000 RWF is stored as 5000 (RWF has no decimal places).
class Money {
  Money._();

  /// How many decimal places a currency uses (USD = 2, RWF = 0, JPY = 0).
  static int fractionDigits(String currency) =>
      NumberFormat.simpleCurrency(name: currency).decimalDigits ?? 2;

  /// What the user typed (e.g. 12.5) -> stored integer (e.g. 1250 for USD).
  static int toMinor(num amount, String currency) =>
      (amount * pow(10, fractionDigits(currency))).round();

  /// Stored integer -> number for display or maths.
  static double fromMinor(int minor, String currency) =>
      minor / pow(10, fractionDigits(currency));

  /// Stored integer -> nicely formatted string, e.g. "$1,234.50".
  static String format(int minor, String currency, {String? locale}) {
    final formatter =
        NumberFormat.simpleCurrency(locale: locale, name: currency);
    return formatter.format(fromMinor(minor, currency));
  }

  /// Share of an amount by basis points (5000 = 50%), rounded down so
  /// buckets never add up to more than the money that actually came in.
  static int share(int minor, int basisPoints) => minor * basisPoints ~/ 10000;
}
