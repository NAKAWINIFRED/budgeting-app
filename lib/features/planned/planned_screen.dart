import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/main_scaffold.dart';
import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/lookups.dart';
import '../../data/transactions_repository.dart';
import '../categories/categories_repository.dart';
import '../dashboard/dashboard_providers.dart';
import 'planned_providers.dart';

String get _currency => kDefaultCurrency;
String _fmt(int minor) => Money.format(minor, _currency);

String _amountText(int minor) {
  final v = Money.fromMinor(minor, _currency);
  return v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(Money.fractionDigits(_currency));
}

/// Ticks an upcoming expense off (asking for the real price and recording
/// the expense) or unticks it (removing that expense). Used on the Upcoming
/// expenses page and on each expenses page.
Future<void> togglePlannedItem(
  BuildContext context,
  WidgetRef ref,
  PlannedExpense item,
  DateTime month,
) async {
  final repo = ref.read(plannedRepositoryProvider);
  if (!item.isDone) {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _BoughtDialog(item: item),
    );
    if (amount == null) return;
    final method =
        await ref.read(transactionsRepositoryProvider).lastPaymentMethod();
    await repo.markDone(item, amount, method);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.name} recorded as an expense of ${_fmt(amount)}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.markUndoneById(item.id),
        ),
      ),
    );
  } else {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Untick ${item.name}?'),
        content: Text(
          'The ${_fmt(item.amountMinor ?? 0)} expense it recorded will be '
          'removed, and it goes back on the list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Untick'),
          ),
        ],
      ),
    );
    if (ok == true) await repo.markUndone(item);
  }
}

class PlannedScreen extends ConsumerStatefulWidget {
  const PlannedScreen({super.key, this.startNextMonth = false});

  final bool startNextMonth;

  @override
  ConsumerState<PlannedScreen> createState() => _PlannedScreenState();
}

class _PlannedScreenState extends ConsumerState<PlannedScreen> {
  late DateTime _month;
  final _quick = TextEditingController();

  /// Items swiped away, hidden at once while the database catches up
  /// (a swiped item must leave the screen immediately).
  final Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month + (widget.startNextMonth ? 1 : 0));
  }

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  DateTime get _thisMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  bool get _isFuture => _month.isAfter(_thisMonth);

  Future<void> _addQuick() async {
    final drafts = parseQuickList(_quick.text);
    if (drafts.isEmpty) return;
    await ref.read(plannedRepositoryProvider).addAll(_month, drafts);
    _quick.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          drafts.length == 1
              ? 'Added ${drafts.first.name}'
              : 'Added ${drafts.length} items',
        ),
      ),
    );
  }

  Future<void> _toggle(PlannedExpense item) =>
      togglePlannedItem(context, ref, item, _month);

  Future<void> _delete(PlannedExpense item) async {
    final repo = ref.read(plannedRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden.add(item.id));
    await repo.delete(item.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('${item.name} removed from the list'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await repo.restore(item);
            if (mounted) setState(() => _hidden.remove(item.id));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final items = ref.watch(plannedExpensesProvider(_month));
    final categories = {
      for (final c in ref.watch(categoriesProvider(CategoryKind.expense)).value ??
          const <CategoryItem>[])
        c.id: c,
    };

    return MainScaffold(
      title: 'Upcoming expenses',
      body: Column(
        children: [
          _MonthPicker(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load the list.\n$e')),
              data: (all) {
                final list = all.where((i) => !_hidden.contains(i.id)).toList();
                final summary = PlannedSummary(list);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
                  children: [
                    _SummaryCard(
                      month: _month,
                      summary: summary,
                      isFuture: _isFuture,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _quick,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addQuick(),
                      decoration: InputDecoration(
                        hintText: 'e.g. water 50, wifi 20, rice, eggs 12',
                        helperText: 'Write freely and separate items with '
                            'commas. Prices are optional. Tap an item later to '
                            'set its category or where it shows.',
                        helperMaxLines: 2,
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.playlist_add_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Add to list',
                          icon: const Icon(Icons.add_circle_rounded, color: AppColors.tide),
                          onPressed: _addQuick,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                      ),
                    ),
                    if (summary.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          'No upcoming expenses for ${DateFormat.MMMM().format(_month)} '
                          'yet. Write down what you know you will need to buy '
                          'or pay: bills, groceries, school things. When you '
                          'buy something, tick it off and it is recorded for you.',
                          style: text.bodyMedium?.copyWith(color: AppColors.mist),
                        ),
                      ),
                    if (summary.pending.isNotEmpty)
                      _GroupHeader(
                        title: 'To buy or pay',
                        amountMinor: summary.remainingMinor,
                      ),
                    // In the order they were written.
                    for (final item in summary.pending)
                      PlannedItemTile(
                        item: item,
                        category: categories[item.categoryId],
                        onToggle: () => _toggle(item),
                        onDelete: () => _delete(item),
                      ),
                    if (summary.done.isNotEmpty) ...[
                      _GroupHeader(
                        title: 'Bought',
                        amountMinor: summary.clearedMinor,
                      ),
                      for (final item in summary.done)
                        PlannedItemTile(
                          item: item,
                          category: categories[item.categoryId],
                          onToggle: () => _toggle(item),
                          onDelete: () => _delete(item),
                        ),
                    ],
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

// ============================================================================

class _MonthPicker extends StatelessWidget {
  const _MonthPicker({required this.month, required this.onChanged});

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = (month.year - now.year) * 12 + month.month - now.month;
    final label = switch (diff) {
      0 => 'This month',
      1 => 'Next month',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: diff <= -12
                ? null
                : () => onChanged(DateTime(month.year, month.month - 1)),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  DateFormat.yMMMM().format(month),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (label != null)
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.mist),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: diff >= 12
                ? null
                : () => onChanged(DateTime(month.year, month.month + 1)),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({
    required this.month,
    required this.summary,
    required this.isFuture,
  });

  final DateTime month;
  final PlannedSummary summary;
  final bool isFuture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final s = summary;
    final monthName = DateFormat.MMMM().format(month);

    // What's left after the list.
    String? incomeLine;
    int? leftAfter;
    if (isFuture) {
      final typical = AppConfig.typicalIncomeMinor;
      if (typical != null) {
        leftAfter = typical - s.remainingMinor;
        incomeLine = 'With your usual income of ${_fmt(typical)}, about '
            '${_fmt(leftAfter.abs())} would be '
            '${leftAfter >= 0 ? 'left' : 'missing'} after this list.';
      } else {
        incomeLine = 'Add your usual monthly income in Settings to see what '
            'would be left after this list.';
      }
    } else {
      final monthSummary = ref.watch(monthSummaryProvider(month)).value;
      if (monthSummary != null && monthSummary.incomeMinor > 0) {
        leftAfter = monthSummary.safeToSpendMinor - s.remainingMinor;
        incomeLine = 'Safe to spend now: ${_fmt(monthSummary.safeToSpendMinor)}. '
            'After everything left on this list: '
            '${leftAfter >= 0 ? '' : 'short by '}${_fmt(leftAfter.abs())}.';
      } else {
        incomeLine = 'Add your income for $monthName to see what is left '
            'after this list.';
      }
    }

    final progress = s.totalMinor == 0 ? 0.0 : s.clearedMinor / s.totalMinor;

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
          Text(
            'Still to buy in $monthName',
            style: text.bodyMedium?.copyWith(color: AppColors.mist),
          ),
          Text(
            _fmt(s.remainingMinor),
            style: AppText.amount(32, weight: FontWeight.w800, color: AppColors.expense),
          ),
          Text(
            [
              '${s.pending.length} ${s.pending.length == 1 ? 'item' : 'items'}',
              if (s.unpricedCount > 0) '${s.unpricedCount} without a price yet',
            ].join(', '),
            style: text.bodySmall?.copyWith(color: AppColors.mist),
          ),
          if (s.done.isNotEmpty) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: AppColors.line,
              color: AppColors.tide,
            ),
            const SizedBox(height: 6),
            Text(
              'Bought ${_fmt(s.clearedMinor)} of ${_fmt(s.totalMinor)} planned',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.water_drop_outlined,
                size: 18,
                color: leftAfter != null && leftAfter < 0
                    ? AppColors.expense
                    : AppColors.tide,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(incomeLine, style: text.bodySmall)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.amountMinor, this.iconKey});

  final String title;
  final int amountMinor;
  final String? iconKey;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 4),
      child: Row(
        children: [
          if (iconKey != null) ...[
            Icon(iconFor(iconKey), size: 18, color: AppColors.mist),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.mist,
              ),
            ),
          ),
          if (amountMinor > 0)
            Text(_fmt(amountMinor), style: AppText.amount(14, color: AppColors.mist)),
        ],
      ),
    );
  }
}

class PlannedItemTile extends StatelessWidget {
  const PlannedItemTile({
    super.key,
    required this.item,
    required this.category,
    required this.onToggle,
    this.onDelete,
  });

  final PlannedExpense item;
  final CategoryItem? category;
  final VoidCallback onToggle;
  /// Swipe-to-delete, when the page supports it.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = item.isDone;

    return Dismissible(
      key: ValueKey(item.id),
      direction: onDelete == null
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.buoyRed,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDelete?.call(),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showPlannedItemSheet(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: done,
                shape: const CircleBorder(),
                activeColor: AppColors.tide,
                onChanged: (_) => onToggle(),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? AppColors.mist : AppColors.deepWater,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: category == null ? Colors.white : AppColors.foam,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: category == null ? AppColors.tide : AppColors.line,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            category == null
                                ? Icons.add_rounded
                                : iconFor(category!.iconKey),
                            size: 14,
                            color: category == null ? AppColors.tide : AppColors.mist,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            category?.name ?? 'Category',
                            style: text.labelSmall?.copyWith(
                              color: category == null ? AppColors.tide : AppColors.mist,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                item.amountMinor == null ? 'No price' : _fmt(item.amountMinor!),
                style: item.amountMinor == null
                    ? text.bodySmall?.copyWith(color: AppColors.mist)
                    : AppText.amount(
                        15,
                        color: done ? AppColors.mist : AppColors.expense,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DIALOG: tick off
// ============================================================================

class _BoughtDialog extends StatefulWidget {
  const _BoughtDialog({required this.item});

  final PlannedExpense item;

  @override
  State<_BoughtDialog> createState() => _BoughtDialogState();
}

class _BoughtDialogState extends State<_BoughtDialog> {
  late final _amount = TextEditingController(
    text: widget.item.amountMinor == null ? '' : _amountText(widget.item.amountMinor!),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseAmountMinor(_amount.text, _currency);
    return AlertDialog(
      title: Text('Bought ${widget.item.name}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How much did it actually cost?'),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: Money.fractionDigits(_currency) > 0,
            ),
            inputFormatters: [amountInputFormatter(_currency)],
            decoration: InputDecoration(prefixText: '${Money.symbol(_currency)} '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'It will be recorded as an expense today.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.mist),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: amount > 0 ? () => Navigator.of(context).pop(amount) : null,
          child: const Text('Record it'),
        ),
      ],
    );
  }
}

// ============================================================================
// SHEET: edit an item
// ============================================================================

Future<void> showPlannedItemSheet(BuildContext context, PlannedExpense item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _ItemSheet(item: item),
  );
}

class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({required this.item});

  final PlannedExpense item;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _amount = TextEditingController(
    text: widget.item.amountMinor == null ? '' : _amountText(widget.item.amountMinor!),
  );
  late String? _categoryId = widget.item.categoryId;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final amount = parseAmountMinor(_amount.text, _currency);
    await ref.read(plannedRepositoryProvider).update(
          widget.item.copyWith(
            name: _name.text.trim().isEmpty ? widget.item.name : _name.text.trim(),
            amountMinor: Value(amount > 0 ? amount : null),
            categoryId: Value(_categoryId),
          ),
        );
    navigator.pop();
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    await ref.read(plannedRepositoryProvider).delete(widget.item.id);
    navigator.pop();
  }

  Widget _chip(String label, IconData icon, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18, color: selected ? AppColors.deepWater : AppColors.mist),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.shallows,
      backgroundColor: Colors.white,
      shape: const StadiumBorder(),
      side: BorderSide(color: selected ? AppColors.tide : AppColors.line),
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tree = ref.watch(categoryTreeProvider(CategoryKind.expense));
    InputDecoration deco(String label, {bool money = false}) => InputDecoration(
          labelText: label,
          prefixText: money ? '${Money.symbol(_currency)} ' : null,
          filled: true,
          fillColor: AppColors.foam,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit item',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: deco('Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.numberWithOptions(
                decimal: Money.fractionDigits(_currency) > 0,
              ),
              inputFormatters: [amountInputFormatter(_currency)],
              decoration: deco(
                widget.item.isDone ? 'Price paid' : 'Price (optional)',
                money: true,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Category',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Optional. Decides which expenses page it shows on once bought; '
            'without one it goes to Other expenses.',
              style: text.bodySmall?.copyWith(color: AppColors.mist),
            ),
            const SizedBox(height: 10),
            tree.when(
              loading: () => const SizedBox(height: 40),
              error: (e, _) => Text('$e'),
              data: (nodes) {
                final selected = nodes
                    .where(
                      (n) =>
                          n.category.id == _categoryId ||
                          n.children.any((c) => c.id == _categoryId),
                    )
                    .firstOrNull;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final n in nodes)
                          _chip(
                            n.category.name,
                            iconFor(n.category.iconKey),
                            selected == n,
                            () => setState(() => _categoryId = n.category.id),
                          ),
                      ],
                    ),
                    if (selected != null && selected.children.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final sub in selected.children)
                            _chip(
                              sub.name,
                              iconFor(sub.iconKey),
                              _categoryId == sub.id,
                              () => setState(
                                () => _categoryId = _categoryId == sub.id
                                    ? selected.category.id
                                    : sub.id,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Save'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.buoyRed),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove from list'),
            ),
          ],
        ),
      ),
    );
  }
}
