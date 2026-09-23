import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/main_scaffold.dart';
import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../dev/sample_data.dart';
import '../debts/debt_providers.dart';
import '../investments/investment_sheets.dart' show gainColor;
import '../investments/investments_providers.dart';
import '../review/month_review.dart';
import '../savings/savings_providers.dart';
import '../shared/activity_row.dart';
import '../subscriptions/subscriptions_providers.dart';
import '../subscriptions/subscriptions_screen.dart';
import '../transactions/quick_add_sheet.dart';
import 'dashboard_providers.dart';
import 'tide_gauge.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);

    return MainScaffold(
      title: 'Overview',
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your overview.\n$e'),
          ),
        ),
        data: (s) => ListView(
          // Bottom padding keeps content clear of the + button.
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
          children: [
            const _Header(),
            const SizedBox(height: 20),
            _SafeToSpendCard(summary: s),
            const MonthReviewCard(),
            const _UpcomingSection(),
            const SizedBox(height: 28),
            _OverviewTiles(summary: s),
            const SizedBox(height: 28),
            _RecentActivitySection(currency: s.currency),
            if (kDebugMode && s.incomeMinor == 0) const _SampleDataButton(),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppConfig.userName == null
              ? greeting
              : '$greeting, ${AppConfig.userName}',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          DateFormat.yMMMM().format(now),
          style: text.bodyMedium?.copyWith(color: AppColors.mist),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------

/// How much trouble money is in right now. Drives the gauge's colors.
enum MoneyHealth {
  /// Money left this month, and debts (if any) are covered by what you have.
  calm,

  /// Spent more than came in this month.
  overspent,

  /// You owe more than the money you can use right now (cash left this
  /// month plus short-term savings).
  inDebt,

  /// Debt is also 3 or more months of income: deep water.
  deepDebt,
}

class _SafeToSpendCard extends ConsumerWidget {
  const _SafeToSpendCard({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final text = Theme.of(context).textTheme;
    final soft = Colors.white.withValues(alpha: 0.78);
    String fmt(int m) => Money.format(m, s.currency);

    // What you owe vs the money you can actually use right now: cash left
    // this month plus short-term savings. Retirement, long-term savings and
    // investments are not counted; you should not have to empty them to
    // pay debts, and often cannot quickly.
    final debtLeft = ref.watch(debtOverviewProvider).value?.remainingMinor ?? 0;
    final savings = ref.watch(savingsOverviewProvider).value;
    final shortTermSaved = savings == null
        ? 0
        : savings.all
            .where((g) => g.goal == null || g.goal!.term == SavingsTerm.shortTerm)
            .fold<int>(0, (sum, g) => sum + g.savedMinor);
    final cashLeft = s.safeToSpendMinor > 0 ? s.safeToSpendMinor : 0;
    final available = cashLeft + (shortTermSaved > 0 ? shortTermSaved : 0);
    final gap = debtLeft - available; // positive = owe more than you can use

    final health = gap > 0
        ? (s.incomeMinor > 0 && debtLeft >= s.incomeMinor * 3
            ? MoneyHealth.deepDebt
            : MoneyHealth.inDebt)
        : s.safeToSpendMinor < 0
            ? MoneyHealth.overspent
            : MoneyHealth.calm;

    final overspent = s.safeToSpendMinor < 0;
    final headline = overspent ? 'Overspent by' : 'Safe to spend';
    final amount = fmt(s.safeToSpendMinor.abs());
    final footer = s.incomeMinor == 0
        ? 'Add income to fill your tide'
        : 'of ${fmt(s.incomeMinor)} received this month';

    final (background, water) = switch (health) {
      MoneyHealth.calm => (AppColors.deepWater, AppColors.tide),
      MoneyHealth.overspent => (AppColors.debtWater, AppColors.amber),
      MoneyHealth.inDebt => (AppColors.debtWater, AppColors.expense),
      MoneyHealth.deepDebt => (AppColors.deepDebtWater, AppColors.expense),
    };

    // Honest, but never shaming, and always pointing to a way out.
    final warning = switch (health) {
      MoneyHealth.calm => null,
      MoneyHealth.overspent =>
        'More went out than came in this month. Tap to see where.',
      MoneyHealth.inDebt =>
        'In debt: you owe ${fmt(debtLeft)}, which is ${fmt(gap)} more than '
            'the money you can use right now. Tap to see your debts.',
      MoneyHealth.deepDebt =>
        'Deep water: you owe ${fmt(debtLeft)}, about '
            '${(debtLeft / s.incomeMinor).toStringAsFixed(1)} months of income. '
            'It can be fixed, one payment at a time. Tap to start.',
    };
    final route = health == MoneyHealth.overspent ? '/expenses' : '/debts';

    return Semantics(
      label: '$headline $amount, $footer. ${warning ?? ''}',
      button: warning != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: warning == null ? null : () => context.go(route),
        child: TideGauge(
          level: s.level,
          height: warning == null ? 220 : 270,
          background: background,
          water: water,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                style: text.titleSmall?.copyWith(
                  color: overspent ? AppColors.amber : soft,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  amount,
                  style: AppText.amount(40, color: Colors.white, weight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              if (warning != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        health == MoneyHealth.deepDebt
                            ? Icons.flood_rounded
                            : Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warning,
                          style: text.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                footer,
                style: text.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------

class _RecentActivitySection extends ConsumerWidget {
  const _RecentActivitySection({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(recentActivityProvider);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Recent activity',
          actionLabel: 'See all',
          onAction: () => context.go('/activity'),
        ),
        activity.when(
          loading: () => const SizedBox(height: 48),
          error: (e, _) => Text('Could not load activity.\n$e'),
          data: (items) => items.isEmpty
              ? Text(
                  'Nothing yet. Tap + to add your first income or expense.',
                  style: text.bodyMedium?.copyWith(color: AppColors.mist),
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(),
                      ActivityRow(
                        item: items[i],
                        currency: currency,
                        onTap: () => showQuickAddSheet(
                          context,
                          existing: items[i].tx,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// Debug builds only: fills this month with realistic test data.
class _SampleDataButton extends ConsumerWidget {
  const _SampleDataButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: OutlinedButton.icon(
        onPressed: () => insertSampleData(ref.read(appDatabaseProvider)),
        icon: const Icon(Icons.science_outlined),
        label: const Text('Load sample data (debug only)'),
      ),
    );
  }
}

/// Bills and subscriptions due soon, with one-tap "Mark as paid".
class _UpcomingSection extends ConsumerWidget {
  const _UpcomingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider).value ?? const [];
    final text = Theme.of(context).textTheme;
    void openAll() => context.push('/expenses/subscriptions');

    if (subs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: openAll,
            icon: const Icon(Icons.autorenew_rounded, size: 20),
            label: const Text('Add subscriptions & bills to get reminders'),
          ),
        ),
      );
    }

    final due = subs.where((s) => s.needsAttention).toList();
    if (due.isEmpty) {
      final next = subs.first;
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: openAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.autorenew_rounded, color: AppColors.mist, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Next bill: ${next.name}, ${next.dueLabel.toLowerCase()}',
                    style: text.bodyMedium?.copyWith(color: AppColors.mist),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.mist),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Coming up',
            actionLabel: 'See all',
            onAction: openAll,
          ),
          for (final s in due) SubscriptionTile(subscription: s),
        ],
      ),
    );
  }
}

/// One small tile per area of the app; tap to open it.
class _OverviewTiles extends ConsumerWidget {
  const _OverviewTiles({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = summary.currency;
    String fmt(int m) => Money.format(m, currency);
    final savings = ref.watch(savingsOverviewProvider).value;
    final investments = ref.watch(investmentsOverviewProvider).value;
    final debts = ref.watch(debtOverviewProvider).value;

    final tiles = <Widget>[
      _Tile(
        label: 'Income',
        value: fmt(summary.incomeMinor),
        caption: 'this month',
        color: AppColors.lagoon,
        icon: Icons.south_west_rounded,
        route: '/income',
      ),
      _Tile(
        label: 'Expenses',
        value: fmt(summary.expenseMinor),
        caption: 'this month',
        color: AppColors.expense,
        icon: Icons.north_east_rounded,
        route: '/expenses',
      ),
      _Tile(
        label: 'Savings',
        value: fmt(savings?.totalSavedMinor ?? 0),
        caption: 'saved in total',
        color: AppColors.tide,
        icon: Icons.savings_rounded,
        route: '/savings',
      ),
      _Tile(
        label: 'Investments',
        value: fmt(investments?.valueMinor ?? 0),
        caption: investments == null || investments.items.isEmpty
            ? 'none yet'
            : '${investments.gainMinor >= 0 ? '+' : '\u2212'}'
                '${(investments.gainPercent.abs() * 100).toStringAsFixed(1)}% growth',
        color: investments == null || investments.items.isEmpty
            ? AppColors.deepWater
            : gainColor(investments.gainMinor),
        icon: Icons.trending_up_rounded,
        route: '/investments',
      ),
      _Tile(
        label: 'Debt left',
        value: fmt(debts?.remainingMinor ?? 0),
        caption: debts == null || debts.active.isEmpty
            ? 'no debts'
            : '${(debts.progress * 100).floor()}% paid off',
        color: AppColors.deepWater,
        icon: Icons.payments_rounded,
        route: '/debts',
      ),
      _Tile(
        label: 'Budget plan',
        value: summary.strategy?.name ?? 'Choose one',
        caption: 'see how you are doing',
        color: AppColors.deepWater,
        icon: Icons.donut_large_rounded,
        route: '/plan',
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: tiles,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.icon,
    required this.route,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;
  final IconData icon;
  final String route;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.go(route),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: AppText.amount(20, color: color)),
            ),
            Text(
              caption,
              style: text.bodySmall?.copyWith(color: AppColors.mist),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
