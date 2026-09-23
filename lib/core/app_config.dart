/// App-wide settings, loaded from the database when the app starts
/// (see main.dart) and saved by onboarding.
class AppConfig {
  AppConfig._();

  /// ISO currency code, e.g. 'USD', 'EUR', 'KES', 'RWF', 'NGN'.
  static String currency = 'USD';

  /// Used for the Overview greeting. Null if the user skipped it.
  static String? userName;

  /// How the user usually gets paid (a PayRhythm name). Null until set.
  static String? payRhythm;

  /// Rough monthly income in minor units, if the user shared it.
  static int? typicalIncomeMinor;

  static bool onboardingDone = false;

  /// Phone notifications before bills are due.
  static bool billReminders = true;
}

/// The currency the whole app displays.
String get kDefaultCurrency => AppConfig.currency;

/// Keys used to store the settings above.
class SettingKeys {
  SettingKeys._();

  static const currency = 'currency';
  static const userName = 'user_name';
  static const payRhythm = 'pay_rhythm';
  static const typicalIncome = 'typical_income_minor';
  static const onboardingDone = 'onboarding_done';
  static const billReminders = 'bill_reminders';
}
