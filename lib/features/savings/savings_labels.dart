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

// A goal's color travels through three clearly different stops as it
// fills: soft blue (just started) -> Tidewise teal (halfway) -> green (done).
const _savingsStops = [
  Color(0xFF6F9FE0), // 0%   soft blue
  AppColors.tide, //    50%  teal
  Color(0xFF2E9D57), // 100% green
];

Color savingsProgressColor(double? progress) {
  if (progress == null) return AppColors.tide;
  final t = progress.clamp(0.0, 1.0).toDouble();
  final (from, to, local) = t < 0.5
      ? (_savingsStops[0], _savingsStops[1], t / 0.5)
      : (_savingsStops[1], _savingsStops[2], (t - 0.5) / 0.5);
  return HSVColor.lerp(
    HSVColor.fromColor(from),
    HSVColor.fromColor(to),
    local,
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
