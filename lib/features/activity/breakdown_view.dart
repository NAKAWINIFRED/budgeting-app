import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import 'activity_providers.dart';

/// "Where your money went": a grand total, each category's total, and
/// inside each category the individual items (Eggs, Soap, Electricity...).
class BreakdownView extends ConsumerWidget {
  const BreakdownView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(monthBreakdownProvider);
    final text = Theme.of(context).textTheme;
    const currency = kDefaultCurrency;

    return breakdown.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load the breakdown.\n$e')),
      data: (b) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
        children: [
          Text(
            'Where your money went',
            style: text.bodyMedium?.copyWith(color: AppColors.mist),
          ),
          Text(
            Money.format(b.totalMinor, currency),
            style: AppText.amount(34, weight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            'Spending, bills, debt payments and savings this month.',
            style: text.bodySmall?.copyWith(color: AppColors.mist),
          ),
          const SizedBox(height: 20),
          if (b.groups.isEmpty)
            Text(
              'Nothing spent this month yet.',
              style: text.bodyMedium?.copyWith(color: AppColors.mist),
            ),
          for (final g in b.groups)
            _GroupTile(group: g, grandTotal: b.totalMinor, currency: currency),
          if (b.groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Tip: when adding an expense, tap "Break it down into items" to '
              'see exactly what each total was made of.',
              style: text.bodySmall?.copyWith(color: AppColors.mist),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupTile extends StatefulWidget {
  const _GroupTile({
    required this.group,
    required this.grandTotal,
    required this.currency,
  });

  final BreakdownGroup group;
  final int grandTotal;
  final String currency;

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final g = widget.group;
    final share =
        widget.grandTotal <= 0 ? 0.0 : g.totalMinor / widget.grandTotal;
    final canOpen = g.lines.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _open ? AppColors.tide : AppColors.line),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: canOpen ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.shallows,
                    child: Icon(
                      iconFor(g.iconKey),
                      size: 20,
                      color: AppColors.deepWater,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.title,
                          style: text.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: share,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(6),
                          backgroundColor: AppColors.line,
                          color: AppColors.tide,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Money.format(g.totalMinor, widget.currency),
                        style: AppText.amount(16),
                      ),
                      Text(
                        '${(share * 100).round()}%',
                        style: text.bodySmall?.copyWith(color: AppColors.mist),
                      ),
                    ],
                  ),
                  if (canOpen)
                    Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.mist,
                    ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(66, 0, 16, 14),
              child: Column(
                children: [
                  for (final line in g.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.count > 1
                                  ? '${line.name}  \u00d7${line.count}'
                                  : line.name,
                              style: text.bodyMedium?.copyWith(
                                color: line.name == 'Not broken down'
                                    ? AppColors.mist
                                    : AppColors.deepWater,
                              ),
                            ),
                          ),
                          Text(
                            Money.format(line.amountMinor, widget.currency),
                            style: AppText.amount(14, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
