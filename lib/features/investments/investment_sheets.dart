import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../savings/savings_providers.dart';
import '../transactions/quick_add_sheet.dart';
import 'investments_providers.dart';

const _currency = kDefaultCurrency;

InputDecoration _decoration(String label, {String? helper, bool money = false}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    helperMaxLines: 3,
    prefixText: money ? '${Money.symbol(_currency)} ' : null,
    filled: true,
    fillColor: AppColors.foam,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );
}

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: child,
    ),
  );
}

String _formatInput(int minor) {
  final value = Money.fromMinor(minor, _currency);
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(Money.fractionDigits(_currency));
}

/// "+$120 (+8.5%)" or "−$40 (−3.1%)"
String formatGain(int gainMinor, double percent) {
  final sign = gainMinor >= 0 ? '+' : '\u2212';
  final pct = (percent.abs() * 100).toStringAsFixed(1);
  return '$sign${Money.format(gainMinor.abs(), _currency)} ($sign$pct%)';
}

Color gainColor(int gainMinor) =>
    gainMinor >= 0 ? AppColors.growth : AppColors.expense;

// ============================================================================
// ADD / EDIT
// ============================================================================

Future<void> showInvestmentSheet(BuildContext context, {SavingsGoal? existing}) =>
    _sheet(context, _InvestmentForm(existing: existing));

class _InvestmentForm extends ConsumerStatefulWidget {
  const _InvestmentForm({this.existing});

  final SavingsGoal? existing;

  @override
  ConsumerState<_InvestmentForm> createState() => _InvestmentFormState();
}

class _InvestmentFormState extends ConsumerState<_InvestmentForm> {
  final _name = TextEditingController();
  final _putIn = TextEditingController();
  final _worth = TextEditingController();
  InvestmentType _type = InvestmentType.stocks;
  DateTime _started = DateTime.now();
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    if (g != null) {
      _name.text = g.name;
      _type = g.investmentType ?? InvestmentType.other;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _putIn, _worth]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _putInMinor => parseAmountMinor(_putIn.text, _currency);

  bool get _canSave =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      (_isEditing || _putInMinor > 0);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final existing = widget.existing;

    if (existing != null) {
      await ref.read(savingsRepositoryProvider).update(
            existing.copyWith(
              name: _name.text.trim(),
              investmentType: Value(_type),
              iconKey: Value(_type.iconKey),
            ),
          );
    } else {
      final worth = parseAmountMinor(_worth.text, _currency);
      await ref.read(investmentsRepositoryProvider).add(
            name: _name.text.trim(),
            type: _type,
            currency: _currency,
            putInMinor: _putInMinor,
            worthNowMinor: worth > 0 ? worth : _putInMinor,
            startedOn: DateTime(_started.year, _started.month, _started.day, 12),
          );
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final g = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${g.name}?'),
        content: const Text(
          'Its value history is removed. Money you recorded putting in stays '
          'in your history as general savings.',
        ),
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
    final navigator = Navigator.of(context);
    await ref.read(savingsRepositoryProvider).delete(g.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final keyboard = TextInputType.numberWithOptions(
      decimal: Money.fractionDigits(_currency) > 0,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEditing ? 'Edit investment' : 'New investment',
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration('Name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Type', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in InvestmentType.values)
                ChoiceChip(
                  avatar: Icon(
                    iconFor(t.iconKey),
                    size: 18,
                    color: _type == t ? AppColors.deepWater : AppColors.mist,
                  ),
                  label: Text(t.label),
                  selected: _type == t,
                  showCheckmark: false,
                  selectedColor: AppColors.shallows,
                  backgroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  side: BorderSide(color: _type == t ? AppColors.tide : AppColors.line),
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          if (!_isEditing) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _putIn,
              keyboardType: keyboard,
              inputFormatters: [amountInputFormatter(_currency)],
              decoration: _decoration('How much have you put in so far?', money: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _worth,
              keyboardType: keyboard,
              inputFormatters: [amountInputFormatter(_currency)],
              decoration: _decoration(
                'What is it worth today? (optional)',
                money: true,
                helper: 'Leave empty if you just started. You can update the '
                    'value any time.',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.event_rounded, size: 18),
                label: Text('Started ${DateFormat.yMMMd().format(_started)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _started,
                    firstDate: DateTime(1970),
                    lastDate: DateTime.now(),
                    helpText: 'When did you start this investment?',
                  );
                  if (picked != null) setState(() => _started = picked);
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(_isEditing ? 'Save changes' : 'Add investment'),
          ),
          if (_isEditing) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.buoyRed),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete investment'),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// UPDATE VALUE
// ============================================================================

Future<void> showUpdateValueSheet(BuildContext context, InvestmentProgress p) =>
    _sheet(context, _UpdateValueForm(progress: p));

class _UpdateValueForm extends ConsumerStatefulWidget {
  const _UpdateValueForm({required this.progress});

  final InvestmentProgress progress;

  @override
  ConsumerState<_UpdateValueForm> createState() => _UpdateValueFormState();
}

class _UpdateValueFormState extends ConsumerState<_UpdateValueForm> {
  late final _value =
      TextEditingController(text: _formatInput(widget.progress.currentValueMinor));
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = parseAmountMinor(_value.text, _currency);
    final p = widget.progress;
    final gain = value - p.contributedMinor;
    final pct = p.contributedMinor <= 0 ? 0.0 : gain / p.contributedMinor;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What is ${p.goal.name} worth now?',
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your app, statement or broker and type the current value.',
            style: text.bodySmall?.copyWith(color: AppColors.mist),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: Money.fractionDigits(_currency) > 0,
            ),
            inputFormatters: [amountInputFormatter(_currency)],
            style: AppText.amount(28),
            decoration: _decoration('Current value', money: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (value > 0)
            Text(
              'That is ${formatGain(gain, pct)} on the '
              '${Money.format(p.contributedMinor, _currency)} you put in.',
              style: text.bodyMedium?.copyWith(
                color: gainColor(gain),
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.event_rounded, size: 18),
              label: Text('As of ${DateFormat.yMMMd().format(_date)}'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: p.startedOn,
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: value <= 0
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    final now = DateTime.now();
                    await ref.read(investmentsRepositoryProvider).addValuation(
                          p.goal.id,
                          value,
                          dateOnly(_date) == dateOnly(now)
                              ? now
                              : DateTime(_date.year, _date.month, _date.day, 12),
                        );
                    navigator.pop();
                  },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Save value'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DETAIL
// ============================================================================

Future<void> showInvestmentDetail(BuildContext context, String goalId) =>
    _sheet(context, _InvestmentDetail(goalId: goalId));

class _InvestmentDetail extends ConsumerWidget {
  const _InvestmentDetail({required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = ref.watch(investmentsOverviewProvider).value?.byId(goalId);
    if (p == null) return const SizedBox(height: 200);

    final span = describeSpan(p.startedOn, DateTime.now());
    final history = p.valuations.reversed.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.goal.name,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showInvestmentSheet(context, existing: p.goal),
              ),
            ],
          ),
          Text(
            (p.goal.investmentType ?? InvestmentType.other).label,
            style: text.bodyMedium?.copyWith(color: AppColors.mist),
          ),
          const SizedBox(height: 16),
          Text('Worth now', style: text.bodySmall?.copyWith(color: AppColors.mist)),
          Text(
            Money.format(p.currentValueMinor, _currency),
            style: AppText.amount(34, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatGain(p.gainMinor, p.gainPercent)} over $span',
            style: text.bodyLarge?.copyWith(
              color: gainColor(p.gainMinor),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You put in ${Money.format(p.contributedMinor, _currency)} since '
            '${DateFormat.yMMMd().format(p.startedOn)}.',
            style: text.bodySmall?.copyWith(color: AppColors.mist),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showUpdateValueSheet(context, p),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Update value'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showQuickAddSheet(
                    context,
                    kind: TransactionKind.savingsDeposit,
                    goalId: p.goal.id,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add money'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Value history',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < history.length; i++)
            _HistoryRow(
              valuation: history[i],
              previous: i + 1 < history.length ? history[i + 1] : null,
              onDelete: history.length > 1
                  ? () => ref
                      .read(investmentsRepositoryProvider)
                      .deleteValuation(history[i].id)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.valuation, this.previous, this.onDelete});

  final InvestmentValuation valuation;
  final InvestmentValuation? previous;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final prev = previous;
    final change = prev == null ? null : valuation.valueMinor - prev.valueMinor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMd().format(valuation.valuedOn),
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  change == null
                      ? 'Starting value'
                      : '${change >= 0 ? '+' : '\u2212'}'
                          '${Money.format(change.abs(), _currency)} since '
                          '${DateFormat.MMMd().format(prev!.valuedOn)}',
                  style: text.bodySmall?.copyWith(
                    color: change == null ? AppColors.mist : gainColor(change),
                  ),
                ),
              ],
            ),
          ),
          Text(
            Money.format(valuation.valueMinor, _currency),
            style: AppText.amount(15),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Remove this update',
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.mist),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
