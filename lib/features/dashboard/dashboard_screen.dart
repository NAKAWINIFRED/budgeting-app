import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../data/database_provider.dart';
import '../../dev/sample_data.dart';
import '../review/month_review.dart';
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: summary.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load your overview.\n$e'),
            ),
          ),
          data: (s) => ListView(
            // Bottom padding keeps content clear of the + button.
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
            children: [
              const _Header(),
              const SizedBox(height: 20),
              _SafeToSpendCard(summary: s),
              const MonthReviewCard(),
              const _UpcomingSection(),
              const SizedBox(height: 36),
              _PlanSection(summary: s),
              const SizedBox(height: 28),
              _RecentActivitySection(currency: s.currency),
              if (kDebugMode && s.incomeMinor == 0) const _SampleDataButton(),
            ],
          ),
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
          greeting,
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

class _SafeToSpendCard extends StatelessWidget {
  const _SafeToSpendCard({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final overspent = s.safeToSpendMinor < 0;
    final text = Theme.of(context).textTheme;
    final soft = Colors.white.withValues(alpha: 0.78);

    final headline = overspent ? 'Overspent by' : 'Safe to spend';
    final amount = Money.format(s.safeToSpendMinor.abs(), s.currency);
    final footer = s.incomeMinor == 0
        ? 'Add income to fill your tide'
        : 'of ${Money.format(s.incomeMinor, s.currency)} received this month';

    return Semantics(
      label: '$headline $amount, $footer',
      excludeSemantics: true,
      child: TideGauge(
        level: s.level,
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
    );
  }
}

// ----------------------------------------------------------------------------

class _PlanSection extends StatelessWidget {
  const _PlanSection({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strategy = summary.strategy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: strategy == null ? 'Your plan' : 'Your plan: ${strategy.name}',
          actionLabel: 'Change',
          onAction: () => context.go('/plan'),
        ),
        if (summary.incomeMinor == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Each time money comes in, your plan splits it into these buckets.',
              style: text.bodyMedium?.copyWith(color: AppColors.mist),
            ),
          ),
        for (final b in summary.buckets)
          _BucketRow(progress: b, currency: summary.currency),
      ],
    );
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({required this.progress, required this.currency});

  final BucketProgress progress;
  final String currency;

  Color get _color {
    final r = progress.ratio;
    if (progress.isGoodWhenOver || r < 0.8) return AppColors.tide;
    if (r <= 1.0) return AppColors.amber;
    return AppColors.buoyRed;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final percent = (progress.ratio * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.bucket.name,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text('$percent%', style: AppText.amount(15, color: _color)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.ratio.clamp(0.0, 1.0).toDouble(),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: AppColors.line,
            color: _color,
          ),
          const SizedBox(height: 6),
          Text(
            '${Money.format(progress.usedMinor, currency)} of '
            '${Money.format(progress.allocatedMinor, currency)}',
            style: text.bodySmall?.copyWith(color: AppColors.mist),
          ),
        ],
      ),
    );
  }
}

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
    void openAll() => context.push('/subscriptions');

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
