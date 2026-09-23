import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../dashboard/dashboard_providers.dart';

// ============================================================================
// PLAIN-LANGUAGE EXPLANATIONS (the financial literacy part)
// ============================================================================

String tagExplanation(BudgetTag tag) => switch (tag) {
      BudgetTag.essentials =>
        'Costs you must pay to live and work: rent, food, transport, utilities, school fees and minimum debt payments.',
      BudgetTag.wants =>
        'Things that make life enjoyable but could be paused if needed: eating out, entertainment, shopping and treats.',
      BudgetTag.longTermSavings =>
        'Money for the future you, like retirement or investments. The earlier it starts, the more time it has to grow.',
      BudgetTag.shortTermSavings =>
        'An emergency fund and goals within a year or two, so a surprise bill does not turn into new debt.',
      BudgetTag.debt =>
        'Paying more than the minimum on what you owe. It clears debt faster and means less interest overall.',
    };

String bucketExplanation(BudgetBucket bucket) =>
    bucket.tagList.map(tagExplanation).join('\n\n');

// ============================================================================
// STATUS OF ONE BUCKET
// ============================================================================

class BucketStatus {
  BucketStatus(this.label, this.color);

  final String label;
  final Color color;
}

BucketStatus bucketStatus(BucketProgress b, String currency) {
  final diff = b.remainingMinor.abs();
  final amount = Money.format(diff, currency);

  if (b.allocatedMinor <= 0) return BucketStatus('No income yet', AppColors.mist);

  if (b.isGoodWhenOver) {
    if (b.remainingMinor <= 0) {
      return b.remainingMinor == 0
          ? BucketStatus('Target reached', AppColors.tide)
          : BucketStatus('$amount extra', AppColors.tide);
    }
    return BucketStatus('$amount to go', AppColors.mist);
  }

  if (b.remainingMinor >= 0) return BucketStatus('$amount left', AppColors.tide);
  // Over plan: amber for a little, red only when it's well over.
  return BucketStatus(
    '$amount over',
    b.ratio > 1.2 ? AppColors.buoyRed : AppColors.amber,
  );
}

// ============================================================================
// TIPS
// Friendly, specific, never judgy. At most three, most useful first.
// ============================================================================

class PlanTip {
  PlanTip(this.icon, this.text, this.color);

  final IconData icon;
  final String text;
  final Color color;
}

List<PlanTip> buildPlanTips(DashboardSummary s) {
  final currency = s.currency;
  String fmt(int minor) => Money.format(minor, currency);

  if (s.incomeMinor <= 0) {
    return [
      PlanTip(
        Icons.lightbulb_outline_rounded,
        'Add the income you receive this month and your plan will work out '
        'how much belongs in each bucket. Paid daily or weekly? Add each '
        'payment as it arrives and the targets grow with it.',
        AppColors.tide,
      ),
    ];
  }

  final tips = <PlanTip>[];
  final spendingBuckets = s.buckets.where((b) => !b.isGoodWhenOver).toList();
  final savingBuckets = s.buckets.where((b) => b.isGoodWhenOver).toList();

  // 1. Spending buckets that are over plan.
  for (final b in spendingBuckets.where((b) => b.remainingMinor < 0)) {
    final over = fmt(-b.remainingMinor);
    final top = _topCategory(s, b);
    final buffer = StringBuffer('${b.bucket.name} is $over over plan.');

    if (top != null) {
      buffer.write(' ${top.$1.name} is the biggest part at ${fmt(top.$2)}.');
      if (top.$1.budgetTag == BudgetTag.essentials) {
        buffer.write(
          ' Costs like this are hard to cut quickly, so it is okay to balance '
          'it with a little less on wants, or pick a plan with more room for '
          'needs while things are tight.',
        );
      } else {
        buffer.write(
          ' Easing off here for the rest of the month would close the gap.',
        );
      }
    }
    tips.add(PlanTip(Icons.info_outline_rounded, buffer.toString(), AppColors.amber));
  }

  // 2. Saving buckets still short of target.
  for (final b in savingBuckets.where((b) => b.remainingMinor > 0)) {
    final gap = b.remainingMinor;
    final roomy = spendingBuckets
        .where((sb) => sb.remainingMinor > 0)
        .fold<BucketProgress?>(
          null,
          (best, sb) =>
              best == null || sb.remainingMinor > best.remainingMinor ? sb : best,
        );

    final text = roomy != null
        ? '${b.bucket.name} is ${fmt(gap)} short of its target. '
            '${roomy.bucket.name} still has ${fmt(roomy.remainingMinor)} left; '
            'moving ${fmt(gap < roomy.remainingMinor ? gap : roomy.remainingMinor)} '
            'across would get you there.'
        : '${b.bucket.name} is ${fmt(gap)} short of its target. Even a small '
            'amount counts; try setting some aside when your next income arrives.';
    tips.add(PlanTip(Icons.savings_outlined, text, AppColors.tide));
  }

  // 3. Everything on plan.
  if (tips.isEmpty) {
    tips.add(
      PlanTip(
        Icons.check_circle_outline_rounded,
        'Everything is on plan so far this month. That is exactly how '
        'good money habits are built.',
        AppColors.tide,
      ),
    );
  }

  return tips.take(3).toList();
}

/// Biggest spending category this month inside a bucket.
(CategoryItem, int)? _topCategory(DashboardSummary s, BucketProgress b) {
  final tags = b.bucket.tagList;
  (CategoryItem, int)? top;
  for (final entry in s.spentByCategory.entries) {
    final category = s.categories[entry.key];
    if (category == null || !tags.contains(category.budgetTag)) continue;
    if (top == null || entry.value > top.$2) top = (category, entry.value);
  }
  return top;
}
