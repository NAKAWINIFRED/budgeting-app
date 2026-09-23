import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../debts/add_debt_sheet.dart';
import '../debts/debt_labels.dart';
import '../debts/debt_providers.dart';
import '../savings/goal_sheet.dart';
import '../savings/savings_labels.dart';
import '../savings/savings_providers.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
        children: const [
          _SavingsSection(),
          SizedBox(height: 40),
          _DebtsSection(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

// ============================================================================
// SAVINGS
// ============================================================================

class _SavingsSection extends ConsumerWidget {
  const _SavingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(savingsOverviewProvider);
    final text = Theme.of(context).textTheme;
    const currency = kDefaultCurrency;

    return overview.when(
      loading: () => const SizedBox(height: 120),
      error: (e, _) => Text('Could not load your savings.\n$e'),
      data: (o) {
        final hasAnything = o.goals.isNotEmpty || o.general.savedMinor != 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasAnything) ...[
              Text(
                'Total saved',
                style: text.bodyMedium?.copyWith(color: AppColors.mist),
              ),
              const SizedBox(height: 4),
              Text(
                Money.format(o.totalSavedMinor, currency),
                style: AppText.amount(34, weight: FontWeight.w800),
              ),
              if (o.thisMonthMinor != 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      o.thisMonthMinor > 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      color: o.thisMonthMinor > 0
                          ? AppColors.tide
                          : AppColors.mist,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${o.thisMonthMinor > 0 ? 'Up' : 'Down'} '
                      '${Money.format(o.thisMonthMinor.abs(), currency)} this month',
                      style: text.bodyMedium?.copyWith(
                        color: o.thisMonthMinor > 0
                            ? AppColors.tide
                            : AppColors.mist,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
            ],
            _Header(
              title: 'Savings goals',
              actionLabel: 'New goal',
              onAction: () => showGoalSheet(context),
            ),
            const SizedBox(height: 8),
            if (o.goals.isEmpty) ...[
              Text(
                'Give your money a job: an emergency fund, school fees, a '
                'phone, a trip. Goals make saving easier to stick to.',
                style: text.bodyMedium?.copyWith(color: AppColors.mist),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showGoalSheet(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create your first goal'),
              ),
              const SizedBox(height: 12),
            ],
            for (final g in o.goals) ...[
              _GoalTile(progress: g),
              const SizedBox(height: 12),
            ],
            if (o.general.savedMinor != 0) _GoalTile(progress: o.general),
          ],
        );
      },
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    const currency = kDefaultCurrency;
    final text = Theme.of(context).textTheme;
    final g = progress;
    final goal = g.goal;
    final color = savingsProgressColor(g.progress);
    final remaining =
        g.remainingMinor == null ? null : Money.format(g.remainingMinor!, currency);

    final details = <String>[
      if (g.hasTarget)
        'Saved ${Money.format(g.savedMinor, currency)} of '
            '${Money.format(g.targetMinor!, currency)} '
            '(${(g.progress! * 100).floor()}%)',
      if (goal?.targetDate != null && !g.isReached)
        'Target date: ${DateFormat.yMMMd().format(goal!.targetDate!)}',
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: goal == null ? null : () => showGoalSheet(context, existing: goal),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: g.progress ?? 0,
                          strokeWidth: 5,
                          backgroundColor: AppColors.line,
                          color: color,
                        ),
                      ),
                      Icon(
                        g.isReached ? Icons.check_rounded : iconFor(g.iconKey),
                        color: g.isReached ? AppColors.tide : AppColors.deepWater,
                        size: 22,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.name,
                        style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        goal == null
                            ? 'Not tied to a goal'
                            : goal.term.label,
                        style: text.bodySmall?.copyWith(color: AppColors.mist),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.format(g.savedMinor, currency),
                      style: AppText.amount(17),
                    ),
                    Text(
                      'saved',
                      style: text.bodySmall?.copyWith(color: AppColors.mist),
                    ),
                  ],
                ),
              ],
            ),
            if (goal != null) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      savingsEncouragement(g.progress, remaining),
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            if (details.isNotEmpty || g.thisMonthMinor != 0) const SizedBox(height: 10),
            for (final line in details)
              Text(line, style: text.bodySmall?.copyWith(color: AppColors.mist)),
            if (g.thisMonthMinor > 0)
              Text(
                'Up ${Money.format(g.thisMonthMinor, currency)} this month',
                style: text.bodySmall?.copyWith(
                  color: AppColors.tide,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (g.monthlyNeededMinor != null)
              Text(
                'Save about ${Money.format(g.monthlyNeededMinor!, currency)} a '
                'month to reach it on time',
                style: text.bodySmall?.copyWith(
                  color: AppColors.deepWater,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (g.isPastDate)
              Text(
                'The target date has passed. Tap to pick a new one. You have '
                'saved ${Money.format(g.savedMinor, currency)} so far.',
                style: text.bodySmall?.copyWith(color: AppColors.mist),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DEBTS
// ============================================================================

class _DebtsSection extends ConsumerWidget {
  const _DebtsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(debtOverviewProvider);

    return overview.when(
      loading: () => const SizedBox(height: 120),
      error: (e, _) => Text('Could not load your debts.\n$e'),
      data: (o) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (o.active.isNotEmpty) ...[
            _DebtSummary(overview: o),
            const SizedBox(height: 28),
          ],
          _Header(
            title: 'Debts',
            actionLabel: 'Add debt',
            onAction: () => showAddDebtSheet(context),
          ),
          const SizedBox(height: 8),
          if (o.active.isEmpty)
            const _EmptyDebts()
          else
            for (final d in o.active) ...[
              _DebtTile(progress: d),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------

class _DebtSummary extends StatelessWidget {
  const _DebtSummary({required this.overview});

  final DebtOverview overview;

  @override
  Widget build(BuildContext context) {
    const currency = kDefaultCurrency;
    final text = Theme.of(context).textTheme;
    final o = overview;
    final color = debtProgressColor(o.progress);
    final percent = (o.progress * 100).floor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Debt left to pay',
          style: text.bodyMedium?.copyWith(color: AppColors.mist),
        ),
        const SizedBox(height: 4),
        Text(
          Money.format(o.remainingMinor, currency),
          style: AppText.amount(34, weight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: o.progress,
          minHeight: 10,
          borderRadius: BorderRadius.circular(10),
          backgroundColor: AppColors.line,
          color: color,
        ),
        const SizedBox(height: 8),
        Text(
          '$percent% paid off of ${Money.format(o.totalMinor, currency)}',
          style: text.bodyMedium?.copyWith(color: AppColors.mist),
        ),
        if (o.paidThisMonthMinor > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.trending_down_rounded, color: AppColors.tide, size: 20),
              const SizedBox(width: 6),
              Text(
                'Down ${Money.format(o.paidThisMonthMinor, currency)} this month',
                style: text.bodyMedium?.copyWith(
                  color: AppColors.tide,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------------------------

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.progress});

  final DebtProgress progress;

  @override
  Widget build(BuildContext context) {
    const currency = kDefaultCurrency;
    final text = Theme.of(context).textTheme;
    final p = progress;
    final debt = p.debt;
    final color = debtProgressColor(p.progress);
    final remaining = Money.format(p.remainingMinor, currency);
    final subtitle =
        debt.lender == null ? debt.debtType.label : 'Owed to ${debt.lender}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Progress ring around the debt's icon.
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: p.progress,
                        strokeWidth: 5,
                        backgroundColor: AppColors.line,
                        color: color,
                      ),
                    ),
                    Icon(
                      p.isPaidOff ? Icons.check_rounded : debt.debtType.icon,
                      color: p.isPaidOff ? AppColors.tide : AppColors.deepWater,
                      size: 22,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debt.name,
                      style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(color: AppColors.mist),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(remaining, style: AppText.amount(17)),
                  Text(
                    p.isPaidOff ? 'paid off' : 'left',
                    style: text.bodySmall?.copyWith(color: AppColors.mist),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  debtEncouragement(p.progress, remaining),
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Paid ${Money.format(p.paidMinor, currency)} of '
            '${Money.format(p.totalMinor, currency)} '
            '(${(p.progress * 100).floor()}%)',
            style: text.bodySmall?.copyWith(color: AppColors.mist),
          ),
          if (p.paidThisMonthMinor > 0)
            Text(
              'Down ${Money.format(p.paidThisMonthMinor, currency)} this month',
              style: text.bodySmall?.copyWith(
                color: AppColors.tide,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (!p.isPaidOff && debt.minimumPaymentMinor != null)
            Text(
              'No payment yet this month',
              style: text.bodySmall?.copyWith(color: AppColors.mist),
            ),
          if (p.monthsLeft != null)
            Text(
              'About ${p.monthsLeft} ${p.monthsLeft == 1 ? 'month' : 'months'} to go '
              'at ${Money.format(debt.minimumPaymentMinor!, currency)} a month',
              style: text.bodySmall?.copyWith(color: AppColors.mist),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------

class _EmptyDebts extends StatelessWidget {
  const _EmptyDebts();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Track what you owe and watch it shrink. A car loan, school fees, '
          'money from a friend: add anything you are paying back.',
          style: text.bodyMedium?.copyWith(color: AppColors.mist),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => showAddDebtSheet(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add your first debt'),
        ),
      ],
    );
  }
}
