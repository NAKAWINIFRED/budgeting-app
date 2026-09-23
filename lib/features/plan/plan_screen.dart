import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_scaffold.dart';
import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../dashboard/dashboard_providers.dart';
import 'plan_insights.dart';
import 'plan_providers.dart';

/// Colors for the segments of a strategy's split bar.
const _splitColors = [
  AppColors.deepWater,
  AppColors.tide,
  AppColors.amber,
  AppColors.mist,
];

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);
    final options = ref.watch(strategyOptionsProvider);

    return MainScaffold(
      title: 'Budget plan',
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load your plan.\n$e')),
        data: (s) {
          final activeBuckets = s.buckets.map((b) => b.bucket).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
            children: [
              _PlanHeader(summary: s),
              const SizedBox(height: 28),
              _ThisMonth(summary: s),
              const SizedBox(height: 28),
              _Tips(tips: buildPlanTips(s)),
              const SizedBox(height: 32),
              _Calculator(buckets: activeBuckets),
              const SizedBox(height: 32),
              _Learn(buckets: activeBuckets),
              const SizedBox(height: 32),
              options.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Text('Could not load strategies.\n$e'),
                data: (list) => _StrategyPicker(
                  options: list,
                  activeId: s.strategy?.id,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: text.bodyMedium?.copyWith(color: AppColors.mist),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strategy = summary.strategy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'You are using',
          style: text.bodyMedium?.copyWith(color: AppColors.mist),
        ),
        Text(
          strategy?.name ?? 'No plan selected',
          style: AppText.amount(32, weight: FontWeight.w800),
        ),
        if (strategy?.description != null) ...[
          const SizedBox(height: 4),
          Text(strategy!.description!, style: text.bodyMedium),
        ],
        const SizedBox(height: 14),
        _SplitBar(buckets: summary.buckets.map((b) => b.bucket).toList()),
      ],
    );
  }
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.buckets, this.height = 12});

  final List<BudgetBucket> buckets;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < buckets.length; i++)
              Expanded(
                flex: buckets[i].basisPoints,
                child: Container(
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                  color: _splitColors[i % _splitColors.length],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------

class _ThisMonth extends StatelessWidget {
  const _ThisMonth({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final subtitle = s.incomeMinor > 0
        ? 'Based on ${Money.format(s.incomeMinor, s.currency)} received so far. '
            'Your plan is a guide, not a rule; being a little off is normal.'
        : 'No income recorded yet this month.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Plan vs. actual', subtitle: subtitle),
        for (var i = 0; i < s.buckets.length; i++)
          _BucketCompare(
            progress: s.buckets[i],
            currency: s.currency,
            dotColor: _splitColors[i % _splitColors.length],
          ),
      ],
    );
  }
}

class _BucketCompare extends StatelessWidget {
  const _BucketCompare({
    required this.progress,
    required this.currency,
    required this.dotColor,
  });

  final BucketProgress progress;
  final String currency;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = progress;
    final status = bucketStatus(b, currency);
    final percent = (b.bucket.basisPoints / 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${b.bucket.name} ($percent%)',
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                status.label,
                style: text.bodyMedium?.copyWith(
                  color: status.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: b.ratio.clamp(0.0, 1.0).toDouble(),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: AppColors.line,
            color: status.color == AppColors.mist ? AppColors.tide : status.color,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Plan',
                  value: Money.format(b.allocatedMinor, currency),
                ),
              ),
              Expanded(
                child: _Figure(
                  label: b.isGoodWhenOver ? 'Put in' : 'Spent',
                  value: Money.format(b.usedMinor, currency),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.mist),
        ),
        Text(value, style: AppText.amount(16)),
      ],
    );
  }
}

// ----------------------------------------------------------------------------

class _Tips extends StatelessWidget {
  const _Tips({required this.tips});

  final List<PlanTip> tips;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Tips for this month'),
        for (final tip in tips)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tip.icon, color: tip.color, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(tip.text, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------

class _Calculator extends StatefulWidget {
  const _Calculator({required this.buckets});

  final List<BudgetBucket> buckets;

  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  static String get _currency => kDefaultCurrency;
  final _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Start with the rough monthly income from onboarding, if shared.
    final typical = AppConfig.typicalIncomeMinor;
    if (typical != null && typical > 0) {
      _amount.text = Money.fromMinor(typical, _currency).round().toString();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final amount = parseAmountMinor(_amount.text, _currency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          'Quick calculator',
          subtitle: 'Type any amount you earn to see how your plan splits it.',
        ),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.numberWithOptions(
            decimal: Money.fractionDigits(_currency) > 0,
          ),
          inputFormatters: [amountInputFormatter(_currency)],
          style: AppText.amount(22),
          decoration: InputDecoration(
            hintText: 'e.g. 1000',
            prefixText: '${Money.symbol(_currency)} ',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.buckets.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _splitColors[i % _splitColors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.buckets[i].name} '
                    '(${(widget.buckets[i].basisPoints / 100).round()}%)',
                    style: text.bodyLarge,
                  ),
                ),
                Text(
                  Money.format(
                    Money.share(amount, widget.buckets[i].basisPoints),
                    _currency,
                  ),
                  style: AppText.amount(16),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------

class _Learn extends StatelessWidget {
  const _Learn({required this.buckets});

  final List<BudgetBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('What goes in each bucket?'),
        for (final b in buckets)
          Theme(
            // Removes ExpansionTile's default divider lines.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedAlignment: Alignment.centerLeft,
              title: Text(
                b.name,
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              children: [Text(bucketExplanation(b), style: text.bodyMedium)],
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------

class _StrategyPicker extends ConsumerWidget {
  const _StrategyPicker({required this.options, required this.activeId});

  final List<StrategyOption> options;
  final String? activeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          'Choose a strategy',
          subtitle: 'You can switch any time. Your transactions stay the same; '
              'only the targets change.',
        ),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: o.strategy.id == activeId
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await ref
                          .read(strategiesRepositoryProvider)
                          .setActive(o.strategy.id);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Now using ${o.strategy.name}')),
                      );
                    },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: o.strategy.id == activeId
                      ? AppColors.shallows
                      : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: o.strategy.id == activeId
                        ? AppColors.tide
                        : AppColors.line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.strategy.name,
                            style: text.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (o.strategy.id == activeId)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.tide,
                          ),
                      ],
                    ),
                    if (o.strategy.description != null)
                      Text(o.strategy.description!, style: text.bodyMedium),
                    const SizedBox(height: 10),
                    _SplitBar(buckets: o.buckets, height: 8),
                    const SizedBox(height: 8),
                    Text(
                      o.splitSummary,
                      style: text.bodySmall?.copyWith(color: AppColors.mist),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Custom plans, where you set your own percentages, are coming soon.',
          style: text.bodySmall?.copyWith(color: AppColors.mist),
        ),
      ],
    );
  }
}
