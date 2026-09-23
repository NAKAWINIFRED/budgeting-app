import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../../core/money_kinds.dart';
import '../../data/database.dart';
import '../../data/lookups.dart';
import '../../data/transactions_repository.dart';
import '../categories/categories_repository.dart';
import '../debts/add_debt_sheet.dart';
import '../debts/debt_labels.dart';
import '../debts/debt_providers.dart';
import '../savings/goal_sheet.dart';
import '../savings/savings_labels.dart';
import '../savings/savings_providers.dart';

/// Opens the quick-add sheet from anywhere in the app. Pass [existing] to
/// edit or delete a transaction instead of adding a new one.
///
/// For a new entry, the optional [kind], [amountMinor], [goalId], [debtId]
/// and [note] pre-fill the form (used by the month-end review and
/// investments).
Future<void> showQuickAddSheet(
  BuildContext context, {
  MoneyTransaction? existing,
  TransactionKind? kind,
  int? amountMinor,
  String? goalId,
  String? debtId,
  String? note,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => QuickAddSheet(
      existing: existing,
      initialKind: kind,
      initialAmountMinor: amountMinor,
      initialGoalId: goalId,
      initialDebtId: debtId,
      initialNote: note,
    ),
  );
}

const _kinds = [
  TransactionKind.expense,
  TransactionKind.income,
  TransactionKind.savingsDeposit,
  TransactionKind.debtPayment,
];

extension on TransactionKind {
  String get tabLabel => switch (this) {
        TransactionKind.expense => 'Expense',
        TransactionKind.income => 'Income',
        TransactionKind.savingsDeposit => 'Savings',
        TransactionKind.debtPayment => 'Debt',
        TransactionKind.savingsWithdrawal => 'Withdraw',
      };

  String get pickerTitle => switch (this) {
        TransactionKind.expense => 'Category',
        TransactionKind.income => 'Type of income',
        TransactionKind.savingsDeposit => 'Save to',
        TransactionKind.debtPayment => 'Pay towards',
        TransactionKind.savingsWithdrawal => 'Take from',
      };

  String get saveLabel => switch (this) {
        TransactionKind.expense => 'Save expense',
        TransactionKind.income => 'Save income',
        TransactionKind.savingsDeposit => 'Add to savings',
        TransactionKind.debtPayment => 'Save payment',
        TransactionKind.savingsWithdrawal => 'Take out of savings',
      };

  String get savedMessage => switch (this) {
        TransactionKind.expense => 'Expense saved',
        TransactionKind.income => 'Income saved',
        TransactionKind.savingsDeposit => 'Added to savings',
        TransactionKind.debtPayment => 'Payment saved',
        TransactionKind.savingsWithdrawal => 'Taken out of savings',
      };
}

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({
    super.key,
    this.existing,
    this.initialKind,
    this.initialAmountMinor,
    this.initialGoalId,
    this.initialDebtId,
    this.initialNote,
  });

  final MoneyTransaction? existing;
  final TransactionKind? initialKind;
  final int? initialAmountMinor;
  final String? initialGoalId;
  final String? initialDebtId;
  final String? initialNote;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  static String get _currency => kDefaultCurrency;

  final _amount = TextEditingController();
  final _note = TextEditingController();

  TransactionKind _kind = TransactionKind.expense;
  String? _categoryId;
  String? _goalId; // null = general savings
  String? _debtId;
  DateTime? _payPeriod; // income only: the month this pay is for
  PaymentMethod? _method; // cash, mobile money, bank, card
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;

  /// Item rows when an expense is broken down (empty = not itemized).
  final List<_ItemRow> _items = [];
  List<TransactionItem> _originalItems = [];

  bool get _isEditing => widget.existing != null;
  bool get _itemized => _items.isNotEmpty;

  String _amountText(int minor) {
    final value = Money.fromMinor(minor, _currency);
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(Money.fractionDigits(_currency));
  }

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    if (tx == null) {
      _kind = widget.initialKind ?? TransactionKind.expense;
      _goalId = widget.initialGoalId;
      _debtId = widget.initialDebtId;
      _note.text = widget.initialNote ?? '';
      final prefill = widget.initialAmountMinor;
      if (prefill != null && prefill > 0) _amount.text = _amountText(prefill);
      // Pre-select the payment method used last time.
      ref.read(transactionsRepositoryProvider).lastPaymentMethod().then((m) {
        if (mounted && _method == null && m != null) setState(() => _method = m);
      });
      return;
    }
    _method = tx.paymentMethod;
    _kind = tx.kind;
    _categoryId = tx.categoryId;
    _goalId = tx.savingsGoalId;
    _debtId = tx.debtId;
    _payPeriod = tx.payPeriod;
    _date = DateUtils.dateOnly(tx.occurredAt);
    _note.text = tx.note ?? '';
    _amount.text = _amountText(tx.amountMinor);

    // Load this transaction's items, if it has any.
    ref.read(transactionsRepositoryProvider).itemsFor(tx.id).then((items) {
      if (!mounted || items.isEmpty) return;
      setState(() {
        _originalItems = items;
        _items.addAll(
          items.map((i) => _ItemRow(i.name, _amountText(i.amountMinor))),
        );
      });
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  /// When itemized, the amount is always the sum of the items.
  int get _amountMinor => _itemized
      ? _itemDrafts().fold(0, (sum, i) => sum + i.amountMinor)
      : parseAmountMinor(_amount.text, _currency);

  List<ItemDraft> _itemDrafts() => [
        for (final row in _items)
          if (parseAmountMinor(row.amount.text, _currency) > 0)
            ItemDraft(
              row.name.text.trim().isEmpty ? 'Item' : row.name.text.trim(),
              parseAmountMinor(row.amount.text, _currency),
            ),
      ];

  void _addItemRow() => setState(() => _items.add(_ItemRow('', '')));

  void _removeItemRow(_ItemRow row) {
    setState(() => _items.remove(row));
    row.dispose();
  }

  bool get _canSave {
    if (_saving || _amountMinor <= 0) return false;
    return switch (_kind) {
      TransactionKind.expense || TransactionKind.income => _categoryId != null,
      TransactionKind.debtPayment => _debtId != null,
      _ => true,
    };
  }

  String get _dateLabel {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    if (_date == today) return 'Today';
    if (_date == yesterday) return 'Yesterday';
    return DateFormat.MMMd().format(_date);
  }

  void _selectKind(TransactionKind kind) {
    setState(() {
      _kind = kind;
      if (kind != TransactionKind.expense) {
        for (final row in _items) {
          row.dispose();
        }
        _items.clear();
      }
      _categoryId = null;
      _payPeriod = null;
      _goalId = null;
      _debtId = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = DateUtils.dateOnly(picked));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final repo = ref.read(transactionsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final kind = _kind;
    final amount = _amountMinor;
    final now = DateTime.now();
    final note = _note.text.trim();

    if (_isEditing) {
      final old = widget.existing!;
      try {
        await repo.update(
          old.copyWith(
            kind: kind,
            amountMinor: amount,
            // Same day keeps the original time; a new day is stored at midday.
            occurredAt: DateUtils.isSameDay(_date, old.occurredAt)
                ? old.occurredAt
                : DateTime(_date.year, _date.month, _date.day, 12),
            categoryId: Value(_categoryId),
            savingsGoalId: Value(_goalId),
            debtId: Value(_debtId),
            note: Value(note.isEmpty ? null : note),
            payPeriod: Value(kind == TransactionKind.income ? _payPeriod : null),
            paymentMethod: Value(_method),
          ),
          items: _itemDrafts(),
        );
        final previousItems = [
          for (final i in _originalItems) ItemDraft(i.name, i.amountMinor),
        ];
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Changes saved'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repo.update(old, items: previousItems),
            ),
          ),
        );
      } catch (e) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save changes. ($e)')),
        );
      }
      return;
    }

    // Goal progress before this deposit, to spot milestones.
    final goalBefore = kind == TransactionKind.savingsDeposit && _goalId != null
        ? ref.read(savingsOverviewProvider).value?.byId(_goalId)
        : null;

    // Debt progress before this payment, to spot milestones.
    final debtBefore = kind == TransactionKind.debtPayment && _debtId != null
        ? ref.read(debtOverviewProvider).value?.byId(_debtId!)
        : null;

    try {
      final id = await repo.add(
        kind: kind,
        amountMinor: amount,
        currency: _currency,
        // Today keeps the exact time; past days are stored at midday.
        occurredAt: DateUtils.isSameDay(_date, now)
            ? now
            : DateTime(_date.year, _date.month, _date.day, 12),
        categoryId: _categoryId,
        savingsGoalId: _goalId,
        debtId: _debtId,
        note: note.isEmpty ? null : note,
        payPeriod: kind == TransactionKind.income ? _payPeriod : null,
        paymentMethod: _method,
        items: _itemDrafts(),
      );

      navigator.pop();

      // A savings goal just reached its target: celebrate.
      if (goalBefore != null &&
          goalBefore.hasTarget &&
          !goalBefore.isReached &&
          goalBefore.savedMinor + amount >= goalBefore.targetMinor!) {
        final goalName = goalBefore.name;
        final target = Money.format(goalBefore.targetMinor!, _currency);
        await showDialog<void>(
          context: navigator.context,
          builder: (context) => AlertDialog(
            icon: const Icon(
              Icons.emoji_events_rounded,
              size: 44,
              color: AppColors.tide,
            ),
            title: Text('You reached $goalName!'),
            content: Text(
              'You saved $target, one deposit at a time. That is real '
              'discipline. Set a new goal whenever you are ready.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        return;
      }

      if (debtBefore != null &&
          !debtBefore.isPaidOff &&
          debtBefore.paidMinor + amount >= debtBefore.totalMinor) {
        final debtName = debtBefore.debt.name;
        await showDialog<void>(
          context: navigator.context,
          builder: (context) => AlertDialog(
            icon: const Icon(
              Icons.celebration_rounded,
              size: 44,
              color: AppColors.tide,
            ),
            title: Text('$debtName is paid off!'),
            content: const Text(
              'That is a huge step. The money that went to this debt is now '
              'free for your savings and goals.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        return;
      }

      final milestone = debtBefore != null
          ? milestoneMessage(
              debtName: debtBefore.debt.name,
              totalMinor: debtBefore.totalMinor,
              paidBeforeMinor: debtBefore.paidMinor,
              paymentMinor: amount,
            )
          : goalBefore != null && goalBefore.hasTarget
              ? savingsMilestoneMessage(
                  goalName: goalBefore.name,
                  targetMinor: goalBefore.targetMinor!,
                  savedBeforeMinor: goalBefore.savedMinor,
                  depositMinor: amount,
                )
              : null;

      messenger.showSnackBar(
        SnackBar(
          content: Text(milestone ?? kind.savedMessage),
          duration: Duration(seconds: milestone == null ? 4 : 6),
          action: SnackBarAction(label: 'Undo', onPressed: () => repo.delete(id)),
        ),
      );
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save. Please try again. ($e)')),
      );
    }
  }

  Future<void> _pickPayPeriod() async {
    final base = DateTime(_date.year, _date.month);
    final months = [for (var i = 1; i >= -6; i--) DateTime(base.year, base.month + i)];
    final noMonth = DateTime(0);

    final choice = await showDialog<DateTime>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which month is this pay for?'),
        children: [
          for (final m in months)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: Text(
                DateFormat.yMMMM().format(m),
                style: TextStyle(
                  fontWeight: m == _payPeriod ? FontWeight.w800 : FontWeight.w500,
                  color: m == _payPeriod ? AppColors.tide : null,
                ),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(noMonth),
            child: const Text('No specific month'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    setState(() => _payPeriod = choice == noMonth ? null : choice);
  }

  Future<void> _addGoal() async {
    final id = await showGoalSheet(context);
    if (id != null && mounted) setState(() => _goalId = id);
  }

  Future<void> _addDebt() async {
    final id = await showAddDebtSheet(context);
    if (id != null && mounted) setState(() => _debtId = id);
  }

  Future<void> _delete() async {
    final tx = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text('It will be removed from your totals.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.buoyRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repo = ref.read(transactionsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final items = await repo.itemsFor(tx.id);
    await repo.delete(tx.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Transaction deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(tx, items)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final digits = Money.fractionDigits(_currency);

    return Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<TransactionKind>(
              segments: [
                for (final k in _kinds)
                  ButtonSegment(value: k, label: Text(k.tabLabel)),
              ],
              // Taking money out is part of the Savings tab.
              selected: {
                _kind == TransactionKind.savingsWithdrawal
                    ? TransactionKind.savingsDeposit
                    : _kind,
              },
              showSelectedIcon: false,
              onSelectionChanged: (s) => _selectKind(s.first),
            ),
            const SizedBox(height: 16),
            if (_itemized)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total from items',
                      style: text.bodySmall?.copyWith(color: AppColors.mist),
                    ),
                    Text(
                      Money.format(_amountMinor, _currency),
                      style: AppText.amount(
                        40,
                        weight: FontWeight.w800,
                        color: amountColorFor(_kind),
                      ),
                    ),
                  ],
                ),
              )
            else
            TextField(
              controller: _amount,
              autofocus: !_isEditing,
              keyboardType: TextInputType.numberWithOptions(decimal: digits > 0),
              textInputAction: TextInputAction.done,
              inputFormatters: [amountInputFormatter(_currency)],
              style: AppText.amount(
                40,
                weight: FontWeight.w800,
                color: amountColorFor(_kind),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0',
                hintStyle: AppText.amount(40, color: AppColors.line, weight: FontWeight.w800),
                prefixText: '${Money.symbol(_currency)} ',
                prefixStyle: AppText.amount(24, color: AppColors.mist),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              _kind.pickerTitle,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _buildPicker(),
            if (_kind == TransactionKind.expense) ...[
              const SizedBox(height: 16),
              if (_itemized) ...[
                Text(
                  'Items',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                for (final row in _items) _buildItemRow(row),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addItemRow,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(
                    _itemized ? 'Add another item' : 'Break it down into items',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              _kind == TransactionKind.income ||
                      _kind == TransactionKind.savingsWithdrawal
                  ? 'Received via'
                  : 'Paid with',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _chipWrap([
              for (final m in PaymentMethod.values)
                _choice(
                  label: m.label,
                  icon: m.icon,
                  selected: _method == m,
                  // Tap again to clear it.
                  onTap: () => setState(() => _method = _method == m ? null : m),
                ),
            ]),
            const SizedBox(height: 16),
            Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(_dateLabel),
                  onPressed: _pickDate,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Add a note',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isEditing ? 'Save changes' : _kind.saveLabel),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: AppColors.buoyRed),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete transaction'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPicker() {
    final muted = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: AppColors.mist);

    if (_kind == TransactionKind.expense || _kind == TransactionKind.income) {
      final kind = _kind == TransactionKind.income
          ? CategoryKind.income
          : CategoryKind.expense;
      return ref.watch(categoryTreeProvider(kind)).when(
            loading: () => const SizedBox(height: 40),
            error: (e, _) => Text('Could not load categories. ($e)'),
            data: (nodes) {
              // The parent that is chosen, directly or via a subcategory.
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
                  _chipWrap([
                    for (final n in nodes)
                      _choice(
                        label: n.category.name,
                        icon: iconFor(n.category.iconKey),
                        selected: selected == n,
                        onTap: () => setState(() => _categoryId = n.category.id),
                      ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: AppColors.tide,
                      ),
                      label: const Text('Edit'),
                      backgroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      side: const BorderSide(color: AppColors.tide),
                      onPressed: () => context.push('/categories?kind=${kind.name}'),
                    ),
                  ]),
                  if (selected != null && selected.children.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Which ${selected.category.name.toLowerCase()}? (optional)',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.mist),
                    ),
                    const SizedBox(height: 8),
                    _chipWrap([
                      for (final sub in selected.children)
                        _choice(
                          label: sub.name,
                          icon: iconFor(sub.iconKey),
                          selected: _categoryId == sub.id,
                          // Tapping the chosen one again goes back to the parent.
                          onTap: () => setState(
                            () => _categoryId = _categoryId == sub.id
                                ? selected.category.id
                                : sub.id,
                          ),
                        ),
                    ]),
                  ],
                  if (_kind == TransactionKind.income) ...[
                    const SizedBox(height: 12),
                    ActionChip(
                      avatar: const Icon(Icons.event_note_rounded, size: 18),
                      label: Text(
                        _payPeriod == null
                            ? 'Which month is this pay for? (optional)'
                            : 'Pay for ${DateFormat.yMMMM().format(_payPeriod!)}',
                      ),
                      onPressed: _pickPayPeriod,
                    ),
                  ],
                ],
              );
            },
          );
    }

    if (_kind == TransactionKind.savingsDeposit ||
        _kind == TransactionKind.savingsWithdrawal) {
      // Keeps savings progress loaded so milestones can be spotted on save.
      ref.watch(savingsOverviewProvider);
      final addGoalChip = ActionChip(
        avatar: const Icon(Icons.add_rounded, size: 18, color: AppColors.tide),
        label: const Text('New goal'),
        backgroundColor: Colors.white,
        shape: const StadiumBorder(),
        side: const BorderSide(color: AppColors.tide),
        onPressed: _addGoal,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Put in')),
              ButtonSegment(value: true, label: Text('Take out')),
            ],
            selected: {_kind == TransactionKind.savingsWithdrawal},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(
              () => _kind = s.first
                  ? TransactionKind.savingsWithdrawal
                  : TransactionKind.savingsDeposit,
            ),
          ),
          const SizedBox(height: 12),
          ref.watch(activeGoalsProvider).when(
                loading: () => const SizedBox(height: 40),
                error: (e, _) => Text('Could not load goals. ($e)'),
                data: (goals) => _chipWrap([
                  _choice(
                    label: 'General savings',
                    icon: Icons.savings_rounded,
                    selected: _goalId == null,
                    onTap: () => setState(() => _goalId = null),
                  ),
                  for (final g in goals)
                    _choice(
                      label: g.name,
                      icon: iconFor(g.iconKey ?? 'savings'),
                      selected: _goalId == g.id,
                      onTap: () => setState(() => _goalId = g.id),
                    ),
                  if (_kind == TransactionKind.savingsDeposit) addGoalChip,
                ]),
              ),
        ],
      );
    }

    // Debt payment. Watching the overview keeps it loaded, so milestones
    // can be detected the moment a payment is saved.
    ref.watch(debtOverviewProvider);
    final addDebtChip = ActionChip(
      avatar: const Icon(Icons.add_rounded, size: 18, color: AppColors.tide),
      label: const Text('Add a debt'),
      backgroundColor: Colors.white,
      shape: const StadiumBorder(),
      side: const BorderSide(color: AppColors.tide),
      onPressed: _addDebt,
    );

    return ref.watch(activeDebtsProvider).when(
          loading: () => const SizedBox(height: 40),
          error: (e, _) => Text('Could not load debts. ($e)'),
          data: (debts) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (debts.isEmpty) ...[
                Text(
                  'Add the debt you are paying, like a car loan or money from a friend.',
                  style: muted,
                ),
                const SizedBox(height: 10),
              ],
              _chipWrap([
                for (final d in debts)
                  _choice(
                    label: d.name,
                    icon: d.debtType.icon,
                    selected: _debtId == d.id,
                    onTap: () => setState(() => _debtId = d.id),
                  ),
                addDebtChip,
              ]),
            ],
          ),
        );
  }

  Widget _buildItemRow(_ItemRow row) {
    InputDecoration deco(String hint, {String? prefix}) => InputDecoration(
          hintText: hint,
          prefixText: prefix,
          isDense: true,
          filled: true,
          fillColor: AppColors.foam,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        );

    return Padding(
      key: ObjectKey(row),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: row.name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: deco('e.g. Eggs'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: row.amount,
              keyboardType: TextInputType.numberWithOptions(
                decimal: Money.fractionDigits(_currency) > 0,
              ),
              inputFormatters: [amountInputFormatter(_currency)],
              decoration: deco('0', prefix: '${Money.symbol(_currency)} '),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            tooltip: 'Remove item',
            icon: const Icon(Icons.close_rounded, color: AppColors.mist),
            onPressed: () => _removeItemRow(row),
          ),
        ],
      ),
    );
  }

  Widget _chipWrap(List<Widget> children) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);

  Widget _choice({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? AppColors.deepWater : AppColors.mist,
      ),
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
}

/// Text fields for one item row in an itemized expense.
class _ItemRow {
  _ItemRow(String name, String amount)
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount);

  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}
