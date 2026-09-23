import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/main_scaffold.dart';
import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../activity/activity_screen.dart' show MonthSwitcher;
import '../shared/day_grouped_list.dart';
import '../subscriptions/subscription_sheet.dart';
import '../subscriptions/subscriptions_providers.dart';
import '../subscriptions/subscriptions_screen.dart';
import 'expenses_providers.dart';

String get _currency => kDefaultCurrency;

/// Big red total with a caption.
class _TotalHeader extends StatelessWidget {
  const _TotalHeader({required this.caption, required this.amountMinor});

  final String caption;
  final int amountMinor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: text.bodyMedium?.copyWith(color: AppColors.mist)),
        Text(
          Money.format(amountMinor, _currency),
          style: AppText.amount(34, weight: FontWeight.w800, color: AppColors.expense),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

// ============================================================================
// ALL EXPENSES
// ============================================================================

class ExpensesOverviewScreen extends ConsumerWidget {
  const ExpensesOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(expensesMonthProvider);
    final text = Theme.of(context).textTheme;

    return MainScaffold(
      title: 'Expenses',
      body: Column(
        children: [
          const MonthSwitcher(),
          Expanded(
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load expenses.\n$e')),
              data: (m) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
                children: [
                  _TotalHeader(caption: 'Spent this month', amountMinor: m.totalMinor),
                  const SizedBox(height: 20),
                  for (final section in ExpenseSection.values)
                    _SectionCard(
                      section: section,
                      totalMinor: m.sections[section]!.totalMinor,
                      share: m.totalMinor == 0
                          ? 0
                          : m.sections[section]!.totalMinor / m.totalMinor,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Savings deposits and debt payments are not counted as '
                    'expenses here. You will find them under Savings and Debt.',
                    style: text.bodySmall?.copyWith(color: AppColors.mist),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.totalMinor,
    required this.share,
  });

  final ExpenseSection section;
  final int totalMinor;
  final double share;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(section.route),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.shallows,
                child: Icon(section.icon, color: AppColors.deepWater),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.label,
                      style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      section.description,
                      style: text.bodySmall?.copyWith(color: AppColors.mist),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: share,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                      backgroundColor: AppColors.line,
                      color: AppColors.expense,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Money.format(totalMinor, _currency),
                    style: AppText.amount(16, color: AppColors.expense),
                  ),
                  Text(
                    '${(share * 100).round()}%',
                    style: text.bodySmall?.copyWith(color: AppColors.mist),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.mist),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ONE SECTION
// ============================================================================

class ExpenseSectionScreen extends ConsumerWidget {
  const ExpenseSectionScreen({super.key, required this.section});

  final ExpenseSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(expensesMonthProvider);
    final isSubs = section == ExpenseSection.subscriptions;

    return MainScaffold(
      title: section.label,
      floatingActionButton: isSubs
          ? FloatingActionButton.extended(
              onPressed: () => showSubscriptionSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add subscription'),
              shape: const StadiumBorder(),
            )
          : null,
      body: Column(
        children: [
          const MonthSwitcher(),
          Expanded(
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load expenses.\n$e')),
              data: (m) {
                final s = m.sections[section]!;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
                  children: [
                    _TotalHeader(
                      caption: 'Spent this month',
                      amountMinor: s.totalMinor,
                    ),
                    Text(
                      section.description,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.mist),
                    ),
                    if (isSubs) const _SubscriptionsList(),
                    if (s.categories.isNotEmpty) ...[
                      const _Title('By category'),
                      for (final c in s.categories)
                        _CategoryRow(total: c, sectionTotal: s.totalMinor),
                    ],
                    _Title(isSubs ? 'Paid this month' : 'Transactions'),
                    DayGroupedList(
                      items: s.items,
                      emptyText: isSubs
                          ? 'No subscription payments this month yet. Tap '
                              '"Mark as paid" on one above when you pay it.'
                          : 'Nothing here this month. Tap + to add an expense.',
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.total, required this.sectionTotal});

  final CategoryTotal total;
  final int sectionTotal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final share = sectionTotal == 0 ? 0.0 : total.totalMinor / sectionTotal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(iconFor(total.iconKey), color: AppColors.deepWater, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(total.name, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: share,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(5),
                  backgroundColor: AppColors.line,
                  color: AppColors.expense,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            Money.format(total.totalMinor, _currency),
            style: AppText.amount(15, color: AppColors.expense),
          ),
        ],
      ),
    );
  }
}

/// All active subscriptions, their combined monthly cost, and Mark as paid.
class _SubscriptionsList extends ConsumerWidget {
  const _SubscriptionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider).value ?? const [];
    final text = Theme.of(context).textTheme;
    final monthly = subs.fold<int>(
      0,
      (sum, s) => sum + s.frequency.monthlyMinor(s.amountMinor),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('Your subscriptions'),
        if (subs.isEmpty)
          Text(
            'Add the things you pay again and again: streaming, gym, phone '
            'plan, insurance, school fees. Tidewise will remind you before '
            'each one is due.',
            style: text.bodyMedium?.copyWith(color: AppColors.mist),
          )
        else ...[
          Text(
            'Together about ${Money.format(monthly, _currency)} a month, or '
            '${Money.format(monthly * 12, _currency)} a year. Worth checking '
            'now and then for anything you no longer use.',
            style: text.bodySmall?.copyWith(color: AppColors.mist),
          ),
          const SizedBox(height: 12),
          for (final s in subs) SubscriptionTile(subscription: s),
        ],
      ],
    );
  }
}
