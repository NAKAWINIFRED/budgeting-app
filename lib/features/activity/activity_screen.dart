import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../dashboard/dashboard_providers.dart';
import '../shared/activity_row.dart';
import '../transactions/quick_add_sheet.dart';
import 'activity_providers.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(monthActivityProvider);
    final filter = ref.watch(activityFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Column(
        children: [
          const _MonthSwitcher(),
          const _FilterBar(),
          Expanded(
            child: activity.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Could not load activity.\n$e')),
              data: (a) => _ActivityList(activity: a, filter: filter),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------

class _MonthSwitcher extends ConsumerWidget {
  const _MonthSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: notifier.previous,
          ),
          Expanded(
            child: Text(
              DateFormat.yMMMM().format(month),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: isCurrentMonth ? null : notifier.next,
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(activityFilterProvider);

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        itemCount: ActivityFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = ActivityFilter.values[i];
          final isSelected = f == selected;
          return ChoiceChip(
            label: Text(f.label),
            selected: isSelected,
            showCheckmark: false,
            selectedColor: AppColors.shallows,
            backgroundColor: Colors.white,
            shape: const StadiumBorder(),
            side: BorderSide(
              color: isSelected ? AppColors.tide : AppColors.line,
            ),
            onSelected: (_) =>
                ref.read(activityFilterProvider.notifier).select(f),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------------

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.activity, required this.filter});

  final MonthActivity activity;
  final ActivityFilter filter;

  static String _dayLabel(DateTime day) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return DateFormat.MMMEd().format(day);
  }

  @override
  Widget build(BuildContext context) {
    const currency = kDefaultCurrency;
    final text = Theme.of(context).textTheme;
    final items = activity.items.where(filter.matches).toList();

    // Group by day, keeping newest days first.
    final days = <DateTime, List<ActivityItem>>{};
    for (final item in items) {
      days
          .putIfAbsent(DateUtils.dateOnly(item.tx.occurredAt), () => [])
          .add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
      children: [
        _MonthTotals(activity: activity),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              filter == ActivityFilter.all
                  ? 'Nothing recorded this month. Tap + to add income or an expense.'
                  : 'No ${filter.label.toLowerCase()} this month.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: AppColors.mist),
            ),
          ),
        for (final entry in days.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(
              _dayLabel(entry.key),
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.mist,
              ),
            ),
          ),
          for (var i = 0; i < entry.value.length; i++) ...[
            if (i > 0) const Divider(),
            ActivityRow(
              item: entry.value[i],
              currency: currency,
              subtitle: _subtitle(entry.value[i]),
              onTap: () => showQuickAddSheet(
                context,
                existing: entry.value[i].tx,
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// The note if there is one, otherwise the time (the day is in the header).
  String _subtitle(ActivityItem item) {
    final note = item.tx.note;
    if (note != null && note.isNotEmpty) return note;
    return DateFormat.jm().format(item.tx.occurredAt);
  }
}

class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.activity});

  final MonthActivity activity;

  @override
  Widget build(BuildContext context) {
    const currency = kDefaultCurrency;
    return Row(
      children: [
        _Stat(
          label: 'In',
          value: Money.format(activity.inMinor, currency),
          color: AppColors.tide,
        ),
        _Stat(label: 'Out', value: Money.format(activity.outMinor, currency)),
        _Stat(label: 'Saved', value: Money.format(activity.savedMinor, currency)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.color = AppColors.deepWater,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.mist),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppText.amount(18, color: color)),
          ),
        ],
      ),
    );
  }
}
