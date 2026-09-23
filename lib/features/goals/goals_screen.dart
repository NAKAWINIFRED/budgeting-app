import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../debts/add_debt_sheet.dart';
import '../debts/debt_labels.dart';
import '../debts/debt_providers.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(debtOverviewProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load your debts.\n$e')),
        data: (o) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
          children: [
            if (o.active.isNotEmpty) ...[
              _DebtSummary(overview: o),
              const SizedBox(height: 32),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Debts',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => showAddDebtSheet(context),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Add debt'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (o.active.isEmpty)
              const _EmptyDebts()
            else
              for (final d in o.active) ...[
                _DebtTile(progress: d),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 24),
            Text(
              'Savings goals',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Savings goals with targets and progress are coming next.',
              style: text.bodyMedium?.copyWith(color: AppColors.mist),
            ),
          ],
        ),
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
