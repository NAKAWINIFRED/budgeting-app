import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../../core/money_kinds.dart';
import 'activity_providers.dart';

/// "Where your money went" (or came from): a grand total, each category's
/// total, and inside each category its subcategories and items, or for
/// income each payment with its date.
class BreakdownView extends ConsumerStatefulWidget {
  const BreakdownView({super.key});

  @override
  ConsumerState<BreakdownView> createState() => _BreakdownViewState();
}

class _BreakdownViewState extends ConsumerState<BreakdownView> {
  bool _income = false;

  @override
  Widget build(BuildContext context) {
    final breakdown = ref.watch(
      _income ? monthIncomeBreakdownProvider : monthBreakdownProvider,
    );
    final text = Theme.of(context).textTheme;
    const currency = kDefaultCurrency;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Spending')),
              ButtonSegment(value: true, label: Text('Income')),
            ],
            selected: {_income},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _income = s.first),
          ),
        ),
        const SizedBox(height: 16),
        breakdown.when(
          loading: () => const SizedBox(height: 120),
          error: (e, _) => Text('Could not load the breakdown.\n$e'),
          data: (b) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _income ? 'Money that came in' : 'Where your money went',
                style: text.bodyMedium?.copyWith(color: AppColors.mist),
              ),
              Text(
                Money.format(b.totalMinor, currency),
                style: AppText.amount(
                  34,
                  weight: FontWeight.w800,
                  color: _income ? AppColors.lagoon : AppColors.expense,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _income
                    ? 'All income received this month, by category.'
                    : 'Spending, bills, debt payments and savings this month.',
                style: text.bodySmall?.copyWith(color: AppColors.mist),
              ),
              if (b.byMethod.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  _income ? 'How it came in' : 'How you paid',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final (method, amount) in b.byMethod)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          method?.icon ?? Icons.help_outline_rounded,
                          size: 20,
                          color: AppColors.mist,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            method?.label ?? 'Not set',
                            style: text.bodyMedium,
                          ),
                        ),
                        Text(
                          '${(b.totalMinor == 0 ? 0 : amount * 100 / b.totalMinor).round()}%',
                          style: text.bodySmall?.copyWith(color: AppColors.mist),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          Money.format(amount, currency),
                          style: AppText.amount(15, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              if (b.groups.isEmpty)
                Text(
                  _income
                      ? 'No income recorded this month yet.'
                      : 'Nothing spent this month yet.',
                  style: text.bodyMedium?.copyWith(color: AppColors.mist),
                ),
              for (final g in b.groups)
                _GroupTile(
                  group: g,
                  grandTotal: b.totalMinor,
                  currency: currency,
                  barColor: amountColorFor(g.kind),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push(
                    '/categories?kind=${_income ? 'income' : 'expense'}',
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  label: const Text('Manage categories'),
                ),
              ),
              if (!_income && b.groups.isNotEmpty)
                Text(
                  'Tip: pick a subcategory, or tap "Break it down into items" '
                  'when adding an expense, to see exactly what each total '
                  'was made of.',
                  style: text.bodySmall?.copyWith(color: AppColors.mist),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupTile extends StatefulWidget {
  const _GroupTile({
    required this.group,
    required this.grandTotal,
    required this.currency,
    this.barColor = AppColors.tide,
  });

  final BreakdownGroup group;
  final int grandTotal;
  final String currency;
  final Color barColor;

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
                          color: widget.barColor,
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.count > 1
                                      ? '${line.name}  \u00d7${line.count}'
                                      : line.name,
                                  style: text.bodyMedium?.copyWith(
                                    color: line.name == 'Not broken down'
                                        ? AppColors.mist
                                        : AppColors.deepWater,
                                  ),
                                ),
                                if (line.detail != null)
                                  Text(
                                    line.detail!,
                                    style: text.bodySmall
                                        ?.copyWith(color: AppColors.mist),
                                  ),
                              ],
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
