import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/database.dart';

extension SavingsTermLabels on SavingsTerm {
  String get label => switch (this) {
        SavingsTerm.shortTerm => 'Within 2 years',
        SavingsTerm.longTerm => 'Long-term',
      };

  String get explanation => switch (this) {
        SavingsTerm.shortTerm =>
          'An emergency fund, rent, school fees, a phone: things you will need soon.',
        SavingsTerm.longTerm =>
          'Retirement, investments, a house: the future you, years from now.',
      };
}

/// Icons a user can pick for a goal (keys from category_icons.dart).
const goalIconKeys = [
  'savings',
  'shield',
  'home',
  'directions_car',
  'school',
  'flight',
  'phone_iphone',
  'celebration',
  'beach_access',
  'favorite',
  'trending_up',
  'storefront',
];

const _sky = Color(0xFF4F9FD8);

/// A goal's color deepens from sky blue to Tidewise teal as it fills up.
Color savingsProgressColor(double? progress) {
  if (progress == null) return AppColors.tide;
  return HSVColor.lerp(
    HSVColor.fromColor(_sky),
    HSVColor.fromColor(AppColors.tide),
    progress.clamp(0.0, 1.0).toDouble(),
  )!
      .toColor();
}

String savingsEncouragement(double? progress, String? remainingText) {
  if (progress == null) {
    return 'No target set. Everything you add builds your cushion.';
  }
  if (progress >= 1) return 'Goal reached. Well done!';
  if (progress >= 0.9) return 'Almost there. Just $remainingText to go.';
  if (progress >= 0.75) return 'Three quarters saved. So close now.';
  if (progress >= 0.5) return 'Halfway there. Keep it flowing.';
  if (progress >= 0.25) return 'A quarter of the way. Small amounts add up.';
  if (progress > 0) return 'Off to a good start. Every deposit counts.';
  return 'Every goal starts with the first deposit.';
}

/// Celebration line if a deposit crosses 25%, 50% or 75% of the target.
/// (Reaching 100% gets its own celebration dialog.)
String? savingsMilestoneMessage({
  required String goalName,
  required int targetMinor,
  required int savedBeforeMinor,
  required int depositMinor,
}) {
  if (targetMinor <= 0) return null;
  final after = savedBeforeMinor + depositMinor;
  bool crossed(int quarters) =>
      savedBeforeMinor * 4 < targetMinor * quarters &&
      after * 4 >= targetMinor * quarters;

  if (crossed(3)) return 'Three quarters of $goalName saved. Almost there!';
  if (crossed(2)) return 'Halfway to $goalName. Great work!';
  if (crossed(1)) return 'A quarter of $goalName saved. Keep going!';
  return null;
}
