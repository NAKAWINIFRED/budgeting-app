import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/main_scaffold.dart';
import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../activity/activity_providers.dart';
import '../activity/activity_screen.dart' show MonthSwitcher;
import '../activity/breakdown_view.dart' show BreakdownGroupTile;
import '../shared/day_grouped_list.dart';

class IncomeScreen extends ConsumerWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(monthIncomeBreakdownProvider);
    final activity = ref.watch(monthActivityProvider);
    final text = Theme.of(context).textTheme;
    final currency = kDefaultCurrency;

    return MainScaffold(
      title: 'Income',
      addKind: TransactionKind.income,
      body: Column(
        children: [
          const MonthSwitcher(),
          Expanded(
            child: breakdown.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load income.\n$e')),
              data: (b) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
                children: [
                  Text(
                    'Received this month',
                    style: text.bodyMedium?.copyWith(color: AppColors.mist),
                  ),
                  Text(
                    Money.format(b.totalMinor, currency),
                    style: AppText.amount(
                      34,
                      weight: FontWeight.w800,
                      color: AppColors.lagoon,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (b.groups.isEmpty)
                    Text(
                      'No income recorded this month yet. Paid daily, weekly '
                      'or whenever work comes in? Add each payment as it '
                      'arrives with the + button.',
                      style: text.bodyMedium?.copyWith(color: AppColors.mist),
                    ),
                  for (final g in b.groups)
                    BreakdownGroupTile(
                      group: g,
                      grandTotal: b.totalMinor,
                      currency: currency,
                      barColor: AppColors.lagoon,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.push('/categories?kind=income'),
                      icon: const Icon(Icons.tune_rounded, size: 20),
                      label: const Text('Manage income categories'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'All payments',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  DayGroupedList(
                    items: (activity.value?.items ?? const [])
                        .where((i) => i.tx.kind == TransactionKind.income)
                        .toList(),
                    emptyText: 'No payments yet this month.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
