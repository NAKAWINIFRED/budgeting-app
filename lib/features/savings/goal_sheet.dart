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
import 'savings_labels.dart';
import 'savings_providers.dart';

/// Opens the goal form. Pass [existing] to edit or delete a goal.
/// Returns the goal's id when saved, or null if cancelled/deleted.
Future<String?> showGoalSheet(BuildContext context, {SavingsGoal? existing}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => GoalSheet(existing: existing),
  );
}

class GoalSheet extends ConsumerStatefulWidget {
  const GoalSheet({super.key, this.existing});

  final SavingsGoal? existing;

  @override
  ConsumerState<GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<GoalSheet> {
  static const _currency = kDefaultCurrency;

  final _name = TextEditingController();
  final _target = TextEditingController();
  final _starting = TextEditingController();

  SavingsTerm _term = SavingsTerm.shortTerm;
  String _iconKey = 'savings';
  DateTime? _targetDate;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  String _amountText(int? minor) {
    if (minor == null || minor <= 0) return '';
    final value = Money.fromMinor(minor, _currency);
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(Money.fractionDigits(_currency));
  }

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    if (g == null) return;
    _name.text = g.name;
    _term = g.term;
    _iconKey = g.iconKey ?? 'savings';
    _targetDate = g.targetDate;
    _target.text = _amountText(g.targetAmountMinor);
    _starting.text = _amountText(g.startingAmountMinor);
  }

  @override
  void dispose() {
    for (final c in [_name, _target, _starting]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave => !_saving && _name.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 50),
      helpText: 'When do you want to reach it?',
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final repo = ref.read(savingsRepositoryProvider);
    final navigator = Navigator.of(context);
    final target = parseAmountMinor(_target.text, _currency);
    final starting = parseAmountMinor(_starting.text, _currency);

    try {
      final existing = widget.existing;
      if (existing != null) {
        await repo.update(
          existing.copyWith(
            name: _name.text.trim(),
            term: _term,
            iconKey: Value(_iconKey),
            targetAmountMinor: Value(target > 0 ? target : null),
            targetDate: Value(_targetDate),
            startingAmountMinor: starting,
          ),
        );
        navigator.pop(existing.id);
      } else {
        final id = await repo.add(
          name: _name.text.trim(),
          term: _term,
          currency: _currency,
          iconKey: _iconKey,
          targetMinor: target > 0 ? target : null,
          targetDate: _targetDate,
          startingMinor: starting,
        );
        navigator.pop(id);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the goal. ($e)')),
      );
    }
  }

  Future<void> _delete() async {
    final goal = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${goal.name}?'),
        content: const Text(
          'Money you saved towards it will not be lost. It moves to General '
          'savings.',
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
    await ref.read(savingsRepositoryProvider).delete(goal.id);
    navigator.pop();
  }

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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final amountKeyboard = TextInputType.numberWithOptions(
      decimal: Money.fractionDigits(_currency) > 0,
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
              _isEditing ? 'Edit goal' : 'New savings goal',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            // Icon picker
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: goalIconKeys.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final key = goalIconKeys[i];
                  final selected = key == _iconKey;
                  return InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _iconKey = key),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          selected ? AppColors.tide : AppColors.shallows,
                      child: Icon(
                        iconFor(key),
                        color: selected ? Colors.white : AppColors.deepWater,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('What are you saving for?'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              'When will you need it?',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<SavingsTerm>(
              segments: [
                for (final t in SavingsTerm.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_term},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _term = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              _term.explanation,
              style: text.bodySmall?.copyWith(color: AppColors.mist),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _target,
              keyboardType: amountKeyboard,
              inputFormatters: [amountInputFormatter(_currency)],
              decoration: _decoration('Target amount (optional)', money: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                    _targetDate == null
                        ? 'Add a target date (optional)'
                        : 'By ${DateFormat.yMMMd().format(_targetDate!)}',
                  ),
                  onPressed: _pickDate,
                ),
                if (_targetDate != null)
                  IconButton(
                    tooltip: 'Remove date',
                    icon: const Icon(Icons.close_rounded, color: AppColors.mist),
                    onPressed: () => setState(() => _targetDate = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _starting,
              keyboardType: amountKeyboard,
              inputFormatters: [amountInputFormatter(_currency)],
              decoration: _decoration(
                'Already saved (optional)',
                money: true,
                helper: 'Money you had set aside before using Tidewise. It '
                    'counts towards the goal but not towards this month.',
              ),
            ),
            const SizedBox(height: 24),
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
                  : Text(_isEditing ? 'Save changes' : 'Create goal'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: AppColors.buoyRed),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete goal'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
