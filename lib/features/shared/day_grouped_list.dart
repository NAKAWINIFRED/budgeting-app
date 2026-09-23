import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/money_kinds.dart';
import '../dashboard/dashboard_providers.dart';
import '../transactions/quick_add_sheet.dart';
import 'activity_row.dart';

/// Transactions grouped under day headings (Today, Yesterday, Mon Sep 21).
/// Not scrollable itself, so it can sit inside a page's list.
class DayGroupedList extends StatelessWidget {
  const DayGroupedList({super.key, required this.items, this.emptyText});

  final List<ActivityItem> items;
  final String? emptyText;

  static String dayLabel(DateTime day) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return DateFormat.MMMEd().format(day);
  }

  static String subtitleFor(ActivityItem item) {
    final note = item.tx.note;
    final main = note != null && note.isNotEmpty
        ? note
        : item.itemNames.isNotEmpty
            ? item.itemNames.join(', ')
            : DateFormat.jm().format(item.tx.occurredAt);
    final method = item.tx.paymentMethod;
    return method == null ? main : '$main, ${method.label}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          emptyText ?? 'Nothing here this month.',
          style: text.bodyMedium?.copyWith(color: AppColors.mist),
        ),
      );
    }

    final days = <DateTime, List<ActivityItem>>{};
    for (final item in items) {
      days.putIfAbsent(DateUtils.dateOnly(item.tx.occurredAt), () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in days.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(
              dayLabel(entry.key),
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
              currency: kDefaultCurrency,
              subtitle: subtitleFor(entry.value[i]),
              onTap: () => showQuickAddSheet(context, existing: entry.value[i].tx),
            ),
          ],
        ],
      ],
    );
  }
}
