import 'dart:ui' show PlatformDispatcher;

import 'package:intl/intl.dart';

/// Currencies offered during onboarding: (code, name).
const currencies = <(String, String)>[
  ('USD', 'US Dollar'),
  ('EUR', 'Euro'),
  ('GBP', 'British Pound'),
  ('RWF', 'Rwandan Franc'),
  ('KES', 'Kenyan Shilling'),
  ('UGX', 'Ugandan Shilling'),
  ('TZS', 'Tanzanian Shilling'),
  ('BIF', 'Burundian Franc'),
  ('CDF', 'Congolese Franc'),
  ('ETB', 'Ethiopian Birr'),
  ('SSP', 'South Sudanese Pound'),
  ('SOS', 'Somali Shilling'),
  ('NGN', 'Nigerian Naira'),
  ('GHS', 'Ghanaian Cedi'),
  ('XOF', 'West African CFA Franc'),
  ('XAF', 'Central African CFA Franc'),
  ('ZAR', 'South African Rand'),
  ('ZMW', 'Zambian Kwacha'),
  ('MWK', 'Malawian Kwacha'),
  ('MZN', 'Mozambican Metical'),
  ('ZWG', 'Zimbabwe Gold'),
  ('BWP', 'Botswana Pula'),
  ('NAD', 'Namibian Dollar'),
  ('AOA', 'Angolan Kwanza'),
  ('EGP', 'Egyptian Pound'),
  ('MAD', 'Moroccan Dirham'),
  ('TND', 'Tunisian Dinar'),
  ('DZD', 'Algerian Dinar'),
  ('INR', 'Indian Rupee'),
  ('PKR', 'Pakistani Rupee'),
  ('BDT', 'Bangladeshi Taka'),
  ('LKR', 'Sri Lankan Rupee'),
  ('NPR', 'Nepalese Rupee'),
  ('CNY', 'Chinese Yuan'),
  ('JPY', 'Japanese Yen'),
  ('KRW', 'South Korean Won'),
  ('PHP', 'Philippine Peso'),
  ('IDR', 'Indonesian Rupiah'),
  ('MYR', 'Malaysian Ringgit'),
  ('SGD', 'Singapore Dollar'),
  ('THB', 'Thai Baht'),
  ('VND', 'Vietnamese Dong'),
  ('AED', 'UAE Dirham'),
  ('SAR', 'Saudi Riyal'),
  ('QAR', 'Qatari Riyal'),
  ('TRY', 'Turkish Lira'),
  ('ILS', 'Israeli Shekel'),
  ('CAD', 'Canadian Dollar'),
  ('AUD', 'Australian Dollar'),
  ('NZD', 'New Zealand Dollar'),
  ('MXN', 'Mexican Peso'),
  ('BRL', 'Brazilian Real'),
  ('ARS', 'Argentine Peso'),
  ('COP', 'Colombian Peso'),
  ('CLP', 'Chilean Peso'),
  ('PEN', 'Peruvian Sol'),
  ('JMD', 'Jamaican Dollar'),
  ('CHF', 'Swiss Franc'),
  ('SEK', 'Swedish Krona'),
  ('NOK', 'Norwegian Krone'),
  ('DKK', 'Danish Krone'),
  ('PLN', 'Polish Zloty'),
  ('CZK', 'Czech Koruna'),
  ('HUF', 'Hungarian Forint'),
  ('RON', 'Romanian Leu'),
  ('UAH', 'Ukrainian Hryvnia'),
];

/// The currency of the phone's region, if we can tell (e.g. 'KES').
String? deviceCurrency() {
  try {
    final locale = PlatformDispatcher.instance.locale.toString();
    return NumberFormat.simpleCurrency(locale: locale).currencyName;
  } catch (_) {
    return null;
  }
}

String currencyName(String code) =>
    currencies.where((c) => c.$1 == code).firstOrNull?.$2 ?? code;
