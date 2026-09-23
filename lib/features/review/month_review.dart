import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/key_values.dart';
import '../dashboard/dashboard_providers.dart';
import '../debts/debt_providers.dart';
import '../investments/investment_sheets.dart';
import '../investments/investments_providers.dart';
import '../savings/savings_providers.dart';
import '../transactions/quick_add_sheet.dart';

/// Which month to review right now, if any: the current month in its last
/// 3 days, or the previous month during the first 7 days of a new one.
(DateTime, bool)? monthToReview(DateTime now) {
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  if (now.day <= 7) return (DateTime(now.year, now.month - 1), false);
  if (now.day >= daysInMonth - 2) return (DateTime(now.year, now.month), true);
  return null;
}

String _reviewKey(DateTime month) =>
    'review_dismissed:${DateFormat('yyyy-MM').format(month)}';

final _reviewDismissedProvider =
    StreamProvider.family<bool, DateTime>((ref, month) {
  return ref
      .watch(keyValueStoreProvider)
      .watch(_reviewKey(month))
      .map((v) => v == 'true');
});

class _Suggestion {
  _Suggestion({
    required this.icon,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String buttonLabel;
  final void Function(BuildContext context) onTap;
}

class MonthReviewCard extends ConsumerWidget {
  const MonthReviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = monthToReview(DateTime.now());
    if (review == null) return const SizedBox.shrink();
    final (month, isCurrent) = review;

    final dismissed = ref.watch(_reviewDismissedProvider(month)).value ?? true;
    final summary = ref.watch(monthSummaryProvider(month)).value;
    if (dismissed || summary == null || summary.incomeMinor <= 0) {
      return const SizedBox.shrink();
    }

    final savings = ref.watch(savingsOverviewProvider).value;
    final debts = ref.watch(debtOverviewProvider).value;
    final investments = ref.watch(investmentsOverviewProvider).value;

    final currency = kDefaultCurrency;
    final text = Theme.of(context).textTheme;
    final monthName = DateFormat.MMMM().format(month);
    final income = summary.incomeMinor;
    final left = summary.safeToSpendMinor;
    String fmt(int m) => Money.format(m, currency);

    late final String headline;
    late final String body;
    var suggestions = <_Suggestion>[];

    if (left > 0) {
      final percent = (left * 100 / income).round();
      headline = isCurrent
          ? '$monthName is almost over and you still have ${fmt(left)}'
          : 'You kept ${fmt(left)} from $monthName';
      body = 'Out of ${fmt(income)} that came in, ${fmt(left)} is still yours '
          '($percent%). That is a real achievement; many people end the '
          'month with nothing left. Here is a simple way to make it work '
          'for you:';
      suggestions = _buildSuggestions(left, savings, debts, investments);
    } else if (left == 0) {
      headline = 'Every bit of $monthName\'s money had a job';
      body = 'You used exactly what came in. Next month, try moving even 5% '
          'to savings the day your income arrives. Paying yourself first '
          'makes saving automatic.';
    } else {
      headline = '$monthName was tight';
      body = '${fmt(-left)} more went out than came in. It happens to '
          'everyone. The Plan tab shows where the money went and what to '
          'adjust, and every month is a fresh start.';
    }

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: left > 0 ? AppColors.shallows : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: left > 0 ? AppColors.tide : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                left > 0
                    ? Icons.emoji_events_rounded
                    : left == 0
                        ? Icons.balance_rounded
                        : Icons.waves_rounded,
                color: left > 0 ? AppColors.tide : AppColors.deepWater,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: text.bodyMedium),
          for (final s in suggestions) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(s.icon, size: 22, color: AppColors.deepWater),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(s.body, style: text.bodySmall),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => s.onTap(context),
                          child: Text(s.buttonLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (left < 0)
                TextButton(
                  onPressed: () => context.go('/plan'),
                  child: const Text('Open my plan'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(keyValueStoreProvider).set(_reviewKey(month), 'true'),
                child: const Text('Got it'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_Suggestion> _buildSuggestions(
    int left,
    SavingsOverview? savings,
    DebtOverview? debts,
    InvestmentsOverview? investments,
  ) {
    final currency = kDefaultCurrency;
    String fmt(int m) => Money.format(m, currency);

    final activeDebts =
        (debts?.active ?? []).where((d) => !d.isPaidOff).toList()
          ..sort((a, b) => a.remainingMinor.compareTo(b.remainingMinor));
    final hasDebt = activeDebts.isNotEmpty;

    // Suggested split of what is left.
    final debtShare = hasDebt ? Money.share(left, 4000) : 0;
    final safetyShare = Money.share(left, hasDebt ? 3000 : 5000);
    final investShare = Money.share(left, hasDebt ? 2000 : 4000);
    final treatShare = left - debtShare - safetyShare - investShare;

    final result = <_Suggestion>[];

    if (hasDebt) {
      final d = activeDebts.first;
      result.add(
        _Suggestion(
          icon: Icons.payments_rounded,
          title: 'Pay ${fmt(debtShare)} extra on ${d.debt.name}',
          body: 'It is your smallest debt (${fmt(d.remainingMinor)} left). '
              'Clearing it frees up money every month after.',
          buttonLabel: 'Record the payment',
          onTap: (context) => showQuickAddSheet(
            context,
            kind: TransactionKind.debtPayment,
            debtId: d.debt.id,
            amountMinor: debtShare,
          ),
        ),
      );
    }

    final shortGoal = savings?.goals
        .where((g) => g.goal?.term == SavingsTerm.shortTerm && !g.isReached)
        .firstOrNull;
    result.add(
      _Suggestion(
        icon: Icons.shield_rounded,
        title: 'Put ${fmt(safetyShare)} in '
            '${shortGoal?.name ?? 'your safety net'}',
        body: 'An emergency fund means a surprise bill does not become new '
            'debt. A good first target is one month of expenses.',
        buttonLabel: 'Move it to savings',
        onTap: (context) => showQuickAddSheet(
          context,
          kind: TransactionKind.savingsDeposit,
          goalId: shortGoal?.goal?.id,
          amountMinor: safetyShare,
        ),
      ),
    );

    final investment = investments?.items.firstOrNull;
    result.add(
      investment != null
          ? _Suggestion(
              icon: Icons.trending_up_rounded,
              title: 'Grow ${fmt(investShare)} in ${investment.goal.name}',
              body: 'Money that is invested can earn more money over time. '
                  'Small, regular amounts add up the most.',
              buttonLabel: 'Add to investment',
              onTap: (context) => showQuickAddSheet(
                context,
                kind: TransactionKind.savingsDeposit,
                goalId: investment.goal.id,
                amountMinor: investShare,
              ),
            )
          : _Suggestion(
              icon: Icons.trending_up_rounded,
              title: 'Start growing ${fmt(investShare)}',
              body: 'Money kept in a drawer loses value over time. A savings '
                  'account with interest, a fund or government bonds let it '
                  'grow. Start small, and only with money you will not need soon.',
              buttonLabel: 'Track an investment',
              onTap: (context) => showInvestmentSheet(context),
            ),
    );

    result.add(
      _Suggestion(
        icon: Icons.card_giftcard_rounded,
        title: 'Treat yourself to ${fmt(treatShare)}',
        body: 'You earned it. Enjoy it guilt-free: a nice meal or something '
            'small you have wanted. Rewards make good habits stick.',
        buttonLabel: 'Log my treat',
        onTap: (context) => showQuickAddSheet(
          context,
          kind: TransactionKind.expense,
          amountMinor: treatShare,
          note: 'Treat',
        ),
      ),
    );

    return result;
  }
}
