import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/lookups.dart';
import '../../data/transactions_repository.dart';
import '../debts/add_debt_sheet.dart';
import '../debts/debt_labels.dart';
import '../debts/debt_providers.dart';

/// Opens the quick-add sheet from anywhere in the app. Pass [existing] to
/// edit or delete a transaction instead of adding a new one.
Future<void> showQuickAddSheet(
  BuildContext context, {
  MoneyTransaction? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => QuickAddSheet(existing: existing),
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
        TransactionKind.savingsWithdrawal => 'Save withdrawal',
      };

  String get savedMessage => switch (this) {
        TransactionKind.expense => 'Expense saved',
        TransactionKind.income => 'Income saved',
        TransactionKind.savingsDeposit => 'Added to savings',
        TransactionKind.debtPayment => 'Payment saved',
        TransactionKind.savingsWithdrawal => 'Withdrawal saved',
      };
}

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, this.existing});

  final MoneyTransaction? existing;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  static const _currency = kDefaultCurrency;

  final _amount = TextEditingController();
  final _note = TextEditingController();

  TransactionKind _kind = TransactionKind.expense;
  String? _categoryId;
  String? _goalId; // null = general savings
  String? _debtId;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    if (tx == null) return;
    _kind = tx.kind;
    _categoryId = tx.categoryId;
    _goalId = tx.savingsGoalId;
    _debtId = tx.debtId;
    _date = DateUtils.dateOnly(tx.occurredAt);
    _note.text = tx.note ?? '';
    final value = Money.fromMinor(tx.amountMinor, _currency);
    _amount.text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(Money.fractionDigits(_currency));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _amountMinor => parseAmountMinor(_amount.text, _currency);

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
      _categoryId = null;
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
          ),
        );
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Changes saved'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repo.update(old),
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
      );

      navigator.pop();

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

      final milestone = debtBefore == null
          ? null
          : milestoneMessage(
              debtName: debtBefore.debt.name,
              totalMinor: debtBefore.totalMinor,
              paidBeforeMinor: debtBefore.paidMinor,
              paymentMinor: amount,
            );

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

    await repo.delete(tx.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Transaction deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(tx)),
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
                for (final k in [
                  ..._kinds,
                  if (widget.existing?.kind == TransactionKind.savingsWithdrawal)
                    TransactionKind.savingsWithdrawal,
                ])
                  ButtonSegment(value: k, label: Text(k.tabLabel)),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _selectKind(s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: !_isEditing,
              keyboardType: TextInputType.numberWithOptions(decimal: digits > 0),
              textInputAction: TextInputAction.done,
              inputFormatters: [amountInputFormatter(_currency)],
              style: AppText.amount(40, weight: FontWeight.w800),
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
            const SizedBox(height: 20),
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
      return ref.watch(categoriesProvider(kind)).when(
            loading: () => const SizedBox(height: 40),
            error: (e, _) => Text('Could not load categories. ($e)'),
            data: (list) => _chipWrap([
              for (final c in list)
                _choice(
                  label: c.name,
                  icon: iconFor(c.iconKey),
                  selected: _categoryId == c.id,
                  onTap: () => setState(() => _categoryId = c.id),
                ),
            ]),
          );
    }

    if (_kind == TransactionKind.savingsDeposit) {
      return ref.watch(activeGoalsProvider).when(
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
            ]),
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
