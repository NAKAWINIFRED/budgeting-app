import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/database.dart';

extension DebtTypeLabels on DebtType {
  String get label => switch (this) {
        DebtType.carLoan => 'Car loan',
        DebtType.studentLoan => 'School / student loan',
        DebtType.mortgage => 'Mortgage / home loan',
        DebtType.creditCard => 'Credit card',
        DebtType.personalLoan => 'Bank / personal loan',
        DebtType.familyOrFriend => 'Family or friend',
        DebtType.mobileLoan => 'Mobile / app loan',
        DebtType.medical => 'Medical bill',
        DebtType.business => 'Business loan',
        DebtType.other => 'Other',
      };

  IconData get icon => switch (this) {
        DebtType.carLoan => Icons.directions_car_rounded,
        DebtType.studentLoan => Icons.school_rounded,
        DebtType.mortgage => Icons.home_rounded,
        DebtType.creditCard => Icons.credit_card_rounded,
        DebtType.personalLoan => Icons.account_balance_rounded,
        DebtType.familyOrFriend => Icons.people_rounded,
        DebtType.mobileLoan => Icons.phone_android_rounded,
        DebtType.medical => Icons.medical_services_rounded,
        DebtType.business => Icons.storefront_rounded,
        DebtType.other => Icons.more_horiz_rounded,
      };
}

/// The debt's color shifts as it shrinks: amber when just started,
/// through green, to Tidewise teal when paid off.
Color debtProgressColor(double progress) {
  final t = progress.clamp(0.0, 1.0).toDouble();
  return HSVColor.lerp(
    HSVColor.fromColor(AppColors.amber),
    HSVColor.fromColor(AppColors.tide),
    t,
  )!
      .toColor();
}

/// A short, encouraging line that changes as the debt goes down.
String debtEncouragement(double progress, String remainingText) {
  if (progress >= 1) return 'Paid off. You did it!';
  if (progress >= 0.9) return 'Almost free. Just $remainingText left.';
  if (progress >= 0.75) return 'Three quarters paid. The finish line is in sight.';
  if (progress >= 0.5) return 'Past halfway. The hardest part is behind you.';
  if (progress >= 0.25) return 'A quarter paid off. Keep the momentum going.';
  if (progress > 0) return 'You have started. Every payment shrinks it.';
  return 'Your first payment starts the countdown.';
}

/// If a payment crosses 25%, 50%, 75% or 100%, returns a celebration line.
String? milestoneMessage({
  required String debtName,
  required int totalMinor,
  required int paidBeforeMinor,
  required int paymentMinor,
}) {
  if (totalMinor <= 0) return null;
  final after = paidBeforeMinor + paymentMinor;
  bool crossed(int quarters) =>
      paidBeforeMinor * 4 < totalMinor * quarters &&
      after * 4 >= totalMinor * quarters;

  if (crossed(4)) return '$debtName is paid off!';
  if (crossed(3)) return 'Three quarters of $debtName paid. Almost there!';
  if (crossed(2)) return 'Halfway through $debtName. Great work!';
  if (crossed(1)) return 'A quarter of $debtName paid off. Keep going!';
  return null;
}
