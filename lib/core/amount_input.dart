import 'package:flutter/services.dart';

import 'money.dart';

/// Only allows valid amounts while typing: digits plus, for currencies with
/// cents, one decimal separator (. or ,) and the right number of decimals.
TextInputFormatter amountInputFormatter(String currency) {
  final digits = Money.fractionDigits(currency);
  final pattern = digits > 0
      ? RegExp('^\\d{0,12}([.,]\\d{0,$digits})?\$')
      : RegExp(r'^\d{0,12}$');
  return TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        pattern.hasMatch(newValue.text) ? newValue : oldValue,
  );
}

/// Turns what the user typed into stored minor units (0 if empty/invalid).
int parseAmountMinor(String text, String currency) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  return value == null ? 0 : Money.toMinor(value, currency);
}
